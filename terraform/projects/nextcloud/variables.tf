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
  type        = string
  description = "Proxmox node to deploy the VM on."
  default     = "pve"
}

variable "proxmox_pool" {
  type        = string
  description = "Optional Proxmox resource pool."
  default     = null
}

variable "template_name" {
  type        = string
  description = "Name of the Proxmox template to clone."
  default     = "ubuntu-24.04-template"
}

variable "vm_name" {
  type        = string
  description = "Name of the Nextcloud VM."
  default     = "nextcloud"
}

variable "cpu_cores" {
  type        = number
  description = "Number of vCPUs for the Nextcloud VM."
  default     = 4
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB for the Nextcloud VM."
  default     = 8192
}

variable "disk0_size" {
  type        = string
  description = "Root disk size (include a unit, e.g. 64G)."
  default     = "64G"
}

variable "proxmox_storage" {
  type        = string
  description = "Proxmox storage pool for the VM disk and cloud-init drive."
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Proxmox network bridge to attach the VM to."
  default     = "vmbr0"
}

variable "vm_user" {
  type        = string
  description = "Cloud-init username created on the VM."
  default     = "ubuntu"
}

variable "ssh_public_key" {
  type        = string
  description = "Path to the SSH public key authorized on the VM."
  default     = "~/.ssh/homelab-proxmox.pub"
}
