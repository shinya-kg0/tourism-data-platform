variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "bucket_names" {
  description = "用途（landing / archive / rejected）→ バケット名"
  type        = map(string)
}

variable "dataset_ids" {
  description = "データセット名 → データセット ID"
  type        = map(string)
}

variable "github_repository" {
  description = "Workload Identity 連携を許可する GitHub リポジトリ（owner/repo）"
  type        = string
}

variable "tfstate_bucket" {
  description = "Terraform の状態ファイルを置くバケット（Terraform の管理外。仕様書 10.2）"
  type        = string
}
