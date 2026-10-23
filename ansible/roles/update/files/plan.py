#!/usr/bin/env python3
"""Turn every host's facts into a report and a plan.

Reads JSON on stdin (written by tasks/plan.yml): the phase, the report
directory, the Proxmox node's guest list, the guest names other repos manage,
and per update target its kind, facts, Proxmox name and components.
Looks up upstream releases on GitHub (GITHUB_TOKEN is used when set, only to
raise the rate limit), writes <report_dir>/<timestamp>-<phase>.json and
latest.json, and prints the plan as JSON: per host the actions `apply` may
take, plus the summary lines the playbook shows.

Standard library only; runs on the controller.
"""
import datetime
import json
import os
import re
import sys
import urllib.request



def vtuple(text):
    m = re.match(r"^v?(\d+(?:\.\d+)*)$", (text or "").strip())
    return tuple(int(p) for p in m.group(1).split(".")) if m else None


def vstr(t):
    return ".".join(str(p) for p in t) if t else None


def github_releases(repo, cache):
    if repo in cache:
        return cache[repo]
    req = urllib.request.Request("https://api.github.com/repos/%s/releases?per_page=100" % repo,
                                 headers={"Accept": "application/vnd.github+json", "User-Agent": "homelab-update"})
    if os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.load(resp)
        cache[repo] = sorted({t for t in (vtuple(r["tag_name"]) for r in data
                                          if not r.get("draft") and not r.get("prerelease")) if t})
    except Exception as exc:  # network, rate limit: report it, keep going
        cache[repo] = exc
    return cache[repo]


def assess(spec, fact, cache):
    """One component on one host: running vs upstream."""
    row = {"name": spec["name"], "running": fact.get("running"), "details": fact.get("details") or {},
           "apply": spec.get("apply", ""), "latest": None, "status": "ok", "note": ""}
    if fact.get("parts") is not None:  # Pi-hole reports its own latest versions
        behind = [p for p in fact["parts"] or [] if p["current"] != p["latest"]]
        row["latest"] = ", ".join("%s %s" % (p["part"], p["latest"]) for p in fact["parts"] or [])
        row["status"] = "update" if behind else ("ok" if fact["parts"] else "unknown")
        return row
    upstream = spec.get("upstream") or {}
    if not upstream.get("github"):
        row["status"] = "os"  # follows the OS packages
        return row
    running = vtuple(row["running"])
    if row["running"] is None:
        row["status"], row["note"] = "absent", "not installed or not running"
        return row
    releases = github_releases(upstream["github"], cache)
    if isinstance(releases, Exception):
        row["status"], row["note"] = "unknown", "GitHub lookup failed: %s" % releases
        return row
    if not running or not releases:
        row["status"], row["note"] = "unknown", "cannot compare %r" % row["running"]
        return row
    newest = releases[-1]
    if upstream.get("track") == "minor":
        line = [r for r in releases if r[:2] == running[:2]]
        target = line[-1] if line else running
        if newest[:2] != running[:2]:
            row["note"] = "newer line: %s" % vstr(newest)
    else:
        target = newest
    row["latest"] = vstr(target)
    row["status"] = "update" if target > running else "ok"
    return row


