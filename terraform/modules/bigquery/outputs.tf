output "dataset_ids" {
  description = "データセット名 → データセット ID"
  value       = { for key, dataset in google_bigquery_dataset.this : key => dataset.dataset_id }
}
