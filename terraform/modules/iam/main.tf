# サービスアカウントと、データ・処理への権限（仕様書 11 章、D-17）
# 個々の Cloud Run Job を実行する権限はジョブ単位で付けるため、modules/pipeline に置く。
# GitHub Actions の Workload Identity 連携は github.tf に置く

locals {
  service_accounts = {
    "sa-ingest"          = "取り込み処理（Cloud Run Job「ingest」）"
    "sa-dbt"             = "dbt（Cloud Run Job「dbt」）"
    "sa-workflows"       = "Workflows（ingest / transform）"
    "sa-eventarc"        = "Eventarc のトリガー"
    "sa-scheduler"       = "Cloud Scheduler"
    "sa-looker"          = "Looker Studio のデータ読み取り（marts のみ）"
    "sa-github-plan"     = "GitHub Actions：PR の terraform plan（読み取りのみ）"
    "sa-github-dbt-ci"   = "GitHub Actions：PR の dbt build（ci_pr_{番号} に書き出す）"
    "sa-github-builder"  = "GitHub Actions：main へのマージでコンテナイメージを送る"
    "sa-github-deployer" = "GitHub Actions：main へのマージで terraform apply（環境 production のみ）"
    "sa-github-docs"     = "GitHub Actions：main へのマージで dbt docs を作る（メタデータのみ）"
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
    { sa = "sa-github-dbt-ci", dataset = "raw", role = "roles/bigquery.dataViewer" },
  ]

  # dbt docs のカタログ（列の型・行数）は、データセットごとの __TABLES__ を読むため、データの閲覧者が要る（書き込みはできない）
  docs_dataset_roles = [
    for dataset in ["raw", "ops", "staging", "intermediate", "marts"] :
    { sa = "sa-github-docs", dataset = dataset, role = "roles/bigquery.dataViewer" }
  ]

  # クエリを実行するサービスアカウント
  job_users = ["sa-ingest", "sa-dbt", "sa-workflows", "sa-looker", "sa-github-docs"]

  # 処理の起動に関わる、プロジェクト単位の権限
  project_roles = [
    { sa = "sa-workflows", role = "roles/logging.logWriter" },
    { sa = "sa-workflows", role = "projects/${var.project_id}/roles/runJobWatcher" },
    { sa = "sa-eventarc", role = "roles/eventarc.eventReceiver" },
    { sa = "sa-eventarc", role = "roles/workflows.invoker" },
    { sa = "sa-scheduler", role = "roles/workflows.invoker" },
    # plan はすべてのリソースとその IAM を読むが、書き込みはしない
    { sa = "sa-github-plan", role = "roles/viewer" },
    { sa = "sa-github-plan", role = "roles/iam.securityReviewer" },
    # ジョブの実行と ci_pr_{番号} の作成。作ったデータセットの所有者になるので、PR を閉じたときに消せる
    { sa = "sa-github-dbt-ci", role = "roles/bigquery.user" },
  ]

  # terraform apply で、このリポジトリが管理するリソースを作り変える（仕様書 10.1）。
  # IAM を管理するため projectIamAdmin は外せない。使えるのは環境 production の承認を経たジョブだけにする（github.tf）
  deployer_roles = [
    "roles/artifactregistry.admin",
    "roles/bigquery.admin",
    "roles/cloudscheduler.admin",
    "roles/eventarc.admin",
    "roles/iam.roleAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/logging.configWriter",
    "roles/monitoring.editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/run.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/storage.admin",
    "roles/workflows.admin",
  ]
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
  for_each = { for r in concat(local.dataset_roles, local.docs_dataset_roles) : "${r.sa}/${r.dataset}/${r.role}" => r }

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

resource "google_project_iam_member" "deployer" {
  for_each = toset(local.deployer_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.this["sa-github-deployer"].member
}

resource "google_project_iam_member" "this" {
  for_each = { for r in local.project_roles : "${r.sa}/${r.role}" => r }

  project = var.project_id
  role    = each.value.role
  member  = google_service_account.this[each.value.sa].member

  # for_each のキーを plan の時点で決めるため、カスタムロールは名前で指定し、作る順番だけをここで決める
  depends_on = [google_project_iam_custom_role.run_job_watcher]
}

# Workflows がジョブの終了を待つには、実行の状態を読む権限が要る。
# 定義済みのロール（roles/run.viewer）はサービスの設定まで読めるため、必要な 2 つだけにする
resource "google_project_iam_custom_role" "run_job_watcher" {
  project     = var.project_id
  role_id     = "runJobWatcher"
  title       = "Cloud Run Job の終了を待つ"
  description = "Workflows のコネクタが、起動した Cloud Run Job の実行の状態を確かめるための権限"
  permissions = ["run.operations.get", "run.executions.get"]
}

# GCS のサービスエージェントが Eventarc にイベントを送るための権限（付け忘れるとイベントが届かない）
data "google_storage_project_service_account" "this" {
  project = var.project_id
}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = data.google_storage_project_service_account.this.member
}
