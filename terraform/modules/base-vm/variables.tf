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

variable "disk0_size" {
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
