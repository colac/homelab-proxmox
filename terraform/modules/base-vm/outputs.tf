output "vm_name" {
  value       = proxmox_vm_qemu.ubuntu_vm.name
  description = "Name of the deployed VM."
}

output "vm_ip" {
  value       = proxmox_vm_qemu.ubuntu_vm.default_ipv4_address
  description = "IP assigned to the deployed VM."
}
