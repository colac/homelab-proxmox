# Packer — Ubuntu base templates

Builds the **golden images** every VM in the homelab is cloned from — by the
monitoring and workloads repos' Terraform, via `template_name`: hardened
Ubuntu LTS Proxmox templates with Docker, Tailscale and the Elastic Agent
package baked in, sealed so that clones boot clean.

This is stage 1 of the pipeline and the main thing the core layer publishes —
see [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) for how the templates are
consumed, and why their names are a contract.

```text
ISO  ──▶ autoinstall (cloud-init user-data over HTTP)
     ──▶ provisioning scripts (proxy, CA, Docker, Elastic Agent, Tailscale)
     ──▶ cleanup + seal
     ──▶ Proxmox template
```

## The two templates

| Directory | Template | VM ID | OS disk | ISO |
|---|---|---|---|---|
| [ubuntu-24.04/](ubuntu-24.04/) | `ubuntu-24.04-template` | 9000 | 32G, **no LVM** | `ubuntu-24.04.3-live-server-amd64.iso` |
| [ubuntu-26.04/](ubuntu-26.04/) | `ubuntu-26.04-template` | 9001 | 24G, LVM | `ubuntu-26.04.1-live-server-amd64.iso` |

The provisioning scripts, hardening, Elasticsearch OS prerequisites and seal are
the same on both sides, and should stay that way — a fix found on one ports to
the other as a straight copy. **The storage layout is where they genuinely
differ**, and that difference is not cosmetic.

`ubuntu-24.04/http/user-data.yml.tpl` sets both `storage.layout` **and**
`storage.config`. Subiquity's autoinstall reference is explicit that "if the
layout feature is used to configure the disks, the config section is not used",
so `layout: {name: direct}` wins and the entire LVM block below it — the volume
group, the separate `/home`, `/tmp` and `/opt` volumes — is dead configuration.
`direct` means one plain root partition. **The 24.04 template has no LVM at
all**, which is also why its logical volumes summing to 35G on a 32G disk never
failed to build: they were never created. `lsblk` on a VM cloned from it will
show no `ubuntu-vg`.

