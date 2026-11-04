output "bucket_names" {
  description = "用途（landing / archive / rejected）→ バケット名"
  value       = { for key, bucket in google_storage_bucket.this : key => bucket.name }
}
