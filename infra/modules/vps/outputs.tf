output "public_ip" {
  value = var.provider_name == "hetzner" ? hcloud_server.this[0].ipv4_address : (
    var.provider_name == "aws" ? aws_instance.this[0].public_ip : digitalocean_droplet.this[0].ipv4_address
  )
}

output "private_ip" {
  value = var.provider_name == "hetzner" ? one([
    for network in hcloud_server.this[0].network : network.ip
  ]) : (
    var.provider_name == "aws" ? aws_instance.this[0].private_ip : digitalocean_droplet.this[0].ipv4_address_private
  )
}

output "hcloud_server_id" {
  value = var.provider_name == "hetzner" ? hcloud_server.this[0].id : null
}

output "do_droplet_id" {
  value = var.provider_name == "digitalocean" ? digitalocean_droplet.this[0].id : null
}
