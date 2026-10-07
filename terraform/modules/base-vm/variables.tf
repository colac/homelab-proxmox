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

variable "cpu_type" {
  type        = string
  description = "CPU type presented to the guest. Defaults to the Packer templates' vm_cpu_type; changing it on an existing VM makes the provider reboot it."
  default     = "host"
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk0_size" {
  type        = string
  description = "OS disk size. Must be >= the Packer template's disk — Telmate cannot shrink a cloned disk. The 26.04 template ships 24G with LVM; only /opt and the OS live here."
  default     = "24G"
}

variable "data_disk_size" {
  type        = string
  description = "Docker data disk (scsi1), mounted at /var/lib/docker by the Ansible docker_data role. This is where container data actually lives — Elasticsearch's esdata volume, Nextcloud AIO's mastercontainer volume — so it, not disk0_size, is the retention ceiling. null means no second disk."
  default     = null
}

variable "data_disk_storage" {
  type        = string
  description = "Proxmox storage for the docker data disk. Defaults to proxmox_storage. Worth setting separately if the data disk should live on different backing storage than the OS disk."
  default     = null
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
