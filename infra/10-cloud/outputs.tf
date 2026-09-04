output "cloud" {
  description = "Active cloud provider for this stack."
  value       = var.cloud
}

output "contract" {
  description = <<-EOT
    Shared interface consumed by infra/20-platform (Stage 2).
    cluster: name, endpoint, ca_certificate
    database: host, port, name, username, secret_ref (NOT the password value)
  EOT
  # Azure kube_config fields are provider-sensitive; GCP path stays safe either way.
  value     = local.contract
  sensitive = true
}

output "cluster" {
  description = "Kubernetes cluster connection info."
  value       = local.contract.cluster
  sensitive   = true
}

output "database" {
  description = "Database connection info (password resolved via secret_ref at deploy time)."
  value       = local.contract.database
  sensitive   = true
}
