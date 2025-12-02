terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc06"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_token_id
  pm_api_token_secret = var.proxmox_token_secret
  pm_tls_insecure     = true
}

resource "proxmox_vm_qemu" "ubuntu_vm" {
  name        = var.vm_name
  target_node = var.proxmox_node
  pool        = var.proxmox_pool

  clone      = var.template_name
  os_type    = "cloud-init"
  agent      = 1
  full_clone = true

  cores   = var.cpu_cores
  sockets = 1
  memory  = var.memory_mb

  # Disk config
  disks {
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = 32
          storage = "local-lvm"
          format  = "raw"
        }
      }
      #      scsi1 {
      #        disk {
      #          size    = 20
      #          storage = "Proxmox-QNAP-LUN"
      #          format  = "raw"
      #        }
      #      }
    }
  }

  # Network config
  network {
    id     = 0
    model  = "virtio"
    bridge = var.network_bridge
  }

  # Cloud-init
  ipconfig0 = "ip=dhcp"
  ciuser    = var.vm_user
  sshkeys   = file(var.ssh_public_key)

  # Optional: wait for QEMU guest agent for IP lookup
  lifecycle {
    ignore_changes = [
      network,
      disks,
    ]
  }
}

output "vm_ip" {
  value       = proxmox_vm_qemu.ubuntu_vm.default_ipv4_address
  description = "IP assigned to the deployed VM."
}
