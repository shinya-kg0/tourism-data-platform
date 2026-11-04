output "service_account_emails" {
  description = "サービスアカウント名 → メールアドレス"
  value       = { for key, sa in google_service_account.this : key => sa.email }
}
