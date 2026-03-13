variable "project_name" {
  type        = string
  description = "Project name used for tags and resource names."
  default     = "openbao-platform"
}

variable "environment" {
  type        = string
  description = "Deployment environment."
  default     = "prod"
}

variable "cloud_provider" {
  type        = string
  description = "Cloud provider selector: hetzner, aws, or digitalocean."
  default     = "hetzner"

  validation {
    condition     = contains(["hetzner", "aws", "digitalocean"], var.cloud_provider)
    error_message = "cloud_provider must be one of hetzner, aws, or digitalocean."
  }
}

variable "ssh_user" {
  type        = string
  description = "SSH username for Ansible and operations."
  default     = "ubuntu"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key contents."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the SSH private key used by automation."
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to connect over SSH."
  default     = ["0.0.0.0/0"]
}

variable "allowed_api_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to connect to OpenBao."
  default     = ["0.0.0.0/0"]
}

variable "server_name" {
  type        = string
  description = "Server name."
  default     = "openbao"
}

variable "server_image" {
  type        = string
  description = "Image identifier."
  default     = "ubuntu-24.04"
}

variable "server_size" {
  type        = string
  description = "Instance size identifier."
  default     = "cpx22"
}

variable "hetzner_token" {
  type        = string
  description = "Hetzner API token."
  sensitive   = true
  default     = ""
}

variable "hetzner_location" {
  type        = string
  description = "Hetzner location."
  default     = "nbg1"
}

variable "hetzner_network_zone" {
  type        = string
  description = "Hetzner network zone."
  default     = "eu-central"
}

variable "hetzner_ssh_key_ids" {
  type        = list(string)
  description = "Hetzner SSH key IDs already registered in the project."
  default     = []
}

variable "aws_region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "aws_access_key_id" {
  type        = string
  description = "AWS access key."
  sensitive   = true
  default     = ""
}

variable "aws_secret_access_key" {
  type        = string
  description = "AWS secret key."
  sensitive   = true
  default     = ""
}

variable "aws_ami" {
  type        = string
  description = "Ubuntu 24.04 AMI for AWS."
  default     = ""
}

variable "aws_instance_type" {
  type        = string
  description = "AWS instance type."
  default     = "t3.medium"
}

variable "aws_key_name" {
  type        = string
  description = "AWS EC2 key pair name."
  default     = ""
}

variable "do_token" {
  type        = string
  description = "DigitalOcean token."
  sensitive   = true
  default     = ""
}

variable "do_region" {
  type        = string
  description = "DigitalOcean region."
  default     = "fra1"
}

variable "do_image" {
  type        = string
  description = "DigitalOcean image slug."
  default     = "ubuntu-24-04-x64"
}

variable "do_size" {
  type        = string
  description = "DigitalOcean droplet size."
  default     = "s-2vcpu-4gb"
}

variable "network_cidr" {
  type        = string
  description = "Primary private network CIDR."
  default     = "10.42.0.0/24"
}

variable "subnet_cidr" {
  type        = string
  description = "Subnet CIDR."
  default     = "10.42.0.0/24"
}

variable "domain" {
  type        = string
  description = "Primary OpenBao domain."
  default     = "openbao.example.com"
}
