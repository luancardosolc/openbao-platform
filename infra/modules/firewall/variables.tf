variable "provider_name" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "aws_vpc_id" {
  type    = string
  default = null
}

variable "do_droplet_ids" {
  type    = list(string)
  default = []
}

variable "hcloud_server_ids" {
  type    = list(string)
  default = []
}

variable "allowed_ssh_cidrs" {
  type = list(string)
}

variable "allowed_api_cidrs" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}
