# Ubuntu 24.04 Proxmox Packer Template

This repository defines a **production-ready, hardened Ubuntu 24.04 LTS base image** built with **Packer** for **Proxmox**.
It follows **immutable infrastructure principles**, designed for **repeatable, secure, and modular deployments**.

---

## 🧱 Overview

This template automates the provisioning of an Ubuntu 24.04 image with:

- **Cloud-init** and **Autoinstall** integration
- **Proxmox ISO builder** (`proxmox-iso`)
- **QEMU Guest Agent** preinstalled
- **Docker CE** (optional via variable)
- **Strict security hardening** (root disabled, SSH hardened, IPv6 disabled)
- **Immutable cleanup & sealing** before converting to a template

---

## 📁 Repository Structure

```txt
.
├── ubuntu-24.04.pkr.hcl             # Main Packer template definition
├── variables.pkr.hcl                # Input variables (user-defined)
├── versions.pkr.hcl                 # Plugin versions and dependencies
├── locals.pkr.hcl                   # Local helper variables
├── http/
│   ├── user-data.yml.tpl            # Cloud-init Autoinstall configuration
│   └── meta-data.yml
└── scripts/
    ├── 00-configure-proxy.sh
    ├── 10-install-custom-ca.sh
    ├── 20-install-docker.sh
    ├── 30-install-alloy.sh
    └── 99-cleanup-seal.sh
```

---

## ⚙️ Configuration Variables

The variables are defined in `variables.pkr.hcl`. They can be overridden via:

- `packer build -var-file=variables.pkrvars.hcl`
- Environment variables (e.g., `PKR_VAR_proxmox_api_url`)

| Variable | Description | Default |
|-----------|-------------|----------|
| `proxmox_api_url` | Proxmox API endpoint | — |
| `proxmox_api_token_id` | Token ID for API authentication | — |
| `proxmox_api_token_secret` | Token secret | — |
| `proxmox_node` | Target Proxmox node name | `pve1` |
| `proxmox_storage_pool` | Storage pool for disks and ISOs | `local-lvm` |
| `proxmox_bridge` | Network bridge | `vmbr0` |
| `vm_name` | Name of resulting template | `ubuntu-24-04-template` |
| `vm_id` | Numeric VM ID | `9000` |
| `vm_cpu_cores` | CPU cores | `2` |
| `vm_cpu_sockets` | CPU sockets | `1` |
| `vm_cpu_type` | CPU type | `host` |
| `vm_memory` | Memory (MB) | `2048` |
| `disk_size` | Disk size (GB) | `20` |
| `vm_timezone` | System timezone | `UTC` |
| `vm_locale` | Default locale | `en_US.UTF-8` |
| `ssh_username` | Primary user | `ubuntu` |
| `ssh_public_key` | Public key for SSH login | — |
| `enable_proxy` | Whether to configure proxy | `false` |
| `install_docker` | Whether to install Docker | `true` |

---

## 🔐 Security Hardening

The image enforces the following security controls:

### SSH

- **Root login disabled** (`PermitRootLogin no`)
- **Password authentication disabled** (`PasswordAuthentication no`)
- **Key-only SSH** (via cloud-init authorized keys)
- Optional **console password login** for `ssh_username` (if autoinstall sets a password hash)

### Users

- Root account locked (`passwd -l root`)
- Main user unlocked for console (optional)
- Sudo privileges configured via `/etc/sudoers.d/90-cloud-init-users`
- Duplicate sudoers entries automatically cleaned during sealing

### Network

- **IPv6 disabled** in sysctl and GRUB
- Optional HTTP/HTTPS proxy configuration
- `no_proxy` support for internal services

### Updates and cloud-init

- **Automatic package upgrades disabled** by `/etc/cloud/cloud.cfg.d/99-disable-updates.cfg`
- `apt-daily` and `apt-daily-upgrade` timers disabled
- Ensures clones never perform network upgrades on first boot

### Time sync

- `systemd-timesyncd` enabled and verified
- NTP synchronization validated before sealing

---

## 🧩 Proxy Configuration

Proxy configuration is modular and optional.
If `enable_proxy` is `true`, the following variables are used:

| Variable | Purpose |
|-----------|----------|
| `http_proxy` | HTTP proxy URL |
| `https_proxy` | HTTPS proxy URL |
| `no_proxy` | Comma-separated list of exceptions |

These are configured for:

- System environment (`/etc/environment`)
- APT configuration (`/etc/apt/apt.conf.d/`)
- Docker daemon (`/etc/systemd/system/docker.service.d/proxy.conf`)

---

## 🧩 Build Process

### Requirements

- Packer ≥ 1.10.x
- Proxmox 9+
- Ubuntu 24.04 ISO available in storage
- API token with VM template management privileges

### Steps

```bash
packer init .
packer validate ubuntu-24.04.pkr.hcl
packer build -var-file=variables.pkrvars.hcl .

# Debug logs
PACKER_LOG=1 packer build -var-file="variables.pkrvars.hcl" .
```

**Outputs:**

- A sealed, hardened Proxmox VM template
- Manifest file for version tracking

---

## 🧹 Cleanup & Sealing

The final cleanup (`scripts/99-cleanup-seal.sh`) performs:

- Apt cache and log cleanup
- Cloud-init cleanup (`cloud-init clean --logs --machine-id`)
- Removal of `/var/lib/cloud/instances` and temporary data
- SSH host key regeneration on clone
- Disk zero-fill to optimize template compression
- Graceful shutdown

---

## 🧠 Design Decisions

| Decision | Reason |
|-----------|--------|
| **Cloud-init Autoinstall** | Reliable, unattended OS provisioning |
| **Immutable cleanup** | Prevent configuration drift across clones |
| **Root disabled by default** | Principle of least privilege |
| **User-unlock + console login** | Enable safe troubleshooting access |
| **No first-boot updates** | Faster and predictable provisioning |
| **IPv6 disabled** | Avoid unwanted dual-stack complexity |
| **Two-phase validation** | Catch errors before sealing |

---

## 🧾 Troubleshooting

| Symptom | Cause | Fix |
|----------|--------|----|
| Cloud-init upgrades packages on first boot | Missing or invalid `/etc/cloud/cloud.cfg.d/99-disable-updates.cfg` |
| Console login fails | Account locked (`!` prefix in `/etc/shadow`) | autoinstall password |
| `checksum mismatch (file change by other user?) (500)` | Cloud-init seed modified post-install | Ensure only static `/etc/cloud/cloud.cfg.d` files are touched |
| Proxy not applied | Variables not exported globally | Verify `/etc/environment` and `/etc/apt/apt.conf.d/proxy.conf` |

---

## 📌 Notes

- Template is **immutable** and **secure by default**
- Console login only for emergency troubleshooting
- System updates must be handled via CI/CD or Ansible
- Cloud-init configuration prevents first-boot drift

---
