# AGENTS.md — homelab-proxmox (core)

Instructions for AI coding agents working in this repo. Humans start at
[README.md](README.md). Read the linked doc before working in its area; the
rules below are the ones that must hold in every session.

## What this repo is

The core layer of a three-repo Proxmox homelab: Packer templates, the
`base-vm` Terraform module, and the `colac.homelab` Ansible collection
(`common`, `docker_data`). It runs no Terraform and has no inventory — it never
touches a running VM. Siblings in `~/git-repos/`:

- `homelab-proxmox-monitoring` — the Elastic Stack VM, agents on every host
- `homelab-proxmox-workloads` — the apps (Nextcloud, k3s), one folder each

Consumers use this repo **at a release tag**, so every change here is an API
change: keep it backward compatible, or add a `BREAKING CHANGE:` footer saying
what consumers must do. Elastic and Nextcloud work belongs in those repos.

## Where to look

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layers and **the contracts
  between repos**; update it whenever one changes
- [docs/CREDENTIALS.md](docs/CREDENTIALS.md) — every credential: issue, store,
  rotate, add
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — mise tasks, conventions,
  releasing and bumping pins
- [packer/README.md](packer/README.md), [terraform/README.md](terraform/README.md),
  [ansible/README.md](ansible/README.md) — each component, with the reasons
  behind the decisions below
- [TODO.md](TODO.md) — status; check items off there, never in this file

## Commands

```bash
mise run lint                                     # pre-commit on all files + ansible-lint
mise run tf:validate                              # base-vm, no credentials
packer validate -syntax-only packer/ubuntu-26.04  # no credentials
mise run secrets:check                            # missing key names only
```

Need credentials — ask the human first: `mise run packer:validate <release>`,
`mise run packer:build <release>`.

## Rules

- **Secrets:** never read, print, `cat`, `grep` or `sed` `secrets.yaml`,
  `mise.local.toml`, the age key, or `*.pkrvars.hcl`; never run `sops -d`,
  `sops decrypt` or `.mise/sops-exec`. Refer to secrets by key name
  (`secrets.yaml.example`) and use `mise run secrets:check`. New secret →
  [CREDENTIALS.md § Adding a secret](docs/CREDENTIALS.md#adding-a-secret).
- **Git:** Conventional Commits; never edit `CHANGELOG.md` or version numbers;
  commit only when asked; the human pushes.
- **Ansible:** ansible-lint stays green at the production profile; role
  variables and `register:` names carry the role prefix.
- **Pins** (Terraform `1.15.7`, Telmate `3.0.2-rc07`, ansible-core `2.17.14`,
  community.general `<13`) are shared with both consumers — never bump one
  casually or in one repo only.

## Deliberate decisions — do not "fix"

- App and VM config is Ansible's, not cloud-init's; `base-vm` uses cloud-init
  only for the login user and SSH key.
- `common` stays generic: every consumer runs it. Workload-specific asserts
  live in that workload's repo (Elasticsearch's in monitoring's
  `elastic_preflight`).
- Elasticsearch's OS prerequisites (`vm.max_map_count`, memlock/nofile,
  `/opt/elastic`) are baked into the templates — a contract with monitoring.
  Changing one means a template rebuild.
- `packer/ubuntu-26.04` has no `storage.layout` key; that is what makes its LVM
  config apply. Do not add it back "for symmetry": 24.04 sets it, which is
  exactly why the 24.04 template has no LVM.
- No logical volume is sized `-1`: the free extents in `ubuntu-vg` are headroom.
- The Docker data disk is Terraform's (`data_disk_size`) and Ansible's
  (`docker_data`), never Packer's — a partitioned image would give every clone
  the same PV/VG UUIDs.
- `docker_data` bind-mounts `/var/lib/docker/containerd-root` over
  `/var/lib/containerd`. Do not replace it with `root =` in containerd's
  `config.toml` or by disabling the containerd image store.
- The Elastic Agent package is pre-installed by Packer and left disabled;
  monitoring enrolls it.
- `base-vm` declares `startup_shutdown` with `-1` values: Proxmox reports
  "unset" that way, and omitting it makes every plan propose a no-op change.
- `base-vm`'s `cpu { type }` is declared and matches the templates (`host`);
  a CPU type change makes the provider reboot the VM.
- Template names and VM IDs are a contract. Build a replacement alongside under
  a new `vm_id`; never rename one in place.
