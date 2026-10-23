# Plan: TrueNAS as code

Status: **in progress** (2026-10-16). Built in `TrueNAS/ansible/` (role,
module, backup and self-test playbooks); `group_vars` filled from discovery
and checked offline against it. Next: RUNBOOK A4 onwards on the live NAS.
This file is the brief for picking
the work up later; delete it once `TrueNAS/ansible/` exists and the README
describes the result.

## The decision

TrueNAS is rebuilt from **documentation + an Ansible playbook**, not from a
config backup file.

- **Manual and documented** (`TrueNAS/README.md`): install, BIOS, pool creation,
  and the settings that live only in TrueNAS's config database (below).
- **Declared in Ansible** (`TrueNAS/ansible/`): users, groups, datasets, SMB and
  NFS shares, periodic snapshot tasks, and the off-site copy task. A new share
  or user is a change to `group_vars`, not a click in the UI.
- **Recovery** = reinstall → import the pool → manual steps → `mise run truenas:play`.
  The pool carries the data, dataset ACLs and snapshots across a reinstall.

Not chosen: a nightly config backup pulled to the Proxmox host. It is no longer
the recovery path; see "Config export" for the two rules that replace it.

## Rules the implementation must follow

1. **Only through TrueNAS's API.** Every task is `midclt call …` over SSH
   (as `truenas_admin`, no sudo). Never install packages or edit files on TrueNAS:
   its system disk is read-only and updates reset OS changes (the same reason
   monitoring's netdata step keeps getting undone).
2. **Pin every UID and GID.** Pool files are owned by numbers. A user
   recreated with a different UID loses access to its own files. Values come
   from the live system (discovery, below), never invented.
3. **Query, then create or update** — the role's idempotency. `--check --diff`
   must work.
4. **Managed means code-only.** Anything the playbook declares is not edited in
   the UI, or the two will fight (the same rule as Pi-hole).
5. **Not automated:** pool and disk creation (one-time, destructive).

Not using `arensb.truenas` (checked 2026-10-09): no modules for Cloud Sync,
replication or API keys; open bugs on 25.10 (SMB share updates, certificate
authority); single maintainer. A small role in this repo is less work than
working around it.

## Layout

```text
TrueNAS/
  README.md            install + manual settings + "run the playbook"
  ansible/
    ansible.cfg
    inventory/
      hosts.yml            truenas, 192.168.1.214, ansible_user truenas_admin
      group_vars/truenas.yml   users, groups, datasets, shares, tasks
    playbooks/site.yml
    roles/truenas/         query → create/update via midclt
  secrets.yaml           (SOPS) SMB passwords of new users
mise.toml              truenas:play / truenas:inventory tasks
```

The Nextcloud SMB user's password is in workloads' `nextcloud/secrets.yaml`
today. Once TrueNAS creates that user, core is the source and workloads holds a
copy — record that in `docs/CREDENTIALS.md`.

## Manual settings to document (config-database only)

Network, hostname, certificates, API keys, alert settings and mail, SMART and
scrub schedules, NTP and timezone, UPS, installed apps. Plus the one-time
export rules below.

## Config export

- **Once now**, before any of this starts: System → Advanced → Manage
  Configuration → Download File, **with the secret seed**. Store it in the
  password manager, not in git.
- **Again after any UI change that is not in the playbook.**

## Steps

1. **Discovery (read-only).** On TrueNAS, run the command below and save the
   output. It picks fields, so no password hashes are printed.
2. **Version and sudo.** Done: 25.10.7; `midclt` works without sudo.
3. **ACLs.** For each share path from step 1: `midclt call filesystem.getacl
   '"/mnt/<path>"'`. Needed only for shares the playbook will create.
4. **Write `group_vars`** from the discovery output: users and groups with
   their current UID and GID, datasets, shares, snapshot tasks.
5. **Write the role.** One "ensure" pattern per object type: `<x>.query` with
   a filter, then `<x>.create` or `<x>.update` only when fields differ. Check
   each method's arguments against the installed version's API docs (they
   changed across 24.04 → 25.10, e.g. NFS `path` vs `paths`, SMB share fields).
6. **Acceptance test 1 — no changes.** `mise run truenas:play --check --diff`
   against the live box must report **nothing to change**. That proves the
   code matches reality.
7. **Acceptance test 2 — lifecycle.** Add a temporary `ansible-test` user,
   dataset and SMB share; apply; check from a client; change one field; apply;
   then `state: absent`, apply, and confirm everything is gone.
8. **Off-site task.** Add once chosen: Backblaze B2 Cloud Sync (credentials
   in SOPS) or replication to a USB disk.
9. **Rewrite `TrueNAS/README.md`** and delete this file.

### Discovery command

Moved to [`RUNBOOK.md` § A3](RUNBOOK.md#a3-discovery-read-only), which is the
step-by-step order for adopting the live system and for rebuilding it.

## Decided since

- **Backup disk (2026-10-09):** the old Synology's ~1.9 TB USB disk becomes a
  ZFS pool (`backup-usb`) on TrueNAS, fed by a local **Replication Task** from
  the daily **Periodic Snapshot Task** on `hdd-home-1/media`. Unplugged
  (pool exported) and stored elsewhere between weekly runs, so it doubles as
  the off-site/offline copy. No cloud spend. The Ansible role declares both
  tasks; creating the pool stays manual (destructive). Headroom: ~1.3 TB used
  of ~1.9 TB, growing ~200 GB per trip — revisit when it passes 80%.
- **Old Synology (DS220j):** kept powered off with its disks intact as a cold
  archive of the pre-migration data (Familia verified complete on TrueNAS by
  name and size on 2026-10-09). Power it on every ~6 months to check it boots.

## Discovery findings (2026-10-16, TrueNAS-25.10.7)

- **Declared:** groups `nextcloud_user` (3000), `home_user` (3001),
  `smb_users` (3002); users `nextcloud_user` (3000) and `home_user` (3001),
  both in `smb_users` and `builtin_users`; datasets `hdd-home-1/media`,
  `media/hugo`, `media/marta` (both ~empty); SMB share `media`.
- **Share access is the ACL** on `/mnt/hdd-home-1/media`: owner `root:root`,
  `builtin_administrators` (544) FULL_CONTROL, `smb_users` (3002) MODIFY, all
  inherited. It lives on the pool, so it survives a reinstall.
- **`backup-usb` already exists** (encrypted, online, empty): RUNBOOK A6 done.
  TrueNAS added a weekly scrub task for it.
- **No snapshot tasks existed** before the playbook: no point-in-time copies.
- **`smart.test.query` does not exist** in 25.10; SMART schedules are not
  in the discovery.
- **Manual settings to fix (UI):** SSH is running but **not set to start
  automatically** — after a reboot Ansible cannot connect. DNS server 1 is
  `192.168.1.53`, not the Pi-hole (`192.168.1.153`). Both NICs use DHCP, so
  `.214` depends on the router's reservation.

## Open decisions

- ~~Sudo for `truenas_admin`~~ — not needed (2026-10-11): `midclt` as
  `truenas_admin` works without sudo on 25.10.7, so the playbooks never
  escalate. Its sudo keeps its password.
- **Data ownership.** The migrated files under `media/Familia` are owned by
  `truenas_admin:root`, mode `770`, with one folder owned by `home_user`. That
  came from the copy, not from a design. Decide the owning users or family
  group, declare them (with fixed UIDs/GIDs), and fix ownership and ACLs once,
  before the playbook takes over.

## Related work, decided in the same session

- **Proxmox host to Ansible**: replace `proxmox/configure.sh` and `backup.sh`
  with `proxmox/ansible/` (roles `pve_access`, `pve_media`, `pve_backup`),
  run as root over SSH with `pveum`/`pvesh` (the `community.proxmox` modules
  need an API token to exist first). Scripts become role templates; systemd
  timers run them.
- **Nextcloud Borg**: NFS dataset on TrueNAS (declared by this playbook) mounted
  on the Nextcloud VM; the change is already described in workloads'
  `nextcloud/README.md`.
- **`docs/RECOVERY.md`** in core: restore order and which backup and key each
  step needs.
- **The age private key and the Borg passphrase** belong in the password
  manager; without the age key, every `secrets.yaml` and every encrypted
  backup is unreadable.
