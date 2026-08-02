output "vm_name" {
  value       = module.nextcloud.vm_name
  description = "Name of the deployed Nextcloud VM."
}

output "vm_ip" {
  value       = module.nextcloud.vm_ip
  description = "IP assigned to the deployed Nextcloud VM."
}

output "ansible_inventory_line" {
  value       = "${module.nextcloud.vm_name} ansible_host=${module.nextcloud.vm_ip} ansible_user=${var.vm_user}"
  description = "Ready-to-paste line for the Ansible inventory (see ansible/inventory)."
}
