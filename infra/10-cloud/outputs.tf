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
  value       = local.contract
}

output "cluster" {
  description = "Kubernetes cluster connection info."
  value       = local.contract.cluster
}

output "database" {
  description = "Database connection info (password resolved via secret_ref at deploy time)."
  value       = local.contract.database
}
