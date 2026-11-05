# 監視と通知（仕様書 13 章）。予算アラートは課金アカウント側で手作業（10.2）

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "運用の通知（メール）"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

# ingest は結果を構造化ログで出す（status：succeeded / skipped / rejected / failed）
resource "google_logging_metric" "ingest_problem" {
  project     = var.project_id
  name        = "ingest_problem"
  description = "ingest の rejected（データの誤り）と failed（一時的なエラー）の件数"
  filter      = <<-EOT
    resource.type="cloud_run_job"
    resource.labels.job_name="${var.job_names["ingest"]}"
    jsonPayload.status=("rejected" OR "failed")
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key        = "status"
      value_type = "STRING"
    }
  }
  label_extractors = {
    status = "EXTRACT(jsonPayload.status)"
  }
}

resource "google_monitoring_alert_policy" "ingest_problem" {
  project      = var.project_id
  display_name = "ingest：rejected / failed"
  combiner     = "OR"

  conditions {
    display_name = "rejected / failed が 1 件以上"
    condition_threshold {
      filter          = "resource.type = \"cloud_run_job\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.ingest_problem.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.status"]
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      ingest が rejected（データの誤り）または failed（一時的なエラー）で終わった。
      ops.ingestion_log の error_message を確かめる（docs/operations.md の「失敗したとき」）。
      rejected のファイルは rejected バケットに移っている。failed は Workflows が最大 3 回やり直す。
    EOT
  }
}

# Workflows の実行の失敗。transform（dbt のテストの不合格を含む）と、
# ingest のやり直しの失敗・ジョブを起動できなかった場合（ingest のログが出ない）を見張る
resource "google_monitoring_alert_policy" "workflow_failed" {
  project      = var.project_id
  display_name = "Workflows：実行の失敗"
  combiner     = "OR"

  conditions {
    display_name = "失敗した実行が 1 件以上"
    condition_threshold {
      filter          = "resource.type = \"workflows.googleapis.com/Workflow\" AND metric.type = \"workflows.googleapis.com/finished_execution_count\" AND metric.labels.status = \"FAILED\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.workflow_id"]
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      Workflows（${join(" / ", values(var.workflow_names))}）の実行が失敗した。
      transform なら ops.dbt_runs と Cloud Run Job「dbt」のログ、ingest なら ops.ingestion_log を確かめる
      （docs/operations.md の「失敗したとき」）。
    EOT
  }
}
