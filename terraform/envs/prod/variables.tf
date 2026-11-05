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
  # 公開リポジトリの PR に plan の結果をコメントするため、表示しない
  sensitive = true
}

variable "github_repository" {
  description = "Workload Identity 連携を許可する GitHub リポジトリ（owner/repo）"
  type        = string
}

variable "image_tag" {
  description = "ingest・dbt のコンテナイメージのタグ（コミットの SHA。scripts/build_push.sh で送ったもの）"
  type        = string
}

variable "github_oidc_subject_prefix" {
  description = "GitHub Actions のトークンの sub の接頭辞（例：repo:{owner}@{owner の ID}/{repo}@{repo の ID}）。gh api repos/{owner}/{repo}/actions/oidc/customization/sub の sub_claim_prefix"
  type        = string
}
