terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = ">= 1.34.0"
    }
  }
  required_version = ">= 0.13"
}
