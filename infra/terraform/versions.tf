terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  cloud {
    organization = "davisschenk-homelab"

    workspaces {
      project = "nixos-homelab-production"
      name    = "nixos-homelab-production"
    }
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.18"
    }
  }
}
