resource "hcloud_server" "this" {
  count       = var.provider_name == "hetzner" ? 1 : 0
  name        = "${var.name_prefix}-${var.server_name}"
  image       = var.server_image
  server_type = var.server_size
  location    = var.hetzner_location
  ssh_keys    = var.hetzner_ssh_key_ids
  user_data   = local.cloud_init

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }
}

resource "hcloud_server_network" "this" {
  count      = var.provider_name == "hetzner" ? 1 : 0
  server_id  = hcloud_server.this[0].id
  network_id = var.private_network_id
}

resource "aws_instance" "this" {
  count                       = var.provider_name == "aws" ? 1 : 0
  ami                         = var.aws_ami
  instance_type               = var.aws_instance_type
  subnet_id                   = var.aws_subnet_id
  key_name                    = var.aws_key_name != "" ? var.aws_key_name : null
  vpc_security_group_ids      = var.aws_security_group_id != null ? [var.aws_security_group_id] : []
  associate_public_ip_address = true
  user_data                   = local.cloud_init
  tags                        = merge(var.tags, { Name = "${var.name_prefix}-${var.server_name}" })
}

resource "digitalocean_ssh_key" "this" {
  count      = var.provider_name == "digitalocean" ? 1 : 0
  name       = "${var.name_prefix}-${var.server_name}"
  public_key = var.ssh_public_key
}

resource "digitalocean_droplet" "this" {
  count     = var.provider_name == "digitalocean" ? 1 : 0
  name      = "${var.name_prefix}-${var.server_name}"
  region    = var.do_region
  image     = var.do_image
  size      = var.do_size
  ssh_keys  = [digitalocean_ssh_key.this[0].id]
  user_data = local.cloud_init
  vpc_uuid  = var.private_network_id
  tags      = values(var.tags)
}

locals {
  cloud_init = templatefile("${path.module}/user-data.tftpl", {
    ssh_user = var.ssh_user
  })
}
