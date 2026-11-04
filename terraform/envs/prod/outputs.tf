output "bucket_names" {
  description = "GCS バケット名"
  value       = module.storage.bucket_names
}

output "dataset_ids" {
  description = "BigQuery データセット ID"
  value       = module.bigquery.dataset_ids
}

output "service_account_emails" {
  description = "サービスアカウントのメールアドレス"
  value       = module.iam.service_account_emails
}

output "image_repository" {
  description = "コンテナイメージの置き場所"
  value       = module.pipeline.image_repository
}

output "workflow_names" {
  description = "Workflows の名前"
  value       = module.pipeline.workflow_names
}
