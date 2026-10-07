# AGENTS.md — DNS (Pi-hole)

Agent instructions for `dns/` (Claude Code loads this via `CLAUDE.md` when
working here). Core's rules — secrets, git, Ansible — are in
[../AGENTS.md](../AGENTS.md); the runbook is [README.md](README.md).

These are the LAN's resolvers: a Raspberry Pi (`pihole-pi`, primary, `.53`,
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
`dns:tf …`, `dns:play …`.

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
