variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "リソースを置くリージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "alert_email" {
  description = "アラートの通知先メールアドレス"
  type        = string
}

variable "github_repository" {
  description = "Workload Identity 連携を許可する GitHub リポジトリ（owner/repo）"
  type        = string
}
