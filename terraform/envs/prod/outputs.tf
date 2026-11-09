output "github_workload_identity_provider" {
  description = "GitHub のリポジトリ変数 GCP_WORKLOAD_IDENTITY_PROVIDER に設定する値"
  value       = module.iam.github_workload_identity_provider
}
