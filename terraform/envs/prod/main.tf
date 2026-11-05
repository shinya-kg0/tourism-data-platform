# 本番環境。modules/ の各モジュールをここから呼び出す（仕様書 10 章）

# 有効にする API。フェーズが進んだら追加する
locals {
  services = [
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "eventarc.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
    "workflowexecutions.googleapis.com",
    "workflows.googleapis.com",
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.services)

  service            = each.value
  disable_on_destroy = false
}

module "storage" {
  source = "../../modules/storage"

  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.this]
}

module "bigquery" {
  source = "../../modules/bigquery"

  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.this]
}

module "iam" {
  source = "../../modules/iam"

  project_id                 = var.project_id
  bucket_names               = module.storage.bucket_names
  dataset_ids                = module.bigquery.dataset_ids
  github_repository          = var.github_repository
  github_oidc_subject_prefix = var.github_oidc_subject_prefix
  tfstate_bucket             = "${var.project_id}-tfstate"

  depends_on = [google_project_service.this]
}

module "pipeline" {
  source = "../../modules/pipeline"

  project_id             = var.project_id
  region                 = var.region
  image_tag              = var.image_tag
  service_account_emails = module.iam.service_account_emails
  landing_bucket         = module.storage.bucket_names["landing"]
  workflows_dir          = "${path.root}/../../../workflows"

  # Eventarc のトリガーより先に、GCS のサービスエージェントの権限を付けておく
  depends_on = [google_project_service.this, module.iam]
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_id     = var.project_id
  alert_email    = var.alert_email
  job_names      = module.pipeline.job_names
  workflow_names = module.pipeline.workflow_names

  depends_on = [google_project_service.this]
}
