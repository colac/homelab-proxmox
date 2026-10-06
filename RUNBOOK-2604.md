# Runbook — Ubuntu 26.04 template + split OS/Docker disks

Working notes for rolling out the 24G LVM OS disk and the separate Docker data
disk. **Temporary**: fold the durable parts into the monitoring repo's
`RUNBOOK.md` and [packer/README.md](packer/README.md), then delete this file.
Phases 0–2 run here (core); 3–4 in `homelab-proxmox-monitoring`; 5 in
`homelab-proxmox-workloads`. All three are siblings under `~/git-repos/`. Status lives in
[TODO.md](TODO.md), not here.

## What changes

| | Before | After |
|---|---|---|
| Template | `ubuntu-24.04-template`, 32G, **no LVM** | `ubuntu-26.04-template`, 24G, LVM |
| OS disk | one partition | `ubuntu-vg`: root 12G, home 2G, tmp 2G, opt 4G, ~2.5G free |
| Docker data | on the root filesystem | own disk, `docker-vg/docker-lv` at `/var/lib/docker` |
| Monitoring | `disk0_size = 100G` | `disk0 24G` + `data_disk 100G` |
| k3s | `disk0_size = 32G` | `disk0 24G` + `data_disk 12G` |
| Nextcloud | 24.04, 64G, no data disk | **unchanged** |

Container data lives in *named Docker volumes* — Elasticsearch's `esdata`,
Nextcloud AIO's `nextcloud_aio_mastercontainer` — so it sits under
`/var/lib/docker/volumes`. The data disk, not `disk0_size`, is the retention
ceiling.

## Phase 0 — Preflight

```bash
cd ~/git-repos/homelab-proxmox

# The one file the agent cannot read for you. A .auto.pkrvars.hcl is loaded on
# every build AND overrides PKR_VAR_* from sops-exec, so a disk_size pinned
# here silently beats the 24G default.
grep -nE 'disk_size|vm_id|vm_name|boot_iso|lv_' packer/ubuntu-26.04/variables.auto.pkrvars.hcl

# Tools and the shared collection (community.general's lvg/lvol/filesystem
# come in as colac.homelab's dependencies)
mise install && mise run setup
(cd ../homelab-proxmox-monitoring && mise install && mise run setup)

# State is in TFC; check what actually exists before planning
(cd ../homelab-proxmox-workloads  && mise run tf k3s state list)
(cd ../homelab-proxmox-monitoring && mise run tf state list)
```

Upload the ISO to Proxmox `local`. The filename must match `boot_iso_file`
exactly — this setup pins `ubuntu-26.04-live-server-amd64.iso` (the GA image),
while the repo default is `ubuntu-26.04.1-live-server-amd64.iso`.

`mise run secrets:check` in each repo confirms its `secrets.yaml` has every
key that repo needs, without printing any value.

> If a k3s VM already exists it is on the 24.04 template at 32G. The new
> settings force a **destroy/recreate** — `clone` is ForceNew and Telmate
> cannot shrink a disk. It is an empty VM, so this is fine; just expect it in
> the plan.

## Phase 1 — Build the template

```bash
mise run packer:validate 26.04
PACKER_LOG=1 mise run packer:build 26.04 2>&1 | tee /tmp/packer-2604.log
```

### If the installer crashes

The installer drops to a shell with `An error occurred. Press enter to start a
shell`. Read, in this order:

```bash
# 1. The traceback. Names the exact key/action that failed.
cat /var/crash/*.crash | sed -n '/Traceback/,/^$/p'

# 2. Full server log — the autoinstall parse and validation steps
less /var/log/installer/subiquity-server-debug.log

# 3. What the installer actually received, after Packer's templating
cat /var/log/installer/autoinstall-user-data

# 4. Only if partitioning started; absent on a config-validation failure
less /var/log/installer/curtin-install.log
```

Two crashes seen so far, both from `storage.config`, which had never been
evaluated before the `layout` key was removed:

| Message | Cause |
|---|---|
| `convert_autoinstall_config: 'id'` | A storage action missing `id`. Every entry needs both `id` and `type`. |
| `Filesystem.__init__() missing 1 required keyword-only argument: 'volume'` | **Not** a missing `volume`. An action type subiquity does not know (here `lvm_lv`, which should be `lvm_partition`) is silently skipped, so the `format` that references it fails its id lookup and drops `volume`. **Check type names first.** |

Valid action types, from `@fsobj(...)` in `subiquity/models/storage.py`:
`dasd`, `nvme_controller`, `disk`, `partition`, `raid`, `lvm_volgroup`,
`lvm_partition`, `dm_crypt`, `device`, `format`, `mount`, `zpool`, `zfs`.

Grep the debug log for silently-ignored actions before anything else:

```bash
grep -i 'ignoring unknown action type' /var/log/installer/subiquity-server-debug.log
```

Copy the crash file off the VM before destroying it:

```bash
# on the installer shell
python3 -m http.server 8000 --directory /var/crash
```

