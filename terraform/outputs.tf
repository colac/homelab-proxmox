output "vm_name" {
  value       = module.base-vm.vm_name
  description = "Name of the deployed VM."
}

output "vm_ip" {
  value       = module.base-vm.vm_ip
  description = "IP assigned to the deployed VM."
}