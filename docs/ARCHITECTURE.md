# Homelab architecture

How the homelab is split into three repos, what each one publishes and
consumes, and how a change moves through them. Each repo's own README covers
its internals; this is the page that ties them together.

## The three layers

| Layer | Repo | Owns | Changes |
|---|---|---|---|
| **core** | [homelab-proxmox](https://github.com/colac/homelab-proxmox) (this) | Packer templates, the `base-vm` Terraform module, the `colac.homelab` Ansible collection (`common`, `docker_data`), homelab-wide docs, TrueNAS notes | Rarely; everything else depends on it |
| **monitoring** | [homelab-proxmox-monitoring](https://github.com/colac/homelab-proxmox-monitoring) | The monitoring VM: single-node Elasticsearch, Kibana, Fleet Server, exporters — and Elastic Agent enrollment on **every** host | Medium |
| **workloads** | [homelab-proxmox-workloads](https://github.com/colac/homelab-proxmox-workloads) | The apps, one folder each: Nextcloud (live), k3s (VM only) | Often |

The split follows blast radius and ownership, not technology:

- **A change can only break its own layer.** A Caddy bump cannot touch
  Elasticsearch, and an Elasticsearch upgrade cannot touch Nextcloud — they
  are different repos, workspaces, secrets and release tags.
- **Each layer holds only the credentials it uses.** Core cannot clone a VM;
  workloads cannot read the Elastic passwords; monitoring cannot read the
  Nextcloud users. Inside each repo, Terraform and Ansible get different
  subsets again (see [Secrets](#secrets-least-privilege-per-command)).
- **Each layer is a small, self-contained context.** A person — or an AI
  agent — working on Nextcloud loads one `AGENTS.md`, one runbook and one
  secrets file, not the history of the Elastic port.
- **Observability is separate from what it observes.** The thing you use to
  see a failure should not share a release, or a failure mode, with it.

```mermaid
flowchart TB
  subgraph core["core — homelab-proxmox"]
    direction LR
    pk["Packer<br/>ubuntu-24.04-template (9000)<br/>ubuntu-26.04-template (9001)"]
    bv["Terraform module<br/>base-vm"]
    cl["Ansible collection<br/>colac.homelab<br/>common · docker_data"]
  end

  subgraph mon["monitoring — homelab-proxmox-monitoring"]
    direction LR
    mtf["terraform/<br/>VM monitoring"]
    man["ansible/<br/>Elastic Stack · exporters<br/>agent enrollment"]
  end

  subgraph wl["workloads — homelab-proxmox-workloads"]
    direction LR
    ntf["nextcloud/terraform"]
    nan["nextcloud/ansible"]
    ktf["k3s/terraform"]
  end

  pk -- "template_name" --> mtf & ntf & ktf
  bv -- "git tag ?ref=vX" --> mtf & ntf & ktf
  cl -- "requirements.yml tag" --> man & nan
  wl -- "agent targets (inventory/hosts.yml)" --> man
```

## Contracts between the layers

Everything that crosses a repo boundary is explicit, versioned, and written
down here. Nothing else may.

| Contract | Producer → consumer | Form | Changing it safely |
|---|---|---|---|
| VM templates | core → all VMs | Proxmox template **name** (`template_name`) | Build the new one alongside (new `vm_id`), move consumers one at a time, delete the old one last |
| ES OS prerequisites | core → monitoring | Baked into the template: `vm.max_map_count ≥ 262144`, memlock/nofile, `/opt/elastic` | Monitoring's `elastic_preflight` fails loudly if a template lacks them |
| Elastic Agent package | core → every VM | Pre-installed by Packer, disabled; version tracks monitoring's `stack_version` | Drift is tolerated: `elastic_agent` reinstalls the right version |
| `base-vm` module | core → every Terraform project | `git::https://github.com/colac/homelab-proxmox.git//terraform/modules/base-vm?ref=vX.Y.Z` | Release a tag; bump one project's `ref`, `init -upgrade`, read the plan |
| `colac.homelab` collection | core → every Ansible tree | `requirements.yml`: `…homelab-proxmox.git#/ansible/`, `version: vX.Y.Z` | Release a tag; bump one consumer; `00-bootstrap.yml --check --diff` |
| Agent targets | workloads → monitoring | Host + address in monitoring's `ansible/inventory/hosts.yml` (group `agents`) | Add/remove the entry; run `20` and `50` with `--limit` |
| Nextcloud metrics | workloads → monitoring | `nextcloud_serverinfo_token`, minted on the VM, stored in monitoring's `secrets.yaml` | Re-mint, update monitoring's secret, re-run `45-exporters.yml` |
| Private DNS names | each layer → PiHole | A records (`nextcloud.<zone>`, `kibana.<zone>`, `pve.<zone>`), set by hand | Moving these into core as code is a TODO |
| Toolchain pins | core → all | Same versions in every `mise.toml` (Terraform 1.15.7, ansible-core 2.17.14, …) | Bump in core first, then the others |

## Runtime view

What actually runs, and the supporting infrastructure none of the repos
provision.

```mermaid
flowchart TB
  internet(["Internet"])
  cf["Cloudflare DNS<br/>ACME DNS-01 TXT only<br/>no inbound ports"]
  off(["Off-LAN devices"])

  subgraph lan["LAN 192.168.1.0/24"]
    pihole["PiHole<br/>LAN DNS · private A records"]
    subgraph pve["Proxmox VE — pve"]
      tpl["templates 9000 / 9001<br/>(core)"]
      nc["VM nextcloud (workloads)<br/>Caddy · Nextcloud AIO<br/>Tailscale subnet router<br/>Elastic Agent"]
      k3s["VM k3s (workloads)<br/>not configured yet"]
      mon["VM monitoring (monitoring)<br/>Elasticsearch · Kibana<br/>Fleet Server · exporters<br/>Elastic Agent"]
    end
    nas[("TrueNAS<br/>ZFS mirror · SMB media<br/>netdata")]
  end

  nc -- "SMB external storage" --> nas
  nc -- "agent → Fleet :8220" --> mon
  nas -- "Graphite :9109" --> mon
  mon -- "serverinfo API via Caddy" --> nc
  nc & mon -- "DNS-01" --> cf
  cf --- internet
  off -- "Tailscale subnet route<br/>+ split-DNS to PiHole" --> nc
  lan -. resolves via .-> pihole
```

- **Nothing is exposed to the internet.** Cloudflare only answers ACME DNS-01
  challenges, so services get real Let's Encrypt certificates for names that
  resolve only through PiHole.
- **Off-LAN reach is Tailscale:** the Nextcloud VM advertises the LAN as a
  subnet route, and split-DNS sends the zone's lookups to PiHole.
- **Data lives on TrueNAS**, mounted by apps over SMB, never on a VM disk.
  VM disks hold only rebuildable state and named Docker volumes on a separate
  data disk.

## How a VM comes to exist

The same three stages for every VM, spread over two repos.

```mermaid
sequenceDiagram
  autonumber
  participant C as core
  participant P as Proxmox
  participant L as monitoring / workloads
  participant V as the VM
  C->>P: mise run packer:build 26.04 (packer token)
  Note over P: template ubuntu-26.04-template
  L->>P: mise run tf … apply (terraform token, base-vm @ tag)
  P->>V: full clone + cloud-init user/SSH key
  L->>V: mise run play … 00-bootstrap (colac.homelab @ tag)
  L->>V: mise run play … the app's playbooks (app secrets)
  Note over V: monitoring then enrolls its Elastic Agent
```

| Stage | Owns | Re-run when |
|---|---|---|
| **Packer** (core) | The golden image: OS, hardening, Docker, Tailscale, the Elastic Agent package, the Elasticsearch OS prerequisites | The base OS or baked-in tooling changes (rare) |
| **Terraform** (monitoring, workloads) | VM existence and shape: CPU/RAM/disks, network, cloud-init user | A VM is resized, added or destroyed |
| **Ansible** (monitoring, workloads) | Everything running inside the VM | Any app/config change (often — it is idempotent) |

Cloud-init is used **only** to create the login user and inject the SSH key.
App configuration through Proxmox's cloud-init hung or timed out on first
boot, runs once, and fails silently; Ansible re-runs in seconds and fails
loudly.

## Rolling out a change to a shared piece

```mermaid
flowchart LR
  a["Change in core<br/>(role, module, template)"] --> b["mise run lint<br/>PR, Conventional Commit"]
  b --> c["merge → semantic-release<br/>tags vX.Y.Z"]
  c --> d["bump ONE consumer's pin<br/>mise run deps"]
  d --> e["--check --diff / plan<br/>read it"]
  e --> f["apply / play"]
  f --> g{"healthy?"}
  g -- yes --> h["next consumer"]
  g -- no --> i["revert the pin<br/>(or fix forward)"]
```

One consumer at a time, each step reversible by moving a pin back. The
exception is Elasticsearch data, which upgrades in place and cannot be
downgraded — that is a monitoring-repo concern, documented in its runbook.

## Secrets: least privilege per command

Every repo uses the same scheme: SOPS + age files committed as ciphertext,
decrypted by `.mise/sops-exec` for **one command**, which exports only what
that command's tool reads. Nothing is ever exported into the shell — so
neither a human's terminal nor an AI agent working in the repo holds a
credential between commands.

```mermaid
flowchart LR
  subgraph repo["any repo"]
    f1[("secrets.yaml<br/>(ciphertext)")]
    f2[("&lt;app&gt;/secrets.yaml<br/>(workloads only)")]
    se[".mise/sops-exec &lt;profile&gt;"]
  end
  key[["~/.config/sops/age/keys.txt"]]
  t1["mise run packer:* → packer<br/>PKR_VAR_*"]
  t2["mise run tf … → terraform<br/>TF_VAR_pm_* · TF_TOKEN_*"]
  t3["mise run play … → ansible-playbook<br/>UPPERCASE app vars"]
  key -.-> se
  f1 --> se
  f2 --> se
  se --> t1 & t2 & t3
```

Which file and profile each repo uses, what each profile exports, and how
every credential is issued and rotated: [CREDENTIALS.md](CREDENTIALS.md).
Next steps toward least privilege — one Terraform token per repo, a
read-only identity for AI agents — are in each repo's TODO.

## Tooling

The same in every repo — mise for tools and entry points, Conventional
Commits and semantic-release for versions, one `AGENTS.md` per repo (plus one
per app in workloads) for AI agents. See [DEVELOPMENT.md](DEVELOPMENT.md).

## DNS today, and where it is heading

PiHole is the LAN's only resolver and holds the private A records every
service depends on — including `pve.<zone>`, which Packer and Terraform need
to reach the Proxmox API with TLS verification on. It runs outside all three
repos and nothing monitors it, which makes it the homelab's least-managed
single point of failure.

The direction (core's TODO): bring PiHole into core as code, with the records
as one list rendered by Ansible, and a second instance off the Proxmox host so
DNS survives the hypervisor. CoreDNS as an authoritative zone with transfers
to a secondary is the step after that, worth it once k3s wants wildcard
records or the record list grows — not before.
