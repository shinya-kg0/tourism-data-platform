# BigQuery データセットと raw・ops のテーブル（仕様書 6 章）
# staging / intermediate / marts のテーブルは dbt が作る

locals {
  datasets = {
    raw          = "取り込んだ縦持ちのデータ（ingest が書き込む）"
    ops          = "取り込みと dbt 実行の記録"
    staging      = "型・表記・公表区分をそろえたもの（dbt）"
    intermediate = "調査どうしを結合したもの（dbt）"
    marts        = "BI ツールから読む集計表（dbt）。BI ツールはここだけを参照する"
  }

  # raw は年でパーティション分割し、「調査・年・期・公表区分」単位の入れ替えを安くする（D-05、D-07）
  tables = {
    overnight_cells = {
      dataset         = "raw"
      description     = "宿泊旅行統計調査（年確定値）の全表を縦持ちにしたもの"
      partition_field = "year"
      clustering      = ["table_id", "area_name"]
    }
    consumption_cells = {
      dataset         = "raw"
      description     = "訪日外国人消費動向調査の対象表を縦持ちにしたもの"
      partition_field = "year"
      clustering      = ["table_id"]
    }
    ingestion_log = {
      dataset         = "ops"
      description     = "ファイルごとの取り込み記録。(source_uri, generation) で二重処理を防ぐ"
      partition_field = null
      clustering      = null
    }
    dbt_runs = {
      dataset         = "ops"
      description     = "dbt 実行の記録。transform はこれより後の取り込みがあるときだけ動く"
      partition_field = null
      clustering      = null
    }
  }
}

resource "google_bigquery_dataset" "this" {
  for_each = local.datasets

  project                    = var.project_id
  dataset_id                 = each.key
  location                   = var.region
  description                = each.value
  delete_contents_on_destroy = false
}

resource "google_bigquery_table" "this" {
  for_each = local.tables

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.this[each.value.dataset].dataset_id
  table_id            = each.key
  description         = each.value.description
  schema              = file("${path.module}/schemas/${each.value.dataset}_${each.key}.json")
  clustering          = each.value.clustering
  deletion_protection = true

  dynamic "range_partitioning" {
    for_each = each.value.partition_field == null ? [] : [each.value.partition_field]
    content {
      field = range_partitioning.value
      range {
        start    = 2000
        end      = 2100
        interval = 1
      }
    }
  }
}
