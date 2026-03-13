terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    digitalocean = {
      source = "digitalocean/digitalocean"
    }
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}
