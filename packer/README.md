# Packer — Ubuntu 24.04 base template

Builds the **golden image** every VM in this repo is cloned from: a hardened
Ubuntu 24.04 LTS Proxmox template with Docker and Tailscale baked in, sealed so
that clones boot clean.

This is stage 1 of the pipeline — see the [root README](../README.md) for how it
fits with Terraform and Ansible.

```text
ISO  ──▶ autoinstall (cloud-init user-data over HTTP)
     ──▶ provisioning scripts (proxy, CA, Docker, Alloy, Tailscale)
     ──▶ cleanup + seal
     ──▶ Proxmox template "ubuntu-24.04-template" (VM ID 9000)
```

## Layout

```txt
packer/ubuntu-24.04/
├── ubuntu-24.04.pkr.hcl          # source + build blocks (proxmox-iso builder)
├── variables.pkr.hcl             # input variables and defaults
├── versions.pkr.hcl              # required plugins/versions
├── locals.pkr.hcl                # renders user-data from the template
├── variables.pkrvars.hcl.example # copy to variables.pkrvars.hcl and fill in
├── http/
│   ├── user-data.yml.tpl         # autoinstall config (templated from locals)
│   └── meta-data.yml
├── custom-ca/                    # drop private root CAs here (see its README)
└── scripts/
    ├── 00-configure-proxy.sh     # system/APT/Docker proxy (opt-in)
    ├── 10-install-custom-ca.sh   # registers custom-ca/*.crt in the guest
    ├── 20-install-docker.sh      # Docker CE
    ├── 30-install-alloy.sh       # Grafana Alloy
    ├── 40-install-tailscale.sh   # Tailscale package only — not authenticated
    └── 99-cleanup-seal.sh        # cleanup, zero-fill, shutdown
```

## Prerequisites

- **Packer ≥ 1.10** — `./install-packer.sh` from the repo root.
- **Proxmox 9+** with an API token for a `packer@pve` user (below).
- **The Ubuntu ISO uploaded to Proxmox storage** — the name must match
  `boot_iso_file` (default `local:iso/ubuntu-24.04.3-live-server-amd64.iso`).
- **A `mkpasswd`-generated password hash** for the console user:
  `mkpasswd -m sha-512 'yourpassword'` (from the `whois` package).
- **An SSH keypair** whose public half goes in `ssh_authorized_keys` and whose
  private half is `ssh_private_key_file` — these must match or the build hangs
  at the SSH connection step. This repo uses `~/.ssh/homelab-proxmox`.

### Create the Packer user in Proxmox

Run in the Proxmox node console:

```bash
# create role and set privileges
pveum role add PackerRole -privs "VM.Config.Disk VM.Config.Cloudinit SDN.Use VM.Snapshot VM.PowerMgmt Datastore.Allocate VM.GuestAgent.Unrestricted VM.Config.Network VM.Config.CDROM VM.Console VM.Backup VM.Migrate VM.Config.Options VM.Clone VM.GuestAgent.Audit VM.Snapshot.Rollback Pool.Audit VM.Config.CPU VM.Config.HWType Datastore.AllocateSpace Datastore.Audit VM.Allocate VM.Config.Memory VM.Audit"

# create user (choose your own password)
pveum user add packer@pve --password 'CHANGE_ME'

# set permissions
pveum aclmod / -user packer@pve -role PackerRole

# create API token — this command prints the secret exactly once
pveum user token add packer@pve packer-automation --privsep 0
```

Put the token ID and secret in `variables.pkrvars.hcl` as
`proxmox_api_token_id` / `proxmox_api_token_secret`.

### Running from WSL

Packer serves the autoinstall files from an HTTP server on the build host, so
the VM must be able to reach WSL. In PowerShell, as Administrator:

```powershell
# Allow inbound connections on the Packer HTTP port
New-NetFirewallRule -DisplayName "WSL2 Packer HTTP" -Direction Inbound -Protocol TCP -LocalPort 8181 -Action Allow

# Forward that port from Windows into the WSL2 VM (use the WSL IP from `ip -br addr`)
netsh interface portproxy add v4tov4 listenport=8181 listenaddress=0.0.0.0 connectport=8181 connectaddress=WSL_IP
```

## Build

```bash
cd packer/ubuntu-24.04
cp variables.pkrvars.hcl.example variables.pkrvars.hcl
# fill in: proxmox_api_token_id, proxmox_api_token_secret, password_hash

packer init .
packer validate -var-file=variables.pkrvars.hcl .
packer build    -var-file=variables.pkrvars.hcl .

# verbose build log
PACKER_LOG=1 packer build -var-file=variables.pkrvars.hcl .
```

Output: a sealed Proxmox **template** (`vm_name`, default
`ubuntu-24.04-template`, at `vm_id` 9000) plus a build manifest. Terraform
clones it from there — nothing else needs to be done to the template.

> Rebuilding with the same `vm_id` fails while the old template still exists.
> Delete or renumber the previous template first.

## How the build works

1. **Autoinstall.** The builder boots the ISO and points Ubuntu's installer at
   `user-data` served over HTTP. `locals.pkr.hcl` renders
   `http/user-data.yml.tpl` with the username, password hash, SSH keys, locale,
   packages, nameservers and NTP servers — so most OS-level settings are
   variables, not edits to the template file.
