# 本番環境。modules/ の各モジュールをここから呼び出す（仕様書 10 章）

# 有効にする API。フェーズが進んだら追加する
locals {
  services = [
    "bigquery.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
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

  project_id   = var.project_id
  bucket_names = module.storage.bucket_names
  dataset_ids  = module.bigquery.dataset_ids
}
