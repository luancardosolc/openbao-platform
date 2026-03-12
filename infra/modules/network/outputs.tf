output "network_id" {
  value = var.provider_name == "hetzner" ? hcloud_network.this[0].id : (
    var.provider_name == "digitalocean" ? digitalocean_vpc.this[0].id : null
  )
}

output "subnet_id" {
  value = var.provider_name == "hetzner" ? hcloud_network_subnet.this[0].id : null
}

output "aws_vpc_id" {
  value = var.provider_name == "aws" ? aws_vpc.this[0].id : null
}

output "aws_subnet_id" {
  value = var.provider_name == "aws" ? aws_subnet.this[0].id : null
}