2. **Wait for cloud-init.** A shell provisioner blocks on
   `cloud-init status --wait` so nothing races the first boot.
3. **Upload custom CAs.** The whole `custom-ca/` directory is uploaded
   unconditionally — it must exist even when empty (see
   [custom-ca/README.md](ubuntu-24.04/custom-ca/README.md)).
4. **Provisioning scripts**, run as root in a fixed order: proxy → CA → Docker
   → Alloy → Tailscale. Each is toggled by an environment variable exported
   from the build block (`INSTALL_DOCKER`, `INSTALL_TAILSCALE`, `ENABLE_PROXY`,
   `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`).
5. **Cleanup and seal** (`99-cleanup-seal.sh`): APT/log cleanup,
   `cloud-init clean --logs --machine-id`, removal of
   `/var/lib/cloud/instances`, SSH host-key regeneration on next boot,
   disk zero-fill, graceful shutdown.

**Tailscale is installed but deliberately not authenticated.** `tailscale up`
needs an auth key, which would bake a credential into the image and give every
clone the same identity — so the Ansible `tailscale` role joins the tailnet
per-VM instead.

## Configuration variables

Defined in `variables.pkr.hcl`; override with
`packer build -var-file=variables.pkrvars.hcl` or `PKR_VAR_*` environment
variables. The most commonly changed ones:

### Proxmox connection

| Variable | Description | Default |
|---|---|---|
| `proxmox_api_url` | API endpoint, e.g. `https://pve.example.com:8006/api2/json` | — |
| `proxmox_api_token_id` | Token ID (`packer@pve!packer-automation`) | — |
| `proxmox_api_token_secret` | Token secret | — |
| `proxmox_node` | Target node name | — |
| `proxmox_skip_tls_verify` | Skip API TLS verification | `false` |
| `storage_pool` | Storage for the VM disk | `local-lvm` |
| `boot_iso_file` | ISO path in Proxmox storage | `local:iso/ubuntu-24.04.3-live-server-amd64.iso` |

### Template shape

| Variable | Description | Default |
|---|---|---|
| `vm_id` | Template VM ID | `9000` |
| `vm_name` | Template name | `ubuntu-24.04-template` |
| `vm_cpu_cores` / `vm_cpu_sockets` / `vm_cpu_type` | CPU layout | `2` / `1` / `host` |
| `vm_memory` | Memory in MB | `4096` |
| `disk_size` | Root disk | `32G` |
| `network_bridge` | Proxmox bridge | `vmbr0` |
| `tags` | Semicolon-separated Proxmox tags | `packer;ubuntu` |

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

`http_interface` matters more than it looks: if the build host's default route
is a VPN tunnel, Packer advertises the tunnel IP and the VM can never fetch
`user-data`. Set it to the LAN NIC (`ip -br addr` to find it).

When `enable_proxy` is true, the proxy is applied to `/etc/environment`,
`/etc/apt/apt.conf.d/`, and `/etc/systemd/system/docker.service.d/proxy.conf`.

## Security hardening

The image ships locked down by default:

- **SSH** — root login disabled, password authentication disabled, key-only
  access via the autoinstall-injected authorized keys.
- **Users** — root account locked (`passwd -l root`); the primary user keeps a
  console password (emergency troubleshooting only) and sudo via
  `/etc/sudoers.d/90-cloud-init-users`. Duplicate sudoers entries are cleaned
  during sealing.
- **Network** — IPv6 disabled in sysctl and GRUB.
- **Updates** — automatic upgrades disabled via
  `/etc/cloud/cloud.cfg.d/99-disable-updates.cfg`, and the `apt-daily` /
  `apt-daily-upgrade` timers are masked, so clones never spend their first boot
  running upgrades. Patching is a deliberate Ansible or rebuild action.
- **Time** — `systemd-timesyncd` enabled and verified before sealing.

## Design decisions

| Decision | Reason |
|---|---|
| Autoinstall over manual install | Unattended and reproducible |
| Immutable image, sealed before templating | No configuration drift across clones |
| Root disabled, key-only SSH | Least privilege |
| Console password kept | Recover a VM that lost network |
| No first-boot updates | Fast, predictable clone boots |
| IPv6 disabled | Avoids dual-stack surprises on this LAN |
| Tailscale installed but not authenticated | Keeps the image credential-free |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Build hangs waiting for SSH | `ssh_authorized_keys` doesn't match `ssh_private_key_file`, or the VM can't reach the HTTP server | Verify the keypair; set `http_interface` to the LAN NIC |
| VM never fetches `user-data` (installer sits at the prompt) | HTTP server bound to a VPN/WSL address | `http_interface`, and the WSL port-proxy above |
| Cloud-init upgrades packages on first boot | Missing/invalid `99-disable-updates.cfg` | Recreate it and re-seal |
| Console login fails | Account locked (`!` in `/etc/shadow`) | Set a valid `password_hash` and rebuild |
| `checksum mismatch (file change by other user?) (500)` | Cloud-init seed modified post-install | Only static files under `/etc/cloud/cloud.cfg.d` should be touched |
| Proxy not applied | Variables not exported globally | Check `/etc/environment` and `/etc/apt/apt.conf.d/proxy.conf` |
| `vm_id` already exists | Previous template still on the node | Delete it or change `vm_id` |
