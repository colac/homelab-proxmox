resource "proxmox_vm_qemu" "ubuntu_vm" {
  name        = var.vm_name
  target_node = var.proxmox_node
  pool        = var.proxmox_pool

  clone      = var.template_name
  os_type    = "cloud-init"
  agent      = 1
  full_clone = true
  scsihw     = "virtio-scsi-single" # match the Packer template

  # Boot from the cloned OS disk (not the cloud-init drive or network/iPXE).
  boot = "order=scsi0"

  cores   = var.cpu_cores
  sockets = 1
  memory  = var.memory_mb

  # Disk config
  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.proxmox_storage
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          # size must be >= the template's disk (60G) — Telmate cannot shrink a
          # cloned disk and will otherwise create a new empty one. No `format`
          # on local-lvm (LVM-thin is block storage, raw is implied).
          size    = var.disk0_size
          storage = var.proxmox_storage
        }
      }
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
