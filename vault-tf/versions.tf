terraform {
  required_version = ">= 1.16"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
  }
}
