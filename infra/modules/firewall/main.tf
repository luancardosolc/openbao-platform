resource "hcloud_firewall" "this" {
  count = var.provider_name == "hetzner" ? 1 : 0
  name  = "${var.name_prefix}-fw"

  dynamic "rule" {
    for_each = concat(
      [for cidr in var.allowed_ssh_cidrs : {
        direction = "in"
        protocol  = "tcp"
        port      = "22"
        source    = cidr
      }],
      [for cidr in var.allowed_api_cidrs : {
        direction = "in"
        protocol  = "tcp"
        port      = "8200"
        source    = cidr
      }]
    )

    content {
      direction  = rule.value.direction
      protocol   = rule.value.protocol
      port       = rule.value.port
      source_ips = [rule.value.source]
    }
  }
}

resource "hcloud_firewall_attachment" "this" {
  count       = var.provider_name == "hetzner" ? 1 : 0
  firewall_id = hcloud_firewall.this[0].id
  server_ids  = compact(var.hcloud_server_ids)
}

resource "aws_security_group" "this" {
  count       = var.provider_name == "aws" ? 1 : 0
  name        = "${var.name_prefix}-sg"
  description = "OpenBao host access policy"
  vpc_id      = var.aws_vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = var.provider_name == "aws" ? toset(var.allowed_ssh_cidrs) : []
  security_group_id = aws_security_group.this[0].id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "openbao" {
  for_each          = var.provider_name == "aws" ? toset(var.allowed_api_cidrs) : []
  security_group_id = aws_security_group.this[0].id
  cidr_ipv4         = each.value
  from_port         = 8200
  to_port           = 8200
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  count             = var.provider_name == "aws" ? 1 : 0
  security_group_id = aws_security_group.this[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "digitalocean_firewall" "this" {
  count       = var.provider_name == "digitalocean" ? 1 : 0
  name        = "${var.name_prefix}-fw"
  droplet_ids = var.do_droplet_ids

  dynamic "inbound_rule" {
    for_each = var.allowed_ssh_cidrs
    content {
      protocol         = "tcp"
      port_range       = "22"
      source_addresses = [inbound_rule.value]
    }
  }

  dynamic "inbound_rule" {
    for_each = var.allowed_api_cidrs
    content {
      protocol         = "tcp"
      port_range       = "8200"
      source_addresses = [inbound_rule.value]
    }
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
