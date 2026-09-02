# Stage 1 — cloud-specific infrastructure only.
# Pick the provider by setting cloud = "gcp" | "azure" | "aws" in a tfvars file.
# Every child module emits the same `contract` output shape for Stage 2.

module "cloud_gcp" {
  source = "./modules/cloud-gcp"
  count  = var.cloud == "gcp" ? 1 : 0

  project_id  = var.gcp_project_id
  region      = var.gcp_region
  zone        = var.gcp_zone
  environment = var.environment
  name_prefix = var.name_prefix
}

module "cloud_azure" {
  source = "./modules/cloud-azure"
  count  = var.cloud == "azure" ? 1 : 0

  location            = var.azure_location
  resource_group_name = var.azure_resource_group_name
  environment         = var.environment
  name_prefix         = var.name_prefix
}

module "cloud_aws" {
  source = "./modules/cloud-aws"
  count  = var.cloud == "aws" ? 1 : 0

  region      = var.aws_region
  environment = var.environment
  name_prefix = var.name_prefix
}

locals {
  # Collapse the selected module's contract — identical shape regardless of cloud.
  contract = one(concat(
    module.cloud_gcp[*].contract,
    module.cloud_azure[*].contract,
    module.cloud_aws[*].contract,
  ))
}
