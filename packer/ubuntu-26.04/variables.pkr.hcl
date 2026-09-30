# --------------------------------------------------------
# Proxmox connection
# --------------------------------------------------------
variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API Token ID"
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Proxmox API Token Secret"
  sensitive   = true
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name"
}

variable "proxmox_skip_tls_verify" {
  type        = bool
  default     = false
  description = "Skip TLS verification"
}

# --------------------------------------------------------
# ISO Boot configuration
# --------------------------------------------------------
variable "boot_iso_type" {
  type        = string
  description = "Boot ISO type"
  default     = "scsi"
}

variable "boot_iso_file" {
  type        = string
  description = "Ubuntu ISO local file"
  default     = "local:iso/ubuntu-26.04.1-live-server-amd64.iso"
}

variable "boot_iso_unmount" {
  type        = bool
  description = "Unmount ISO after installation?"
  default     = true
}

# --------------------------------------------------------
# Virtual Machine Settings
# --------------------------------------------------------
# 9001, not 9000: packer/ubuntu-24.04 owns 9000 and the two templates are meant
# to coexist while VMs are migrated across. Proxmox refuses a build whose vm_id
# already exists, so a collision here fails the build rather than replacing the
# 24.04 template.
variable "vm_id" {
  type        = number
  description = "VM template ID"
  default     = 9001
}

variable "vm_name" {
  type        = string
  description = "VM template name"
  default     = "ubuntu-26.04-template"
}

variable "vm_description" {
  type        = string
  description = "VM template description"
  default     = "Ubuntu 26.04 LTS (Resolute Raccoon) template"
}

variable "qemu_agent" {
  type    = bool
  default = true
}

variable "scsi_controller" {
  type    = string
  default = "virtio-scsi-single"
}

# OS disk only. The Docker data disk is not part of the golden image — see the
# storage comment in http/user-data.yml.tpl for why it is Terraform's and
# Ansible's job. 24G holds the OS comfortably once /var/lib/docker lives
# elsewhere; the LV sizes below deliberately leave the remainder unallocated.
variable "disk_size" {
  type        = string
  description = "OS disk size. Must be at least the sum of the lv_*_size values plus ~1.5G for the BIOS/EFI/boot partitions."
  default     = "24G"
}

# ----------------------------------------------------------------------------
# Logical volume sizes inside ubuntu-vg.
#
# These are sizes, not proportions, and they intentionally do not add up to the
# whole disk: on the 24G default they claim 20G and leave ~2.4G of free extents
# in the volume group. That slack is what makes growing a filesystem a one-liner
# later (`lvextend` + `resize2fs`) instead of a repartition.
#
# Growing past the slack means growing the Proxmox disk first, then:
#   growpart /dev/sda 4 && pvresize /dev/sda4
#   lvextend -L +20G /dev/ubuntu-vg/root && resize2fs /dev/ubuntu-vg/root
# ----------------------------------------------------------------------------
variable "lv_root_size" {
  type        = string
  description = "Size of the root logical volume."
  default     = "12G"
}

variable "lv_home_size" {
  type        = string
  description = "Size of the /home logical volume."
  default     = "2G"
}

variable "lv_tmp_size" {
  type        = string
  description = "Size of the /tmp logical volume."
  default     = "2G"
}

variable "lv_opt_size" {
  type        = string
  description = "Size of the /opt logical volume. Holds the compose projects (elastic_base_dir), not container data."
  default     = "4G"
}

variable "storage_pool" {
  type        = string
  description = "Storage pool for VM disk"
  default     = "local-lvm"
}

variable "disk_type" {
  type        = string
  description = "Disk Type"
  default     = "scsi"
}

variable "vm_cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 2
}

variable "vm_cpu_sockets" {
  type        = number
  description = "Number of CPU sockets"
  default     = 1
}

variable "vm_cpu_type" {
  type        = string
  description = "CPU type"
  default     = "host"
}

variable "vm_memory" {
  type        = number
  description = "Memory in MB"
  default     = 4096
}

variable "network_model" {
  type        = string
  description = "Network Model"
  default     = "virtio"
}

variable "network_bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

# The autoinstall boot command drives GRUB's edit screen by keystroke: three
# <down>s to reach the linux line, <end>, then four <bs> to strip the trailing
# "---" before appending the autoinstall arguments. That makes it the one part
# of this build coupled to the ISO's GRUB menu layout, which is exactly the
# thing a new Ubuntu release is free to change. It is a variable so a layout
# change can be corrected from variables.pkrvars.hcl instead of by patching the
# source block. The {{ }} placeholders are Packer's, not HCL's, and pass through
# this default untouched.
variable "boot_command" {
  type        = list(string)
  description = "Keystrokes that add the autoinstall kernel arguments at the ISO's GRUB menu."
  default = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]
}

variable "http_interface" {
  type        = string
  description = "Host network interface whose IP is advertised to the VM for the autoinstall HTTP server (empty = auto-detect). Set to the LAN NIC when the host's default route is a VPN."
  default     = ""
}

# --------------------------------------------------------
# Cloud-init and autoinstall
# --------------------------------------------------------
variable "username" {
  type        = string
  description = "Default user"
  default     = "ubuntu"
}

variable "password" {
  type        = string
  description = "Default user plaintext password (unused unless ssh_password is re-enabled; console login uses password_hash)"
  sensitive   = true
  default     = ""
}