### Other failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Sits at the boot menu, never fetches `user-data` | 26.04's GRUB menu moved the linux line | Re-count the `<down>`s; set `boot_command` in `variables.auto.pkrvars.hcl` |
| Provisioner dies on a command fine on 24.04 | `sudo-rs` / Rust coreutils | Reproduce it in the guest before editing the script |
| No space / missing LVs | `lv_*_size` sums above `disk_size` minus ~1.5G | Lower an LV or raise `disk_size`; Packer has no cross-variable check |

### `status: error` after "Waiting for cloud-init..." (`/tmp/script_NNNN.sh` exits 1)

This is **not** a Packer provisioner failing. It is the very first provisioner
— `ubuntu-26.04.pkr.hcl`'s inline "wait for cloud-init" block — reporting
cloud-init's own exit code from the **installed OS's first boot**, which runs
separately from (and after) subiquity's install-time use of the autoinstall
document. If you got this far, the storage/LVM config already worked.

The inline block is `#!/bin/sh -e` by default (Packer's shell provisioner
default shebang), so `sudo cloud-init status --wait` printing `status: error`
aborts the script immediately — that is the whole story behind the generic
"exited with 1". The real cause is whichever cloud-init module failed inside
the guest, and it is gone once Packer's cleanup provisioner deletes the VM.

To catch it, re-run with `-on-error=ask` so the VM survives the failure:

```bash
PACKER_LOG=1 packer build -on-error=ask . 2>&1 | tee /tmp/packer-2604.log
```

When it stops, SSH to the build IP shown in the log (or use the Proxmox
console) before answering the prompt:

```bash
sudo cloud-init status --long          # names the failed module directly
sudo cloud-init analyze show           # per-stage timing, easier to spot what hung
sudo grep -iE 'error|traceback|warn' /var/log/cloud-init.log
less /var/log/cloud-init-output.log    # stdout/stderr of every runcmd line
```

`write_files`/`runcmd`/`packages` in `http/user-data.yml.tpl` are byte-for-byte
identical to `packer/ubuntu-24.04` (diffed and confirmed) and every package in
the list exists for `resolute`, so this isn't the same bug ported from 24.04.

