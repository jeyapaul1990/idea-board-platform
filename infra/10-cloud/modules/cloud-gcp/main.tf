terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
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

resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${local.name}-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${local.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "primary" {
  project       = var.project_id
  name          = "${local.name}-subnet"
  ip_cidr_range = "10.10.0.0/20"
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

resource "google_compute_global_address" "sql_private" {
  project       = var.project_id
  name          = "${local.name}-sql-peering"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.sql_private.name]
}

resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = "${local.name}-gke"
  location = var.zone

  remove_default_node_pool = true
  initial_node_count     = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.primary.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_service_networking_connection.private_vpc]
}

resource "google_container_node_pool" "primary" {
  project  = var.project_id
  name     = "${local.name}-pool"
  location = var.zone
  cluster  = google_container_cluster.primary.name

  initial_node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "e2-small"
    disk_size_gb = 30

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      environment = var.environment
    }
  }
}

resource "google_sql_database_instance" "postgres" {
  project          = var.project_id
  name             = "${local.name}-sql"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled = true
    }
  }

  depends_on = [google_service_networking_connection.private_vpc]
}

resource "google_sql_database" "ideas" {
  project  = var.project_id
  name     = "ideas"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "ideas" {
  project  = var.project_id
  name     = "ideas"
  instance = google_sql_database_instance.postgres.name
  password = random_password.db.result
}

output "contract" {
  description = "Standard contract for Stage 2 — same shape as cloud-azure and cloud-aws."
  value = {
    cloud = "gcp"
    cluster = {
      name           = google_container_cluster.primary.name
      endpoint       = "https://${google_container_cluster.primary.endpoint}"
      ca_certificate = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
      location       = google_container_cluster.primary.location
      project_id     = var.project_id
    }
    database = {
      host       = google_sql_database_instance.postgres.private_ip_address
      port       = 5432
      name       = google_sql_database.ideas.name
      username   = google_sql_user.ideas.name
      secret_ref = {
        provider = "gcp"
        project  = var.project_id
        id       = google_secret_manager_secret.db_password.secret_id
      }
    }
    network = {
      vpc_name = google_compute_network.vpc.name
      region   = var.region
    }
  }
  sensitive = false
}
