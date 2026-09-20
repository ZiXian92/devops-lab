terraform {
  required_version = ">= 1.16"

  required_providers {
    nexus = {
      source  = "datadrivers/nexus"
      version = ">= 3.0"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
  }
}
