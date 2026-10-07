# base-vm (Terraform module)

Reusable module that clones a Proxmox VM template into a cloud-init VM. Used by
the Terraform projects in the monitoring and workloads repos, pinned to a
release tag of this repo — see [../../README.md](../../README.md).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | > 1.9.0, < 2.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.2-rc07 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 3.0.2-rc07 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_vm_qemu.ubuntu_vm](https://registry.terraform.io/providers/Telmate/proxmox/3.0.2-rc07/docs/resources/vm_qemu) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cpu_cores"></a> [cpu\_cores](#input\_cpu\_cores) | n/a | `number` | `2` | no |
| <a name="input_cpu_type"></a> [cpu\_type](#input\_cpu\_type) | CPU type presented to the guest. Defaults to the Packer templates' vm\_cpu\_type; changing it on an existing VM makes the provider reboot it. | `string` | `"host"` | no |
| <a name="input_data_disk_size"></a> [data\_disk\_size](#input\_data\_disk\_size) | Docker data disk (scsi1), mounted at /var/lib/docker by the Ansible docker\_data role. This is where container data actually lives — Elasticsearch's esdata volume, Nextcloud AIO's mastercontainer volume — so it, not disk0\_size, is the retention ceiling. null means no second disk. | `string` | `null` | no |
| <a name="input_data_disk_storage"></a> [data\_disk\_storage](#input\_data\_disk\_storage) | Proxmox storage for the docker data disk. Defaults to proxmox\_storage. Worth setting separately if the data disk should live on different backing storage than the OS disk. | `string` | `null` | no |
| <a name="input_disk0_size"></a> [disk0\_size](#input\_disk0\_size) | OS disk size. Must be >= the Packer template's disk — Telmate cannot shrink a cloned disk. The 26.04 template ships 24G with LVM; only /opt and the OS live here. | `string` | `"24G"` | no |
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