def main():
    data = json.load(sys.stdin)
    now = datetime.datetime.now().astimezone()
    cache, plan = {}, {"generated": now.isoformat(timespec="seconds"), "phase": data["phase"], "hosts": {},
                       "components": [], "untracked_containers": [], "untracked_guests": [], "summary": []}
    guests = data.get("guests") or []
    if isinstance(guests, dict):  # pvesh failed on the node
        plan["guest_error"] = guests.get("error")
        guests = []

    for name, host in data["hosts"].items():
        facts = host.get("facts")
        entry = {"reachable": facts is not None, "kind": host["kind"], "actions": [], "problems": []}
        plan["hosts"][name] = entry
        if facts is None:
            entry["problems"].append("unreachable")
            continue
        upg = facts["apt"]["upgradable"]
        entry.update({
            "os": facts["os"], "pending": len(upg), "security": sum(1 for p in upg if p["security"]),
            "packages": [p["name"] for p in upg], "apt_errors": facts["apt"]["errors"],
            "reboot": facts["reboot"]["reasons"], "restart": facts["restart_units"],
            "health": facts["health"],
        })
        if upg:
            entry["actions"].append("apt")
        if entry["reboot"] or entry["restart"]:
            entry["actions"].append("reboot")
        if not facts["health"]["ok"]:
            entry["problems"] += facts["health"]["failures"]
        if entry["apt_errors"]:
            entry["problems"] += ["apt: " + e for e in entry["apt_errors"]]

        # Proxmox identity: snapshots and container reboots act on the guest
        # found here — exactly one, by name and type.
        if host["kind"] in ("vm", "lxc"):
            want = "qemu" if host["kind"] == "vm" else "lxc"
            match = [g for g in guests if g.get("name") == host.get("proxmox_name") and g.get("type") == want]
            entry["guest"] = match[0] if len(match) == 1 else None
            if len(match) != 1:
                why = (": " + plan["guest_error"]) if plan.get("guest_error") else (
                    "; no guest list: add the Proxmox node to proxmox_hosts (update/proxmox.yml)" if not guests else "")
                entry["problems"].append("%d %s guests named %r on Proxmox (need exactly 1)%s" % (
                    len(match), want, host.get("proxmox_name"), why))

        claimed = set()
        for spec, fact in zip(host["components"], facts["components"]):
            row = dict(assess(spec, fact, cache), host=name)
            plan["components"].append(row)
            claimed.update(fact.get("containers") or [])
            if row["status"] == "update" and spec.get("apply_role"):
                entry["actions"].append("component:" + spec["name"])
        for c in facts.get("containers") or []:
            if isinstance(c, dict) and c["name"] not in claimed:
                plan["untracked_containers"].append({"host": name, "name": c["name"], "image": c["image"]})

    if data.get("check_untracked_guests"):
        known = set(data.get("guests_elsewhere") or []) | {
            h.get("proxmox_name") for h in data["hosts"].values() if h.get("proxmox_name")}
        plan["untracked_guests"] = [g for g in guests if g.get("name") not in known]

    # Summary for the terminal.
    s = plan["summary"]
    s.append("Update report (%s), %s" % (plan["phase"], plan["generated"]))
    for name, e in plan["hosts"].items():
        if not e["reachable"]:
            s.append("%-14s UNREACHABLE" % name)
            continue
        line = "%-14s %-28s %3d pending (%d security)" % (name, e["os"][:28], e["pending"], e["security"])
        if e["reboot"]:
            line += "; reboot: " + "; ".join(e["reboot"])
        if e["restart"]:
            more = len(e["restart"]) - 5
            line += "; restart: " + ", ".join(e["restart"][:5]) + (" +%d more" % more if more > 0 else "")
        shown = ", ".join("%s %s" % (k, v) for k, v in e["health"]["report"].items() if v is not None)
        if shown:
            line += "  [%s]" % shown
        s.append(line)
        s += ["%-14s   ! %s" % ("", p) for p in e["problems"]]
    s.append("")
    for r in plan["components"]:
        mark = {"ok": "ok", "update": "UPDATE", "os": "(apt)", "absent": "-", "unknown": "?"}[r["status"]]
        line = "%-7s %-14s %-36s %-22s" % (mark, r["host"], r["name"][:36], r["running"] or "-")
        if r["status"] == "update":
            line += " -> %s  [%s]" % (r["latest"], r["apply"])
        if r["note"]:
            line += "  (%s)" % r["note"]
        details = ", ".join("%s %s" % (k, v) for k, v in r["details"].items() if v)
        if details:
            line += "  [%s]" % details
        s.append(line.rstrip())
    for c in plan["untracked_containers"]:
        s.append("UNTRACKED container %s on %s (%s): add it to update_components" % (c["name"], c["host"], c["image"]))
    for g in plan["untracked_guests"]:
        s.append("UNTRACKED guest %s %s (%s): no repo's update procedure covers it" % (g["type"], g["vmid"], g["name"]))

    # Default: reports/ in the directory ansible-playbook runs from (the
    # consumer's tree), never the collection's own directory.
    report_dir = data.get("report_dir") or os.path.join(os.getcwd(), "reports")
    os.makedirs(report_dir, exist_ok=True)
    body = json.dumps(plan, indent=1)
    for fname in (now.strftime("%Y%m%d-%H%M%S-") + plan["phase"] + ".json", "latest.json"):
        with open(os.path.join(report_dir, fname), "w", encoding="utf-8") as f:
            f.write(body + "\n")
    print(json.dumps(plan))


if __name__ == "__main__":
    main()
