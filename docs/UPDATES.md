# Updates

How every machine and container in the homelab gets its updates. Each repo
runs the same procedure for the machines it owns. The procedure is the
`colac.homelab.update` playbook and the `update` role in this repo's
collection. Nothing updates from a central place, because the layers are
split on purpose ([ARCHITECTURE.md](ARCHITECTURE.md)).

| Repo | Command | Covers |
|---|---|---|
| core | `mise run update` | The Proxmox host and the Pi-hole container (`dns/`) |
| monitoring | `mise run update` | The monitoring VM: Elastic Stack, its Elastic Agent, the exporters |
| workloads | `mise run update <app>` (`nextcloud`) | The app's VM: Nextcloud AIO, Caddy |

TrueNAS is outside the procedure for now. Its updates go through its own UI
and are planned separately (`TrueNAS/`).

## What a run does

**`mise run update`: report only.** It refreshes apt's package lists and
changes nothing else. Per host it reports:

- pending packages (and how many are security updates);
- whether a reboot is needed (a newer kernel, or the OS asks for one);
- which services still run code from a replaced library;
- the health checks;
- each component's running version against its upstream release.

It also flags anything **untracked**:

- a running container that no component claims;
- on core's report, any Proxmox guest that no repo covers.

The report is printed and saved as JSON under `reports/` (git-ignored) in the
directory the playbook runs from. Upstream versions come from GitHub's releases API.
That API allows 60 calls an hour without a token, and a run makes a few.
Export `GITHUB_TOKEN` (any token, no scopes) if you run it often. A
component whose lookup fails shows `?`, and `apply` never acts on an unknown
version.

**`mise run update:apply`** goes host by host and stops the whole run at the
first failure:

1. **Refuses** a host that was already unhealthy, and a guest that does not
   match exactly one VM or container on Proxmox by name.
2. **Snapshots** the guest on Proxmox (`preupdate_<date>_<time>`; the last
   two are kept).
3. **`apt full-upgrade`**, keeping existing config files.
4. **Component updates** that the repo applies itself (`apply_role`): today
   `pihole -up` (core) and AIO's own update script (workloads).
5. **Reboots** only with `-e update_reboot=true`, and only guests that need it.
   The Proxmox host is never rebooted.
6. **Waits until healthy**. If the host is not healthy in time, the run stops
   and prints the rollback command (`qm rollback <vmid> <snapshot>`, or
   `pct rollback`, on the Proxmox host). The hosts after it are left untouched.
7. Reports again, so you can see what is still pending.

Flags (added after the command):

| Flag | Effect |
|---|---|
| `-e update_reboot=true` | Reboot guests that need it |
| `-e update_allow_pve=true` | Core: also upgrade the Proxmox host's packages |
| `-e '{"update_force": ["Nextcloud AIO"]}'` | Run a component's update even when its version is current |
| `-e update_snapshot=false` | Skip the snapshot (storage without snapshot support) |
| `--limit <host>` / `--limit '!<host>'` | One host only / all but one |

## What each component's update looks like

| Component | Repo | Reported | Applied by |
|---|---|---|---|
| OS packages, every host | each | apt | `update:apply` |
| Proxmox VE | core | `pveversion` | `update:apply -e update_allow_pve=true` |
| Pi-hole (core, web, FTL) | core | `pihole -v` | `update:apply` (`pihole -up`) |
| Nextcloud AIO, all its containers | workloads | AIO version, PHP | `update:apply nextcloud` (AIO's script) |
| Caddy | workloads | `caddy version` | bump `reverse_proxy_caddy_version`, `10-nextcloud.yml` |
| Elastic Stack (ES, Kibana, Fleet) | monitoring | image tag, newest patch of the running minor line | bump `stack_version`, monitoring's `RUNBOOK.md` § Upgrading the stack |
| Elastic Agent, every host | monitoring | its own VM's agent; every agent in Kibana → Fleet | follows `stack_version` (`50-elastic-agent.yml`) |
| Exporters | monitoring | image tags | bump the `exporters_*_image` pin, `45-exporters.yml` |
| Packer templates | core | — | rebuild now and then; clones get apt's updates either way |

Pinned versions (Caddy, Elastic, the exporters) stay deliberate changes in git:
the report says when a newer release exists, and you or a pull request bump the
pin. The procedure applies only what has no pin to bump: OS packages, Pi-hole,
and AIO, whose mastercontainer supports only `latest`.

## Adding a service

Every container and guest must be covered by some repo's procedure. That is
what makes "all updates are managed" checkable:

- **A new container:** add a component to that repo's `update_components`
  (`inventory/group_vars/update_targets.yml`), with `containers:` matching its
  name. Until then the report lists it as UNTRACKED.
- **A new VM or container on Proxmox:** put it in its repo's `update_targets`
  with `update_proxmox_name`, and add the name to core's
  `update_guests_elsewhere` (`updates/inventory/group_vars/all.yml`). Until
  then core's report lists it as UNTRACKED.
- **A health check:** `update_checks` (systemd units, a port, required
  containers, or a command's JSON output). Apply waits for these after
  updating, so they decide whether an update "worked".

The full contract is in `ansible/roles/update/defaults/main.yml`.

## Setup per repo

- **The Proxmox node:** monitoring and workloads list it in
  `ansible/update/proxmox.yml` (copy the `.example`; git-ignored). Only the
  update tasks read that file, so their other playbooks can never target the
  node. Core lists it in `updates/inventory/hosts.yml`. Snapshots and container
  restarts run there as root, over the same SSH as `ssh root@<node>`.
- **The collection:** core runs its own checkout (`updates/collections` is a
  symlink to `ansible/`). Monitoring and workloads use their pinned tag. A
  change to the role reaches them after a core release, a bump of the pin in
  their `requirements.yml`, and `mise run deps`. `mise run deps:dev` uses the
  sibling checkout in the meantime.

## Automation, step by step

1. **Now: manual.** You run `mise run update` in each repo and decide.
2. **Scheduled report.** A weekly timer runs the three reports and ships
   `reports/latest.json` into Elastic. A Kibana alert fires when something is
   pending, a reboot is due, or a host is unhealthy.
3. **Unattended low-risk updates.**
   - The Ubuntu VMs already install security updates by themselves; the timer
     adds the reboots.
   - The same for the Pi-hole container.
   - AIO's daily backup with automatic updates, once its Borg target exists.
   - Renovate pull requests for the pins.
4. **An AI agent.** It runs the same tasks, started by a timer or a Renovate
   pull request (Claude Code headless: `claude -p`, with a settings file that
   allows only the commands below). It reads the report and the release
   notes, applies what policy allows, checks health, and writes a summary.
   Anything else goes to you.

### Policy: what may run without a human

| Action | Today | With an agent (step 4) |
|---|---|---|
| `mise run update` (report) | Ask first (it reaches live hosts) | Allowed |
| `update:apply` on guests, no reboot | Ask first | Allowed, one repo at a time, stop on the first failure |
| `-e update_reboot=true` | Ask first | Allowed for guests; not on the Proxmox host |
| `-e update_allow_pve=true` | Ask first | Never: a human runs it |
| Pin bumps (Elastic, Caddy, exporters) | A pull request | The agent may open the pull request; a human merges and applies |
| Rollback from a snapshot | A human | A human (the agent only prints the command) |

The procedure needs no secrets, only the SSH key, so an agent never needs
`sops-exec` to run it.
