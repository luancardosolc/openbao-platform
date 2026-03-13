terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = var.cloud_provider == "aws" ? var.aws_access_key_id : "mock-access-key"
  secret_key                  = var.cloud_provider == "aws" ? var.aws_secret_access_key : "mock-secret-key"
  skip_credentials_validation = var.cloud_provider != "aws"
  skip_metadata_api_check     = var.cloud_provider != "aws"
  skip_requesting_account_id  = var.cloud_provider != "aws"
  skip_region_validation      = var.cloud_provider != "aws"
}

provider "digitalocean" {
  token = var.do_token != "" ? var.do_token : null
}

provider "hcloud" {
  token = var.hetzner_token != "" ? var.hetzner_token : null
}
