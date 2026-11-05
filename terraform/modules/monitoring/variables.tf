variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "alert_email" {
  description = "アラートの通知先メールアドレス"
  type        = string
  sensitive   = true
}

variable "job_names" {
  description = "Cloud Run Jobs の名前（ingest / dbt）"
  type        = map(string)
}

variable "workflow_names" {
  description = "Workflows の名前（ingest / transform）"
  type        = map(string)
}