**Speculative fix already applied, unconfirmed**: `homelab-proxmox-elastic`'s
`packer/ubuntu-26.04` hit and fixed the same-shaped failure on the same OS on
Proxmox (its README's ADR-6): dracut's hostonly mode bundles network modules
into the initrd based on the *build machine*, not the target, so on first boot
`systemd-networkd` DHCPs the NIC before cloud-init's netplan rename runs, and
the rename fails ("`[busy] Error renaming ... from ens18 to eth0`"). That repo
only saw it as `degraded done` (caught later via a wrong-IP Terraform clone);
ours is a harder `status: error`, consistent with the same race failing more
completely. Ported as `scripts/15-fix-initrd-network.sh`, but run from
`late-commands` (base64-embedded via `locals.pkr.hcl`, decoded and executed
chrooted into `/target`) instead of as a Packer provisioner — our failure is
on the very first boot, before any provisioner runs, so a post-boot fix would
always be one boot too late here. **Not yet proven against a real build.** If
this build still fails with `status: error`, rule this out explicitly:

```bash
sudo cloud-init status --long
sudo journalctl -b | grep -i 'rename\|networkd\|busy'
```

No `[busy] Error renaming` text means the initrd race wasn't the (only)
cause — go back to `cloud-init status --long` and `/var/log/cloud-init.log`
cold, without this hypothesis.

**Resolved (2026-09-03), confirmed via console on a paused build.** The initrd
race was a red herring for this build: the journal shows `ens18` DHCPing
cleanly with no rename ever attempted (`ens18: DHCPv4 address 192.168.1.112/24
... acquired`) — that race only bites a *static* IP applied through Proxmox's
generated network-config forcing an `ens18`→`eth0` rename, which a plain-DHCP
Packer build never triggers. `scripts/15-fix-initrd-network.sh` did no harm
and stays in place — Terraform-cloned VMs (static IPs, per
`terraform/modules/base-vm`) can still hit the real ADR-6 race, so it's
worth keeping as a preventive measure even though it wasn't this bug.

The real cause, from `/var/log/cloud-init.log` on the console:

```text
cc_ntp.py[ERROR]: Failed to reload/start ntp service: Unexpected error while running command.
Command: ['systemctl', 'reload-or-restart', 'systemd-timesyncd']
Exit code: 5
Stderr: Failed to reload-or-restart systemd-timesyncd.service: Unit systemd-timesyncd.service not found.
```

`user-data.yml.tpl` forced `ntp_client: systemd-timesyncd`. Checked against
cloud-init's own source (`cc_ntp.py`): that client's config entry has
`"packages": []` — cc_ntp assumes the binary is already on the image and
never installs anything for it. It isn't on this 26.04 image. Fixed by
switching to `ntp_client: chrony` (`packages: ["chrony"]`, so cc_ntp installs
it if missing; first in cloud-init's own default client priority order;
cloud-init's own docs use it as *the* example override for Ubuntu) and adding
`chrony` to `variables.pkr.hcl`'s `packages` list so it's baked in rather than
relying on cc_ntp's own install-if-missing fallback, same as everything else
on that list. `packer/ubuntu-24.04` still hardcodes `systemd-timesyncd` too
— left alone, since that image apparently still ships the binary and 24.04
isn't in scope here; worth the same fix if it's ever rebuilt and hits this.

**Third build (2026-09-03, same day), new symptom: `status: disabled`.** The
chrony fix worked — `cloud-init.log`'s tail showed `Ran 12 modules with 0
failures`, `boot-finished` written, `sd_notify(STATUS=Completed)`. But the
"wait for cloud-init" provisioner still failed (exit 2 this time, not 1).
Confirmed on console: `/etc/cloud/cloud-init.disabled` exists
(`boot_status_code: disabled-by-marker-file`) — that's Ubuntu's autoinstall
system disabling cloud-init for every boot *after* the first, which is
correct, expected behavior, not a bug. The exit code 2 was actually caused by
something unrelated showing up in the same output: cloud-init's own CLI
reference (`cli.rst`) documents `status --wait`'s exit codes precisely —
**1 = crashed, 2 = finished but with recoverable errors, 0 = clean** — and
our `recoverable_errors` was just a WARNING: `'passwd' in user-data is
ignored for existing user ubuntu` (subiquity's installer already created that
user with that password hash; cloud-init correctly declines to re-set it on
an existing account on first boot, and logs it, nothing functionally wrong).
Fixed in `ubuntu-26.04.pkr.hcl`'s "wait for cloud-init" provisioner: it now
distinguishes exit 1 (fatal, aborts the build) from exit 2 (logged via
`cloud-init status --long` for visibility, build continues) instead of
treating any non-zero exit as fatal.

## Phase 2 — Prove LVM exists (the gate)

The whole point of the rework. Do not skip: 24.04 silently produced no LVM at
all for months.

```bash
# on the Proxmox node. 9006 is this setup's actual template ID (vm_id is
# overridden in variables.auto.pkrvars.hcl; the repo default is 9001).
qm clone 9006 999 --name lvm-smoke --full 1
qm set 999 --ipconfig0 ip=dhcp && qm start 999
```

SSH in:

```bash
lsblk                       # ubuntu-vg with root/home/tmp/opt under sda
vgs                         # VFree ≈ 2.5G on ubuntu-vg — the deliberate headroom
lvs
df -h / /home /tmp /opt
```

`vgs` reporting no volume groups means `layout:` is back and `config:` is being
ignored again. Stop and fix.

```bash
qm stop 999 && qm destroy 999
```

## Phase 3 — Monitoring VM

In `homelab-proxmox-monitoring`:

```bash
mise run tf:plan     # expect: scsi0 24G, scsi1 100G, ubuntu-26.04-template
mise run tf:apply
```

The guest-agent IP `check` block usually fails on the first apply. Re-run
`apply` once the VM has booted so `ansible/inventory/monitoring.yml` gets a real
address.

## Phase 4 — Ansible

Still in `homelab-proxmox-monitoring`:

```bash
mise run inventory               # monitoring-vm under monitoring, elasticsearch, kibana
mise run play playbooks/00-bootstrap.yml --check --diff
mise run play playbooks/00-bootstrap.yml
```

`00-bootstrap.yml` targets only the `monitoring` group now — the Nextcloud host
belongs to the workloads repo, and appears in this inventory only as an agent
target.

Verify on the VM before continuing:

```bash
findmnt /var/lib/docker          # /dev/mapper/docker--vg-docker--lv, ext4
findmnt /var/lib/containerd      # same LV, [/containerd-root] — images off the OS disk
vgs                              # ubuntu-vg AND docker-vg
df -h /var/lib/docker            # ~100G
docker info | grep -i 'Root Dir'
```

Then the rest:

```bash
mise run play playbooks/site.yml
```

## Phase 5 — k3s (whenever)

In `homelab-proxmox-workloads`:

```bash
mise run tf k3s plan
```

Recreate if the plan says so, or pin `disk0_size = "32G"` in `terraform.tfvars`
to avoid it. Nothing configures this VM yet and it has no inventory fragment.

## Moving the Docker disk to another VM

The reason the disks are split.

1. Create the receiving VM with **`data_disk_size = null`**. It must have no
   `docker-vg` of its own, or two groups share a name.
2. Stop Docker on the source, then stop both VMs.
3. Reassign the disk in Proxmox — Hardware → Disk Action → Reassign Owner, or
   `qm disk move` with `--target-vmid` on 8+ (check the syntax for your
   version).
4. On the receiver, in the repo that owns it:
   `mise run play [app] playbooks/00-bootstrap.yml --limit <host>`.
   The role finds an existing `docker-vg`, **adopts it, and never reformats**.
5. Only if both hosts have a `docker-vg`: `vgs -o vg_name,vg_uuid`, then
   `vgrename <uuid> docker-vg` — by UUID, since the names collide.

## Rollback

Nextcloud is untouched: 24.04 template, 64G, no second disk. Do not run
`terraform apply` in that project and it cannot be affected. The 24.04 template
stays on the node under its own VM ID, so the old clone path stays available
throughout.
