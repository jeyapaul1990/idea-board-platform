cloud                     = "azure"
environment               = "demo"
name_prefix               = "idea-board"
azure_location            = "centralindia"
azure_resource_group_name = ""

# Satisfy google provider init when cloud=azure (unused).
gcp_project_id = "idea-board-platform"

# Also set in the shell before terraform (azurerm 4.x):
#   $env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