`ubuntu-26.04/` drops the `layout` key so the actions actually apply, and sizes
the volumes to fit with room left over. See
[Disk layout](#disk-layout-2604) below.

Removing `layout` exposed three schema errors that had never been evaluated,
all of which failed the first real build with
`subiquity/Filesystem/apply_autoinstall_config/convert_autoinstall_config: 'id'`:

| Was | Should be | Why |
|---|---|---|
| `match: {largest: true}` | `match: {size: largest}` | `largest` is not a match-spec key; the key is `size`, valued `largest` or `smallest` |
| `flags: [ bios_grub ]` | `flag: bios_grub` | curtin's partition flag is a singular string, not a list |
| `mount` actions with no `id` | `id:` on every action | curtin: "the two dictionary keys that every entry in the list needs to have are `id` and `type`" — this is the one that raised `KeyError: 'id'` |
| `type: lvm_lv` | `type: lvm_partition` | subiquity registers `LVM_LogicalVolume` as `@fsobj("lvm_partition")`. `lvm_lv` is not a known type, and unknown types are **silently ignored** — see below |

The `lvm_lv` one deserves its own note, because the error it produces names
nothing to do with LVM. `_actions_from_config` skips any action whose type is
not in `_type_to_cls`, so the logical volumes never reach `byid`. The `format`
action that references one then fails its `byid[volume]` lookup, that `KeyError`
is deliberately swallowed (it is how bcache dependencies get pruned), and
`volume` simply never makes it into the kwargs. The install dies several steps
later with:

```text
Filesystem.__init__() missing 1 required keyword-only argument: 'volume'
```

So: **an unrecognised action type shows up as a missing argument on a different,
valid action.** If you see that error, check your type names first.

`ubuntu-24.04/` still carries all four. They are harmless there **only** because
`layout` suppresses the block; anyone removing that key without fixing them will
hit the same crashes in the same order.

Nextcloud (workloads repo) is still cloned from 24.04. Monitoring and k3s
use `ubuntu-26.04-template`, because their 24G `disk0_size` only makes sense
against a template whose OS disk is actually 24G. Both templates sit on the
node at once, which is the point of the separate VM IDs.

## Disk layout (26.04)

The template builds **one** disk. The Docker data disk is attached by Terraform
(`data_disk_size` on the `base-vm` module) and turned into LVM by the Ansible
`docker_data` role — see [ansible/README.md](../ansible/README.md).

```text
/dev/sda  (disk_size, default 24G)
├─ 1M    BIOS grub
├─ 512M  EFI            /boot/efi
├─ 1G    ext4           /boot
└─ rest  LVM PV ── ubuntu-vg (~22.5G)
                   ├─ root  12G  /       (lv_root_size)
                   ├─ home   2G  /home   (lv_home_size, nodev,nosuid)
                   ├─ tmp    2G  /tmp    (lv_tmp_size,  nodev,nosuid)
                   ├─ opt    4G  /opt    (lv_opt_size,  noatime)
                   └─ ~2.5G unallocated  <- deliberate

/dev/sdb  (Terraform data_disk_size)  raw at clone time
└─ LVM PV ── docker-vg ── docker-lv ── ext4 ── /var/lib/docker
             created by the Ansible docker_data role, not here
                                               └─ containerd-root/  bind-mounted
                                                  at /var/lib/containerd (images)
```

**No logical volume is sized `-1`.** Leaving free extents in `ubuntu-vg` is the
whole reason for using LVM here: whichever filesystem fills up first grows in
place, with no repartitioning and no reboot:

```bash
lvextend -L +2G /dev/ubuntu-vg/root
resize2fs /dev/ubuntu-vg/root
```

Past the free extents, grow the Proxmox disk first, then:

```bash
growpart /dev/sda 4 && pvresize /dev/sda4
lvextend -L +20G /dev/ubuntu-vg/root && resize2fs /dev/ubuntu-vg/root
```

**Why /opt is only 4G.** It holds `elastic_base_dir` — the compose files, `.env`
files, certs and secrets, a few MB. It is not where container data goes.
Elasticsearch's `esdata` and Nextcloud AIO's `nextcloud_aio_mastercontainer` are
*named Docker volumes*, so they live under `/var/lib/docker/volumes` on the data
disk. That disk, not `disk0_size`, is what caps how much data a host can hold.

**Why the data disk is not in the template.** A full clone copies LVM metadata
byte-for-byte, so a data disk partitioned here would give every VM an identical
PV and VG UUID. Detaching one host's disk and attaching it to another — the
reason for splitting the disks in the first place — would then need
`vgimportclone` before LVM would touch it. Creating the volume group on the
running host instead means each one generates its own UUIDs, and a VM built to
*receive* an existing disk is simply created with no `data_disk_size` and no
volume group of its own to collide.

## Layout

Each release directory has the same shape:

```txt
packer/<release>/
├── <release>.pkr.hcl             # source + build blocks (proxmox-iso builder)
├── variables.pkr.hcl             # input variables and defaults
├── versions.pkr.hcl              # required plugins/versions
├── locals.pkr.hcl                # renders user-data from the template
├── variables.pkrvars.hcl.example # OPTIONAL non-secret overrides (secrets come
│                                 # from PKR_VAR_* via .mise/sops-exec)
├── http/
│   ├── user-data.yml.tpl         # autoinstall config (templated from locals)
│   └── meta-data.yml
├── custom-ca/                    # drop private root CAs here (see its README)
└── scripts/
    ├── 00-configure-proxy.sh     # system/APT/Docker proxy (opt-in)
    ├── 10-install-custom-ca.sh   # registers custom-ca/*.crt in the guest
    ├── 20-install-docker.sh      # Docker CE
    ├── 30-install-elastic-agent.sh  # Elastic Agent (installed, left disabled)
    ├── 40-install-tailscale.sh   # Tailscale package only — not authenticated
    └── 99-cleanup-seal.sh        # cleanup, zero-fill, shutdown
```

`ubuntu-26.04/` also has `scripts/15-fix-initrd-network.sh`, not run as a
provisioner like the others — see "Ubuntu 26.04 specifics" below for why.

## Prerequisites

- **Packer** — pinned in `mise.toml`; `mise install` from the repo root.
- **Proxmox 9+.**
- **The Ubuntu ISO uploaded to Proxmox storage** — the name must match
  `boot_iso_file` for the release you are building (see the table above).
- **Credentials** in core's `secrets.yaml`: the `packer@pve` token, the
  console password hash and `proxmox_endpoint`, plus the SSH deploy key in
  `~/.ssh/`. How to issue each:
  [docs/CREDENTIALS.md](../docs/CREDENTIALS.md#packer-proxmox-token).
  `.mise/sops-exec packer` hands them to Packer as `PKR_VAR_*` for the one
  command it wraps; both release directories use the same profile.

### Running from WSL

Packer serves the autoinstall files from an HTTP server on the build host, so
the VM must be able to reach WSL. In PowerShell, as Administrator:

```powershell
# Allow inbound connections on the Packer HTTP port
New-NetFirewallRule -DisplayName "WSL2 Packer HTTP" -Direction Inbound -Protocol TCP -LocalPort 8181 -Action Allow

# Forward that port from Windows into the WSL2 VM (use the WSL IP from `ip -br addr`)
netsh interface portproxy add v4tov4 listenport=8181 listenaddress=0.0.0.0 connectport=8181 connectaddress=WSL_IP
```

Both builds pin the HTTP server to port 8181, so one rule covers either — but
they cannot run **at the same time** for that reason. Build them one after the
other.

## Build

```bash
mise run secrets:check            # every key present? (names only, no values)
mise run packer:validate 26.04    # init + validate with the real variables
mise run packer:build 26.04       # or 24.04

# verbose build log; extra args go to `packer build`
PACKER_LOG=1 mise run packer:build 26.04 -on-error=ask
```

No var-file is needed. `.mise/sops-exec packer` supplies the API URL, token,
node, TLS flag, `password_hash`, and `ssh_authorized_keys` (read from
`~/.ssh/homelab-proxmox.pub` at run time, because password auth is disabled in
the image — an empty value would build a template nobody can log in to). If the
key file is missing, sops-exec refuses to start the build rather than letting
it succeed unusably. Running `packer` bare in a release directory gets **no**
credentials — by design, nothing is exported into your shell.

`variables.pkrvars.hcl.example` is now only for **non-secret** overrides
(sizing, ISO, feature flags). A `-var-file` still takes precedence over
`PKR_VAR_*`, so an existing local `variables.pkrvars.hcl` keeps working.

Building while a VPN holds the default route? Set `PACKER_HTTP_INTERFACE` to
your LAN NIC in `mise.local.toml` (git-ignored) so `{{ .HTTPIP }}` in the boot
command resolves to an address the VM can actually reach:

```toml
# mise.local.toml
[env]
PACKER_HTTP_INTERFACE = "enp3s0"
```

Output: a sealed Proxmox **template** at the `vm_name` / `vm_id` for that
release, plus a build manifest. The other repos' Terraform clones it from there
by name — nothing else needs to be done to the template. Renaming a template
breaks every consumer whose `template_name` points at it.

> Rebuilding with the same `vm_id` fails while the old template still exists.
> Delete or renumber the previous template first. This is also why 26.04 sits at
> 9001: a 26.04 build can never quietly take out the 24.04 template Nextcloud
> is cloned from. The IDs in the table are the repo defaults; a git-ignored
> `variables.auto.pkrvars.hcl` can override them — this setup builds 26.04 at
> **9006**. That file loads on every build and wins over `PKR_VAR_*`, so check
> it first when a build uses a size or ID you did not expect.

### Verify a new template

Before pointing any project at a fresh template, clone it once and check the
disk layout — the 24.04 template silently produced no LVM for months. On the
Proxmox node (use your template's real ID):

```bash
qm clone 9006 999 --name lvm-smoke --full 1
qm set 999 --ipconfig0 ip=dhcp && qm start 999
# then, on the clone:
lsblk && vgs && df -h / /home /tmp /opt   # ubuntu-vg, ~2.5G VFree, four LVs
# then, on the node:
qm stop 999 && qm destroy 999
```

No volume group at all means a `storage.layout` key is back in
`user-data.yml.tpl`.

## How the build works

1. **Autoinstall.** The builder boots the ISO and points Ubuntu's installer at
   `user-data` served over HTTP. `locals.pkr.hcl` renders
   `http/user-data.yml.tpl` with the username, password hash, SSH keys, locale,
   packages, nameservers and NTP servers — so most OS-level settings are
   variables, not edits to the template file. On 26.04, `late-commands` also
   runs `scripts/15-fix-initrd-network.sh` chrooted into `/target` before the
   final reboot — see "Ubuntu 26.04 specifics" below.
2. **Wait for cloud-init.** A shell provisioner blocks on
   `cloud-init status --wait` so nothing races the first boot. Its exit code
   is treated per cloud-init's own documented meaning — 1 (crashed) fails the
   build, 2 (finished, but with recoverable errors — logged via
   `cloud-init status --long`, not swallowed) does not. On 26.04, `boot-finished`
   also coincides with autoinstall disabling cloud-init for every later boot
   (`/etc/cloud/cloud-init.disabled`) — expected, unrelated to the exit code.
3. **Upload custom CAs.** The whole `custom-ca/` directory is uploaded
   unconditionally — it must exist even when empty (see each release's
   `custom-ca/README.md`).
4. **Provisioning scripts**, run as root in a fixed order: proxy → CA → Docker
   → Elastic Agent → Tailscale. Each is toggled by an environment variable exported
   from the build block (`INSTALL_DOCKER`, `INSTALL_TAILSCALE`, `ENABLE_PROXY`,
   `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`).
5. **Cleanup and seal** (`99-cleanup-seal.sh`): APT/log cleanup,
   `cloud-init clean --logs --seed` followed by `rm -rf /var/lib/cloud/*`,
   truncated `machine-id`, removed SSH host keys (cloud-init regenerates them
   on the clone's first boot), disk zero-fill, graceful shutdown.

**Tailscale is installed but deliberately not authenticated.** `tailscale up`
needs an auth key, which would bake a credential into the image and give every
clone the same identity — so the Ansible `tailscale` role joins the tailnet
per-VM instead.

## Ubuntu 26.04 specifics

Everything below was checked against the actual 26.04 archive before the port,
because each is a place where a new release could have silently broken the
build:

- **Codename is `resolute`.** The Docker and Tailscale install scripts derive
  the repository suffix from the guest's own `$VERSION_CODENAME`, and both
  vendors publish for it (`download.docker.com/linux/ubuntu/dists/resolute`,
  `pkgs.tailscale.com/stable/ubuntu/resolute.*`). No fallback or pinning was
  needed, so the scripts are byte-identical to the 24.04 ones apart from their
  header comment.
- **Every package in the autoinstall list exists in `resolute`** — including the
  ones most likely to have been dropped or renamed (`inetutils-ping`,
  `vim-nox`, `mc`, `audispd-plugins`, `apt-transport-https`).
- **`boot_command` is a variable here**, not inline in the source block. It
  drives GRUB's edit screen by keystroke — three `<down>`s to the linux line,
  `<end>`, four `<bs>` to strip the trailing `---` — which makes it the one part
  of the build coupled to the ISO's menu layout, and the layout is exactly the
  kind of thing a new release is free to change. If the build stalls at the
  installer prompt, that sequence is the first thing to correct, and it can be
  corrected from `variables.pkrvars.hcl` without patching tracked code.
- **The `storage.layout` key is gone**, so the LVM actions actually run. Keeping
  it alongside `storage.config` is what silently disables LVM on the 24.04 side;
  do not add it back. A build that comes up with no `ubuntu-vg` is this.
- **26.04 ships `sudo-rs` and the Rust `coreutils` as defaults.** The build runs
  its provisioners as `sudo -E bash`, and the seal script leans on `truncate`,
  `dd` and `find -exec`; all of that is within what the replacements implement.
  It is still the likeliest source of a novel failure, so if a provisioner dies
  with a permissions or argument-parsing error that makes no sense on 24.04,
  suspect these two before anything else.
- **`scripts/15-fix-initrd-network.sh` disables networking in the initrd** —
  precautionary, not a fix for anything hit on this build. Dracut's hostonly
  mode bundles network modules into the initrd based on the *build machine*,
  not the target, so `systemd-networkd` can DHCP the NIC before cloud-init's
  netplan rename runs, and the rename fails ("`[busy] Error renaming ... from
  ens18 to eth0`") — but only when a cloud-init network-config asks for that
  rename. Proxmox generates one for every Terraform clone (`base-vm` sets
  `ipconfig0`, DHCP); a Packer build has none and never triggers it. Ported from `homelab-proxmox-elastic`'s `packer/ubuntu-26.04`
  (its README's ADR-6), which hit this live on a Terraform-cloned VM. That
  repo runs the fix as a Packer provisioner; this one runs it from
  `late-commands` instead (base64-embedded via `locals.pkr.hcl`, decoded and
  executed chrooted into `/target`), so it lands before the first boot instead
  of after.
- **`ntp_client: chrony`, not `systemd-timesyncd`.** Confirmed live on
  2026-09-03: cloud-init's `ntp` module failed the whole run
  (`cc_ntp.py[ERROR]: ... Unit systemd-timesyncd.service not found`, exit
  code 5) because that binary isn't on this image. Checked against
  cloud-init's own source: the `systemd-timesyncd` client entry ships
  `packages: []` — cc_ntp assumes it's already there and never installs
  anything for it. `chrony`'s entry carries `packages: ["chrony"]` (installed
  if missing), sits first in cloud-init's own default client priority order,
  and is cloud-init's own documented example override for Ubuntu. `chrony` is
  also baked into `packages` directly rather than left to that fallback.
  `ubuntu-24.04` still hardcodes `systemd-timesyncd`, unchanged — that image
  apparently still ships the binary, and 24.04 wasn't in scope for this fix.

## Configuration variables

Defined in each release's `variables.pkr.hcl`. The credential-shaped ones arrive
as `PKR_VAR_*` from `.mise/sops-exec packer`; anything else can be overridden with
`packer build -var-file=variables.pkrvars.hcl`, which wins over the environment.
The most commonly changed ones:

### Proxmox connection

| Variable | Description | Default |
|---|---|---|
| `proxmox_api_url` | API endpoint, e.g. `https://pve.example.com:8006/api2/json` | — |
| `proxmox_api_token_id` | Token ID (`packer@pve!packer-automation`) | — |
| `proxmox_api_token_secret` | Token secret | — |
| `proxmox_node` | Target node name | — |
| `proxmox_skip_tls_verify` | Skip API TLS verification | `false` |
| `storage_pool` | Storage for the VM disk | `local-lvm` |
| `boot_iso_file` | ISO path in Proxmox storage | per release — see the table above |

### Template shape

| Variable | Description | Default |
|---|---|---|
| `vm_id` | Template VM ID | `9000` (24.04) / `9001` (26.04) |
| `vm_name` | Template name | `ubuntu-<release>-template` |
| `vm_cpu_cores` / `vm_cpu_sockets` / `vm_cpu_type` | CPU layout | `2` / `1` / `host` |
| `vm_memory` | Memory in MB | `4096` |
| `disk_size` | OS disk | `32G` (24.04) / `24G` (26.04) |
| `lv_root_size` / `lv_home_size` / `lv_tmp_size` / `lv_opt_size` | Logical volume sizes inside `ubuntu-vg` (**26.04 only**). Must sum to at least ~1.5G below `disk_size`; the remainder is left as free extents on purpose | `12G` / `2G` / `2G` / `4G` |
| `network_bridge` | Proxmox bridge | `vmbr0` |
| `tags` | Semicolon-separated Proxmox tags | `packer;ubuntu` (24.04) / `packer;ubuntu;26-04` (26.04) |

### Guest OS

| Variable | Description | Default |
|---|---|---|
| `username` | Primary user | `ubuntu` |
| `password_hash` | SHA-512 hash for console login (`mkpasswd -m sha-512`) | — |
| `ssh_authorized_keys` | Public keys for the primary user | `[]` |
| `ssh_private_key_file` | Key Packer connects with — must match the above | — |
| `additional_users` | Extra users to create | `[]` |
| `hostname` / `timezone` / `locale` / `keyboard_layout` | System basics | `ubuntu-template` / `Europe/Lisbon` / `en_US.UTF-8` / `us` |
| `packages` | Packages installed by autoinstall | see file |
| `nameservers` / `ntp_servers` | DNS and NTP for the guest | see file |

### Feature toggles

| Variable | Description | Default |
|---|---|---|
| `install_docker` | Install Docker CE | `true` |
| `install_tailscale` | Install Tailscale (unauthenticated) | `true` |
| `enable_proxy` | Configure a system-wide proxy | `false` |
| `http_proxy` / `https_proxy` / `no_proxy` | Proxy settings when enabled | `""` |
| `http_interface` | Host NIC whose IP is advertised for the autoinstall HTTP server (empty = auto-detect) | `""` |
| `boot_command` | Autoinstall keystrokes at the GRUB menu (**26.04 only**) | see file |

`http_interface` matters more than it looks: if the build host's default route
is a VPN tunnel, Packer advertises the tunnel IP and the VM can never fetch
`user-data`. Set it to the LAN NIC (`ip -br addr` to find it).

When `enable_proxy` is true, the proxy is applied to `/etc/environment`,
`/etc/apt/apt.conf.d/`, and `/etc/systemd/system/docker.service.d/proxy.conf`.

## Security hardening

The images ship locked down by default:

- **SSH** — root login disabled, password authentication disabled, key-only
  access via the autoinstall-injected authorized keys.
- **Users** — root account locked (`passwd -l root`, shell set to `nologin`);
  the primary user keeps a console password (emergency troubleshooting only)
  and passwordless sudo via `/etc/sudoers.d/90-cloud-init-users`.
- **Network** — IPv6 disabled in sysctl and GRUB.
- **Updates** — `unattended-upgrades` is **enabled**: the autoinstall writes
  `20auto-upgrades` with `APT::Periodic::Unattended-Upgrade "1"` and restricts
  `50unattended-upgrades` to the security pockets, with automatic reboots off.
  Cloud-init also runs `package_upgrade: true`, so a clone does patch on its
  first boot — budget for that rather than expecting an instant-ready VM.
- **Auditing** — `auditd` installed and enabled, with an SSH banner and
  `LogLevel VERBOSE`.
- **Time** — NTP client enabled and verified before sealing: `systemd-timesyncd`
  on 24.04, `chrony` on 26.04 (see "Ubuntu 26.04 specifics" for why they
  differ).

## Design decisions

| Decision | Reason |
|---|---|
| Autoinstall over manual install | Unattended and reproducible |
| Immutable image, sealed before templating | No configuration drift across clones |
| Root disabled, key-only SSH | Least privilege |
| Console password kept | Recover a VM that lost network |
| IPv6 disabled | Avoids dual-stack surprises on this LAN |
| Tailscale installed but not authenticated | Keeps the image credential-free |
| One directory per release, not a `release` variable | A build is pinned to one ISO's installer behaviour; a shared tree would need conditionals in exactly the places that are hardest to test |
| 26.04 on its own VM ID | Both templates coexist, so the migration is a `template_name` change per Terraform project rather than a flag day |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Build hangs waiting for SSH | `ssh_authorized_keys` doesn't match `ssh_private_key_file`, or the VM can't reach the HTTP server | Verify the keypair; set `http_interface` to the LAN NIC |
| VM never fetches `user-data` (installer sits at the prompt) | HTTP server bound to a VPN/WSL address, or the GRUB menu layout moved | `http_interface`, and the WSL port-proxy above; on 26.04 also re-count the `<down>`s in `boot_command` |
| Cloud-init upgrades packages on first boot | Expected — `package_upgrade: true` in `user-data.yml.tpl` | Set it to `false` and rebuild if you want clones to boot without patching |
| Console login fails | Account locked (`!` in `/etc/shadow`) | Set a valid `password_hash` and rebuild |
| `checksum mismatch (file change by other user?) (500)` | Cloud-init seed modified post-install | Only static files under `/etc/cloud/cloud.cfg.d` should be touched |
| Proxy not applied | Variables not exported globally | Check `/etc/environment` and `/etc/apt/apt.conf.d/proxy.conf` |
| `vm_id` already exists | Previous template still on the node | Delete it or change `vm_id` |
| `403 Permission check failed (/vms/<id>, VM.Config.Cloudinit)` at "Adding a cloud-init cdrom" | The live `PackerRole` has drifted from the privilege list in [CREDENTIALS.md](../docs/CREDENTIALS.md#packer-proxmox-token) — everything else in the build already succeeded, so it is the role, not the token's privsep | Re-run that `pveum role add` line as `pveum role modify PackerRole -privs "…"`, then answer `r` at the `-on-error=ask` prompt; the template already exists by this point, so no rebuild is needed |
| Second build fails to bind port 8181 | Both releases pin the same autoinstall HTTP port | Build them one at a time |
| 26.04 provisioner fails on a command that works on 24.04 | `sudo-rs` / Rust `coreutils` behaviour difference | Reproduce the exact command in the guest before changing the script |
| Install fails with no space, or LVs are missing | `lv_*_size` sums above `disk_size` minus ~1.5G for BIOS/EFI/boot | Lower an LV or raise `disk_size`; there is no cross-variable check in Packer |
| Clone has no `ubuntu-vg` at all | A `storage.layout` key crept back into `user-data.yml.tpl` and disabled `storage.config` | Remove `layout`; only `config` may be present |
| Wait-for-cloud-init provisioner fails; VM already deleted | Cloud-init failed on the installed system's first boot — not a provisioner. Exit 1 (crashed) fails the build; exit 2 (finished, recoverable errors only — e.g. a benign "passwd ignored for existing user" warning) is logged but does not, since cloud-init's own docs define exit 2 as non-fatal | See [Debugging a failed build](#debugging-a-failed-build) |
| `/var/lib/docker` is still on the OS disk | No `data_disk_size` set for that project, so no scsi1 exists | Set it in the project's `variables.tf` and re-apply, then re-run `00-bootstrap.yml` |

### Debugging a failed build

Keep the VM alive with `mise run packer:build 26.04 -on-error=ask`, and
inspect it before answering the prompt.

**The installer crashed** (`An error occurred. Press enter to start a shell`),
usually a storage-config error. Read, in this order:

```bash
cat /var/crash/*.crash | sed -n '/Traceback/,/^$/p'   # names the failing key/action
grep -i 'ignoring unknown action type' /var/log/installer/subiquity-server-debug.log
cat /var/log/installer/autoinstall-user-data          # what the installer received
less /var/log/installer/curtin-install.log            # only if partitioning started
python3 -m http.server 8000 --directory /var/crash    # copy the crash file off first
```

Valid storage action types (subiquity's `@fsobj(...)`): `dasd`,
`nvme_controller`, `disk`, `partition`, `raid`, `lvm_volgroup`,
`lvm_partition`, `dm_crypt`, `device`, `format`, `mount`, `zpool`, `zfs`.
Anything else is skipped silently, and the error appears on a *different*
action — see [The two templates](#the-two-templates).

**Cloud-init failed on first boot** (the "wait for cloud-init" step exits 1).
SSH to the build IP from the log, or use the Proxmox console:

```bash
sudo cloud-init status --long          # names the failed module
sudo cloud-init analyze show           # per-stage timing
sudo grep -iE 'error|traceback|warn' /var/log/cloud-init.log
less /var/log/cloud-init-output.log    # stdout/stderr of every runcmd line
```

The 26.04 build hit this once (`systemd-timesyncd` missing — see
[Ubuntu 26.04 specifics](#ubuntu-2604-specifics)).
