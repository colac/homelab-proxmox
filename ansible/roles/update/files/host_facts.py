#!/usr/bin/env python3
"""Everything the update procedure needs to know about one host, as JSON.

Read-only, except that `refresh` runs `apt-get update` (package lists only).
The single argument is the configuration as base64-encoded JSON:

  refresh         bool   refresh apt's package lists first
  health_only     bool   only run the health checks (used while waiting)
  components      list   update_components entries for this host
  checks          list   update_checks for this host
  proxmox_guests  bool   list the node's VMs and containers (Proxmox host)
  guests_only     bool   only list them: the node is not one of this repo's
                         update targets, but its guest list identifies them

Python 3 standard library only: it runs on Debian, Ubuntu and Proxmox as-is.
"""
import base64
import json
import os
import re
import shutil
import socket
import subprocess
import sys


def run(cmd, timeout=120):
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
        return proc.returncode, proc.stdout, proc.stderr
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, "", str(exc)


def natural(version):
    return [int(p) if p.isdigit() else p for p in re.split(r"(\d+)", version)]


def in_container():
    rc, out, _ = run(["systemd-detect-virt", "--container"])
    return rc == 0 and out.strip() not in ("", "none")


def os_name():
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            pairs = dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)
        return pairs.get("PRETTY_NAME", "").strip('"')
    except OSError:
        return ""


def apt(refresh):
    result = {"errors": [], "upgradable": []}
    if not shutil.which("apt-get"):
        result["errors"].append("apt-get not found")
        return result
    if refresh:
        rc, out, err = run(["apt-get", "update", "-q"], timeout=600)
        result["errors"] = [l.strip() for l in (out + err).splitlines() if l.startswith(("E:", "Err:"))]
        if rc != 0 and not result["errors"]:
            result["errors"].append("apt-get update exited %d" % rc)
    held = held_back()
    _, out, _ = run(["apt", "list", "--upgradable"])
    for line in out.splitlines():
        # name/suite1,suite2 version arch [upgradable from: old]
        m = re.match(r"^(\S+?)/(\S+)\s+(\S+)\s+\S+\s+\[upgradable from: ([^\]]+)\]", line)
        if m:
            result["upgradable"].append({"name": m[1], "suites": m[2], "version": m[3], "from": m[4],
                                         "security": "security" in m[2], "held": held.get(m[1])})
    return result


def held_back():
    """Upgradable packages apt would not install now, with the reason.

    `apt list --upgradable` includes Ubuntu's phased updates, which apt
    defers until the rollout reaches this machine, and packages it keeps back
    (unresolvable). apt full-upgrade installs neither, so the report must not
    count them as pending. A simulation lists both.
    """
    _, out, _ = run(["apt-get", "-s", "-o", "Debug::NoLocking=1", "dist-upgrade"], timeout=300)
    held, reason = {}, None
    for line in out.splitlines():
        if line.startswith("The following") and line.rstrip().endswith(":"):
            reason = ("phased" if "phasing" in line else "kept back" if "kept back" in line else None)
        elif reason and line.startswith(" "):
            for name in line.split():
                held[name.split(":")[0]] = reason
        else:
            reason = None
    return held


def reboot():
    reasons = []
    if os.path.exists("/run/reboot-required"):
        pkgs = ""
        try:
            with open("/run/reboot-required.pkgs", encoding="utf-8") as f:
                pkgs = " (" + ", ".join(sorted(set(f.read().split()))) + ")"
        except OSError:
            pass
        reasons.append("the OS asks for it" + pkgs)
    container = in_container()
    running = os.uname().release
    kernels = []
    if not container and os.path.isdir("/boot"):
        kernels = [n[len("vmlinuz-"):] for n in os.listdir("/boot") if n.startswith("vmlinuz-")]
    newest = max(kernels, key=natural) if kernels else None
    if newest and newest != running:
        reasons.append("kernel %s installed, %s running" % (newest, running))
    return {"reasons": reasons, "container": container, "kernel_running": running, "kernel_newest": newest}


def restart_units():
    """systemd services still running code from a library that apt replaced."""
    units = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/maps" % pid, encoding="utf-8", errors="replace") as f:
                stale = any("(deleted)" in l and re.search(r"\.so(\.|\s)", l) and "memfd:" not in l for l in f)
            if not stale:
                continue
            with open("/proc/%s/cgroup" % pid, encoding="utf-8") as f:
                # This host's system services only: the path must start at
                # /system.slice, which leaves out user sessions and, on a
                # Proxmox host, its guests' processes (/lxc/<id>/…, /qemu.slice/…).
                found = re.findall(r"^\d+:[^:]*:/system\.slice/(?:[^/\s]+/)*?([^/\s]+\.service)$",
                                   f.read(), re.MULTILINE)
        except OSError:
            continue
        if found:
            units.add(found[-1])
    return sorted(units)


def containers():
    if not shutil.which("docker"):
        return None
    rc, out, err = run(["docker", "ps", "-a", "--format", "{{json .}}"])
    if rc != 0:
        return {"error": err.strip() or "docker ps exited %d" % rc}
    rows = []
    for line in out.splitlines():
        d = json.loads(line)
        status = d.get("Status", "")
        health = None
        for marker, value in (("(healthy)", "healthy"), ("(unhealthy)", "unhealthy"), ("(health: starting)", "starting")):
            if marker in status:
                health = value
        rows.append({"name": d.get("Names", ""), "image": d.get("Image", ""), "state": d.get("State", ""),
                     "status": status, "health": health})
    return rows


