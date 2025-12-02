variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API endpoint"
}

variable "proxmox_token_id" {
  type        = string
  description = "Token ID (format: user@pve!role)"
  sensitive   = true
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "proxmox_pool" {
  type    = string
  default = null
}

variable "template_name" {
  type        = string
  description = "Name of the Proxmox template to clone"
}

variable "vm_name" {
  type = string
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "proxmox_storage" {
  type    = string
  default = "local-lvm"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "vm_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_key" {
  type        = string
  description = "Path to SSH public key"
}
