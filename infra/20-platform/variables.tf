variable "cloud" {
  description = "Must match Stage 1 cloud for remote state lookup."
  type        = string
}

variable "environment" {
  type    = string
  default = "demo"
}

variable "state_bucket" {
  description = "GCS bucket holding Terraform remote state."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig prepared by scripts/kubeconfig.sh (the one cloud-aware seam)."
  type        = string
  default     = "~/.kube/config"
}

variable "database_password" {
  description = "Resolved from secret_ref by CI/local script — never stored in Stage 1 outputs."
  type        = string
  sensitive   = true
}

variable "backend_image" {
  type    = string
  default = "ghcr.io/OWNER/idea-board-backend:latest"
}

variable "frontend_image" {
  type    = string
  default = "ghcr.io/OWNER/idea-board-frontend:latest"
}

variable "backend_replicas" {
  type    = number
  default = 1
}

variable "frontend_replicas" {
  type    = number
  default = 1
}
