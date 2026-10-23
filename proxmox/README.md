# Proxmox host — configuration and backup

The Proxmox VE node (`pve`, 192.168.1.169) as code, as far as the homelab
depends on it. Two scripts, both run **on the node as root**:

| Script | What it does | When |
|---|---|---|
| `configure.sh` | Creates or corrects the API roles, users, ACLs and tokens; downloads the ISOs and LXC template Packer and Terraform reference; optionally adds the OpenTelemetry metric server; installs the backup timer | After a fresh install, or any time, to put drift back |
| `backup.sh` | Writes one age-encrypted archive of the node's configuration; installed as `pve-config-backup` with a daily systemd timer | Daily (timer), or by hand before a risky change |

```bash
scp -r proxmox root@192.168.1.169:/root/homelab-proxmox-host
ssh root@192.168.1.169 /root/homelab-proxmox-host/configure.sh --check   # prints the plan, changes nothing
ssh root@192.168.1.169 /root/homelab-proxmox-host/configure.sh
```

## What `configure.sh` owns

The declared state is at the top of the script. Every role, user and token
there mirrors [docs/CREDENTIALS.md](../docs/CREDENTIALS.md) — change both
together.

The lists were taken from the live node (`pveum role list`, `pveum acl list`)
on 2026-10-08, so a `--check` run against it should report everything in sync.

- **Roles** `PackerProv`, `TerraformRole`, `McpReadOnlyRole`. A drifted role
  is reported with its live and declared privileges, then set to exactly the
  declared list.
- **Users** `packer@pve`, `terraform@pve`, `terraform-core@pve`, `mcp@pve`,
  each with its one ACL on `/`, and `pve-exporter@pve` (`PVEAuditor`) only
  with `ENABLE_PVE_EXPORTER=1`. New users get no password; they use API
  tokens.
- **Tokens** `packer-automation`, `terraform-automation`,
  `terraform-automation-core`, `mcp` are created when missing and their secret
  printed **once** — store it where CREDENTIALS.md says straight away. A token
  reported missing lists the tokens the user does have, so a renamed one is
  easy to spot before you create a duplicate. Existing tokens are
  never regenerated; to rotate one, follow CREDENTIALS.md.
- **Files on `local`:** the Ubuntu ISOs the Packer templates name
  (`boot_iso_file`), checksum-verified, and the Debian 13 LXC template
  `dns/terraform` names (`ostemplate`). Bump them here when you bump them there.
- **Metric server:** skipped unless `OTEL_SERVER` is set, because pushing to
  an address where nothing listens only fills the journal. Once the monitoring
  VM runs an OTLP receiver on the LAN:
  `OTEL_SERVER=192.168.1.87 OTEL_BEARER_TOKEN=… ./configure.sh` (the token
  becomes an `Authorization: Bearer` header the receiver checks).

It never deletes anything it does not declare, and it does not touch the
network, storage or any guest — the installer and the backup cover those.

## Backups

The archive (`pve-config-<host>-<timestamp>.tar.gz.age`) contains:

- `/var/lib/pve-cluster/config.db`, the database behind `/etc/pve`;
- `/etc/pve` as files;
- network, hosts, apt sources, kernel/modprobe/sysctl settings, LVM metadata,
  SSH config, cron and systemd units;
- `manifest.txt` (versions, guests, storage) and the package selection list.

`/etc/pve/priv` holds token secrets, private keys and password hashes, so the
archive is encrypted to the homelab's **age public key** (the recipient in
`.sops.yaml`) before it is written. The node cannot decrypt its own backups;
only the workstation's age key can.

Settings are in `/etc/default/pve-config-backup` on the node, seeded once from
`pve-config-backup.default`. The default destination is the node's own disk,
which does not survive the node. Point `BACKUP_DIR` at the NAS, for example
an NFS storage added under Datacenter → Storage and mounted at `/mnt/pve/<id>`,
and set `BACKUP_MOUNT` so that a failed mount stops the backup instead of
writing to the local disk.

```bash
systemctl list-timers pve-config-backup.timer   # next run
systemctl start pve-config-backup.service       # run now
journalctl -u pve-config-backup.service         # what it wrote
```

Guest disks are not in this archive — that is vzdump's job.

## Restoring

On the workstation, decrypt and inspect:

```bash
mkdir restore && age -d -i ~/.config/sops/age/keys.txt pve-config-….tar.gz.age | tar -xzf - -C restore
```

Onto a fresh Proxmox VE install of the same major version, following
Proxmox's documented pmxcfs recovery: with nothing running, stop
`pve-cluster`, put `config.db` in `/var/lib/pve-cluster/` (mode `0600`),
restore `/etc/hostname`, `/etc/hosts` and `/etc/network/interfaces` from the
archive, and reboot. Users, roles, tokens (secrets included), storage
definitions and guest configs all come back with `config.db`; the guests'
disks come from vzdump.

With no archive at all, `configure.sh` rebuilds the access setup, but the
tokens are new — update every `secrets.yaml` that holds one.