def extract(text, pattern):
    text = text.strip()
    if pattern:
        m = re.search(pattern, text, re.MULTILINE)
        return m.group(1) if m else None
    return text.splitlines()[0].strip() if text else None


def read_value(spec, rows):
    """A version or detail: from an image tag, a command in a container, or on the host."""
    if "image_tag_of" in spec:
        for c in rows or []:
            if c["name"] == spec["image_tag_of"]:
                image = c["image"].split("@")[0]
                return image.rsplit(":", 1)[1] if ":" in image.rsplit("/", 1)[-1] else "latest"
        return None
    if "exec" in spec:
        rc, out, _ = run(["docker", "exec"] + list(spec["exec"]))
    elif "command" in spec:
        rc, out, _ = run(list(spec["command"]))
    else:
        return None
    return extract(out, spec.get("pattern")) if rc == 0 else None


def pihole_versions():
    """`pihole -v`: v6 prints a section per part, older versions one line each."""
    if not shutil.which("pihole"):
        return None
    rc, out, _ = run(["pihole", "-v"])
    if rc != 0:
        return None
    parts, section = [], None
    for line in out.splitlines():
        if line and not line[0].isspace() and "version" not in line.lower():
            section = line.strip()
        m = re.search(r"(?:(\S+) )?[Vv]ersion is (\S+) \(Latest: (\S+)\)", line)
        if m:
            parts.append({"part": m[1] if m[1] and m[1].lower() != "version" else section,
                          "current": m[2], "latest": m[3]})
    return parts


def component(spec, rows):
    result = {"name": spec["name"]}
    version = spec.get("version", {})
    if version.get("pihole"):
        result["parts"] = pihole_versions()
        result["running"] = ", ".join("%s %s" % (p["part"], p["current"]) for p in result["parts"] or [])
    else:
        result["running"] = read_value(version, rows)
    result["details"] = {d["label"]: read_value(d, rows) for d in spec.get("details", [])}
    if spec.get("containers") and rows is not None:
        result["containers"] = [c["name"] for c in rows if re.search(spec["containers"], c["name"])]
    return result


def check(spec, rows):
    """One health check; returns a list of failures (empty means healthy)."""
    failures, report = [], {}
    if "systemd" in spec:
        for unit in spec["systemd"]:
            _, out, _ = run(["systemctl", "is-active", unit])
            if out.strip() != "active":
                failures.append("%s is %s" % (unit, out.strip() or "unknown"))
    if "port" in spec:
        try:
            with socket.create_connection((spec.get("address", "127.0.0.1"), spec["port"]), timeout=5):
                pass
        except OSError as exc:
            failures.append("nothing answers on port %s (%s)" % (spec["port"], exc))
    if "containers" in spec:
        by_name = {c["name"]: c for c in rows or []}
        for name in spec["containers"]:
            c = by_name.get(name)
            if c is None:
                failures.append("container %s does not exist" % name)
            elif c["state"] != "running":
                failures.append("container %s is %s" % (name, c["state"]))
            elif c["health"] in ("unhealthy", "starting"):
                failures.append("container %s is %s" % (name, c["health"]))
    if "command_json" in spec:
        rc, out, err = run(list(spec["command_json"]))
        try:
            data = json.loads(out) if rc == 0 else None
        except ValueError:
            data = None
        if data is None:
            failures.append("%s failed: %s" % (" ".join(spec["command_json"][:6]), (err or out).strip()[:200]))
        else:
            for key, want in spec.get("expect", {}).items():
                if data.get(key) != want:
                    failures.append("%s is %s, expected %s" % (key, json.dumps(data.get(key)), json.dumps(want)))
            report = {k: data.get(k) for k in spec.get("report", [])}
    return failures, report


def health(checks, rows):
    failures, report = [], {}
    for spec in checks:
        f, r = check(spec, rows)
        failures += f
        report.update(r)
    for c in rows or []:
        if c["state"] == "running" and c["health"] == "unhealthy":
            msg = "container %s is unhealthy" % c["name"]
            if msg not in failures:
                failures.append(msg)
    return {"ok": not failures, "failures": failures, "report": report}


def proxmox_guests():
    rc, out, err = run(["pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"])
    if rc != 0:
        return {"error": err.strip()}
    return [{"vmid": g.get("vmid"), "name": g.get("name"), "type": g.get("type"), "node": g.get("node"),
             "status": g.get("status")} for g in json.loads(out) if not g.get("template")]


def main():
    cfg = json.loads(base64.b64decode(sys.argv[1]).decode()) if len(sys.argv) > 1 else {}
    if cfg.get("guests_only"):
        print(json.dumps({"proxmox_guests": proxmox_guests()}))
        return
    rows = containers()
    container_rows = rows if isinstance(rows, list) else []
    out = {"health": health(cfg.get("checks", []), container_rows)}
    if not cfg.get("health_only"):
        out.update({
            "os": os_name(),
            "apt": apt(cfg.get("refresh", False)),
            "reboot": reboot(),
            "restart_units": restart_units(),
            "containers": rows,
            "components": [component(c, container_rows) for c in cfg.get("components", [])],
        })
        if cfg.get("proxmox_guests"):
            out["proxmox_guests"] = proxmox_guests()
    print(json.dumps(out))


if __name__ == "__main__":
    main()
