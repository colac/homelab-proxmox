output "vm_name" {
  value       = module.base-vm.vm_name
  description = "Name of the deployed VM."
}

output "vm_ip" {
  value       = module.base-vm.vm_ip
  description = "IP assigned to the deployed VM."
}

output "ansible_inventory_line" {
  value       = "${module.base-vm.vm_name} ansible_host=${module.base-vm.vm_ip} ansible_user=${var.vm_user}"
  description = "Ready-to-paste line for the Ansible inventory (see ansible/inventory)."
}
