# TODO / Roadmap

The single place core's status lives, plus the homelab-wide items no other
repo owns. When something lands, check it off here — `README.md` and
`AGENTS.md` point at this file rather than duplicating status inline. Each of
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
- [x] **Released core as `v2.0.0`**; both consumers pin it
- [x] **GitHub repos created** — `colac/homelab-proxmox-monitoring` and
      `colac/homelab-proxmox-workloads`, both releasing
- [x] **Docs centralised in `docs/`**: `CREDENTIALS.md` (every credential:
      issue, store, rotate), `DEVELOPMENT.md` (tools, conventions, releases);
      `AGENTS.md` per repo, imported by a one-line `CLAUDE.md`
- [ ] **Revisit the committed `.claude/settings.json` in all three repos**:
      swap the `make`/`.venv` entries for the mise tasks, deny `sops -d` and
      `sops-exec` outright, keep `apply`/`play`/`packer build` on ask
- [ ] **Keep `galaxy.yml`'s version in step with releases**, or have
      semantic-release write it (`@semantic-release/exec`)
- [x] **JSON formatted like `terraform fmt`**: pre-commit's `check-json` and
      `pretty-format-json` (2-space, key order kept)

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
- [x] **Built the 26.04 template** (template ID 9006 here, via a local
      `variables.auto.pkrvars.hcl`) and moved monitoring onto it. Debugging
      notes from those builds are in `packer/README.md`
- [ ] **Move Nextcloud to 26.04** — tracked in the workloads repo's TODO; it
      needs the AIO backup/restore path first. Then the 24.04 template can go

## Module (Terraform)

- [x] **`startup_shutdown` drift**: every plan proposed removing the block
      Proxmox reports as `-1`. `base-vm` now declares it (`fix:` → v2.0.1)
- [x] **`cores`/`sockets` deprecation**: moved into `cpu { }`, with `type`
      declared (`host`, as the templates set it) so the move cannot change the
      live VMs' CPU model
- [ ] **Roll out v2.0.1** (both fixes): plan each consumer against the
      unreleased module first (`mise run deps:dev`), release, then bump
      `?ref=` and `requirements.yml` to `v2.0.1`; each plan should say
      "No changes"

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
