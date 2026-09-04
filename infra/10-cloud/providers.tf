provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "azurerm" {
  features {}
  # Set before terraform: $env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
}

provider "aws" {
  region = var.aws_region
}
