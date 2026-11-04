# サービスアカウントと、データへの権限（仕様書 11 章、D-17）
# Cloud Run・Workflows・Eventarc を起動する権限と Workload Identity 連携は、
# それぞれのリソースを作るフェーズで追加する

locals {
  service_accounts = {
    "sa-ingest"    = "取り込み処理（Cloud Run Job「ingest」）"
    "sa-dbt"       = "dbt（Cloud Run Job「dbt」）"
    "sa-workflows" = "Workflows（ingest / transform）"
    "sa-eventarc"  = "Eventarc のトリガー"
    "sa-scheduler" = "Cloud Scheduler"
    "sa-looker"    = "Looker Studio のデータ読み取り（marts のみ）"
  }

  bucket_roles = [
    for bucket in ["landing", "archive", "rejected"] :
    { sa = "sa-ingest", bucket = bucket, role = "roles/storage.objectAdmin" }
  ]

  dataset_roles = [
    { sa = "sa-ingest", dataset = "raw", role = "roles/bigquery.dataEditor" },
    { sa = "sa-ingest", dataset = "ops", role = "roles/bigquery.dataEditor" },
    { sa = "sa-dbt", dataset = "raw", role = "roles/bigquery.dataViewer" },
    { sa = "sa-dbt", dataset = "ops", role = "roles/bigquery.dataViewer" },
    { sa = "sa-dbt", dataset = "staging", role = "roles/bigquery.dataEditor" },
    { sa = "sa-dbt", dataset = "intermediate", role = "roles/bigquery.dataEditor" },
    { sa = "sa-dbt", dataset = "marts", role = "roles/bigquery.dataEditor" },
    { sa = "sa-workflows", dataset = "ops", role = "roles/bigquery.dataEditor" },
    { sa = "sa-looker", dataset = "marts", role = "roles/bigquery.dataViewer" },
  ]

  # クエリを実行するサービスアカウント
  job_users = ["sa-ingest", "sa-dbt", "sa-workflows", "sa-looker"]
}

resource "google_service_account" "this" {
  for_each = local.service_accounts

  project      = var.project_id
  account_id   = each.key
  display_name = each.key
  description  = each.value
}

resource "google_storage_bucket_iam_member" "this" {
  for_each = { for r in local.bucket_roles : "${r.sa}/${r.bucket}/${r.role}" => r }

  bucket = var.bucket_names[each.value.bucket]
  role   = each.value.role
  member = google_service_account.this[each.value.sa].member
}

resource "google_bigquery_dataset_iam_member" "this" {
  for_each = { for r in local.dataset_roles : "${r.sa}/${r.dataset}/${r.role}" => r }

  project    = var.project_id
  dataset_id = var.dataset_ids[each.value.dataset]
  role       = each.value.role
  member     = google_service_account.this[each.value.sa].member
}

resource "google_project_iam_member" "bigquery_job_user" {
  for_each = toset(local.job_users)

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.this[each.value].member
}
