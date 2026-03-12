output "aws_security_group_id" {
  value = var.provider_name == "aws" ? aws_security_group.this[0].id : null
}
