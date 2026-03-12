module "vps" {
  source = "../modules/vps"

  provider_name         = var.cloud_provider
  name_prefix           = local.name_prefix
  ssh_public_key        = var.ssh_public_key
  ssh_user              = var.ssh_user
  server_name           = var.server_name
  server_image          = var.server_image
  server_size           = var.server_size
  aws_ami               = var.aws_ami
  aws_instance_type     = var.aws_instance_type
  aws_key_name          = var.aws_key_name
  do_image              = var.do_image
  do_size               = var.do_size
  do_region             = var.do_region
  hetzner_location      = var.hetzner_location
  hetzner_ssh_key_ids   = var.hetzner_ssh_key_ids
  private_network_id    = module.network.network_id
  private_subnet_id     = module.network.subnet_id
  aws_subnet_id         = module.network.aws_subnet_id
  aws_security_group_id = module.firewall.aws_security_group_id
  tags                  = local.common_tags
}
