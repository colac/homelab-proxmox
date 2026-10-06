# Ansible collection `colac.homelab` — shared host roles

The roles every VM in the homelab runs, whichever layer owns it. This repo
does not run them: it has no inventory and no playbooks. The
[monitoring](https://github.com/colac/homelab-proxmox-monitoring) and
[workloads](https://github.com/colac/homelab-proxmox-workloads) repos install
the collection from git, pinned to a release tag of this repo, and call the
roles by their fully qualified names in their own `00-bootstrap.yml`.

| Role | Does | Mutates? |
|---|---|---|
| `colac.homelab.common` | Preflight asserts: the host has an address, runs a supported Ubuntu, has Docker and Compose | No |
| `colac.homelab.docker_data` | Puts `/var/lib/docker` (and containerd's image store) on the Terraform-attached data disk, under LVM | Yes |

Why a collection rather than a copy in each repo: a fix to `docker_data` —
like the containerd bind mount that stopped the monitoring VM's root filling
up — is made once, released once, and rolled out by bumping one pin per
consumer. Copies drift.

## Consuming it

In the consumer's `ansible/requirements.yml`:

```yaml
collections:
  - name: https://github.com/colac/homelab-proxmox.git#/ansible/
    type: git
    version: v2.0.0     # a tag of this repo, never a branch
```

```yaml
# playbooks/00-bootstrap.yml
- name: Preflight
  hosts: monitoring
  roles:
    - colac.homelab.common
    - colac.homelab.docker_data
```

`mise run setup` in the consumer installs it. To try an unreleased change
from a sibling checkout before tagging, `mise run deps:dev` installs this
directory over the pinned one; `mise run setup` puts the pin back.

## Releasing a change

1. Change the role here, `mise run lint`.
2. Merge with a Conventional Commit — semantic-release tags it (`fix:` →
   patch, `feat:` → minor, a `BREAKING CHANGE:` footer → major).
3. Bump `version:` in each consumer's `requirements.yml`, `mise run setup`,
   and run its `00-bootstrap.yml` with `--check` first.

Bump `version:` in [`galaxy.yml`](galaxy.yml) on a breaking change too. It
does not select anything (the tag does), but it is what
`ansible-galaxy collection list` shows.

## `common`

Preflight asserts only, nothing mutating. Checks the host has an address (a
Terraform-generated inventory fragment written before the guest agent reported
an IP has none), runs a supported Ubuntu, and has Docker and Compose — all
baked by the Packer template, so a failure here means a host cloned from the
wrong template.

Checks that belong to one workload are not here. The Elasticsearch
prerequisites (`vm.max_map_count`, the stack passwords) are asserted by the
monitoring repo's `elastic_preflight` role.

## `docker_data`

Puts `/var/lib/docker` on the second disk Terraform attaches (`base-vm`'s
`data_disk_size`), under LVM, so it can be grown later without repartitioning
and detached and moved to another VM.

This is where the data actually is. Every service in the homelab keeps state in
*named Docker volumes* — Elasticsearch's `esdata`, Nextcloud AIO's
`nextcloud_aio_mastercontainer`, Caddy's `nextcloud_caddy_data` — and those live
under `/var/lib/docker/volumes`. The data disk's size, not `disk0_size`, is
what caps retention.

Images go there too. Docker's containerd image store keeps them in
`/var/lib/containerd`, outside `/var/lib/docker`, so the role bind-mounts
`/var/lib/docker/containerd-root` over it, moving any existing content across
first and deleting the OS-disk copy. Systemd drop-ins make `containerd` and
`docker` require both mounts: without the data disk the VM boots with Docker
stopped rather than running it empty on the OS root.

It distinguishes three states before writing anything:

| Device state | What it does |
|---|---|
| Blank | `pvcreate` → `vgcreate docker-vg` → `lvcreate` → `mkfs` → seed from the existing `/var/lib/docker` → mount |
| Already an LVM PV in `docker-vg` | Adopts it untouched. This is the path when a populated disk is moved from another VM. |
| Anything else | Refuses and says why, rather than running `pvcreate` over it |

Hosts with no data disk attached skip the role and keep `/var/lib/docker` on
the OS disk, so it is safe to run against every host. Run it before any play
that starts a container: seeding the volume means stopping Docker — cheap on a
fresh host, disruptive later.

Growing it: enlarge the disk in Proxmox, `pvresize /dev/sdb`, then re-run the
role — `lvol` extends the volume and the filesystem with it. Moving it: set
`data_disk_size` on the *receiving* Terraform project to `null` so that VM has
no `docker-vg` of its own, detach the disk in Proxmox, attach it there, and
re-run. Two volume groups of the same name on one host is the one case that
needs a manual `vgrename <vg-uuid> docker-vg` first.

Why the disk is partitioned here and not in the Packer template: a full clone
copies LVM metadata verbatim, so every VM would get byte-identical PV and VG
UUIDs and moving a disk would need `vgimportclone`.

## Linting

```bash
mise run lint:ansible     # ansible-lint at the production profile, from ansible/
```

Role variables are prefixed with the role name (`docker_data_*`,
`_common_*` for registers) — the production profile enforces it.
