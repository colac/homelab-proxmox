# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

The **core layer** of a three-repo homelab on Proxmox VE: the pieces every VM
is built from. It runs no Terraform, has no inventory, and never touches a
running VM.

| Repo (siblings under `~/git-repos/`) | Owns |
|---|---|
| `homelab-proxmox` — **this, core** | Packer templates, the `base-vm` Terraform module, the `colac.homelab` Ansible collection (`common`, `docker_data`), homelab-wide docs, TrueNAS notes |
| `homelab-proxmox-monitoring` | The monitoring VM (Elastic Stack) and Elastic Agent enrollment on every host |
| `homelab-proxmox-workloads` | The apps, one folder each: Nextcloud, k3s |

Everything here is consumed by the other two **at a pinned release tag** — a
change lands on a VM only when a consumer bumps its pin. So a change here is
an API change: keep it backward compatible, or mark it `BREAKING CHANGE:` and
say what consumers must do. Work on Elastic or Nextcloud belongs in those
repos — do not re-add it here.

Docs by scope: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) is the
homelab-wide picture and **the list of cross-repo contracts** (update it when
one changes); each component folder documents itself
([packer](packer/README.md), [terraform](terraform/README.md),
[ansible](ansible/README.md), [scripts](scripts/README.md),
[TrueNAS](TrueNAS/README.md)); [TODO.md](TODO.md) is the status tracker for
core and homelab-wide items — check items off there, not here.

## Layout

```text
packer/ubuntu-24.04/        Template build (proxmox-iso), VM ID 9000 — Nextcloud clones it
packer/ubuntu-26.04/        Same on 26.04 LTS with LVM, VM ID 9001 — monitoring, k3s
terraform/modules/base-vm/  The one VM module; consumers use ?ref=vX.Y.Z
ansible/                    The colac.homelab collection (galaxy.yml at its root)
  roles/common/             Generic preflight asserts — nothing workload-specific
  roles/docker_data/        /var/lib/docker + containerd's store on the LVM data disk
docs/ARCHITECTURE.md        Layers, contracts, runtime, secrets, rollout
scripts/                    Standalone ops helpers (disk vetting); not pipeline
TrueNAS/                    NAS install/hardening notes (not Ansible-managed)
RUNBOOK-2604.md             Temporary cross-repo rollout notes for the 26.04 template
.mise/sops-exec             The only thing that decrypts secrets.yaml
mise.toml                   Tools, env, tasks (`mise tasks`)
```

## Decisions that are deliberate (do not "fix" these)

- **App/VM config is Ansible's, not cloud-init's.** The owner hit timeouts and
  hangs using cloud-init directly with Proxmox. `base-vm` uses cloud-init only
  for the login user and SSH key.
- **`common` stays generic.** It is run by every consumer, so it asserts only
  what every host needs (address, Ubuntu, Docker, Compose). Workload-specific
  checks live in the workload's repo — the Elasticsearch ones are monitoring's
  `elastic_preflight`. Do not move them back.
- **Elasticsearch's OS prerequisites are baked into the templates**, not
  applied by Ansible: `vm.max_map_count` (a hard bootstrap check — ES refuses
  to start below 262144), memlock/nofile limits, and `/opt/elastic`. They are
  a contract with the monitoring repo; removing one breaks it. Changing any of
  them means rebuilding the template.
- **The 26.04 template drops `storage.layout`, and that is what turns LVM on.**
  Subiquity ignores `storage.config` entirely when `storage.layout` is also
  present. `packer/ubuntu-24.04` sets both, so its LVM block is dead and the
  24.04 template has **no LVM** — which is also why its volumes summing to 35G
  on a 32G disk never failed to build. Do not "restore" `layout:` for symmetry.
- **No logical volume is sized `-1`.** The leftover extents in `ubuntu-vg` are
  deliberate headroom: `lvextend` + `resize2fs` grows whatever fills first.
- **The Docker data disk is Terraform's and Ansible's, never Packer's.** The OS
  disk (24G, LVM) is baked; the data disk is attached by `base-vm`'s
  `data_disk_size` and turned into `docker-vg`/`docker-lv` by `docker_data` at
  first run. Partitioning it in the golden image would give every clone
  byte-identical PV/VG UUIDs, so moving a disk would need `vgimportclone`.
