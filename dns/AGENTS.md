# AGENTS.md — DNS (Pi-hole) and the Pi's notification services

Agent instructions for `dns/` (Claude Code loads this via `CLAUDE.md` when
working here). Core's rules — secrets, git, Ansible — are in
[../AGENTS.md](../AGENTS.md); the runbook is [README.md](README.md).

Two deployments share this folder and its one inventory: **Pi-hole** on
both resolvers (group `pihole`, `playbooks/site.yml`, `mise run dns:play`) and
the **notification services** on the Pi only (group `ntfy`: Tailscale, ntfy,
the doorbell; `playbooks/ntfy.yml`, `mise run dns:play:ntfy`; runbook
[NTFY.md](NTFY.md)). Keep them separate: a change to one never touches the
other's playbooks, `group_vars` or services.

The resolvers are a Raspberry Pi (`pihole-pi`, primary, `.53`,
hand-flashed, in the git-ignored `inventory/hosts.yml`) and an LXC container
(`pihole-ct`, failover, `.153`, created by `terraform/`). Both get the same
configuration. A mistake here takes name resolution away from every device,
and from the Terraform and Packer runs that would fix it — so change one host
at a time (`--limit`) whenever the change could break resolution.

## Commands

```bash
mise run tf:validate        # includes dns/terraform; no credentials
mise run lint:ansible       # includes dns/ansible
mise run dns:inventory      # no credentials
```

Need credentials — ask the human first: `mise run dns:plan`, `dns:apply`,
`dns:tf …`, `dns:play …`, `dns:play:ntfy …`, and `mise run secrets:generate`
(it writes the ntfy keys into `dns/secrets.yaml`).

## Deliberate decisions — do not "fix"

- **Native Pi-hole on Debian 13** — an unprivileged LXC on Proxmox,
  Raspberry Pi OS Lite on the Pi — not Docker, not a VM. The role must stay
  host-agnostic: per-host differences (user, `become`) live in inventory.
- **Every setting is an `FTLCONF_*` variable** in `ftlconf.env`, loaded by a
  systemd drop-in. Never template or edit `pihole.toml` beyond the one-time
  seed (`force: false`) — Pi-hole rewrites it, and FTLCONF overrides it.
- **Records are relative to `pihole_zone`** (from `dns/secrets.yaml`), so the
  real domain never appears in the repo. Use `fqdn:` only for names outside
  the zone.
- **Adlists are insert-only** (`INSERT OR IGNORE`); never delete lists the
  role did not add.
- **Upgrades only with `-e pihole_upgrade=true`** — never as a side effect of
  applying config.
- **The container's own resolvers are public** (`bootstrap_nameservers`), not
  127.0.0.1: it must resolve the installer's downloads before Pi-hole exists.
- **`colac.homelab.common` is not run here** — it asserts Docker, which this
  container deliberately lacks.

## The notification services (`ntfy` group, the Pi only)

The Pi is also the primary resolver: anything here that breaks the Pi
breaks DNS for every device.

- **Never touch Pi-hole from these roles** (`tailscale`, `ntfy`,
  `ntfy_doorbell`): no restart, no config, no package.
- **Never Tailscale Funnel**, never a port forward: ntfy is reachable from
  the tailnet only. The tailscale role stops if Funnel is on.
- **`--accept-dns=false` stays**: the resolver keeps its own resolv.conf.
- **The ntfy credentials are generated, never typed**: the phone's
  password, the doorbell topic and the tokens are in `dns/secrets.yaml`
  (key names in `secrets.yaml.example`), made by `mise run secrets:generate`.
  Only the phone has a password; never add one for a client that can use a
  token. `ansible/.secrets-cache/` is the old plaintext location: never read
  it.
- **The doorbell carries nothing but its fixed text and a priority.** Alert
  content goes to the private server only.
- Topic names and the files under `/etc/ntfy/clients/` are a contract with
  monitoring ([NTFY.md](NTFY.md), "What other repos rely on").
