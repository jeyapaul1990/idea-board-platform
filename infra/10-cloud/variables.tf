variable "cloud" {
  description = "Target cloud provider. Same root module, different reusable child module."
  type        = string

  validation {
    condition     = contains(["gcp", "azure", "aws"], var.cloud)
    error_message = "cloud must be one of: gcp, azure, aws."
  }
}

variable "environment" {
  description = "Environment name (staging, production, demo)."
  type        = string
  default     = "demo"
}

variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
  default     = "idea-board"
}

# --- GCP (used when cloud = gcp) ---

variable "gcp_project_id" {
  description = "GCP project ID."
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region."
  type        = string
  default     = "asia-south1"
}

variable "gcp_zone" {
  description = "GCP zone for zonal GKE cluster."
  type        = string
  default     = "asia-south1-a"
}

# --- Azure (used when cloud = azure) ---

variable "azure_location" {
  description = "Azure region."
  type        = string
  default     = "centralindia"
}

variable "azure_resource_group_name" {
  description = "Azure resource group name."
  type        = string
  default     = ""
}

# --- AWS (used when cloud = aws) ---

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}
