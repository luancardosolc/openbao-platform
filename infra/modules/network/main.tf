resource "hcloud_network" "this" {
  count    = var.provider_name == "hetzner" ? 1 : 0
  name     = "${var.name_prefix}-net"
  ip_range = var.network_cidr
}

resource "hcloud_network_subnet" "this" {
  count        = var.provider_name == "hetzner" ? 1 : 0
  network_id   = hcloud_network.this[0].id
  type         = "cloud"
  network_zone = var.hetzner_network_zone
  ip_range     = var.subnet_cidr
}

resource "aws_vpc" "this" {
  count                = var.provider_name == "aws" ? 1 : 0
  cidr_block           = var.network_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_subnet" "this" {
  count                   = var.provider_name == "aws" ? 1 : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.name_prefix}-subnet" })
}

resource "aws_internet_gateway" "this" {
  count  = var.provider_name == "aws" ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_route_table" "public" {
  count  = var.provider_name == "aws" ? 1 : 0
  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt" })
}

resource "aws_route_table_association" "public" {
  count          = var.provider_name == "aws" ? 1 : 0
  subnet_id      = aws_subnet.this[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "digitalocean_vpc" "this" {
  count    = var.provider_name == "digitalocean" ? 1 : 0
  name     = "${var.name_prefix}-vpc"
  region   = var.do_region
  ip_range = var.network_cidr
}
