# TODO / Roadmap

The single place core's status lives, plus the homelab-wide items no other
repo owns. When something lands, check it off here — `README.md` and
`CLAUDE.md` point at this file rather than duplicating status inline. Each of
the other repos has its own `TODO.md`: monitoring for the Elastic Stack,
workloads for Nextcloud and k3s.

## The split into three repos

- [x] **monitoring** and **workloads** extracted with `git filter-repo`,
      keeping each path's history; core keeps the templates, `base-vm`, and
      the shared roles as the `colac.homelab` collection
- [x] `common` reduced to generic asserts; the Elasticsearch ones moved to
      monitoring's `elastic_preflight`
- [x] mise replaces the Makefile, `install-*.sh` and the four `.envrc` files;
      `.mise/sops-exec` decrypts per command, one profile per consumer
- [x] Secrets split per repo (and per app in workloads); the shared
      `reverse_proxy_acme_email` key renamed `acme_email`
- [ ] **Release core as `v2.0.0`** (merge with a `BREAKING CHANGE:` footer) —
      the tag both consumers pin; `terraform init` and `mise run setup` there
      fail until it exists
- [ ] **Create the GitHub repos** `colac/homelab-proxmox-monitoring` and
      `colac/homelab-proxmox-workloads`, push, and enable the release workflow
- [ ] **Revisit the committed `.claude/settings.json` in all three repos**:
      swap the `make`/`.venv` entries for the mise tasks, deny `sops -d` and
      `sops-exec` outright, keep `apply`/`play`/`packer build` on ask
- [ ] **Keep `galaxy.yml`'s version in step with releases**, or have
      semantic-release write it (`@semantic-release/exec`)

## Templates (Packer)

- [x] **Ubuntu 26.04 base template.** `packer/ubuntu-26.04/` builds the same
      image on 26.04 LTS at VM ID 9001, so it sits alongside the 24.04
      template rather than replacing it. Docker and Tailscale both publish
      `resolute` repos and every autoinstall package still exists, so the
      provisioning scripts are unchanged
- [x] **Split OS and Docker data disks.** 24G LVM OS disk in the 26.04
      template; a second disk attached by `base-vm`'s `data_disk_size` and
      turned into `docker-vg` by the `docker_data` role, mounted at
      `/var/lib/docker`. k3s gets 12G, monitoring 100G. Nextcloud left alone
- [ ] **Actually build and cut over to 26.04.** The 26.04 tree is validated by
      `packer validate` only — it has never been run against the ISO. The
      autoinstall's GRUB keystrokes, the reworked LVM storage config, and
      26.04's switch to `sudo-rs` and Rust `coreutils` are what a live build
      would test. Confirm with `lsblk` that `ubuntu-vg` actually exists —
      the 24.04 template silently produced none. Cutting over is then a
      `template_name` change in each consumer project, one at a time, and a
      re-clone. Working notes: [RUNBOOK-2604.md](RUNBOOK-2604.md)

## Module (Terraform)

- [ ] **`sockets` deprecation in `modules/base-vm`.** `terraform validate`
      warns that `sockets = 1` should be `cpu { sockets = }`. Every consumer
      picks it up on its next pin bump, and it changes the live Nextcloud VM's
      plan — release it on its own and read each plan, not as a drive-by

## DNS (homelab-wide)

- [ ] **PiHole as code, in core.** It runs on the Proxmox host outside every
      repo, is not monitored, and holds the A records everything depends on
      (`pve.<zone>` included — Packer and Terraform need it). Bring its config
      and the record list into core, rendered by Ansible
- [ ] **A second resolver off the Proxmox host** (TrueNAS app or a Pi), from
      the same config, handed out by DHCP — today DNS dies with the hypervisor
- [ ] **CoreDNS** as an authoritative zone with transfers to the secondary —
      only once k3s needs wildcard records or the record list outgrows PiHole

## Repo / tooling

- [ ] **Enable the commented-out pre-commit hooks.** `ansible-lint`,
      `yamllint` and `gitleaks` are configured but disabled in
      `.pre-commit-config.yaml`. `ansible-lint` passes at the production
      profile, so it can be turned on now
- [ ] **`mise.lock`.** Run `mise lock` once and commit it, so every machine
      installs byte-identical tools (checksums, not just versions)
- [ ] **A read-only agent identity.** A separate age key and a
      `PVEAuditor`-only Proxmox token an AI agent can use for validation and
      plans, with builds and applies kept for the human
