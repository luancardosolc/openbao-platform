output "provider" {
  value       = var.cloud_provider
  description = "Selected provider."
}

output "server_public_ip" {
  value       = module.vps.public_ip
  description = "Public IP for the OpenBao server."
}

output "server_private_ip" {
  value       = module.vps.private_ip
  description = "Private IP for the OpenBao server."
}

output "ssh_connection" {
  value = {
    host           = module.vps.public_ip
    user           = var.ssh_user
    private_key    = var.ssh_private_key_path
    inventory_file = local_file.ansible_inventory.filename
  }
  description = "Rendered SSH connection details for automation."
  sensitive   = true
}

output "openbao_url" {
  value       = "https://${var.domain}:8200"
  description = "Expected OpenBao API and UI URL."
}
