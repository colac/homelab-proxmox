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
- [x] **Revisit the committed `.claude/settings.json` in all three repos**:
      swap the `make`/`.venv` entries for the mise tasks, deny `sops -d` and
      `sops-exec` outright, keep `apply`/`play`/`packer build` on ask
- [x] **`galaxy.yml`'s version follows releases**: `@semantic-release/exec`
      rewrites it and the release commit includes it. It stays `2.0.0` until
      the first release after this lands
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
- [x] **Roll out v2.0.1** (both fixes): plan each consumer against the
      unreleased module first (`mise run deps:dev`), release, then bump
      `?ref=` and `requirements.yml` to `v2.0.1`; each plan should say
      "No changes"
- [x] **VMs stayed off after a host reboot** (2026-10-28): the provider
      leaves `onboot` off, so nextcloud and monitoring stayed stopped from
      2026-10-24 until started by hand (Pi-hole, with `onboot`, came back).
      `base-vm` now sets `start_at_node_boot` (default `true`)
- [x] **Roll it out**: monitoring and workloads pin v2.3.0, and the
      nextcloud and monitoring VMs have `onboot: 1` (checked 2026-11-10)

## DNS (homelab-wide)

- [x] **Pi-hole as code, in core** (`dns/`): one role and one configuration
      for two resolvers, through `FTLCONF_*` (read-only in the UI); the record
      list is `dns/ansible/inventory/group_vars/pihole.yml`
- [x] **Deployed the container** `pihole-ct` at `192.168.1.153` (2026-10-07,
      Terraform workspace `DNS`, health check green) and made it the router's
      DNS server; the hand-built Pi-hole at `.53` is stopped
- [x] **Tailscale split-DNS → `192.168.1.153`** — it still names `.53`, which
      is stopped, so off-LAN devices cannot resolve the zone until it changes
- [x] **Delete the hand-built Pi-hole container** after a quiet week (from
      2026-10-14) — until then `pct start` on it is the rollback
- [ ] **Router:** DHCP reservation for `.153` (`BC:24:11:00:01:53`), and check
      what it advertises as IPv6 DNS. Server 2: not a public resolver (it
      leaks ads and breaks private names at random) — `.153`, with the Pi as
      server 1 (the switch-over below). On 2026-11-10 a laptop on the LAN got
      `1.1.1.1` as its second DNS server
- [x] **Added the Raspberry Pi as primary** at `192.168.1.53` (2026-11-18;
      Pi 3 B+, Raspberry Pi OS Lite 64-bit on Debian 13), configured by the
      same playbook. Flashed with Raspberry Pi Imager, then the first-boot
      files `dns/raspberry-pi/write-boot-config.sh` writes (hostname, user,
      deploy key, static `.53`)
- [ ] **`mise run dns:pi-image <device>`:** flash the card and write the
      first-boot files in one step, instead of Imager then the script
- [ ] **Switch over to the Pi:** router server 1 → `.53` (server 2 → `.153`)
      and a DHCP reservation for `.53`; Tailscale split-DNS adds `.53`;
      TrueNAS: already declared (`.53` first, `.153` second, in
      `TrueNAS/ansible/inventory/group_vars/truenas.yml`), applied by the next
      `mise run truenas:play playbooks/site.yml`. Until then DNS still goes
      down with Proxmox. Monitoring's
      `docs/ai-ops/deployment.md` step 8 has the same list
- [ ] **Updates for the Pi:** `updates/` cannot update it yet.
      `updates/ansible.cfg` loads only the generated `pihole.yml`, and
      `updates/inventory/group_vars/pihole.yml` sets `update_kind: lxc` and
      `update_proxmox_name: pihole` for the whole group, so the Pi would be
      treated as the container. The `update` role knows only `vm`, `lxc` and
      `pve`; a physical host needs its own kind (no snapshot, its own reboot).
      Until then: `apt` by hand, which also covers ntfy and Tailscale
- [x] **Monitor them:** both are agent targets on `dns-agents-policy`
      (`pihole-ct` 2026-10-08, `pihole-pi` 2026-11-18); the `pihole-silent`
      alert rule is written in monitoring, not applied yet
- [ ] **The Pi's notification services** (`dns/NTFY.md`: Tailscale, the
      private ntfy, the doorbell): written 2026-11-19, not applied. Steps in
      monitoring's `docs/ai-ops/deployment.md`, step 1
- [ ] **Move `home-nas.local` into the zone** (`nas.<zone>`): `.local` is
      mDNS's, and some clients never ask Pi-hole for it
- [ ] **CoreDNS** as an authoritative zone with transfers to the secondary —
      only once k3s needs wildcard records or the record list outgrows Pi-hole

## Repo / tooling

- [ ] **Enable the commented-out pre-commit hooks.** `ansible-lint`,
      `yamllint` and `gitleaks` are configured but disabled in
      `.pre-commit-config.yaml`. `ansible-lint` passes at the production
      profile, so it can be turned on now
- [ ] **`mise.lock`.** Run `mise lock` once and commit it, so every machine
      installs byte-identical tools (checksums, not just versions)
- [ ] **AI agent identities.** Written 2026-11-20, not applied:
      `colac.homelab.agent_access` (a forced-command `homelab-agent` account on
      every Linux host) and `homelab-agent@pve` (`proxmox/configure.sh`).
      Steps in monitoring's `docs/ai-ops/deployment.md`, steps 4 and 5. Still
      open from the first idea: a separate age key, so an agent could run
      plans without the human's key
