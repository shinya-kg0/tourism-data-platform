# GCS バケット（landing / archive / rejected）
# Eventarc はバケット単位でしか絞り込めないため、用途ごとにバケットを分ける（仕様書 4.1、D-01）

locals {
  buckets = {
    # アップロード先。取り込み後に archive へ移すので、残ったものは 30 日で削除する
    landing = { versioning = true, delete_after_days = 30 }
    # 取り込みに成功した元ファイルの保管
    archive = { versioning = true, delete_after_days = null }
    # 不正なファイルの隔離
    rejected = { versioning = false, delete_after_days = 90 }
  }
}

resource "google_storage_bucket" "this" {
  for_each = local.buckets

  name                        = "${var.project_id}-${each.key}"
  project                     = var.project_id
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = each.value.versioning
  }

  dynamic "lifecycle_rule" {
    for_each = each.value.delete_after_days == null ? [] : [each.value.delete_after_days]
    content {
      condition {
        age = lifecycle_rule.value
      }
      action {
        type = "Delete"
      }
    }
  }

  # 版の保存が有効なバケットでは、削除・上書きで残った古い版も同じ日数で消す
  dynamic "lifecycle_rule" {
    for_each = each.value.versioning && each.value.delete_after_days != null ? [each.value.delete_after_days] : []
    content {
      condition {
        days_since_noncurrent_time = lifecycle_rule.value
      }
      action {
        type = "Delete"
      }
    }
  }
}