- **Images live on the data disk too, via a bind mount of `/var/lib/containerd`.**
  Docker's containerd image store keeps images in containerd's root, which a
  mount at `/var/lib/docker` does not cover — that filled the monitoring VM's
  12G root. `docker_data` bind-mounts `/var/lib/docker/containerd-root` over
  `/var/lib/containerd`. Do not swap it for `root =` in
  `/etc/containerd/config.toml` (a package conffile) or for disabling the image
  store in `daemon.json` (it is Docker's default). Systemd drop-ins make
  containerd and Docker *require* both mounts, so a host missing its data disk
  boots with Docker down instead of running it empty on the OS root.
- **The Elastic Agent package is pre-installed by Packer and left disabled.**
  There is nothing to enroll against at build time. Monitoring's
  `elastic_agent` role enrolls and starts it, and reinstalls when the version
  drifts from its `stack_version`.
- **Consumers pin tags, never branches** — `?ref=vX.Y.Z` for the module,
  `version: vX.Y.Z` for the collection. `galaxy.yml`'s `version` does not
  select anything; bump it on a breaking role change anyway, so installs are
  distinguishable.
- **Template names are a contract.** Never rename or renumber a template in
  place; build the replacement alongside under a new `vm_id`.

## Toolchain & how to run things

mise pins every tool (`mise.toml`) and provides every entry point. There is no
Makefile, no `install-*.sh`, and no direnv.

```bash
mise run lint                   # pre-commit on every file + ansible-lint
mise run lint:ansible           # ansible-lint (production profile) on the collection
mise run tf:validate            # base-vm: fmt + validate, no backend, no credentials
mise run secrets:check          # names missing keys; never prints values
packer validate -syntax-only packer/ubuntu-26.04   # no credentials needed
```

`mise run packer:validate|build <release>` need credentials and are for the
human (ask first). pre-commit's `packer_validate` is syntax-only for the same
reason.

- ansible-lint must pass at the **production** profile (`ansible/.ansible-lint`).
- Pins are load-bearing and shared with the other two repos: Terraform
  `1.15.7`, Telmate/proxmox provider `3.0.2-rc07`, terraform-docs `0.21.0`,
  ansible-core `2.17.14`, community.general `<13` (13.x needs ansible-core
  2.18). Don't bump them casually; bump here first.

## Secrets — SOPS + age, decrypted per command

- **`secrets.yaml` IS committed.** SOPS encrypts values in place, so the file
  is ciphertext. It is deliberately absent from `.gitignore` and allowlisted in
  `.gitleaks.toml`. Adding it to `.gitignore` would silently stop it from ever
  being committed — that was a real bug in the elastic repo.
- **Never read, print, `cat`, `grep` or `sed` `secrets.yaml`,
  `mise.local.toml`, the age key, or the git-ignored `*.pkrvars.hcl`. Never
  run `sops -d`, `sops decrypt` or `.mise/sops-exec` yourself.** Reference
  secrets by key name only; `secrets.yaml.example` lists them and
  `mise run secrets:check` reports missing ones without values.
- **Nothing is exported into the shell.** `.mise/sops-exec packer <cmd>`
  decrypts for one command and exports only `PKR_VAR_*`. Core holds only the
  template-build credentials; the Terraform token and app secrets live in the
  other repos. Never add one here.
- The `while read` decrypt loop in `sops-exec` is deliberate: `eval` would
  re-parse plaintext as shell, and any value with a space, quote or `$` breaks
  or is word-split — verified, it drops the value entirely.
- `secrets.yaml.example` is the tracked plaintext key reference. Keep its
  **keys** in sync with `secrets.yaml`; never put a real value in it.
- SSH **private** keys stay in `~/.ssh/` (the deploy key is
  `~/.ssh/homelab-proxmox`); public keys may appear in example files.

## Conventions

- **Conventional Commits**, enforced by commitlint + semantic-release
  (versioning, tags and `CHANGELOG.md` are automated — don't hand-edit or bump
  versions). Commit only when asked; the human pushes.
- **Ansible role variables are prefixed with the role name**, register names
  too, after an optional leading underscore (`_docker_data_current_mount`).
- Markdown: heading levels increment by one (MD001); fenced code blocks
  declare a language (MD040).
