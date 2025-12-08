<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | > 1.9.0, < 2.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.2-rc06 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 3.0.2-rc06 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_vm_qemu.ubuntu_vm](https://registry.terraform.io/providers/Telmate/proxmox/3.0.2-rc06/docs/resources/vm_qemu) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cpu_cores"></a> [cpu\_cores](#input\_cpu\_cores) | n/a | `number` | `2` | no |
| <a name="input_disk0_size"></a> [disk0\_size](#input\_disk0\_size) | n/a | `string` | `"20G"` | no |
| <a name="input_memory_mb"></a> [memory\_mb](#input\_memory\_mb) | n/a | `number` | `8192` | no |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | n/a | `string` | `"vmbr0"` | no |
| <a name="input_proxmox_node"></a> [proxmox\_node](#input\_proxmox\_node) | n/a | `string` | `"pve"` | no |
| <a name="input_proxmox_pool"></a> [proxmox\_pool](#input\_proxmox\_pool) | n/a | `string` | `null` | no |
| <a name="input_proxmox_storage"></a> [proxmox\_storage](#input\_proxmox\_storage) | n/a | `string` | `"local-lvm"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Path to SSH public key | `string` | n/a | yes |
| <a name="input_template_name"></a> [template\_name](#input\_template\_name) | Name of the Proxmox template to clone | `string` | n/a | yes |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | n/a | `string` | n/a | yes |
| <a name="input_vm_user"></a> [vm\_user](#input\_vm\_user) | n/a | `string` | `"ubuntu"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_vm_ip"></a> [vm\_ip](#output\_vm\_ip) | IP assigned to the deployed VM. |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | Name of the deployed VM. |
<!-- END_TF_DOCS -->