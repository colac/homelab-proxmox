# colac.homelab.agent_access

A limited account for AI agents on one Linux host, so an agent can
troubleshoot (and, later, mitigate after a human approves) without being
able to crash the host, delete data, read secrets or install anything.

The pattern is Red Hat's for AI troubleshooting on RHEL (the MCP server for
RHEL): a dedicated non-root account, key-only SSH with host-key checking, a
fixed set of read-only commands rather than a shell, logs through the `adm`
and `systemd-journal` groups, and credentials redacted from the output.
Mitigation is a second tier with its own key, off by default.

| Piece | On the host |
|---|---|
| Account `homelab-agent` | System account, no usable password, groups `adm` and `systemd-journal` only (never `docker`, which is root-equivalent) |
| `authorized_keys` | Root-owned. Each key: `restrict` (no pty, forwarding, X11, agent, file transfer), `from=` the LAN, `command=` the dispatcher with its tier |
| `/usr/local/sbin/homelab-agent-ctl` | The dispatcher: parses the requested command without a shell, validates every argument, runs fixed command lines, redacts, logs each call to syslog (`homelab-agent-ctl`), which reaches Kibana |
| `/etc/sudoers.d/homelab-agent` | Only `homelab-agent-ctl --root …`: the dispatcher re-runs itself as root for the verbs that need it and validates again |
| `/etc/homelab-agent/policy.json` | What the act tier may touch, the cooldown, the daily cap, the paths and log files the read tier may see |
| `/var/lib/homelab-agent-ctl/actions.json` | Root-only memory of mitigations, for the cooldown |

## Verbs

`help` lists them with this host's policy.

- **Read** (the read key): `failed`, `status <unit>`, `journal [<unit>]`,
  `logfile <path>` (listed files), `df`, `du <path>` (listed paths), `top`,
  `facts`, `net`, `docker-ps`, `docker-logs <container>`,
  `docker-state <container>` (State only: a full `docker inspect` shows
  the environment, which holds secrets), `docker-stats`, `docker-df`,
  `actions`.
- **Act** (the act key, only when `agent_access_act_enabled`):
  `restart-unit <unit>`, `restart-container <container>`, both limited to
  the lists in inventory; `free-disk journal|apt|docker-images`: caches,
  dangling images and build cache, never data, volumes or `image prune -a`.
  A second action on the same target within `agent_access_cooldown_hours`
  is refused: needing it again that soon means a bigger problem, for a
  human. At most `agent_access_max_actions_per_day` per host. The host
  enforces both, so a faulty client cannot loop.

Deliberately absent: any file read outside the listed logs, `docker exec`,
a full `docker inspect`, package operations, deletion of anything but
caches, and any shell.

## Use

Prerequisite on the controller: `mise run agent install` in
homelab-proxmox-monitoring, which creates the key pairs in
`~/.config/homelab-agent/ssh/` (`read_ed25519`, `act_ed25519`). The role
reads their public halves from there and writes, also there, an ssh
`config` entry and `known_hosts` line per host. Then, from the monitoring
checkout: `mise run hostctl <host> <verb>`.

```yaml
- hosts: monitoring
  become: true
  roles:
    - role: colac.homelab.agent_access
      vars:
        agent_access_restart_units: [elastic-agent]
        agent_access_restart_containers: [kibana, fleet-server]
        agent_access_free_disk: [journal, apt, docker-images]
```

The act key is authorised only when `agent_access_act_enabled: true`.
Approval is the wrapper's job (monitoring's agent/, L2): the read key, which
the model and interactive sessions use, cannot mitigate at all.
