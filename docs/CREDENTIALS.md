# Credentials

Every credential the homelab uses, across all three repos: what it is, how to
issue it, where it is stored, what reads it, and how to rotate it. This is the
one place that documents issuing them — other docs link here instead of
repeating commands.

- **Setting up from zero?** Work through [Issue order](#issue-order).
- **Rotating one?** Find it in [the inventory](#inventory) and follow its
  section.
- **Adding a new secret to a repo?** [Adding a secret](#adding-a-secret).

## How secrets are stored and delivered

Each repo keeps its human-chosen secrets in a SOPS + age encrypted
`secrets.yaml` — ciphertext, **committed**. Workloads has one per app as well
(`nextcloud/secrets.yaml`), so a Terraform run never sees an app password.
`*.example` next to each file lists its keys with placeholder values.

Nothing exports secrets into your shell. `.mise/sops-exec <profile> <cmd>`
decrypts one file for one command and passes on only what that tool reads:

| Repo | File | Profile → used by | Exports |
|---|---|---|---|
| core | `secrets.yaml` | `packer` → `mise run packer:*` | `PKR_VAR_proxmox_api_*`, `PKR_VAR_password_hash`, `PKR_VAR_ssh_authorized_keys` (from `~/.ssh/homelab-proxmox.pub`), node/TLS flag |
| monitoring | `secrets.yaml` | `terraform` → `mise run tf…` | `TF_VAR_pm_api_*`, `TF_VAR_pm_tls_insecure`, `TF_TOKEN_app_terraform_io` (if set) |
| monitoring | `secrets.yaml` | `ansible` → `mise run play` | `ELASTIC_PASSWORD`, `KIBANA_SYSTEM_PASSWORD`, `KIBANA_ENCRYPTION_KEY`, `NEXTCLOUD_DOMAIN`, `ACME_EMAIL`, `CLOUDFLARE_DNS_API_TOKEN`, `NEXTCLOUD_SERVERINFO_TOKEN`, `PVE_EXPORTER_TOKEN_*` |
| workloads | `secrets.yaml` | `terraform` → `mise run tf <app>` | as monitoring's `terraform` |
| workloads | `nextcloud/secrets.yaml` | `nextcloud` → `mise run play nextcloud` | `NEXTCLOUD_DOMAIN`, `ACME_EMAIL`, `CLOUDFLARE_DNS_API_TOKEN`, `NEXTCLOUD_NAS_*`, `NEXTCLOUD_USERS_JSON`, `TAILSCALE_AUTHKEY` |

Ansible reads the UPPERCASE names back with `lookup('env', …)` in
`inventory/group_vars/` — the only place they are consumed.

```bash
mise run secrets:edit [app]   # decrypt into VS Code, re-encrypt on save
mise run secrets:check        # names of missing keys; never prints a value
```

What stays out of git entirely: the age private key, the SSH deploy key's
private half, `mise.local.toml`, and any `*.tfvars` / `*.pkrvars.hcl`.
Monitoring's generated Elastic material (`ansible/.certs/`,
`ansible/.secrets-cache/`) is machine state, not a credential you issue —
losing it is recoverable by re-running the roles.

## Inventory

| Credential | Issued in | Stored as | Used by |
|---|---|---|---|
| [age key](#age-key) | your machine | `~/.config/sops/age/keys.txt` | sops, in every repo |
| [SSH deploy key](#ssh-deploy-key) | your machine | `~/.ssh/homelab-proxmox` | Packer, Terraform (cloud-init), Ansible |
| [Proxmox endpoint](#proxmox-endpoint) | — (an address) | `proxmox_endpoint`, all three repos | Packer, Terraform |
| [Packer Proxmox token](#packer-proxmox-token) | Proxmox | core: `proxmox_packer_token_*` | Packer |
| [Template console password](#template-console-password) | your machine | core: `packer_password_hash` | Packer |
| [Terraform Proxmox token](#terraform-proxmox-token) | Proxmox | monitoring + workloads: `proxmox_terraform_token_*` | Terraform |
| [Terraform Cloud token](#terraform-cloud-token) | app.terraform.io | monitoring + workloads: `tf_cloud_token` (optional) | Terraform state |
| [Cloudflare DNS tokens](#cloudflare-dns-tokens) | Cloudflare | monitoring + workloads/nextcloud: `cloudflare_dns_api_token` | Kibana's certbot; Nextcloud's Caddy |
| [Elastic passwords and key](#elastic-passwords-and-encryption-key) | you choose | monitoring: `elastic_password`, `kibana_system_password`, `kibana_encryption_key` | Elastic Stack |
| [Nextcloud serverinfo token](#nextcloud-serverinfo-token) | Nextcloud VM | monitoring: `nextcloud_serverinfo_token` | metrics exporter |
| [Proxmox exporter token](#proxmox-exporter-token) | Proxmox | monitoring: `pve_exporter_token_*` (optional) | pve-exporter |
| [Tailscale auth key](#tailscale-auth-key) | Tailscale | workloads/nextcloud: `tailscale_authkey` (optional) | first `tailscale up` |
| [TrueNAS SMB account](#truenas-smb-account) | TrueNAS | workloads/nextcloud: `nextcloud_nas_user`, `nextcloud_nas_password` | Nextcloud external storage |
| [Nextcloud accounts](#nextcloud-accounts) | you choose | workloads/nextcloud: `nextcloud_users_json` | Nextcloud user creation |
| [Not in any repo](#kept-outside-the-repos) | — | password manager | AIO, Proxmox, TrueNAS admin logins |

`nextcloud_domain` and `acme_email` sit in `secrets.yaml` too — not secret,
just kept out of the public repos.

## Issue order

1. [age key](#age-key) and [SSH deploy key](#ssh-deploy-key), then clone the
   three repos side by side and `mise run setup` in each.
2. Core: [Packer token](#packer-proxmox-token),
   [console password](#template-console-password), `proxmox_endpoint` →
   `mise run secrets:check`.
3. Monitoring and workloads: [Terraform token](#terraform-proxmox-token) and
   optionally the [Terraform Cloud token](#terraform-cloud-token).
4. Workloads/nextcloud: [Cloudflare](#cloudflare-dns-tokens),
   [TrueNAS SMB](#truenas-smb-account), [accounts](#nextcloud-accounts),
   [Tailscale](#tailscale-auth-key) → deploy Nextcloud.
5. Monitoring: [Elastic](#elastic-passwords-and-encryption-key),
   [Cloudflare](#cloudflare-dns-tokens), then — once Nextcloud runs — the
   [serverinfo token](#nextcloud-serverinfo-token) → deploy monitoring.

## age key

The one key that decrypts every `secrets.yaml`. **Everything else is
recoverable; this is not** — keep an offline copy (password manager).

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt    # the public half: age1…
```

The public half is the recipient in each repo's `.sops.yaml`. To let another
machine or person decrypt, add their `age1…` there (comma-separated) and
re-encrypt every file in that repo:

```bash
sops updatekeys secrets.yaml                 # and nextcloud/secrets.yaml in workloads
```

Rotating: add the new recipient, `updatekeys`, confirm decryption with
`mise run secrets:check`, then remove the old recipient and `updatekeys` again.
Old ciphertext in git history stays readable with the old key.

## SSH deploy key

One keypair for all three stages: Packer bakes the public half into the
template (password login is disabled), Terraform adds it via cloud-init, and
Ansible connects with the private half (`private_key_file` in each
`ansible.cfg`).

```bash
ssh-keygen -t ed25519 -N "" -C "homelab-proxmox-deploy" -f ~/.ssh/homelab-proxmox
```

Every default already points at `~/.ssh/homelab-proxmox` / `.pub`.
Rotating means a template rebuild and re-clones — or adding the new public key
to `~/.ssh/authorized_keys` on each live VM first, then swapping.

## Proxmox endpoint

`proxmox_endpoint`: the API base URL **without** `/api2/json`
(`https://pve.<zone>:8006`); sops-exec appends the path. The name resolves only
through PiHole, and TLS verification is on (`PROXMOX_TLS_INSECURE=false` in
`mise.toml`) because the host has a valid certificate for it.

## Packer Proxmox token

`packer@pve!packer-automation` — template-build rights, core only. On the
Proxmox node:

```bash
pveum role add PackerRole -privs "VM.Config.Disk VM.Config.Cloudinit SDN.Use VM.Snapshot VM.PowerMgmt Datastore.Allocate VM.GuestAgent.Unrestricted VM.Config.Network VM.Config.CDROM VM.Console VM.Backup VM.Migrate VM.Config.Options VM.Clone VM.GuestAgent.Audit VM.Snapshot.Rollback Pool.Audit VM.Config.CPU VM.Config.HWType Datastore.AllocateSpace Datastore.Audit VM.Allocate VM.Config.Memory VM.Audit"
pveum user add packer@pve --password '<choose one>'
pveum aclmod / -user packer@pve -role PackerRole
pveum user token add packer@pve packer-automation --privsep 0   # prints the secret ONCE
```

Store in core: `proxmox_packer_token_id` (`packer@pve!packer-automation`) and
`proxmox_packer_token_secret`. If a build fails with
`403 Permission check failed … VM.Config.Cloudinit`, the live role has drifted
from this list — re-run the first line as `pveum role modify PackerRole -privs "…"`.

Rotating: `pveum user token remove packer@pve packer-automation`, re-add,
update the secret.

## Template console password

A SHA-512 hash for the template user's **console** login (SSH is key-only;
this is the break-glass path when a VM has no network). Needs `mkpasswd` from
the `whois` package:

```bash
mkpasswd -m sha-512 '<choose one>'
```

Store the hash in core as `packer_password_hash`. It applies to templates
built afterwards; existing VMs keep the old one.

## Terraform Proxmox token

`terraform@pve` — clone/configure rights. A different token from Packer's:
neither should carry the other's rights. On the Proxmox node:

```bash
pveum role add TerraformRole -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt VM.GuestAgent.Audit SDN.Use"
pveum user add terraform@pve --password '<choose one>'
pveum aclmod / -user terraform@pve -role TerraformRole
pveum user token add terraform@pve terraform-automation --privsep 0   # prints the secret ONCE
```

Store in **monitoring and workloads**: `proxmox_terraform_token_id` and
`proxmox_terraform_token_secret`. Better, mint one token per repo
(`terraform-monitoring`, `terraform-workloads`) under the same user, so
revoking one cannot break the other — it is in each repo's TODO.

## Terraform Cloud token

State lives in Terraform Cloud (org `colac_homelab`, Local execution). Either
run `terraform login` once (stored in `~/.terraform.d/credentials.tfrc.json`)
and leave `tf_cloud_token` empty, or create a user token at app.terraform.io →
User settings → Tokens and store it as `tf_cloud_token` in monitoring and
workloads.

## Cloudflare DNS tokens

Let's Encrypt DNS-01 for the private names: Cloudflare only answers the
challenge TXT record, nothing is exposed. **Two tokens, one per certificate**,
so rotating one never breaks the other:

| Token | Repo / key | Serves |
|---|---|---|
| Caddy | workloads `nextcloud/secrets.yaml` → `cloudflare_dns_api_token` | `nextcloud.<zone>` |
| Kibana certbot | monitoring `secrets.yaml` → `cloudflare_dns_api_token` | `kibana.<zone>` |

Issue: Cloudflare dashboard → My Profile → API Tokens → Create Token → **Edit
zone DNS** template → Permissions `Zone · DNS · Edit`, Zone Resources
`Include · Specific zone · <your zone>`. Copy it once.

Rotating, then **prove** the renewal works — Let's Encrypt certs last 90 days
and both tools start renewing at 30 days left, so a broken token shows up weeks
later as an expired cert:

```bash
# Nextcloud (workloads)
mise run secrets:edit nextcloud && mise run secrets:check
mise run play nextcloud playbooks/10-nextcloud.yml        # rewrites Caddy's .env, restarts it
ssh ubuntu@<nextcloud-ip> 'sudo docker logs nextcloud-caddy 2>&1 | tail -50'   # "certificate obtained successfully"

# Kibana (monitoring)
mise run secrets:edit && mise run secrets:check
mise run play playbooks/35-kibana.yml                     # rewrites certbot's cloudflare.ini
ssh ubuntu@<monitoring-ip> 'sudo certbot renew --dry-run'
```

Usual failures: a token scoped to the wrong zone, or `Zone:Read` without
`DNS:Edit`.

## Elastic passwords and encryption key

All three are chosen by you, before the first monitoring deploy:

```bash
openssl rand -base64 24    # elastic_password, kibana_system_password
openssl rand -hex 32       # kibana_encryption_key
```

| Key | What it is | Rotating |
|---|---|---|
| `elastic_password` | The superuser; your Kibana login | Elasticsearch only reads it on first start. Change it in Kibana (Stack Management → Users → elastic) **first**, then update the secret |
| `kibana_system_password` | Kibana's own least-privilege account | Update the secret, then `mise run play playbooks/30-elasticsearch-security.yml playbooks/35-kibana.yml` — the bootstrap re-applies it every run |
| `kibana_encryption_key` | Encrypts Fleet's stored tokens and API keys | **Do not rotate casually.** A new key makes the stored saved objects unreadable, and Fleet must be re-bootstrapped |

## Nextcloud serverinfo token

Lets the monitoring VM read Nextcloud's application metrics without holding a
login. Generate on the **Nextcloud VM**, store in **monitoring**:

```bash
sudo docker exec -u www-data nextcloud-aio-nextcloud \
  php occ config:app:set serverinfo token --value "$(openssl rand -hex 32)"
sudo docker exec -u www-data nextcloud-aio-nextcloud \
  php occ config:app:get serverinfo token      # copy into monitoring's secrets.yaml
```

Rotating: run both again, update `nextcloud_serverinfo_token`, then
`mise run play playbooks/45-exporters.yml` in monitoring.

## Proxmox exporter token

Optional — only once `exporters_pve_enabled: true` in monitoring's
`group_vars/monitoring.yml`. Read-only (`PVEAuditor`): even a compromised
monitoring VM cannot change the hypervisor with it.

```bash
pveum user add pve-exporter@pve --comment "Read-only Prometheus exporter"
pveum aclmod / -user pve-exporter@pve -role PVEAuditor
pveum user token add pve-exporter@pve monitoring --privsep 0   # prints the secret ONCE
```

Store in monitoring: `pve_exporter_token_id` (`pve-exporter@pve!monitoring`)
and `pve_exporter_token_secret`.

## Tailscale auth key

Optional. Lets the `tailscale` role run `tailscale up` unattended on the
Nextcloud VM; leave `tailscale_authkey` empty to authenticate by hand. Issue:
Tailscale admin console → Settings → Keys → Generate auth key (one-off is
enough). Only the first join uses it — after that the node keeps its own
identity, so an expired key is harmless. The subnet-route approval and
split-DNS entry are separate one-time steps in the Nextcloud runbook.

## TrueNAS SMB account

A dedicated SMB user — never `root`/`admin` — with read/write on the `media`
share (TrueNAS → Credentials → Users; see core's
[TrueNAS/README.md](../TrueNAS/README.md)). Store as `nextcloud_nas_user` /
`nextcloud_nas_password` in workloads' `nextcloud/secrets.yaml`.

Rotating: **the mounts are create-only**, so a new password in `secrets.yaml`
does not reach mounts that already exist. Change it in TrueNAS, update the
secret, then on the Nextcloud VM set it on each mount (or delete the mounts and
re-run the playbook):

```bash
sudo docker exec --user www-data nextcloud-aio-nextcloud php occ files_external:list
sudo docker exec --user www-data nextcloud-aio-nextcloud php occ files_external:config <id> password '<new>'
```

## Nextcloud accounts

`nextcloud_users_json` in workloads' `nextcloud/secrets.yaml`: a single-line
JSON array (`[{"name":"alice","display_name":"Alice","password":"…","nas_folder":true}]`),
because sops' dotenv output is flat `key=value` only. Usernames live here with
the passwords so no family name is in the repo.

The role only **creates** missing accounts. Changing a password in the secret
does nothing to an existing account — change it in Nextcloud itself.

## Kept outside the repos

Not used by automation, so they belong in a password manager, not in
`secrets.yaml`:

- the Nextcloud **AIO passphrase** (shown once in the AIO admin UI) and the
  Nextcloud admin password;
- the **Borg backup passphrase**, once AIO backups are set up — without it the
  backups are unrecoverable;
- Proxmox `root@pam`, TrueNAS admin, Cloudflare, Tailscale and GitHub logins.

## Adding a secret

1. Add the key, a placeholder and a comment to the right `*.example`.
2. Add the value: `mise run secrets:edit [app]`.
3. Map it in `.mise/sops-exec`: `need` (required) or `want` (optional) in the
   right profile, plus a `put` to the name the tool reads.
4. Read it with `lookup('env', 'NAME')` in `inventory/group_vars/` — never a
   literal in `group_vars` or a role default.
5. Add it to the [inventory](#inventory) above, with how it is issued.
6. `mise run secrets:check`.
