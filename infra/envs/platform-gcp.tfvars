cloud        = "gcp"
environment  = "demo"
state_bucket = "idea-board-platform-tfstate"

backend_image  = "ghcr.io/jeyapaul1990/idea-board-backend:latest"
frontend_image = "ghcr.io/jeyapaul1990/idea-board-frontend:latest"

backend_replicas  = 1
frontend_replicas = 1

# database_password is NOT in tfvars — pass at apply time:
#   -var="database_password=$(./scripts/resolve-db-password.sh gcp ...)"
