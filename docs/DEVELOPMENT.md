# Development

How to work in any of the three homelab repos: tools, tasks, conventions and
releases. The repos share all of it, so it is written once, here. Each repo's
README covers only what is specific to it.

## Setup

The repos are siblings, and some tasks rely on that:

```text
~/git-repos/homelab-proxmox              core
~/git-repos/homelab-proxmox-monitoring
~/git-repos/homelab-proxmox-workloads
```

[mise](https://mise.jdx.dev) pins every tool and provides every entry point —
there is no Makefile and no direnv. Once per clone, and again after a
`mise.toml` change:

```bash
mise trust && mise install    # Terraform, Packer (core), sops, age, Python 3.12, Node, linters
mise run setup                # Python venv, Node tools, git hooks, tflint plugins, Ansible collections
mise tasks                    # everything this repo can run
```

`setup` installs the Ansible collections last, from core's release tag. To try
an unreleased core change, `mise run deps:dev` installs the sibling checkout
instead; `mise run deps` puts the pin back.

Credentials need their own one-time setup — see
[CREDENTIALS.md](CREDENTIALS.md). Per-machine settings (say, the LAN NIC
Packer should advertise behind a VPN) go in a git-ignored `mise.local.toml`:

```toml
[env]
PACKER_HTTP_INTERFACE = "enp3s0"
```

## Tasks

Arguments after a task name go straight to the tool, quoting intact. In
workloads the app comes first.

| | core | monitoring | workloads |
|---|---|---|---|
| Lint everything | `mise run lint` | `mise run lint` | `mise run lint` |
| Terraform validate (no credentials) | `mise run tf:validate` | `mise run tf:validate` | `mise run tf:validate` |
| Terraform (credentials) | — | `mise run tf:plan` / `tf:apply` / `tf <args>` | `mise run tf <app> <args>` |
| Ansible (credentials) | — | `mise run play <playbook> [args]` | `mise run play <app> <playbook> [args]` |
| Inventory / SSH check | — | `mise run inventory` / `ping` | `mise run inventory <app>` / `ping <app>` |
| Packer (credentials) | `mise run packer:validate <release>` / `packer:build <release>` | — | — |
| Secrets | `mise run secrets:edit` / `secrets:check` | same | same, plus `secrets:edit <app>` |
| Next release version | `mise run release:dry-run` | same | same |

A bare `terraform`, `packer` or `ansible-playbook` gets no credentials, by
design — run them through the tasks.

**Pins are load-bearing** and the same in every `mise.toml`: Terraform
`1.15.7`, Telmate/proxmox provider `3.0.2-rc07`, ansible-core `2.17.14`
(controller Python ≤ 3.12), community.general `<13` (13.x needs ansible-core
2.18). Bump them in core first, then the others — never one repo alone.

## Conventions

- **Conventional Commits**, checked by commitlint on every commit.
  semantic-release reads them to tag releases and write `CHANGELOG.md` — never
  edit either by hand. `fix:` → patch, `feat:` → minor, a `BREAKING CHANGE:`
  footer → major.
- **pre-commit** runs on every commit (`mise run lint` runs it on all files):
  terraform_docs and terraform_fmt, packer_fmt and syntax-only packer_validate
  (core), markdownlint, shellcheck, editorconfig, commitlint.
- **ansible-lint must pass at the production profile** (each `ansible/` has an
  `.ansible-lint`). Role variables and `register:` names are prefixed with the
  role name (`_docker_data_current_mount`). Non-secret values shared across
  hosts go in `inventory/group_vars/`, because role defaults are not visible
  cross-host.
- **Terraform docs are generated.** The block between `BEGIN_TF_DOCS` and
  `END_TF_DOCS` in a Terraform README is written by `terraform-docs`; edit the
  descriptions in the `.tf` files.
- **Markdown:** heading levels increment by one; fenced code blocks declare a
  language. MD013/MD033/MD060 are off.
- **Branches:** work on a branch; pre-commit refuses commits to `main`.

## Releasing a core change

Core's module, collection and templates reach a VM only when a consumer bumps
its pin, one consumer at a time:

1. Change core, `mise run lint`, merge with a Conventional Commit. The Release
   workflow tags `vX.Y.Z`.
2. In one consumer, bump the tag in every place it is pinned — they move
   together, so a repo is always on one core version:
   - `?ref=vX.Y.Z` in each `terraform/main.tf`
   - `version: vX.Y.Z` in each `ansible/requirements.yml`
3. `mise run deps`, then read the plan and the check-mode diff before applying:
   `mise run tf:plan` and `mise run play playbooks/00-bootstrap.yml --check --diff`
   (with the app name first in workloads).
4. Healthy → the next consumer. Not healthy → move the pin back.

A template change is different: build the new one alongside the old under a
new `vm_id`, then change `template_name` per project and re-clone.

## Docs map

| Question | Where |
|---|---|
| How do the layers fit; what crosses a repo boundary? | [ARCHITECTURE.md](ARCHITECTURE.md) |
| How do I issue, store or rotate a credential? | [CREDENTIALS.md](CREDENTIALS.md) |
| How do I work in these repos? | this file |
| How do I deploy X from zero? | monitoring's `RUNBOOK.md`, workloads' `nextcloud/README.md` |
| What is done and what is not? | each repo's `TODO.md` |
| What must an AI agent know? | each repo's `AGENTS.md` (imported by `CLAUDE.md`) |
