# AWS module — same contract shape as cloud-gcp (plan-clean in CI, no apply).
# Reusable: EKS + RDS; Stage 2 unchanged.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "region" {
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
}

resource "random_password" "db" {
  length  = 24
  special = false
}

# --- Stub contract for validate/plan; full EKS + RDS in Phase 3 ---

output "contract" {
  description = "Contract placeholder — expand with EKS + RDS resources."
  value = {
    cloud = "aws"
    cluster = {
      name           = "${local.name}-eks"
      endpoint       = "https://PLACEHOLDER"
      ca_certificate = "PLACEHOLDER"
      region         = var.region
    }
    database = {
      host       = "PLACEHOLDER"
      port       = 5432
      name       = "ideas"
      username   = "ideas"
      secret_ref = {
        provider = "aws"
        arn      = "arn:aws:secretsmanager:${var.region}:ACCOUNT:secret:${local.name}/db-password"
      }
    }
    network = {
      region = var.region
    }
  }
}
