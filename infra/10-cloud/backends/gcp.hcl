# Partial backend configs — keep GCP and Azure state prefixes separate.
# Usage (from infra/10-cloud):
#   terraform init -reconfigure -backend-config=backends/gcp.hcl
#   terraform init -reconfigure -backend-config=backends/azure.hcl

bucket = "idea-board-platform-tfstate"
prefix = "10-cloud/gcp"
