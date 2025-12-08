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
          size    = var.disk0_size
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
  sshkeys   = var.ssh_public_key

  # Optional: wait for QEMU guest agent for IP lookup
  # lifecycle {
  #   ignore_changes = [
  #     network,
  #     disks,
  #   ]
  # }
}
