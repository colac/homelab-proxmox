# k3s VM (Terraform project)

Clones the Packer-built template into a VM. State is stored in the Terraform
Cloud `k3s` workspace of the `colac_homelab` organization.

```bash
cp terraform.tfvars.example terraform.tfvars   # then fill in secrets
terraform init
terraform apply
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | > 1.9.0, < 2.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.2-rc07 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_base-vm"></a> [base-vm](#module\_base-vm) | ../../modules/base-vm | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cpu_cores"></a> [cpu\_cores](#input\_cpu\_cores) | n/a | `number` | `2` | no |
| <a name="input_disk0_size"></a> [disk0\_size](#input\_disk0\_size) | n/a | `string` | `"32G"` | no |
| <a name="input_memory_mb"></a> [memory\_mb](#input\_memory\_mb) | n/a | `number` | `8192` | no |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | n/a | `string` | `"vmbr0"` | no |
| <a name="input_pm_api_token_id"></a> [pm\_api\_token\_id](#input\_pm\_api\_token\_id) | This is an API token you have previously created for a specific user. | `string` | n/a | yes |
| <a name="input_pm_api_token_secret"></a> [pm\_api\_token\_secret](#input\_pm\_api\_token\_secret) | This uuid is only available when the token was initially created. | `string` | n/a | yes |
| <a name="input_pm_api_url"></a> [pm\_api\_url](#input\_pm\_api\_url) | This is the target Proxmox API endpoint. | `string` | n/a | yes |
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
| <a name="output_ansible_inventory_line"></a> [ansible\_inventory\_line](#output\_ansible\_inventory\_line) | Ready-to-paste line for the Ansible inventory (see ansible/inventory). |
| <a name="output_vm_ip"></a> [vm\_ip](#output\_vm\_ip) | IP assigned to the deployed VM. |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | Name of the deployed VM. |
<!-- END_TF_DOCS -->
