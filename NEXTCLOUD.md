# Deploying the Nextcloud machine

End-to-end, from-zero runbook to build and run Nextcloud (All-in-One) on
Proxmox, served privately at `https://nextcloud.example.com` (a real
Let's Encrypt cert, no public exposure), with a TrueNAS box attached as
external storage over SMB.

```text
Packer    → builds template "ubuntu-24.04-template" (Docker + Tailscale baked in)
Terraform → clones the template into the "nextcloud" VM, outputs its IP
Ansible   → deploys Nextcloud AIO + a Caddy reverse proxy (TLS) + a Tailscale
            subnet route + attaches TrueNAS as external storage
```

## How `nextcloud.example.com` stays private but works everywhere

TLS is terminated by a small **Caddy** reverse proxy on the VM, which gets a
Let's Encrypt cert for the domain via **Cloudflare DNS-01** (a DNS TXT record —
no inbound ports are opened). One DNS A record points the name at the VM's LAN
IP, and the VM advertises the LAN as a **Tailscale subnet route**:

| Where you are | DNS resolves via | Path to the VM |
|---|---|---|
| Home, no Tailscale | PiHole (LAN) → VM LAN IP | direct on the LAN |
| Away, on Tailscale | PiHole via Tailscale split-DNS → VM LAN IP | via the subnet route |

The cert is valid on either path because it matches the hostname, not an IP.

## Files you create