variable "password_hash" {
  type        = string
  description = <<EOT
Console-login password hash for the default user (SSH is key-only; this is the
tty/serial fallback). Supplied as PKR_VAR_password_hash by packer/.envrc, from
packer_password_hash in the SOPS-encrypted secrets.yaml. Generate with:
$ mkpasswd -m sha-512 '<yourpassword>'
EOT
  sensitive   = true
}

variable "hostname" {
  type        = string
  description = "System hostname"
  default     = "ubuntu-template"
}

variable "timezone" {
  type        = string
  description = "System timezone"
  default     = "Europe/Lisbon"
}

variable "locale" {
  type        = string
  description = "System locale"
  default     = "en_US.UTF-8"
}

variable "keyboard_layout" {
  type        = string
  description = "Keyboard layout"
  default     = "us"
}

variable "keyboard_variant" {
  type        = string
  description = "Keyboard variant"
  default     = "intl"
}

# Packages
variable "packages" {
  type        = list(string)
  description = "List of packages to install"
  default = [
    "qemu-guest-agent",
    "cloud-init",
    "lvm2",
    # NTP client cloud-init's `ntp:` block manages (see http/user-data.yml.tpl
    # for why chrony, not systemd-timesyncd, on this release). Baked in here
    # rather than left to cc_ntp's own install-if-missing fallback, same as
    # every other package on this list.
    "chrony",
    # minimal OS
    "ubuntu-minimal",
    # docker dependencies
    "ca-certificates",
    "curl",
    "gnupg",
    "lsb-release",
    "apt-transport-https",
    "software-properties-common",
    # troubleshooting tools
    "net-tools",
    "inetutils-ping",
    "traceroute",
    "dnsutils",
    "iproute2",
    "tcpdump",
    "unzip",
    "jq",
    "htop",
    "tmux",
    "lsof",
    "strace",
    "vim-nox",
    "mc",
    "sysstat",
    "rsync",
    "git",
    # security scanners
    # "rkhunter",
    # "chkrootkit",
    # "lynis",
    # "debsums",
    # "aide",
    # "aide-common",
    # audo subsystem
    "auditd",
    "audispd-plugins"
  ]
}

# SSH Configuration
variable "ssh_private_key_file" {
  type        = string
  description = "Private key file to use for SSH during the build. Path only — the key itself stays in ~/.ssh and never enters the repo."
  sensitive   = true
  default     = "~/.ssh/homelab-proxmox"
}

variable "ssh_timeout" {
  type        = string
  description = "SSH timeout"
  default     = "20m"
}

# SSH Keys for Default user. Password auth is disabled in the image, so if this
# is empty nobody — Packer included — can ever log in to the built template.
# packer/.envrc fills it from ~/.ssh/homelab-proxmox.pub at direnv load time.
variable "ssh_authorized_keys" {
  type        = list(string)
  description = "SSH authorized keys for default user"
  default     = []
}

# Additional Users (optional)
variable "additional_users" {
  type = list(object({
    name                = string
    groups              = list(string)
    sudo                = string
    shell               = string
    ssh_authorized_keys = list(string)
    lock_passwd         = bool
  }))
  description = "Additional users to create"
  default     = []
}

variable "tags" {
  type        = string
  description = "The tags to set. This is a semicolon separated list. For example, debian-12;template."
  default     = "packer;ubuntu;26-04"
}

# DNS nameservers configured during autoinstall (PiHole primary, public fallback).
variable "nameservers" {
  type        = list(string)
  description = "DNS nameservers for the VM (first is primary)."
  default = [
    "192.168.1.53",
    "1.1.1.1"
  ]
}

# NTP Servers
variable "ntp_servers" {
  type        = list(string)
  description = "List of NTP servers"
  default = [
    "0.pool.ntp.org",
    "1.pool.ntp.org",
    "2.pool.ntp.org",
    "3.pool.ntp.org"
  ]
}

# Docker
variable "install_docker" {
  type        = bool
  description = "Wheter to install Docker"
  default     = true
}

# Tailscale
variable "install_tailscale" {
  type        = bool
  description = "Whether to install Tailscale (the node is not authenticated at build time)"
  default     = true
}

# HTTP Proxy
variable "enable_proxy" {
  type        = bool
  description = "Whether to configure system-wide proxy settings"
  default     = false
}

variable "http_proxy" {
  type        = string
  description = "HTTP proxy address (e.g. http://proxy.example.com:8080)"
  default     = ""
}

variable "https_proxy" {
  type        = string
  description = "HTTPS proxy address"
  default     = ""
}

variable "no_proxy" {
  type        = string
  description = "Comma-separated list of domains or IPs to exclude from proxy"
  default     = "localhost,127.0.0.1"
}

# Elastic Stack OS prerequisites
#
# Baked into the image rather than applied by Ansible, matching how the
# Elastic repo's template does it: a clone arrives ready to run
# Elasticsearch, and Ansible has zero involvement in OS configuration.
# Changing either of these means rebuilding the template.
variable "vm_max_map_count" {
  type        = number
  description = "vm.max_map_count sysctl. Elasticsearch runs a hard bootstrap check on this and refuses to start below 262144."
  default     = 262144
}

variable "elastic_base_dir" {
  type        = string
  description = "Base directory for the Elastic Stack compose projects. Must match elastic_base_dir in ansible/inventory/group_vars/all.yml."
  default     = "/opt/elastic"
}

variable "elastic_agent_version" {
  type        = string
  description = "Elastic Agent version pre-installed (and left disabled) in the template. Should match stack_version in ansible/inventory/group_vars/all.yml; the elastic_agent role reinstalls if they drift."
  default     = "9.5.4"
}
