output "service_account_emails" {
  description = "サービスアカウント名 → メールアドレス"
  value       = { for key, sa in google_service_account.this : key => sa.email }
}

output "github_workload_identity_provider" {
  description = "GitHub Actions の認証（google-github-actions/auth）に渡すプロバイダの名前"
  value       = google_iam_workload_identity_pool_provider.github.name
}
