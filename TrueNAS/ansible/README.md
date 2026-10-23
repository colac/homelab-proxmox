# TrueNAS — declared configuration

Users, groups, datasets, SMB/NFS shares, periodic snapshot tasks and the USB
backup's replication task, declared in
[`inventory/group_vars/truenas.yml`](inventory/group_vars/truenas.yml) and
applied through TrueNAS's own API. The plan and its reasoning are in
[`../ANSIBLE-PLAN.md`](../ANSIBLE-PLAN.md); the step-by-step order — adopting
the live NAS, rebuilding it, restoring the data — is
[`../RUNBOOK.md`](../RUNBOOK.md).

**Requirements:** TrueNAS installed, its pools created by hand
([`../README.md`](../README.md)), and `~/.ssh/truenas_admin` as
`truenas_admin`'s SSH login. Nothing is installed on TrueNAS.

```bash
mise run truenas:inventory
mise run truenas:play playbooks/site.yml --check --diff   # what would change
mise run truenas:play playbooks/site.yml                  # apply
mise run truenas:play playbooks/20-backup-usb.yml         # back up to the USB disk now
mise run truenas:play playbooks/90-selftest.yml           # prove the module on throwaway objects
```

No sudo and no password: TrueNAS runs a local `midclt` call with the calling
user's roles, and `truenas_admin` is a full admin.

## How it works

Every task is the role's own module,
[`truenas_object`](roles/truenas/library/truenas_object.py). It runs on
TrueNAS and calls `midclt`, the middleware client:

1. `<namespace>.query` with filters that pick one object (a user by
   `username`, a share by `name`, …).
2. Missing → `<namespace>.create`. Present → compare **only the declared
   fields** and `<namespace>.update` the ones that differ. Nothing to do → no
   change.
3. `state: absent` → `<namespace>.delete`.

Each item in `group_vars` uses **the API's own field names** (v25.10,
<https://api.truenas.com/v25.10/>), so the API reference is the documentation
for every field. The module adds four things:

| Rule | Why |
|---|---|
| `uid` and `gid` are **immutable**: a mismatch fails the run | Pool files are owned by number; re-numbering a user locks them out of their files |
| Deleting a **dataset** also needs `allow_delete: true` | It deletes the data |
| Passwords are only ever sent on **create**, and never shown | Changing a password is done in the UI (or a new `password_env`) |
| A user's `group`/`groups` and a replication's `periodic_snapshot_tasks` are written as **names** | The module resolves them to API ids |

**Managed means code-only.** Anything declared here is changed here, not in
the UI — the next run would put it back.

## The USB backup

`backup-usb` is a ZFS pool on the ~1.9 TB USB disk, **created by hand,
encrypted with a key** (Storage → Create Pool → Encryption; download the key
into the password manager). The disk is stored away from the house and
plugged in for a run:

1. Plug in; Storage → Import Pool → `backup-usb`.
2. `mise run truenas:play playbooks/20-backup-usb.yml` — checks the pool is
   online, the tasks exist and there is a snapshot to send, runs the
   replication, then fails unless every dataset on the pool is encrypted. It
   sends the latest daily (01:00) snapshot, so the copy is at most a day old.
3. Storage → `backup-usb` → Export/Disconnect (keep the data); unplug.

The replication task has `auto: false`: with the disk away most of the time,
a scheduled run would fail and alert daily. Source snapshots are kept 8 weeks,
so a run after a month away is still incremental; the task never replicates
"from scratch", which would wipe the backup first.

## Tests

- **Offline:** the module was exercised against a fake `midclt` that returns
  TrueNAS's query shapes (ZFS properties as `{value, rawvalue, parsed}`, a
  user's group as an object): create → no-op repeat → update → guards →
  delete, plus `site.yml` and `20-backup-usb.yml` end to end.
- **Live, once:** `90-selftest.yml` repeats the lifecycle on real TrueNAS with
  throwaway `ansible-test` objects (UID/GID 39999, dataset
  `hdd-home-1/ansible-test`) and removes them, also on failure.
- **Every change:** `--check --diff` against the live system must report no
  changes for anything already in place.
