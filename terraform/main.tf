provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
}


module "base-vm" {
  source       = "./modules/base-vm"
  vm_name      = var.vm_name
  proxmox_node = var.proxmox_node
  proxmox_pool = var.proxmox_pool

  template_name = var.template_name

  cpu_cores = var.cpu_cores
  memory_mb = var.memory_mb

  disk0_size = var.disk0_size

  # Cloud-init
  vm_user        = var.vm_user
  ssh_public_key = file(pathexpand(var.ssh_public_key))

}