Two, not five. Everything credential-shaped goes into the repo-root
`secrets.yaml`, which is SOPS-encrypted (ciphertext on disk, safe to commit) and
reaches Packer, Terraform and Ansible as environment variables via direnv — so
there is no `.tfvars`, no `.pkrvars.hcl` and no Ansible vault to maintain. See
[Secrets](README.md#secrets).

| Create this | How | Holds |
|---|---|---|
| `secrets.yaml` | `sops secrets.yaml` (keys documented in `secrets.yaml.example`) | Proxmox tokens, `packer_password_hash`, domain, ACME email, TrueNAS SMB user + password, the Nextcloud user list (names **and** passwords), Cloudflare token, Tailscale key |
| `ansible/inventory/hosts.yml` | copy `.example` | the VM's IP (from Terraform output) — git-ignored |

You also need an age key at `~/.config/sops/age/keys.txt` whose public half is a
recipient in `.sops.yaml`; without it nothing decrypts.

## Keys & passwords you need

| Secret | How to get it | Goes in |
|---|---|---|
| age keypair | `age-keygen -o ~/.config/sops/age/keys.txt` | decrypts `secrets.yaml`; public half goes in `.sops.yaml` |
| Packer Proxmox token (`packer@pve`) | `pveum` commands in [packer/README.md](packer/README.md) | `secrets.yaml` → `proxmox_packer_token_*` |
| Terraform Proxmox token (`terraform@pve`) | `pveum` commands in [terraform/README.md](terraform/README.md) | `secrets.yaml` → `proxmox_terraform_token_*` |
| SSH deploy keypair | generated below (`~/.ssh/homelab-proxmox`) | stays in `~/.ssh`; Packer reads the public half at direnv load |
| Template console password hash | `mkpasswd -m sha-512 'pass'` (`whois` package) | `secrets.yaml` → `packer_password_hash` |
| TrueNAS SMB user + password | create in the TrueNAS UI (see prerequisites) | `secrets.yaml` (the NAS *host* goes in `group_vars`) |
| Nextcloud user names + passwords | you choose them | `secrets.yaml` → `nextcloud_users_json` |
| Cloudflare API token | Cloudflare dashboard → My Profile → API Tokens (Zone:DNS:Edit on the `example.com` zone) | `secrets.yaml` |
| Tailscale auth key (optional) | Tailscale admin → Settings → Keys | `secrets.yaml` |
| Terraform Cloud token | `terraform login` | `~/.terraform.d/`, or `secrets.yaml` → `tf_cloud_token` |
| AIO passphrase | auto-generated at first run | shown in AIO UI — save it |
| Nextcloud admin password | you set during AIO setup | Nextcloud login |

## SSH deploy key

A single dedicated keypair is used across all three stages: its public key is
baked into the template (Packer) and added to the clone (Terraform), and Ansible
connects with the private key. Generate it once:

```bash
ssh-keygen -t ed25519 -N "" -C "homelab-proxmox-nextcloud-deploy" \
  -f ~/.ssh/homelab-proxmox
```

The example files and `ansible/ansible.cfg` already point at this path
(`~/.ssh/homelab-proxmox` / `.pub`), so no edits are needed if you keep the name.

## 0. One-time prerequisites

These cannot come from this repo — do them once:

- **Dev tools:** `make all` (installs Terraform 1.15.7, the Python venv with
  Ansible, and Node tools) and `./install-packer.sh`. Then install the Ansible
  collections: `cd ansible && ansible-galaxy collection install -r requirements.yml`.
- **Proxmox users/tokens:** create the `packer@pve` and `terraform@pve` roles,
  users, and API tokens (commands in [README.md](README.md) and
  [terraform/README.md](terraform/README.md)).
- **Ubuntu ISO:** upload `ubuntu-24.04.x-live-server-amd64.iso` to a Proxmox
  storage (referenced by `boot_iso_file`).
- **Terraform Cloud:** run `terraform login`. The `Nextcloud` workspace already
  exists in the `colac_homelab` org — set it to **Local** execution mode
  (Workspace → Settings → Execution Mode) so it runs against Proxmox from your
  machine.
- **Tailscale:** in the admin console enable **MagicDNS**; optionally create an
  **auth key**. (The subnet-route approval and split-DNS entry are done after the
  VM joins — see step 4.)
- **Cloudflare:** the `example.com` zone is on Cloudflare. Create a scoped API
  token (**Zone → DNS → Edit**, limited to this zone) for the ACME DNS-01
  challenge; it goes in `secrets.yaml` as `cloudflare_dns_api_token`.
- **PiHole:** add a local DNS A record `nextcloud.example.com → <VM LAN IP>`
  (Local DNS → DNS Records). This is what makes the name resolve on the LAN.
- **TrueNAS:** Sharing → SMB → enable the service and create the share(s);
  Credentials → Users → create a dedicated SMB user (not `root`/`admin`) with
  read/write access to it. See [TrueNAS/README.md](TrueNAS/README.md).

## 1. Build the base template (Packer)

```bash
cd packer/ubuntu-24.04    # direnv exports PKR_VAR_* on the way in
packer init .
packer validate .
packer build .
```

Produces the `ubuntu-24.04-template` template with Docker and Tailscale
pre-installed (Tailscale is installed but not yet authenticated).

> Password login is disabled in the image. `packer/.envrc` sets
> `ssh_authorized_keys` by reading `~/.ssh/homelab-proxmox.pub` at load time, so
> it always matches `ssh_private_key_file`. If that file is missing, direnv says
> so at `cd` time — otherwise the build would succeed and produce a template
> nobody can log in to.

## 2. Create the VM (Terraform)

```bash
cd ../../terraform/projects/nextcloud   # direnv exports TF_VAR_pm_api_* here
terraform init
terraform apply
terraform output ansible_inventory_line
```

The defaults in `variables.tf` are sized for Nextcloud (4 vCPU / 8 GB / 64 GB)
and state lives in the Terraform Cloud `Nextcloud` workspace. Copy the `ansible_inventory_line` output.

## 3. Configure the host (Ansible)

```bash
# From the repo root, first put the values in place:
sops secrets.yaml     # set: nextcloud_domain, reverse_proxy_acme_email,
#   nextcloud_nas_user + nextcloud_nas_password, nextcloud_users_json,
#   cloudflare_dns_api_token, tailscale_authkey

cd ansible            # direnv exports them and puts .venv/bin on PATH
cp inventory/hosts.yml.example inventory/hosts.yml   # paste the VM IP
# edit inventory/group_vars/nextcloud.yml: nextcloud_aio_nas_host,
#   nextcloud_aio_nas_mounts, nextcloud_aio_nas_personal_share
ansible-playbook playbooks/10-nextcloud.yml
```

This deploys the AIO stack, builds the Caddy reverse proxy, and (if you supplied
a Tailscale auth key) joins the tailnet. The NAS step only completes once
Nextcloud is running — see the two-pass note below.

After the first run, do the two one-time Tailscale admin steps the playbook
reminds you about:

- **Approve the subnet route** `192.168.1.0/24` (Machines → the node → Edit route
  settings) so off-LAN devices can reach the VM.
- **Add split-DNS** for `example.com` pointing at the PiHole (DNS → Nameservers
  → Restrict to domain) so tailnet devices resolve the name to the LAN IP.

## 4. Finish Nextcloud setup, then run Ansible again

```bash
# Tunnel to the AIO admin UI (bound to localhost for safety)
ssh -L 8080:localhost:8080 ubuntu@<vm-ip>
# browse https://localhost:8080 → copy the passphrase →
#   set domain to nextcloud.example.com → start containers → set admin pw

# Second pass: now that the container is up, create the users and NAS mounts
ansible-playbook playbooks/10-nextcloud.yml
```

Then reach Nextcloud at `https://nextcloud.example.com` — on the LAN directly,
or from anywhere once you're on the tailnet.

> **Why two passes:** the user and NAS tasks need the Nextcloud container
> *running* — which only happens after AIO's first-run setup. Pass 1 deploys
> AIO + Caddy; pass 2 creates the extra Nextcloud users and attaches the NAS
> mounts. The tasks are idempotent, so re-running is safe. (Caddy serves a 502
> until you start the containers in AIO — that's expected.)

## 5. Storage and user layout

What pass 2 configures (details and syntax in
[ansible/README.md](ansible/README.md)):

| Nextcloud folder | TrueNAS path | Who | Access | Declared in |
|---|---|---|---|---|
| `<username>` | `media/<username>` | that user only | read-write | `secrets.yaml` → `nextcloud_users_json` |
| `Familia` | `media/Familia` | all users | **read-only** | `group_vars/nextcloud.yml` |

Every person gets a private folder of their own, derived from their entry in
the `nextcloud_aio_users` list (any entry with `nas_folder: true`) — that is
the target for phone camera auto-upload. Shared folders are declared once in
`group_vars/nextcloud.yml` and are visible to everyone.

`Familia` holds curated, irreplaceable family photos and video, so **no
Nextcloud account can write to it — `admin` included**. Phones upload into
their owner's private folder; nothing on a phone can touch the curated library.

Curation — moving files from someone's private folder into `Familia` — is done
over SMB straight to TrueNAS, not in the Nextcloud UI:

```bash
mv /mnt/hdd-home-1/media/<username>/<batch> /mnt/hdd-home-1/media/Familia/
```

Nextcloud notices the change by itself the next time someone opens the
folder: every mount has `filesystem_check_changes` set to "once every direct
access", which the role enforces on every run (`nextcloud_aio_nas_check_changes`).
Mounts created with `occ` get no value for it, and Nextcloud treats that as
*never*, so without it SMB changes never appear. A rescan is still worth it
after a large batch: search, Photos and Memories only index what is in the file
cache, and a folder nobody has opened yet is not in it:

```bash
docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan --path="/admin/files/Familia"
```

That is faster *and* safer. Both folders live in one dataset, so the move is an
instant metadata rename; the same drag-and-drop inside Nextcloud would stream
every byte out of TrueNAS, through the VM, and back again, because Nextcloud
only does server-side renames within a single storage. Since the UI buys
nothing for this operation, giving it write access buys nothing either.

Three caveats worth knowing:

- Nextcloud sees a folder renamed over SMB as a folder **deleted** and a new
  one **created**. Shares, tags, comments and favourites on the old name do
  not carry over. Rename inside Nextcloud when any of those matter.

- The read-only flag is enforced by **Nextcloud**, not the NAS. The SMB account
  still has write permission on the share (it needs it for the private
  folders), and an admin can flip the flag in Settings → External storage. It
  is a guard rail
  against accident, not a defence against a determined mistake. To make it
  structural, give the Nextcloud SMB user read-only ACLs on `Familia` in
  TrueNAS and curate with your own SMB login instead.
- Auto-upload must target the user's own NAS folder, never Nextcloud's default
  local storage — the VM disk is 64 GB and a phone's photo library will fill it.

### Adding a person

1. **Create the storage**, named after the user, inside `media`. Either works:
   - a **plain folder** (over SMB, the TrueNAS file browser, or `mkdir`) — it
     inherits the parent's ACL;
   - a **child dataset** (Datasets → Add Dataset) — preferred, since it can
     have its own snapshot task and quota. A new dataset gets a *fresh* ACL
     rather than inheriting, so check that the Nextcloud SMB account still has
     write access (e.g. via the `smb_users` group) before applying.

   Do **not** give it its own SMB share. Mounts connect to the `media` share
   and traverse into the subfolder/dataset, so a per-user share is unused.
2. **In `secrets.yaml`**: `sops secrets.yaml` from the repo root and append an
   object to the `nextcloud_users_json` array:

   ```json
   {"name": "maria", "display_name": "Maria", "password": "…", "nas_folder": true}
   ```

   `name` must be lowercase and match the folder name exactly; `display_name`
   is free-form and shown in the UI. It is one line of JSON rather than YAML
   because `sops -d --output-type dotenv` only emits flat `key=value` pairs —
   `group_vars/nextcloud.yml` parses it back with `from_json`.

   The username *is* the folder name — `"name": "maria"` mounts `media/maria`.
   Keep the list complete: it drives both account creation and the private
   mounts, so removing an existing person's entry stops their folder from
   being recreated.

3. **Apply**: `cd ansible && ansible-playbook playbooks/10-nextcloud.yml`. It
   creates the account and mounts `/maria` scoped to her alone; existing users
   and mounts are skipped. If a folder mount already exists but is unscoped
   (Applicable Users: `All`), delete it first — see the create-only gotcha
   below, since the run will not retrofit the scoping.
4. **Test the write path** before pointing a phone at it: log in as the new
   user and upload one small file. A wrong ACL on the NAS side shows up here,
   and it is far easier to debug than a phone that silently fails to
   auto-upload. On TrueNAS, the dataset's `Used` figure moving off its empty
   ~96 KiB confirms the file really landed there.
5. **On the phone**: install the Nextcloud app, log in, and set auto-upload's
   target folder to `/<username>`. `Familia` needs no action — it is already
   visible, read-only, to every account.

## Gotchas for this setup

- **Building behind ProtonVPN:** set `PACKER_HTTP_INTERFACE` to your LAN NIC in
  `.envrc.local` (git-ignored) so Packer advertises your LAN IP, not the VPN
  tunnel, to the VM during autoinstall. Confirm the NIC with `ip -br addr`.
- **DNS:** the configs use `https://pve.example.com:8006/api2/json`, which only
  resolves through PiHole — keep PiHole as your DNS while deploying. TLS
  verification is on and the Let's Encrypt cert is valid, so it works by name.
- **The AIO domain is permanent:** whatever you submit in the AIO UI cannot be
  changed later. Type `nextcloud.example.com` exactly — it must match the Caddy
  vhost and the PiHole record.
- **Caddy cert on first boot:** Caddy needs the Cloudflare token to solve DNS-01.
  If the cert never issues, check the token scope (Zone:DNS:Edit on this zone)
  with `docker logs nextcloud-caddy`.
- **Subnet route + split-DNS are required for off-LAN access.** Until you approve
  the route and add the split-DNS entry in the Tailscale admin console, the
  domain only works on the LAN.
- **External-storage mounts are matched by name, not by target — and are only
  configured at creation.** The Ansible task creates a mount if no mount with
  that name exists, and skips the whole block otherwise. So changing *anything*
  about an existing mount — its host, share, `applicable_users`, or `readonly`
  — has no effect: the playbook sees the name is taken and moves on, leaving
  the old settings in place. The one exception is change detection
  (`filesystem_check_changes`), which is checked and corrected on every run. Delete the mount first, then re-run so it is
  recreated with the new configuration:

  ```bash
  docker exec --user www-data nextcloud-aio-nextcloud php occ files_external:list
  docker exec --user www-data nextcloud-aio-nextcloud php occ files_external:delete <id> -y
  ```

  Deleting a mount only detaches it — it does not touch the files on the NAS.

## Updating the containers

Two images, updated two different ways.

**Caddy is pinned in the repo.** `reverse_proxy_caddy_version` and
`reverse_proxy_caddy_dns_cloudflare_version` in
`ansible/roles/reverse_proxy/defaults/main.yml` (tags:
[caddy](https://hub.docker.com/_/caddy),
[caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare/tags)). Bump
them, then:

```bash
ansible-playbook playbooks/10-nextcloud.yml --limit nextcloud-vm
# on the VM: the rebuild recreates Caddy, a few seconds without HTTPS
docker exec nextcloud-caddy caddy version
docker exec nextcloud-caddy caddy list-modules | grep cloudflare
sudo docker image prune -f && sudo docker builder prune -f   # old image + Go build cache
```

**AIO updates itself; the repo stays on `nextcloud/all-in-one:latest`.** AIO
supports only `latest` (or `beta`) for the mastercontainer, which then pins
and updates every Nextcloud container it manages. Pinning it in the repo would
break that. To update, open the AIO interface
(`ssh -L 8080:localhost:8080 ubuntu@<vm>`, then `https://localhost:8080`):
if it offers a mastercontainer update, take it first, then
**Stop containers** → **Start and update containers**. Nextcloud is down for a
few minutes. Enabling daily backups with automatic updates in the same
interface makes this unattended.

## Backup and disaster recovery

### What protects what

| Data | Lives on | Protected by |
|---|---|---|
| Nextcloud database, app config, local user files | VM docker volumes | AIO Borgbackup (below) |
| `Familia`, `hugo` — the actual files | TrueNAS `hdd-home-1/media` | **TrueNAS** snapshots + off-box copy |
| VM shape, template, roles | This repo + Terraform Cloud state | git; rebuildable from scratch |

> **AIO's backup does not cover the NAS mounts.** Borgbackup captures
> Nextcloud's own docker volumes only. Files on SMB external storage physically
> live on TrueNAS and are merely referenced by Nextcloud — so `Familia`'s
> safety depends entirely on TrueNAS-side protection: Periodic Snapshot Tasks
> on `hdd-home-1/media` plus a real 3-2-1 off-box copy (both are Tier 2 in
> [TrueNAS/README.md](TrueNAS/README.md)). For critical data that matters more
> than the Nextcloud backup below.

### TrueNAS config export

After any share/user change: System → General → Manage Configuration →
**Download File**. Store it outside this repo (it's a binary config export, not
something to commit) — a password-manager attachment or the off-box backup
target. It turns a dead boot NVMe into a reinstall-and-upload-config job.

### AIO Borgbackup — not yet configured

AIO's backup writes to a host directory bind-mounted into the mastercontainer.
That directory must live on storage separate from the VM's own disk, so the
plan is a dedicated TrueNAS export:

1. **On TrueNAS**: create a *separate* dataset/share for backups — do not reuse
   the `media` share that external storage points at. NFS is the simpler host
   mount on Linux; SMB works too.
2. **Repo changes**: mount that export on the VM host (e.g. `/mnt/ncbackup`)
   via `ansible.posix.mount` so it survives reboots; add the same path as a
   bind mount to `nextcloud-aio-mastercontainer` in the `nextcloud_aio` role's
   `compose.yaml.j2` (AIO requires the path to appear identically inside the
   container) and set `NEXTCLOUD_MOUNT: /mnt/ncbackup` so the UI will accept it.
3. **In the AIO admin UI** ("Backup and restore", via the SSH tunnel): point it
   at that directory, set the **Borg encryption passphrase** and record it
   somewhere durable — without it the backups are unrecoverable — then run the
   first backup manually and enable the scheduled one.

Open decisions: NFS or SMB and the export name; where the Borg passphrase and
the TrueNAS config export are stored long-term.

### Rebuilding the VM from scratch

Assumes the **TrueNAS box and pool survive** — this restores Nextcloud, not the
family photos. Rebuilding TrueNAS itself is a separate procedure (reinstall,
then Manage Configuration → Upload File) and is not part of this pipeline.

1. Run steps 1–3 above unchanged: Packer template (only if it's gone),
   `terraform apply`, first Ansible pass.
2. Complete the AIO first-run setup and set the admin password — the domain
   must be typed identically to the original.
3. Mount the backup export and use AIO's **Restore** flow with the saved Borg
   passphrase to bring back the database and app data.
4. Re-run `cd ansible && ansible-playbook playbooks/10-nextcloud.yml` to
   recreate users and reattach the TrueNAS mounts. Both tasks are idempotent,
   so it's harmless if the restore already recreated them.
5. Caddy, Tailscale, PiHole, and Cloudflare need nothing new — the cert is
   re-issued automatically via DNS-01, and the PiHole record only changes if
   the VM's IP did.

## Troubleshooting

### Rotating the Cloudflare API token (or a cert failed to renew)

One token, `cloudflare_dns_api_token` in `secrets.yaml`, serves **both** certs:
Caddy on the Nextcloud VM and certbot on the monitoring VM (Kibana). Rotate it
in one pass. The token needs `Zone:DNS:Edit` on the zone of `nextcloud_domain`.

```bash
# 1. Cloudflare dashboard → My Profile → API Tokens → create/roll the token.
# 2. Put it in place (values are edited via sops, never with a text editor):
sops secrets.yaml            # set cloudflare_dns_api_token
direnv reload                # or cd out and back in; verify with: env | grep -c CLOUDFLARE_DNS_API_TOKEN

# 3. Push it to both hosts (from ansible/, venv active)
ansible-playbook playbooks/10-nextcloud.yml --limit nextcloud-vm   # rewrites Caddy's .env, restarts Caddy
ansible-playbook playbooks/35-kibana.yml    --limit monitoring-vm  # rewrites /etc/letsencrypt/cloudflare.ini, renews if due
```

Then confirm each cert actually renews rather than assuming:

- **Caddy:** `docker logs nextcloud-caddy 2>&1 | tail -50` on the Nextcloud VM.
  Caddy retries ACME on restart, so a new token normally issues within a minute
  or two. Look for `certificate obtained successfully`.
- **Kibana:** on the monitoring VM, `sudo certbot renew --dry-run` proves the
  new credentials work. The playbook only renews when the cert is inside
  certbot's 30-day window; if it is not yet due but you want the new token
  exercised for real, `sudo certbot renew --force-renewal` (the deploy-hook
  copies the pair in and restarts Kibana). Check the result with
  `sudo certbot certificates`.

If it still fails, the usual causes are a token scoped to the wrong zone, a
token with `Zone:Read` but no `DNS:Edit`, or the env var not reaching Ansible
(the `common` role's assert fails the run in that case). Expiry dates of the
old cert are your deadline: Let's Encrypt certs last 90 days and both tools
start renewing at 30 days remaining.

### An off-LAN device (phone/laptop on Tailscale) can't open the URL

Almost always **DNS, not connectivity**. The hostname only exists as a private
PiHole record, so a remote device has no way to resolve it until Tailscale is
told to ask PiHole for that domain.

1. **Confirm it's DNS.** From the device, browse to the VM's *tailnet* IP
   directly, `https://<vm-tailnet-ip>`. You'll get a certificate warning (the cert
   is for the hostname, not the IP) — but if the page loads past the warning,
   tailnet routing works and only name resolution is missing.
2. **Add split-DNS** (admin console → **DNS** → Nameservers → Add nameserver →
   Custom): nameserver = the **PiHole IP**, toggle **Restrict to domain** = your
   apex domain (`example.com`). This routes only that domain's lookups to PiHole,
   over the approved subnet route; everything else on the device is untouched.
3. **Check the record exists**: PiHole has `nextcloud.example.com → <vm-lan-ip>`
   (Local DNS → DNS Records).
4. **Re-toggle Tailscale** on the device so it picks up the new DNS config.

Prerequisites for the above: the `192.168.1.0/24` route is **Approved** (Machines
→ node → Subnets) and **MagicDNS** is enabled. Mobile Tailscale clients use
approved subnet routes automatically; if a "Use Tailscale subnets" toggle is
present in the app, ensure it's on.

## Readiness checklist

| Item | Provided by repo | You supply |
|---|---|---|
| Packer template + scripts | yes | ISO |
| Terraform config + module | yes | TFC login |
| Ansible roles + playbook | yes | `inventory/hosts.yml` |
| Secrets scheme (SOPS + direnv) | yes | age key, values in `secrets.yaml` |
| SSH deploy key | command above | run it once |
| Proxmox users / API tokens | docs only | create per README |
| Caddy reverse proxy + Tailscale roles | yes | Cloudflare token, route approval, split-DNS |
| Tailscale + TrueNAS + PiHole prep | — | enable in their consoles |
