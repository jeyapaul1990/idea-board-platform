provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

data "terraform_remote_state" "cloud" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "10-cloud/${var.cloud}"
  }
}

locals {
  contract  = data.terraform_remote_state.cloud.outputs.contract
  namespace = "idea-board-${var.environment}"
  db_url    = "postgresql://${local.contract.database.username}:${var.database_password}@${local.contract.database.host}:${local.contract.database.port}/${local.contract.database.name}"
}
