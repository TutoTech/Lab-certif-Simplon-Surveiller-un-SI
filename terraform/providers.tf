terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_tls_insecure

  # SSH est utilisé par bpg/proxmox pour certaines opérations
  # (uploads d'images, opérations sur templates, etc.)
  ssh {
    agent    = true
    username = "root"
  }
}
