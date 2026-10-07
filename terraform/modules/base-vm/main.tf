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

  # The provider's cpu block replaces the deprecated top-level cores/sockets.
  # `type` is declared, not left to the provider's default: it must match what
  # the Packer templates set (vm_cpu_type, "host"), because a CPU type change
  # is one of the edits that makes the provider reboot the VM.
  cpu {
    cores   = var.cpu_cores
    sockets = 1
    type    = var.cpu_type
  }
  memory = var.memory_mb

  # Proxmox reports an unset startup/shutdown order as -1 for each field, and
  # the provider stores that as a startup_shutdown block on every refresh.
  # Left undeclared, every plan proposes deleting the block — and applying
  # that changes nothing, because the next refresh reads -1 again. Declaring
  # Proxmox's own "unset" values keeps plans clean without touching the VM.
  startup_shutdown {
    order            = -1
    shutdown_timeout = -1
    startup_delay    = -1
  }

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
          # size must be >= the template's OS disk — Telmate cannot shrink a
          # cloned disk and will otherwise create a new empty one. No `format`
          # on local-lvm (LVM-thin is block storage, raw is implied).
          size    = var.disk0_size
          storage = var.proxmox_storage
        }
      }

      # Docker data disk. Absent unless the project asks for one, so a VM that
      # exists to *receive* an already-populated disk can be created without a
      # docker-vg of its own and import the other one cleanly.
      #
      # This disk is created raw and stays raw as far as Proxmox is concerned.
      # The Ansible `docker_data` role does pvcreate/vgcreate/lvcreate/mkfs on
      # first run and mounts it at /var/lib/docker; on a disk that already
      # carries a docker-vg it adopts what is there instead. Keeping it out of
      # the Packer template is what gives each VM its own LVM UUIDs — a full
      # clone would copy them byte-for-byte and make the disk unmovable without
      # vgimportclone.
      dynamic "scsi1" {
        for_each = var.data_disk_size == null ? [] : [var.data_disk_size]
        content {
          disk {
            size    = scsi1.value
            storage = coalesce(var.data_disk_storage, var.proxmox_storage)
          }
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
