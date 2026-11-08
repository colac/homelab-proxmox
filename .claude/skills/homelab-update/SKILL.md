---
name: homelab-update
description: Update the whole homelab — Nextcloud VM, monitoring VM, Pi-hole, Proxmox host, TrueNAS — by running each repo's own update skill in a safe order, watching every run and reporting the outcome. Use when asked to update or patch the homelab, check for (security) updates, or run "the update".
---

# Update the whole homelab

Each repo owns its machines and its procedure (core's `docs/UPDATES.md`). This
skill holds no update logic of its own: it runs the per-repo skills in order
and watches them. Read each one before its step:

| Repo | Skill file | Covers |
|---|---|---|
| workloads | `~/git-repos/homelab-proxmox-workloads/.claude/skills/update/SKILL.md` | Nextcloud VM, AIO, Caddy pin |
| monitoring | `~/git-repos/homelab-proxmox-monitoring/.claude/skills/update/SKILL.md` | Monitoring VM, Elastic and exporter pins |
| core | `~/git-repos/homelab-proxmox/.claude/skills/update/SKILL.md` | Pi-hole, Proxmox host |
| core | `~/git-repos/homelab-proxmox/.claude/skills/truenas-update/SKILL.md` | TrueNAS |

## 1. Check the repos

Each repo should be on `main`, clean and up to date (`git fetch`, then
`git status -sb`). Report anything else. Never run a procedure from a
half-finished branch without saying so: its inventory is what runs.

## 2. Report: change nothing

Run every report, one after the other: `mise run update` in core, monitoring
and `workloads … nextcloud`, plus the TrueNAS report. Never as parallel shell
calls, because they share the working directory and race. Then summarize, per
host:

- pending packages and how many are security updates;
- reboots due (and why);
- components with a newer release;
- pins to bump.

For pins, read the release notes and say which security issues each bump
fixes. Recommend what to do.

## 3. Confirm once

Ask once, with the plan, before changing anything that the request did not
name. "Update everything" covers OS packages, AIO, Pi-hole and guest reboots.
The Proxmox host's packages, the host reboot and the TrueNAS update need the
request to say so, or a yes now.

## 4. Apply, in this order

1. **Guests.** Workloads `update:apply nextcloud`, monitoring `update:apply`,
   core `update:apply` (Pi-hole, plus `-e update_allow_pve=true` for the
   host's packages). Workloads and monitoring may run at the same time, as
   background jobs with separate logs.
2. **Guest reboots.** The same commands with `-e update_reboot=true`.
3. **Proxmox host reboot, last**, and only after every other run has
   finished: core `update:apply -e update_reboot=true -e update_reboot_pve=true`.
   Then run the monitoring and workloads reports again to confirm their
   health.
4. **TrueNAS**, with its skill. Its reboot interrupts NFS and SMB, so do it
   after the VMs are back.
5. **Pins.** Bump on branches and lint, then give the user the plays to run,
   since they need credentials. Report the result after they run them.

## Watching the runs

- Start each run with `run_in_background`, writing to a log in the scratchpad.
  Give the user every log path so they can `tail -f` it. You are woken when a
  job exits, so don't poll, and don't start a sub-agent to watch.
- After each job, read its `PLAY RECAP` and the "Update report (after)"
  lines, and say what changed and what is still pending.
- On a failure, stop: later steps wait. Show the failing task and the
  rollback command the run printed, and let the user decide.

## Finish

End with one table per host: before → after (packages, kernel, component
versions), what is still pending, and the snapshots that were taken. Then
list the branches waiting for a commit or the user's plays.
