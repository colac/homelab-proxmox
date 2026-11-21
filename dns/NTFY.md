# The Pi's notification services: Tailscale, ntfy, the doorbell

The Raspberry Pi (`pihole-pi`) is the one machine that does not share a
failure with the Proxmox node, so it carries what must keep working when the
node is down. This is the second of `dns/`'s two deployments
([README.md](README.md)): Pi-hole runs on both resolvers; this one runs on
the Pi only, from the same inventory (group `ntfy`), and never touches
Pi-hole:

| Service | What it does | Role |
|---|---|---|
| Tailscale | Puts the Pi on the tailnet. `tailscale serve` publishes ntfy over HTTPS to the tailnet only, on port 8443; never Funnel | `tailscale` |
| ntfy | The private notification server: alerts, investigation updates, the phone's buttons. Listens on loopback; deny-all access rules | `ntfy` |
| Doorbell | Watches the private topics and rings a topic on the public ntfy.sh with a fixed text ("Homelab needs you. Open Tailscale."), because the phone usually runs another VPN | `ntfy_doorbell` |

Why it is built this way (one public doorbell with no content, details only
on the tailnet, no port forward, no Funnel):
homelab-proxmox-monitoring's `docs/ai-ops/architecture.md`.
Monitoring's alert notifier also runs on the Pi, deployed from that repo.

## Run it

The credentials are in `dns/secrets.yaml`, next to Pi-hole's, and nobody
types them: `mise run secrets:generate` creates them with random values
(the phone's password, the doorbell topic, one token per other client) and
prints only their names. The play gets only these keys (`.mise/sops-exec`
profile `ntfy`). The Pi is already in `dns/ansible/inventory/hosts.yml` for
Pi-hole; add the `ntfy` group with the phone's tailnet name, as
`hosts.yml.example` shows.

```bash
mise run secrets:generate            # once; commit dns/secrets.yaml
mise run dns:inventory               # pihole-pi in both groups, pihole and ntfy
mise run dns:play:ntfy --check --diff
mise run dns:play:ntfy
```

The first run stops twice, on purpose, with the command to run:

1. **Log the Pi in to the tailnet, once:**
   `ssh <user>@192.168.1.53 sudo tailscale up --hostname=pihole-pi --accept-dns=false`,
   then open the URL it prints. In the admin console, turn off key expiry
   for this machine: it is a server.
2. **HTTPS certificates for the tailnet**, if they are not on yet: admin
   console, DNS page, enable MagicDNS and "HTTPS Certificates". The Pi's
   name then appears in public certificate transparency logs, which is why
   the URL stays out of the repos.

The play ends by checking that ntfy answers, that a request without a
token is refused, and that every client reaches the topics it may read. Its
last message is the server's address, which the phone needs.

## Topics and who may use them

Declared in [group_vars/ntfy.yml](ansible/inventory/group_vars/ntfy.yml)
(`ntfy_clients`):

| Topic | Written by | Read by |
|---|---|---|
| `homelab-alerts` | `notifier` (monitoring's alert notifier, on the Pi) | `phone`, `runner`, `doorbell` |
| `homelab-agent` | `runner` (the investigation runner, on the laptop) | `phone`, `doorbell` |
| `homelab-control` | `actions` (the token the phone's buttons send) | `runner` |

Every other access is refused (`auth-default-access: deny-all`). Signup is
off. Only `phone` logs in with a password; the others use tokens, and their
passwords are random ones the Pi makes and throws away once hashed.

## Set up the phone (Android)

1. Install ntfy from **Google Play** (not F-Droid: only the Play build gets
   ntfy.sh topics through Firebase, which is what makes the doorbell arrive
   while another VPN is on). Settings → Apps → ntfy → Battery:
   **Unrestricted**.
2. Open the values: `mise run secrets:edit dns` shows `ntfy_doorbell_topic`
   and `ntfy_phone_password`; close it without saving.
3. Subscribe to the doorbell on the default server (ntfy.sh): the topic is
   `ntfy_doorbell_topic`.
4. Turn Tailscale on. In ntfy: Settings → Users → Add user: the server is
   the address the play printed last (`https://pihole-pi.<tailnet>.ts.net:8443`),
   the user `phone`, the password `ntfy_phone_password`.
5. Subscribe to `homelab-alerts` and `homelab-agent`, choosing "use another
   server" with that same address.

With another VPN on, the doorbell arrives; switch to Tailscale and the
private messages arrive with their buttons. The server keeps 72 hours of
messages, so nothing is lost while Tailscale is off.

## Test it

From the laptop, with Tailscale on (a test alert, through the notifier's
token; the address is the one the play printed):

```bash
curl -H "Authorization: Bearer $(sops -d --extract '["ntfy_notifier_token"]' dns/secrets.yaml)" \
     -H "Priority: 4" -H "Title: Test alert" -d "Sent from the laptop" \
     "https://pihole-pi.<tailnet>.ts.net:8443/homelab-alerts"
```

With the phone on Tailscale, the message arrives and the doorbell stays
quiet (the phone is online). With the phone on another VPN, the doorbell
rings within seconds. Without Tailscale on the laptop, the URL does not
resolve: the server is not reachable from outside the tailnet.

On the Pi: `journalctl -u ntfy-doorbell` says why each message rang or not;
`journalctl -u ntfy` shows the server.

## What other repos rely on

On the Pi (monitoring's alert notifier reads these with systemd
`LoadCredential`):

- ntfy at `http://127.0.0.1:2586`;
- `/etc/ntfy/clients/notifier.token` and `/etc/ntfy/clients/actions.token`
  (root, 0600);
- `/etc/ntfy/base-url`: the tailnet URL, for buttons the phone sends.

On the laptop, for monitoring's `mise run agent install`: the keys
`ntfy_runner_token` and `ntfy_actions_token` in this checkout's
`dns/secrets.yaml` (it decrypts those two), and the Pi as `pihole-pi` on the
tailnet, serving on port 8443 (it finds the address in the laptop's
`tailscale status`).

The topic names are the contract with monitoring's notifier and runner;
rename them in both repos together.

## Rotate a credential

Name the key: `mise run secrets:generate ntfy_runner_token` (any of the
six in `dns/secrets.yaml.example`; several at once is fine). It replaces the
value, prints only the name, and you commit `dns/secrets.yaml`. Then run
`mise run dns:play:ntfy` and give the new value to whoever uses it: the
phone's password or doorbell subscription; `mise run agent install` in
monitoring for the `runner` and `actions` tokens (it re-reads them from
this checkout); monitoring's notifier play for `notifier` and `actions` on
the Pi (its service reads them at every start, so a restart is enough).

Before 2026-11-21 the play kept these values in plaintext in
`dns/ansible/.secrets-cache/`. That folder is no longer read: delete it.
Values generated since then exist only in `dns/secrets.yaml`, encrypted.

## Not yet

- **Second subnet router** (D3): the Pi does not advertise
  `192.168.1.0/24` yet. Before it does, Pi-hole's listening mode must
  accept tailnet clients (`pihole_listening_mode: ALL` for `pihole-pi`, or
  confirm they arrive SNATed).
- **Updates:** core's update procedure does not cover the Pi; `apt` keeps
  ntfy (pinned here) and Tailscale (its own repository) as they are until
  the next play or `apt upgrade`.
