variable "provider_name" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_user" {
  type = string
}

variable "server_name" {
  type = string
}

variable "server_image" {
  type = string
}

variable "server_size" {
  type = string
}

variable "aws_ami" {
  type = string
}

variable "aws_instance_type" {
  type = string
}

variable "aws_key_name" {
  type = string
}

variable "do_image" {
  type = string
}

variable "do_size" {
  type = string
}

variable "do_region" {
  type = string
}

variable "hetzner_location" {
  type = string
}

variable "hetzner_ssh_key_ids" {
  type = list(string)
}

variable "private_network_id" {
  type    = string
  default = null
}

variable "private_subnet_id" {
  type    = string
  default = null
}

variable "aws_subnet_id" {
  type    = string
  default = null
}

variable "aws_security_group_id" {
  type    = string
  default = null
}

variable "tags" {
  type = map(string)
}
