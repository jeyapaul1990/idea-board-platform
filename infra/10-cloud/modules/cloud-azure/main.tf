# Azure — AKS (Free control plane) + PostgreSQL Flexible Server (private VNet).
# Contract output shape matches cloud-gcp so Stage 2 needs no cloud-specific logic.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
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

data "azurerm_client_config" "current" {}

locals {
  name = "${var.name_prefix}-${var.environment}"
  rg   = var.resource_group_name != "" ? var.resource_group_name : "${local.name}-rg"
}

resource "random_password" "db" {
  length  = 24
  special = false
}

# Key Vault names are globally unique (3–24 chars).
resource "random_string" "kv" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = local.rg
  location = var.location

  tags = {
    environment = var.environment
    managed-by  = "terraform"
    project     = "idea-board"
  }
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.50.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "${local.name}-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.50.1.0/24"]
}

resource "azurerm_subnet" "postgres" {
  name                 = "${local.name}-pg"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.50.2.0/24"]

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.name}-pg-dns"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.name}-aks-id"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.name}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix = "${var.name_prefix}${var.environment}"
  sku_tier   = "Free"

  default_node_pool {
    name                        = "system"
    node_count                  = 1
    # B2s is blocked in centralindia for many new subscriptions; B2s_v2 is allowed.
    vm_size                     = "Standard_B2s_v2"
    vnet_subnet_id              = azurerm_subnet.aks.id
    os_disk_size_gb             = 64
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.41.0.0/16"
    dns_service_ip      = "10.41.0.10"
    load_balancer_sku   = "standard"
  }

  tags = {
    environment = var.environment
  }

  depends_on = [azurerm_role_assignment.aks_network]
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "${local.name}-pg"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = "16"
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  administrator_login           = "ideas"
  administrator_password        = random_password.db.result
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  zone                          = "1"

  tags = {
    environment = var.environment
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "ideas" {
  name      = "ideas"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_key_vault" "db" {
  name                       = "ib${var.environment}${random_string.kv.result}kv"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  rbac_authorization_enabled = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge",
    ]
  }
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = random_password.db.result
  key_vault_id = azurerm_key_vault.db.id
}

output "contract" {
  description = "Standard contract for Stage 2 — same shape as cloud-gcp and cloud-aws."
  sensitive   = true
  value = {
    cloud = "azure"
    cluster = {
      name           = azurerm_kubernetes_cluster.main.name
      endpoint       = azurerm_kubernetes_cluster.main.kube_config[0].host
      ca_certificate = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
      location       = azurerm_resource_group.main.location
      resource_group = azurerm_resource_group.main.name
    }
    database = {
      host = azurerm_postgresql_flexible_server.main.fqdn
      port = 5432
      name = azurerm_postgresql_flexible_server_database.ideas.name
      username = azurerm_postgresql_flexible_server.main.administrator_login
      secret_ref = {
        provider = "azure"
        vault    = azurerm_key_vault.db.name
        secret   = azurerm_key_vault_secret.db_password.name
      }
    }
    network = {
      location = azurerm_resource_group.main.location
      vnet     = azurerm_virtual_network.main.name
    }
  }
}
