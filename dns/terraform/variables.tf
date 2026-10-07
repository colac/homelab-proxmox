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
  description = "Skip TLS verification against the Proxmox API. Set via TF_VAR_pm_tls_insecure by .mise/sops-exec (PROXMOX_TLS_INSECURE in mise.toml)."
  default     = false
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node to create the container on."
  default     = "pve"
}

variable "vmid" {
  type        = number
  description = "Container ID. Null lets Proxmox pick the next free one."
  default     = null
}

variable "hostname" {
  type        = string
  description = "Container hostname. The Ansible inventory host is hostname + \"-ct\", because a host and a group must not share a name."
  default     = "pihole"
}

variable "ostemplate" {
  type        = string
  description = "LXC template the container is created from. It must already be on the node: `pveam download local <name>` (see dns/README.md). Changing it re-creates the container."
  default     = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "ip_address" {
  type        = string
  description = "Fixed IPv4 address of this (failover) resolver. The router hands it out as DNS server 2, after the Raspberry Pi at 192.168.1.53."
  default     = "192.168.1.153"
}

variable "hwaddr" {
  type        = string
  description = "Fixed MAC address of eth0 (Proxmox's BC:24:11 prefix), so the router's DHCP reservation for ip_address survives a rebuild."
  default     = "BC:24:11:00:01:53"
}

variable "prefix_length" {
  type        = number
  description = "Prefix length of the LAN."
  default     = 24
}

variable "gateway" {
  type        = string
  description = "Default gateway of the LAN (the router)."
  default     = "192.168.1.1"
}

variable "bootstrap_nameservers" {
  type        = list(string)
  description = "Resolvers the container itself uses. Public ones, not 127.0.0.1: the container must resolve the Pi-hole download before Pi-hole exists."
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "cores" {
  type        = number
  description = "CPU cores."
  default     = 1
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB. Pi-hole uses well under 200 MB."
  default     = 512
}

variable "disk_size" {
  type        = string
  description = "Root filesystem size. Gravity's database and the query log are the only things that grow."
  default     = "4G"
}

variable "storage" {
  type        = string
  description = "Proxmox storage for the root filesystem."
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Proxmox bridge for eth0."
  default     = "vmbr0"
}

variable "ssh_public_key" {
  type        = string
  description = "Path to the deploy key's public half, authorised for root so Ansible can connect."
  default     = "~/.ssh/homelab-proxmox.pub"
}

variable "ansible_inventory_path" {
  type        = string
  description = "Where to write the generated Ansible inventory fragment. Relative to this project directory."
  default     = "../ansible/inventory/pihole.yml"
}
