# Every credential arrives as a TF_VAR_* environment variable from
# .mise/sops-exec (`mise run dns:plan`), which decrypts the repo-root
# secrets.yaml for that one command.
provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = var.pm_tls_insecure
}

# Pi-hole in an LXC system container — the platform's LAN resolver.
#
# A container, not a VM: one service that needs a few hundred MB. Pi-hole is
# installed natively inside it by Ansible (dns/ansible), not as Docker-in-LXC,
# which Proxmox advises against. Everything the container needs to be rebuilt
# is in this repo, so replacing it (a new ostemplate, a broken install) is
# `apply` + the playbook, not a repair.
resource "proxmox_lxc" "pihole" {
  target_node = var.proxmox_node
  vmid        = var.vmid
  hostname    = var.hostname
  ostemplate  = var.ostemplate
  description = "Pi-hole — managed by homelab-proxmox/dns (Terraform + Ansible). Do not configure by hand."
  tags        = "dns;pihole;terraform"

  # Unprivileged: container root is an unprivileged user on the host. Nesting
  # is what Proxmox enables by default for unprivileged containers, so that a
  # current systemd can use its sandboxing inside.
  unprivileged = true
  features {
    nesting = true
  }

  # DNS comes up first after a host reboot — everything else resolves through it.
  onboot  = true
  start   = true
  startup = "order=1"

  cores  = var.cores
  memory = var.memory_mb
  swap   = var.memory_mb

  rootfs {
    storage = var.storage
    size    = var.disk_size
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    hwaddr = var.hwaddr
    ip     = "${var.ip_address}/${var.prefix_length}"
    gw     = var.gateway
  }

  nameserver      = join(" ", var.bootstrap_nameservers)
  ssh_public_keys = file(pathexpand(var.ssh_public_key))
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    inventory_hostname = "${var.hostname}-ct"
    ip_address         = var.ip_address
    vmid               = proxmox_lxc.pihole.vmid
  })
  filename        = "${path.module}/${var.ansible_inventory_path}"
  file_permission = "0640"
}
