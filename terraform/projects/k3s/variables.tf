variable "pm_api_url" {
  type        = string
  description = "This is the target Proxmox API endpoint."
}

variable "pm_api_token_id" {
  type        = string
  description = "This is an API token you have previously created for a specific user."
  sensitive   = true
}

variable "pm_api_token_secret" {
  type        = string
  description = "This uuid is only available when the token was initially created."
  sensitive   = true
}

variable "pm_tls_insecure" {
  type        = bool
  description = "Skip TLS verification against the Proxmox API. Set via TF_VAR_pm_tls_insecure from terraform/.envrc (PROXMOX_TLS_INSECURE); true is only needed when the endpoint serves a self-signed certificate."
  default     = false
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "proxmox_pool" {
  type    = string
  default = null
}

# See the monitoring project for why this is the 26.04 template: a 24G disk0
# requires the template whose OS disk is actually 24G and actually uses LVM.
variable "template_name" {
  type        = string
  description = "Name of the Proxmox template to clone"
  default     = "ubuntu-26.04-template"
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
  type        = string
  description = "OS disk size. Must be >= the Packer template's disk — Telmate cannot shrink a cloned disk."
  default     = "24G"
}

variable "data_disk_size" {
  type        = string
  description = "Docker data disk, mounted at /var/lib/docker."
  default     = "12G"
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
  default     = "~/.ssh/homelab-proxmox.pub"
}
