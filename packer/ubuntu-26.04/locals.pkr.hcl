locals {
  # Timestamp for unique naming
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")

  # User data from template
  user_data = templatefile("${path.root}/http/user-data.yml.tpl", {
    username            = var.username
    password_hash       = var.password_hash
    hostname            = var.hostname
    enable_proxy        = var.enable_proxy
    proxy_url           = var.http_proxy
    timezone            = var.timezone
    locale              = var.locale
    keyboard_layout     = var.keyboard_layout
    keyboard_variant    = var.keyboard_variant
    packages            = var.packages
    additional_users    = var.additional_users
    ssh_authorized_keys = var.ssh_authorized_keys
    ntp_servers         = var.ntp_servers
    nameservers         = var.nameservers
    lv_root_size        = var.lv_root_size
    lv_home_size        = var.lv_home_size
    lv_tmp_size         = var.lv_tmp_size
    lv_opt_size         = var.lv_opt_size
    vm_max_map_count    = var.vm_max_map_count
    elastic_base_dir    = var.elastic_base_dir

    # Base64 so the script's own quoting (single-quoted heredocs, etc.)
    # survives being dropped into a YAML late-command untouched. Decoded
    # and run chrooted into /target before the first boot that would
    # otherwise race — see the script's own header comment for why this
    # can't be a Packer provisioner instead.
    initrd_network_fix_b64 = filebase64("${path.root}/scripts/15-fix-initrd-network.sh")
  })

  # Meta data (can also be templated if needed)
  meta_data = file("${path.root}/http/meta-data.yml")
}
