# Azure module stub — full AKS + PostgreSQL Flexible Server implemented in Phase 3.
# Contract output shape matches cloud-gcp exactly so Stage 2 needs no changes.

terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "name_prefix" {
  type = string
}

locals {
  name = "${var.name_prefix}-${var.environment}"
  rg   = var.resource_group_name != "" ? var.resource_group_name : "${local.name}-rg"
}

resource "random_password" "db" {
  length  = 24
  special = false
}

output "contract" {
  description = "Contract placeholder — Phase 3 adds AKS + Flexible Server with real values."
  value = {
    cloud = "azure"
    cluster = {
      name           = "${local.name}-aks"
      endpoint       = "https://PLACEHOLDER"
      ca_certificate = "PLACEHOLDER"
      location       = var.location
      resource_group = local.rg
    }
    database = {
      host       = "PLACEHOLDER"
      port       = 5432
      name       = "ideas"
      username   = "ideas"
      secret_ref = {
        provider = "azure"
        vault    = "${local.name}-kv"
        secret   = "db-password"
      }
    }
    network = {
      location = var.location
    }
  }
}
