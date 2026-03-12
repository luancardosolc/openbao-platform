locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "opentofu"
  }
}

module "network" {
  source = "../modules/network"

  provider_name        = var.cloud_provider
  name_prefix          = local.name_prefix
  network_cidr         = var.network_cidr
  subnet_cidr          = var.subnet_cidr
  hetzner_network_zone = var.hetzner_network_zone
  aws_region           = var.aws_region
  do_region            = var.do_region
  tags                 = local.common_tags
}

resource "local_file" "ansible_inventory" {
  filename = "${path.root}/inventory.ini"
  content = templatefile("${path.module}/inventory.tftpl", {
    host     = module.vps.public_ip
    user     = var.ssh_user
    key_path = var.ssh_private_key_path
  })
}
