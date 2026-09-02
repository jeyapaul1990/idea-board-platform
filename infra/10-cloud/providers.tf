provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "azurerm" {
  features {}
}

provider "aws" {
  region = var.aws_region
}
