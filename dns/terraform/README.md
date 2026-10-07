# DNS container (Terraform project)

Creates the Pi-hole LXC container at its fixed address and writes the Ansible
inventory fragment for it. State is in the Terraform Cloud `DNS` workspace
(Local execution). The runbook — template download, cutover, operations — is
[../README.md](../README.md).

```bash
mise run dns:plan
mise run dns:apply
mise run dns:tf output admin_url
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.15.7 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.2-rc07 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.9.1 |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 3.0.2-rc07 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [local_file.ansible_inventory](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [proxmox_lxc.pihole](https://registry.terraform.io/providers/Telmate/proxmox/3.0.2-rc07/docs/resources/lxc) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ansible_inventory_path"></a> [ansible\_inventory\_path](#input\_ansible\_inventory\_path) | Where to write the generated Ansible inventory fragment. Relative to this project directory. | `string` | `"../ansible/inventory/pihole.yml"` | no |
| <a name="input_bootstrap_nameservers"></a> [bootstrap\_nameservers](#input\_bootstrap\_nameservers) | Resolvers the container itself uses. Public ones, not 127.0.0.1: the container must resolve the Pi-hole download before Pi-hole exists. | `list(string)` | <pre>[<br/>  "1.1.1.1",<br/>  "9.9.9.9"<br/>]</pre> | no |
| <a name="input_cores"></a> [cores](#input\_cores) | CPU cores. | `number` | `1` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Root filesystem size. Gravity's database and the query log are the only things that grow. | `string` | `"4G"` | no |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Default gateway of the LAN (the router). | `string` | `"192.168.1.1"` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | Container hostname. The Ansible inventory host is hostname + "-ct", because a host and a group must not share a name. | `string` | `"pihole"` | no |
| <a name="input_hwaddr"></a> [hwaddr](#input\_hwaddr) | Fixed MAC address of eth0 (Proxmox's BC:24:11 prefix), so the router's DHCP reservation for ip\_address survives a rebuild. | `string` | `"BC:24:11:00:01:53"` | no |
| <a name="input_ip_address"></a> [ip\_address](#input\_ip\_address) | Fixed IPv4 address of this (failover) resolver. The router hands it out as DNS server 2, after the Raspberry Pi at 192.168.1.53. | `string` | `"192.168.1.153"` | no |
| <a name="input_memory_mb"></a> [memory\_mb](#input\_memory\_mb) | Memory in MB. Pi-hole uses well under 200 MB. | `number` | `512` | no |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | Proxmox bridge for eth0. | `string` | `"vmbr0"` | no |
| <a name="input_ostemplate"></a> [ostemplate](#input\_ostemplate) | LXC template the container is created from. It must already be on the node: `pveam download local <name>` (see dns/README.md). Changing it re-creates the container. | `string` | `"local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"` | no |
| <a name="input_pm_api_token_id"></a> [pm\_api\_token\_id](#input\_pm\_api\_token\_id) | This is an API token you have previously created for a specific user. | `string` | n/a | yes |
| <a name="input_pm_api_token_secret"></a> [pm\_api\_token\_secret](#input\_pm\_api\_token\_secret) | This uuid is only available when the token was initially created. | `string` | n/a | yes |
| <a name="input_pm_api_url"></a> [pm\_api\_url](#input\_pm\_api\_url) | This is the target Proxmox API endpoint. | `string` | n/a | yes |
| <a name="input_pm_tls_insecure"></a> [pm\_tls\_insecure](#input\_pm\_tls\_insecure) | Skip TLS verification against the Proxmox API. Set via TF\_VAR\_pm\_tls\_insecure by .mise/sops-exec (PROXMOX\_TLS\_INSECURE in mise.toml). | `bool` | `false` | no |
| <a name="input_prefix_length"></a> [prefix\_length](#input\_prefix\_length) | Prefix length of the LAN. | `number` | `24` | no |
| <a name="input_proxmox_node"></a> [proxmox\_node](#input\_proxmox\_node) | Proxmox node to create the container on. | `string` | `"pve"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Path to the deploy key's public half, authorised for root so Ansible can connect. | `string` | `"~/.ssh/homelab-proxmox.pub"` | no |
| <a name="input_storage"></a> [storage](#input\_storage) | Proxmox storage for the root filesystem. | `string` | `"local-lvm"` | no |
| <a name="input_vmid"></a> [vmid](#input\_vmid) | Container ID. Null lets Proxmox pick the next free one. | `number` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_url"></a> [admin\_url](#output\_admin\_url) | Pi-hole's web interface. |
| <a name="output_ansible_inventory_file"></a> [ansible\_inventory\_file](#output\_ansible\_inventory\_file) | Generated Ansible inventory fragment. |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | The resolver's fixed address. |
| <a name="output_vmid"></a> [vmid](#output\_vmid) | Proxmox ID of the Pi-hole container. |
<!-- END_TF_DOCS -->
