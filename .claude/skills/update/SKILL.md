---
name: update
description: Update core's machines — the Pi-hole container and the Proxmox host — with core's own update procedure (colac.homelab.update), including reboots and the Proxmox host reboot. Use when asked to update, patch or reboot Pi-hole or the Proxmox host, or when the homelab-update skill gets to core.
---

# Update core: Pi-hole and the Proxmox host

The procedure and its rules are in [docs/UPDATES.md](../../../docs/UPDATES.md);
this is how to run it. Everything runs from this repo, with SSH keys only (no
secrets, never `sops-exec`). TrueNAS has its own skill, `truenas-update`.

## Commands

Run each one as a background job, with its output in a log file in the
scratchpad, and tell the user the log path so they can `tail -f` it. Use
`mise -C ~/git-repos/homelab-proxmox run …`, never `cd` in parallel calls: they
share the shell's working directory and race.

| Step | Command | Changes |
|---|---|---|
| Report | `mise run update` | Nothing (apt's lists only). JSON in `updates/reports/latest.json` |
| Pi-hole | `mise run update:apply` | Snapshot, apt, `pihole -up`, health |
| Proxmox packages | add `-e update_allow_pve=true` | apt on the host. No reboot |
| Guest reboots | add `-e update_reboot=true` | Restarts Pi-hole when it needs it (a new library or kernel) |
| Host reboot | add `-e update_reboot_pve=true` | Reboots the host last, after Pi-hole |

The host reboot restarts every guest, including monitoring's and workloads'
VMs. So:

- Run it only after every other repo's update has finished: snapshots and
  reboots in flight would be cut off.
- It refuses while a running guest does not start at boot, and waits until
  every guest that was running runs again.
- Afterwards, run `mise run update` in monitoring and workloads (their own
  skills) to see their health; core only checks that their guests started.

## Reading the result

- `PLAY RECAP` with `failed=0` and `<host> is healthy.` per host: done.
- The "Update report (after)" lines say what is still pending: packages, a
  reboot (with the reason), services running replaced libraries, components
  with a newer release.
- On a failure the run stops at that host, and later hosts are untouched. The
  message names the snapshot and prints the rollback command
  (`pct rollback <vmid> <snapshot>` on the Proxmox host). Never roll back
  yourself: show the user the failing task and the command.

## Asking first

The user's request decides. "Update" covers the report, apply and guest
reboots. Upgrading the Proxmox host's packages and rebooting the host need it
said explicitly in the request, or a yes after you show the report.
