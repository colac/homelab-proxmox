# ==========================================================
# Packer Template: Ubuntu 26.04 LTS "Resolute Raccoon" (Proxmox ISO)
# Modular layout — variables and versions are in separate files.
#
# Ported from packer/ubuntu-24.04 and deliberately kept close to it: the two
# trees differ only in release-specific values (ISO, vm_id, vm_name, tags) and
# in boot_command being a variable here. Everything else — the storage layout,
# the hardening, the Elasticsearch OS prerequisites, the seal — is the same
# proven build, so a fix found on one side ports cleanly to the other.
#
# The third-party repositories the provisioning scripts add both publish for
# 26.04's codename (checked: download.docker.com/linux/ubuntu/dists/resolute and
# pkgs.tailscale.com/stable/ubuntu/resolute.*), so the scripts' existing
# $VERSION_CODENAME lookups need no special-casing.
# ==========================================================

source "proxmox-iso" "ubuntu-26-04" {
  # --------------------------------------------------------
  # Proxmox connection
  # --------------------------------------------------------
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.proxmox_skip_tls_verify

  # --------------------------------------------------------
  # ISO Boot configuration
  # --------------------------------------------------------
  boot_iso {
    type     = var.boot_iso_type
    iso_file = var.boot_iso_file
    unmount  = var.boot_iso_unmount
  }

  # --------------------------------------------------------
  # Virtual Machine Settings
  # --------------------------------------------------------
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_description = var.vm_description

  qemu_agent      = var.qemu_agent
  scsi_controller = var.scsi_controller

  disks {
    disk_size    = var.disk_size
    storage_pool = var.storage_pool
    type         = var.disk_type
    format       = "raw"
    io_thread    = true
    ssd          = true
    discard      = true
  }

  cores    = var.vm_cpu_cores
  sockets  = var.vm_cpu_sockets
  cpu_type = var.vm_cpu_type
  memory   = var.vm_memory

  network_adapters {
    model    = var.network_model
    bridge   = var.network_bridge
    firewall = false
  }

  # --------------------------------------------------------
  # Cloud-init and autoinstall
  # --------------------------------------------------------
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # IP advertised to the VM in the boot command. Empty var.http_interface =
  # auto-detect (binds all interfaces). Set it to the LAN NIC when building from
  # a host whose default route is a VPN, so {{ .HTTPIP }} resolves to the
  # reachable LAN address instead of the tunnel IP. (http_interface and
  # http_bind_address are mutually exclusive in the proxmox plugin.)
  http_interface    = var.http_interface != "" ? var.http_interface : null
  http_bind_address = var.http_interface != "" ? null : "0.0.0.0"

  http_port_min = 8181
  http_port_max = 8181

  http_content = {
    "/user-data" = local.user_data
    "/meta-data" = local.meta_data
  }

  # --------------------------------------------------------
  # Boot commands for autoinstall
  # --------------------------------------------------------
  # Keystrokes live in var.boot_command — they depend on the ISO's GRUB menu
  # layout, the part of an autoinstall most likely to shift between releases.
  boot_command = var.boot_command
  boot         = "c"
  boot_wait    = "5s"

  # --------------------------------------------------------
  # SSH setup
  # --------------------------------------------------------
  #ssh_host = "guest-agent"
  ssh_username = var.username
  #ssh_password = var.password
  ssh_private_key_file = var.ssh_private_key_file
  # if ssh key has password use the agent
  #ssh_agent_auth = true
  ssh_timeout = var.ssh_timeout

  # --------------------------------------------------------
  # Define Tags
  # --------------------------------------------------------
  tags = var.tags
}

# ==========================================================
# Build configuration
# ==========================================================
build {
  name    = "ubuntu-26-04-template"
  sources = ["source.proxmox-iso.ubuntu-26-04"]

  # --------------------------------------------------------
  # Wait for cloud-init to complete (non-root safe)
  # --------------------------------------------------------
  provisioner "shell" {
    # cloud-init status --wait's exit code is documented (cloud-init's own
    # CLI reference) as 1 = crashed, 2 = finished but with recoverable
    # errors, 0 = finished clean. Exit 2 is a completed run, not a failure —
    # e.g. cloud-init deliberately not re-setting the primary user's passwd
    # on first boot, because subiquity's installer already created that user
    # with it, logs as a WARNING-level recoverable error and nothing else.
    # Autoinstall also disables cloud-init for all boots after this one via
    # /etc/cloud/cloud-init.disabled — expected, not a failure either; the
    # exit-code check above is what actually matters, not that file's
    # presence. Only exit 1 aborts the build here; exit 2 is logged with the
    # detail cloud-init recorded, not swallowed silently. The follow-up
    # `cloud-init status --long` calls are each `|| true`-guarded: run
    # without --wait, they hit the exact same exit-code logic and would
    # themselves return 1/2 — under this script's `-e` shebang, an unguarded
    # call aborts the script right there, before the final echo, silently
    # turning the "log it, don't fail" branch back into a failure.
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "ec=0",
      "sudo cloud-init status --wait || ec=$?",
      "if [ \"$ec\" -eq 1 ]; then echo 'cloud-init crashed (exit 1):'; sudo cloud-init status --long || true; exit 1; fi",
      "if [ \"$ec\" -eq 2 ]; then echo 'cloud-init finished with recoverable errors (exit 2, non-fatal):'; sudo cloud-init status --long || true; fi",
      "echo 'cloud-init finished.'"
    ]
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
  }

  # -----------------------
  # Upload custom ROOT CA certificates
  # -----------------------
  provisioner "file" {
    source      = "${path.root}/custom-ca"
    destination = "/tmp/custom-ca"
  }

  # -----------------------
  # Run provisioning scripts (as root) — environment variables exported here
  # Keep execution order deterministic: proxy -> docker -> elastic-agent
  # -----------------------
  provisioner "shell" {
    environment_vars = [
      "INSTALL_DOCKER=${var.install_docker}",
      "INSTALL_TAILSCALE=${var.install_tailscale}",
      "ELASTIC_AGENT_VERSION=${var.elastic_agent_version}",
      "ENABLE_PROXY=${var.enable_proxy}",
      "HTTP_PROXY=${var.http_proxy}",
      "HTTPS_PROXY=${var.https_proxy}",
      "NO_PROXY=${var.no_proxy}",
    ]
    execute_command = "sudo -E bash '{{ .Path }}'"
    # Keep execution order deterministic: proxy -> ca -> docker -> elastic-agent -> tailscale
    scripts = [
      "${path.root}/scripts/00-configure-proxy.sh",
      "${path.root}/scripts/10-install-custom-ca.sh",
      "${path.root}/scripts/20-install-docker.sh",
      "${path.root}/scripts/30-install-elastic-agent.sh",
      "${path.root}/scripts/40-install-tailscale.sh"
    ]
  }

  # ------------------------------------------------------------
  # Run cleanup and seal the template
  # ------------------------------------------------------------
  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/99-cleanup-seal.sh"
    ]
  }
}
