output "namespace" {
  value = kubernetes_namespace.app.metadata[0].name
}

output "frontend_service" {
  description = "Run: kubectl get svc frontend -n <namespace> for external IP."
  value       = kubernetes_service.frontend.metadata[0].name
}

output "contract_cloud" {
  value = local.contract.cloud
}

output "database_host" {
  value = local.contract.database.host
}
