output "image_repository" {
  description = "コンテナイメージの置き場所（{image_repository}/ingest:{tag} など）"
  value       = local.image_base
}

output "job_names" {
  description = "Cloud Run Jobs の名前"
  value       = { ingest = google_cloud_run_v2_job.ingest.name, dbt = google_cloud_run_v2_job.dbt.name }
}

output "workflow_names" {
  description = "Workflows の名前"
  value       = { ingest = google_workflows_workflow.ingest.name, transform = google_workflows_workflow.transform.name }
}
