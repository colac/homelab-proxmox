# TrueNAS runbook — adopting Ansible, and rebuilding with it

Two procedures:

- **[A. Adopt](#a-adopt-the-running-system-once)** — once: bring the running
  NAS under `TrueNAS/ansible/` without changing anything that works today.
- **[B. Rebuild](#b-rebuild-truenas-from-scratch)** — whenever TrueNAS has to
  be reinstalled: boot disk dead, NAS replaced, or a clean start.
- **[C. Restore the data](#c-restore-the-data-from-the-usb-disk)** — only if
  the data pool itself is lost.

Commands run from the core repo on your laptop unless they say "on TrueNAS".
The playbooks only ever call TrueNAS's API as `truenas_admin` (no sudo).

## A. Adopt the running system (once)

**The rule throughout:** never apply to "see what happens". `--check --diff`
first; if it shows a change you did not expect, stop and fix the declaration.

### A1. Safety net (UI, 5 minutes)

1. **Config export:** System → Advanced → Manage Configuration → Download
   File, **with "Export Password Secret Seed"**. Into the password manager.
2. **Snapshot of the data:** Datasets → `hdd-home-1/media` → Data Protection →
   Create Snapshot, **recursive**, name `before-ansible`. Free, and undoes any
   accident to files. Delete it in a month.

### A2. Check the connection

```bash
ssh -i ~/.ssh/truenas_admin truenas_admin@192.168.1.214 midclt call system.version
mise run truenas:inventory
```

### A3. Discovery (read-only)

Writes `~/truenas-discovery.json` on the laptop. It picks fields, so **no
password hashes, keys or credentials** are included.

```bash
ssh -i ~/.ssh/truenas_admin truenas_admin@192.168.1.214 python3 - > ~/truenas-discovery.json <<'EOF'
import json, subprocess

def q(method, *args):
    out = subprocess.check_output(["midclt", "call", method, *map(json.dumps, args)], text=True).strip()
    try:
        return json.loads(out)
    except ValueError:
        return out  # midclt prints string results raw, e.g. system.version

def pick(rows, keys):
    rows = rows if isinstance(rows, list) else [rows]
    return [{k: r[k] for k in keys if k in r} for r in rows]

def prop(v):
    return v.get("value") if isinstance(v, dict) and "value" in v else v

def flatten(datasets, seen):
    for d in datasets:
        if d["id"] not in seen:
            seen[d["id"]] = {k: prop(d.get(k)) for k in (
                "id", "type", "encrypted", "encryption_root", "comments", "compression", "acltype",
                "aclmode", "atime", "recordsize", "casesensitivity", "sync", "readonly", "snapdir",
                "quota", "refquota", "mountpoint", "used")}
        flatten(d.get("children", []), seen)
    return seen

smb, nfs = q("sharing.smb.query"), q("sharing.nfs.query")
acls = {}
for path in sorted({s["path"] for s in smb} | {s["path"] for s in nfs}):
    try:
        a = q("filesystem.getacl", path)
        acls[path] = {k: a.get(k) for k in ("uid", "gid", "acltype", "trivial", "acl")}
    except Exception as exc:
        acls[path] = {"error": str(exc)}

sections = {
    "version": lambda: q("system.version"),
    "users": lambda: pick(q("user.query"), ["id", "username", "uid", "full_name", "group", "groups", "home", "shell",
                                    "smb", "builtin", "locked", "password_disabled", "ssh_password_enabled",
                                    "sudo_commands", "sudo_commands_nopasswd", "email", "roles"]),
    "groups": lambda: pick(q("group.query"), ["id", "name", "gid", "smb", "builtin", "users", "roles",
                                      "sudo_commands", "sudo_commands_nopasswd"]),
    "datasets": lambda: list(flatten(q("pool.dataset.query"), {}).values()),
    "pools": lambda: pick(q("pool.query"), ["name", "status", "healthy"]),
    "smb_shares": lambda: smb,
    "nfs_shares": lambda: nfs,
    "share_acls": lambda: acls,
    "snapshot_tasks": lambda: q("pool.snapshottask.query"),
    "replication_tasks": lambda: pick(q("replication.query"), ["id", "name", "direction", "transport", "source_datasets",
                                                       "target_dataset", "auto", "enabled"]),
    "cloudsync_tasks": lambda: pick(q("cloudsync.query"), ["id", "description", "path", "direction", "enabled"]),
    "scrub_tasks": lambda: q("pool.scrub.query"),
    "smart_tests": lambda: pick(q("smart.test.query"), ["id", "type", "schedule", "all_disks", "disks", "desc"]),
    "services": lambda: pick(q("service.query"), ["service", "enable", "state"]),
    "smb_config": lambda: pick(q("smb.config"), ["netbiosname", "workgroup", "description", "enable_smb1",
                                         "aapl_extensions", "multichannel", "guest", "bindip"]),
    "nfs_config": lambda: pick(q("nfs.config"), ["servers", "protocols", "bindip", "v4_domain"]),
    "network": lambda: pick(q("network.configuration.config"), ["hostname", "domain", "ipv4gateway",
                                                        "nameserver1", "nameserver2", "nameserver3"]),
    "interfaces": lambda: pick(q("interface.query"), ["name", "type", "ipv4_dhcp", "ipv6_auto", "aliases", "mtu"]),
    "general": lambda: pick(q("system.general.config"), ["timezone", "language", "kbdmap", "ui_httpsport",
                                                 "ui_httpsredirect"]),
}
# One failing call (a method renamed or removed in this version) is recorded,
# not fatal: e.g. smart.test.query does not exist on 25.10.
out = {}
for name, read in sections.items():
    try:
        out[name] = read()
    except Exception as exc:
        out[name] = {"error": str(exc)}
print(json.dumps(out, indent=1, default=str))
EOF
python3 -m json.tool ~/truenas-discovery.json > /dev/null && echo "valid JSON, $(wc -c < ~/truenas-discovery.json) bytes"
```

Then ask Claude (or do it by hand) to fill `inventory/group_vars/truenas.yml`
from it: users and groups **with their current UIDs/GIDs**, datasets, shares.
`truenas_admin` and other built-in accounts stay unmanaged.

### A4. Prove the module on throwaway objects

Creates and removes only `ansible-test` objects (UID/GID 39999, dataset
`hdd-home-1/ansible-test`) — discovery must show none of those exist.

```bash
mise run truenas:play playbooks/90-selftest.yml
```

Expect: `Self-test passed: create, no-op repeat, update, guards and delete
all behave.` Afterwards, nothing named `ansible-test` remains.

### A5. The declaration must match reality

```bash
mise run truenas:play playbooks/site.yml --check --diff
```

Expect **no change** for groups, users, datasets and shares, and **create**
for only the two backup tasks (snapshot + replication), unless those were
already made in the UI. Anything else: stop; the declaration is wrong, not the
NAS — fix `group_vars` and repeat.

### A6. The backup disk (UI, once)

1. Plug the Toshiba disk into TrueNAS.
2. Storage → Create Pool → name **`backup-usb`**, the one disk as **Stripe**,
   **Encryption on** (key, not passphrase) → confirm the wipe.
3. **Download the encryption key** when offered → password manager, next to
   the age key and the config export.

### A7. Apply, then prove it settled

```bash
mise run truenas:play playbooks/site.yml
mise run truenas:play playbooks/site.yml --check --diff   # must now be all "ok", no "changed"
```

### A8. First backup (most of a day — SMR disk)

Not on the day A7 created the tasks: the backup sends the daily 01:00
snapshot, so wait for the first one (Data Protection → Periodic Snapshot
Tasks shows it ran; the playbook refuses to start without one).

```bash
mise run truenas:play playbooks/20-backup-usb.yml
```

Ends with `Backup done; every dataset on backup-usb is encrypted.` Then
Storage → `backup-usb` → **Export/Disconnect** (keep the data), unplug.

### A9. Restore test (once — the backup is not proven until this works)

1. Plug in; Storage → Import Pool → `backup-usb`. If asked, unlock with the
   key **from the password manager** (proves that copy works).
2. Browse a few photos under `/mnt/backup-usb/media` (Shell or an SMB client
   via a temporary read-only share).
3. Export and unplug again.

### A10. From now on

- **A change** (new share, user, dataset): edit `group_vars`,
  `--check --diff`, apply. Not in the UI.
- **Weekly:** plug in, import, `20-backup-usb.yml`, export, unplug, store
  away.
- **After a UI-only change** (network, certificates, alerts): a new config
  export into the password manager.

## B. Rebuild TrueNAS from scratch

For a dead boot NVMe, a replacement NAS, or a clean reinstall. The data pool
`hdd-home-1` survives (if it does not, do [C](#c-restore-the-data-from-the-usb-disk)
after B4).

What you need: TrueNAS installer USB, the password manager (encryption key of
`backup-usb`, config export), `~/.ssh/truenas_admin.pub`.

### B1. Install

[`README.md`](README.md) steps 1–7: BIOS, install to the NVMe, first boot.
Same major version (25.10.x) or newer.

### B2. Manual settings (UI)

The ones Ansible does not manage. Exact values: the last
`~/truenas-discovery.json` (`network`, `interfaces`, `general`, `services`,
`smb_config`, `nfs_config`, `scrub_tasks`, `smart_tests` — an `error`
there means that method does not exist in this version; read the UI instead).

1. **Network:** hostname, static `192.168.1.214` (or DHCP reservation),
   gateway `192.168.1.1`, DNS → the Pi-hole.
2. **Timezone / NTP** (System → General).
3. **SSH for Ansible:** Credentials → Users → `truenas_admin` → paste
   `~/.ssh/truenas_admin.pub` as its key; System → Services → **SSH**: enable,
   start automatically.
4. **Services:** SMB and NFS enabled and set to start automatically, with the
   settings from `smb_config` / `nfs_config`.
5. **Scrub and SMART tasks**, alert email.

### B3. Import the data pool

Storage → Import Pool → `hdd-home-1`. Datasets, files, their ACLs and
snapshots all come back with it.

### B4. Ansible

```bash
ssh -i ~/.ssh/truenas_admin truenas_admin@192.168.1.214 midclt call system.version
mise run truenas:play playbooks/site.yml --check --diff
```

Expect **create** for groups, users, shares and both backup tasks, and **no
change** for datasets (they came back with the pool). Then apply:

```bash
mise run truenas:play playbooks/site.yml
mise run truenas:play playbooks/site.yml --check --diff   # all "ok"
```

Users come back with **their old UIDs**, so they own their files again.

### B5. User passwords

Recreated users get a **random password** (no passwords are stored in the
repo yet). Set each one in Credentials → Users. The Nextcloud SMB user must
get the password workloads holds in `nextcloud/secrets.yaml`
(`nextcloud_nas_password`) — otherwise Nextcloud's external storage stays
disconnected.

### B6. The backup disk

Plug in; Storage → Import Pool → `backup-usb`, **unlock with the key from the
password manager** (the new install does not have it). Run
`20-backup-usb.yml`: it continues incrementally, because the source snapshots
came back with `hdd-home-1`.

### B7. Check the clients

Nextcloud external storage (Admin → External storage: green), SMB from a PC,
and the Proxmox host's NFS backup target if it uses one.

## C. Restore the data from the USB disk

Only when `hdd-home-1` itself is lost (both mirror disks, or the pool).

1. Replace the disks; Storage → Create Pool → **`hdd-home-1`** (same name,
   mirror).
2. Import `backup-usb` and unlock it with the key from the password manager.
3. Data Protection → Replication → Add, **one-off**: LOCAL, source
   `backup-usb/media`, destination `hdd-home-1/media`, recursive, not
   encrypted (the destination pool is not), run once. Then delete that task.
4. The copy arrives **read-only** (the backup task sets `readonly`):
   Datasets → `hdd-home-1/media` → Edit → Read-only: **off**, for it and its
   children.
5. Run [B4](#b4-ansible) — shares, users and tasks are declared — then
   [B5](#b5-user-passwords).

Data written after the last backup run is not on the disk; the more often the
weekly routine runs, the less that is.
