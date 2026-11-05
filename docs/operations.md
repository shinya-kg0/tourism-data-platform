# 運用手順

イベント駆動の処理（仕様書 9 章）のデプロイと、日々の運用の手順。

```
landing へのアップロード → Eventarc「ingest-on-upload」→ Workflows「ingest」→ Cloud Run Job「ingest」
Cloud Scheduler「transform-daily」（毎日 04:00 JST）→ Workflows「transform」→ Cloud Run Job「dbt」
```

以下のコマンドは、リポジトリの直下で実行する。

## 1. デプロイ

GitHub Actions の build-push / terraform-apply（フェーズ5）ができるまでは、手元から行う。

```bash
# 1) コンテナイメージを作り、Artifact Registry に送る（表示された image_tag を控える）
GCP_PROJECT_ID=tourism-data-platform scripts/build_push.sh

# 2) Cloud Run Jobs のイメージを差し替える（Workflows の YAML の変更もここで反映される）
cd terraform/envs/prod
terraform plan -var image_tag=<1 で表示されたタグ> -out=tfplan
terraform apply tfplan
```

- タグはコミットの短い SHA。`ingest/` か `dbt/` に未コミットの変更があると、スクリプトは止まる。
- 新しい環境に初めて作るときは、Artifact Registry がないとイメージを送れず、イメージがないと Cloud Run Job を作れない。
  先に API と Artifact Registry だけを作ってから、上の手順を行う。

  ```bash
  terraform apply -var image_tag=bootstrap \
    -target=google_project_service.this \
    -target=module.pipeline.google_artifact_registry_repository.this
  ```

- Eventarc の API を有効にした直後は、Eventarc のサービスエージェントの権限が行き渡るまで、トリガーの作成が
  `storage.buckets.get` の権限エラーで失敗することがある。数分おいてから apply をやり直せば通る。

## 2. データを取り込む

決まったパスに Excel を置くだけで取り込まれる（パスのルールは仕様書 4.2）。

```bash
# 宿泊旅行統計（年確定値）
gcloud storage cp 2026.xlsx gs://tourism-data-platform-landing/overnight/annual/2026.xlsx

# 消費動向調査（暦年の確報、四半期の速報）
gcloud storage cp 002025515.xls gs://tourism-data-platform-landing/consumption/annual/2025.xls
gcloud storage cp 002027756.xlsx gs://tourism-data-platform-landing/consumption/quarterly/2026_Q3_preliminary1.xlsx
```

- 消費動向調査は、シートに書かれた期間と公表区分（例：「2026年7-9月期 【1次速報】」）がパスと合わないと rejected になる。
  観光庁サイトのファイル名は番号だけなので、上げる前にどの期のファイルかを確かめる。
- 2020 年は 1–3 月期、2021 年は 10–12 月期の集計表しかない。`consumption/quarterly/2020_Q1.xls` のように四半期として上げる。

- 取り込みに成功したファイルは archive バケットへ、ルールや構造に合わないファイルは rejected バケットへ移る。
- 何度上げ直しても、raw は「調査・年・期・公表区分」の単位で入れ替わるだけ（D-05）。改定されたファイルは、同じパスに上げ直せばよい。
- 複数のファイルを一度に上げてもよい。raw へのトランザクションがぶつかったときは、ingest がその場で待ってやり直す。
- marts への反映は、翌朝 04:00 の transform で行われる（D-12）。すぐに反映したいときは、3 の手順で transform を手動で実行する。

### 見出し定義を増やしたあと、取り込み済みの年を取り込み直す

取り込むのは見出し定義（`ingest/header_defs/`）がある表だけなので、表を増やしたら、デプロイしたあとで
archive にある元ファイルを landing に戻して取り込み直す。名前の世代番号（`__` のあと）を外して戻す。

```bash
# 例：宿泊旅行統計の各年について、最新の世代を landing に戻す
for year in $(seq 2016 2025); do
  src=$(gcloud storage ls "gs://tourism-data-platform-archive/overnight/annual/${year}__*.xlsx" | sort | tail -1)
  gcloud storage cp "$src" "gs://tourism-data-platform-landing/overnight/annual/${year}.xlsx"
done
```

### 結果の確かめ方

```sql
-- 取り込みの記録（新しい順）
SELECT source_uri, generation, status, row_count, error_message, finished_at
FROM `tourism-data-platform.ops.ingestion_log`
ORDER BY started_at DESC
LIMIT 20;
```

```bash
# Workflows の実行（FAILED は 3 回やり直しても失敗したもの）
gcloud workflows executions list ingest --location=asia-northeast1 --limit=20
```

## 3. 変換（dbt）を手動で実行する

```bash
# 新しい取り込みがあるときだけ dbt を実行する（Scheduler と同じ動き）
gcloud workflows run transform --location=asia-northeast1

# 新しい取り込みがなくても実行する（dbt のモデルを変えてデプロイした後など）
gcloud workflows run transform --location=asia-northeast1 --data='{"force": true}'
```

- 実行の結果は `ops.dbt_runs` に記録される（`trigger` は手動なら `manual`、Scheduler なら `schedule`）。
- dbt のテストに落ちると、その先の marts は更新されず、Workflows の実行は失敗で終わる。
  原因は Cloud Run Job「dbt」のログで確かめる。

```bash
gcloud run jobs executions list --job=dbt --region=asia-northeast1 --limit=5
```

## 4. 失敗したとき

| 状態 | 確かめる場所 | 対応 |
|---|---|---|
| ingestion_log が `rejected` | `error_message`、rejected バケット | パスかファイルを直して landing に上げ直す |
| ingestion_log が `failed`、Workflows「ingest」が FAILED | Cloud Run Job「ingest」のログ | 一時的なエラーなら、同じファイルを landing に上げ直す |
| Workflows「transform」が FAILED | Cloud Run Job「dbt」のログ、`ops.dbt_runs` | モデルかデータを直し、`force` を付けて transform を実行する |

## 5. まだデプロイしていない取り込みで dbt を試す

ingest の変更（表の追加など）をデプロイする前に dbt のモデルを作るときは、手元で解析した結果を
開発用のデータセットに読み込み、`DBT_RAW_DATASET` で dbt の読み先を差し替える。本番の `raw` には書かない。

```bash
cd dbt
DBT_RAW_DATASET=dbt_${DBT_USER}_raw uv run dbt build
```

- 開発用のデータセットのテーブルには有効期限を付けておく（本番の raw と同じスキーマ：`terraform/modules/bigquery/schemas/`）。

rejected と failed をメールで知らせる仕組み（仕様書 13 章）は、フェーズ5で追加する。
