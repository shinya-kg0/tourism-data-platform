variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "リソースを置くリージョン"
  type        = string
}

variable "image_tag" {
  description = "ingest・dbt のコンテナイメージのタグ（コミットの SHA）"
  type        = string
}

variable "service_account_emails" {
  description = "サービスアカウント名 → メールアドレス"
  type        = map(string)
}

variable "landing_bucket" {
  description = "Eventarc が監視する landing バケットの名前"
  type        = string
}

variable "workflows_dir" {
  description = "Workflows の定義（ingest.yaml / transform.yaml）を置いたディレクトリ"
  type        = string
}
