module "firewall" {
  source = "../modules/firewall"

  provider_name     = var.cloud_provider
  name_prefix       = local.name_prefix
  aws_vpc_id        = module.network.aws_vpc_id
  do_droplet_ids    = module.vps.do_droplet_id != null ? [module.vps.do_droplet_id] : []
  hcloud_server_ids = module.vps.hcloud_server_id != null ? [module.vps.hcloud_server_id] : []
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  allowed_api_cidrs = var.allowed_api_cidrs
  tags              = local.common_tags
}
