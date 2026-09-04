cloud        = "azure"
environment  = "demo"
state_bucket = "idea-board-platform-tfstate"

backend_image  = "ghcr.io/jeyapaul1990/idea-board-backend:latest"
frontend_image = "ghcr.io/jeyapaul1990/idea-board-frontend:latest"

backend_replicas  = 1
frontend_replicas = 1

# database_password is NOT in tfvars — pass at apply time (trim newlines!):
#   $DB_PASS = (az keyvault secret show --vault-name <vault> --name db-password --query value -o tsv).Trim()
#   terraform apply -var-file=..\envs\platform-azure.tfvars -var="database_password=$DB_PASS"
