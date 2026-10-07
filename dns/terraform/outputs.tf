output "vmid" {
  value       = proxmox_lxc.pihole.vmid
  description = "Proxmox ID of the Pi-hole container."
}

output "ip_address" {
  value       = var.ip_address
  description = "The resolver's fixed address."
}

output "admin_url" {
  value       = "http://${var.ip_address}/admin"
  description = "Pi-hole's web interface."
}

output "ansible_inventory_file" {
  value       = local_file.ansible_inventory.filename
  description = "Generated Ansible inventory fragment."
}
