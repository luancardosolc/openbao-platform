variable "provider_name" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "network_cidr" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "hetzner_network_zone" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "do_region" {
  type = string
}

variable "tags" {
  type = map(string)
}
