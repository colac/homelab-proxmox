---
name: truenas-update
description: Check for and install TrueNAS updates with a way back — config backup with the secret seed, pre-update pool snapshots, the running boot environment kept — then reboot and verify. Use when asked to update TrueNAS or the NAS, check whether TrueNAS has an update, or roll a TrueNAS update back, or when the homelab-update skill gets to TrueNAS.
---

# Update TrueNAS

The procedure is `TrueNAS/ansible/playbooks/30-update.yml`, and
[TrueNAS/RUNBOOK.md § D](../../../TrueNAS/RUNBOOK.md#d-updates) is its
reference, rollback included. It runs over SSH as `truenas_admin` with no sudo
and no secrets.

## Before you start

- **The SSH key.** If a call fails with `agent refused operation`, the user's
  ssh agent has locked the `truenas_admin` key. Ask them to unlock it; never
  work around it.
- **How to run.** Use `mise -C ~/git-repos/homelab-proxmox run …`, as
  background jobs with the output in a scratchpad log, and give the user the
  path to `tail -f`.

## Steps

1. **Report:** `mise run truenas:update`. It changes nothing. Summarize:
   - the running version and the update profile;
   - any pending version, with the security part of its release notes;
   - the boot environments (active, kept);
   - pool states, running jobs and services.
2. **Ask** before installing, unless the request said to update TrueNAS: the
   reboot takes SMB down for 5–10 minutes. If the `backup-usb` pool is
   imported, say so. The disk should be exported and stored away between
   backups.
3. **Apply:** `mise run truenas:update:apply`.
   - It refuses while a pool is unhealthy or scrubbing, or a job runs. Report
     which, and wait or let the user decide.
   - It takes the backups, installs, reboots, and waits for a new boot and the
     services. Expect 10–30 minutes, mostly the download.
   - A failure before the reboot changes nothing: TrueNAS still runs the old
     version.
4. **After it:**
   - the final message lists the three ways back;
   - remind the user to redo monitoring's netdata Graphite step, which an
     update resets;
   - run `mise run truenas:play playbooks/site.yml --check --diff`, which
     should report no changes. The exception is `enabled: false → true` on
     `media-to-backup-usb` while the USB disk is exported: the export disabled
     the task and the import enables it again, so don't apply that change;
   - run `mise run truenas:update` again, which should report no update.

`mise run truenas:update:backup` takes the backups alone, for example before
risky manual work in the UI.

## Rolling back

Only on the user's word. Show them the command from the runbook's table and
let them choose:

- **The OS:** activate the previous boot environment, then reboot.
- **Files:** copy them back from `.zfs/snapshot/preupdate-…/`.
- **A whole dataset:** `pool.snapshot.rollback`. It is destructive.
- **A reinstall:** upload the config tar.

Never roll back `.system`, and never run a rollback yourself.
