# Artifact Registry、Cloud Run Jobs、Workflows、Eventarc、Cloud Scheduler（仕様書 2・5・7.5・9 章）
#
# landing へのアップロード → Eventarc → Workflows「ingest」→ Cloud Run Job「ingest」
# Cloud Scheduler（毎日 04:00 JST）→ Workflows「transform」→ Cloud Run Job「dbt」

locals {
  image_base = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}

# ingest・dbt のコンテナイメージの置き場所。タグはコミットの SHA（仕様書 12 章）
resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.region
  repository_id = "tourism"
  description   = "Cloud Run Jobs（ingest / dbt）のコンテナイメージ"
  format        = "DOCKER"

  # 保存の費用を抑えるため、イメージごとに新しい 10 個だけを残す
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "${30 * 24 * 60 * 60}s"
    }
  }
}

# --- Cloud Run Jobs -----------------------------------------------------------
# やり直しは Workflows が決めるので、ジョブ自身はやり直さない（max_retries = 0、D-04）

resource "google_cloud_run_v2_job" "ingest" {
  project             = var.project_id
  location            = var.region
  name                = "ingest"
  deletion_protection = false

  template {
    task_count = 1
    template {
      service_account = var.service_account_emails["sa-ingest"]
      timeout         = "900s"
      max_retries     = 0

      containers {
        image = "${local.image_base}/ingest:${var.image_tag}"
        # 引数（オブジェクト名・世代番号）は Workflows が実行のたびに上書きする
        resources {
          limits = { cpu = "1", memory = "2Gi" }
        }
        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
      }
    }
  }
}

resource "google_cloud_run_v2_job" "dbt" {
  project             = var.project_id
  location            = var.region
  name                = "dbt"
  deletion_protection = false

  template {
    task_count = 1
    template {
      service_account = var.service_account_emails["sa-dbt"]
      timeout         = "1800s"
      max_retries     = 0

      containers {
        # 既定のコマンドは dbt build --target prod（dbt/Dockerfile）
        image = "${local.image_base}/dbt:${var.image_tag}"
        resources {
          limits = { cpu = "1", memory = "1Gi" }
        }
        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
      }
    }
  }
}

# Workflows が起動できるのは、この 2 つのジョブだけ（D-17）。
# 引数を上書きするのは ingest だけなので、dbt には上書きできない権限を付ける
resource "google_cloud_run_v2_job_iam_member" "workflows_ingest" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.ingest.name
  role     = "roles/run.jobsExecutorWithOverrides"
  member   = "serviceAccount:${var.service_account_emails["sa-workflows"]}"
}

resource "google_cloud_run_v2_job_iam_member" "workflows_dbt" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.dbt.name
  role     = "roles/run.jobsExecutor"
  member   = "serviceAccount:${var.service_account_emails["sa-workflows"]}"
}

# --- Workflows ----------------------------------------------------------------

resource "google_workflows_workflow" "ingest" {
  project             = var.project_id
  region              = var.region
  name                = "ingest"
  description         = "landing へのアップロードをきっかけに Cloud Run Job「ingest」を実行する"
  service_account     = var.service_account_emails["sa-workflows"]
  source_contents     = file("${var.workflows_dir}/ingest.yaml")
  call_log_level      = "LOG_ERRORS_ONLY"
  deletion_protection = false

  user_env_vars = {
    INGEST_JOB = google_cloud_run_v2_job.ingest.name
  }
}

resource "google_workflows_workflow" "transform" {
  project             = var.project_id
  region              = var.region
  name                = "transform"
  description         = "新しい取り込みがあれば Cloud Run Job「dbt」を実行し、ops.dbt_runs に記録する"
  service_account     = var.service_account_emails["sa-workflows"]
  source_contents     = file("${var.workflows_dir}/transform.yaml")
  call_log_level      = "LOG_ERRORS_ONLY"
  deletion_protection = false

  user_env_vars = {
    DBT_JOB = google_cloud_run_v2_job.dbt.name
  }
}

# --- きっかけ -----------------------------------------------------------------

# landing だけを監視する。archive / rejected への移動は別のバケットなので、イベントにならない（D-01）
resource "google_eventarc_trigger" "ingest" {
  project         = var.project_id
  location        = var.region
  name            = "ingest-on-upload"
  service_account = var.service_account_emails["sa-eventarc"]

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = var.landing_bucket
  }

  destination {
    workflow = google_workflows_workflow.ingest.id
  }
}

# 変換は 1 日 1 回にまとめる（D-12）
resource "google_cloud_scheduler_job" "transform" {
  project     = var.project_id
  region      = var.region
  name        = "transform-daily"
  description = "毎日 04:00 JST に Workflows「transform」を起動する"
  schedule    = "0 4 * * *"
  time_zone   = "Asia/Tokyo"

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.transform.id}/executions"
    body        = base64encode(jsonencode({ argument = jsonencode({ trigger = "schedule" }) }))
    headers     = { "Content-Type" = "application/json" }

    oauth_token {
      service_account_email = var.service_account_emails["sa-scheduler"]
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}
