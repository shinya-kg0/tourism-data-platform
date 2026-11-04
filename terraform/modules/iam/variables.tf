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
