# tourism-data-platform

観光庁の「訪日外国人消費動向調査」と「宿泊旅行統計調査」を BigQuery に蓄積し、BI ツールからそのまま読める集計表（marts）まで整える分析基盤。

- 取り込み：GCS への Excel アップロード → Eventarc → Workflows → Cloud Run Jobs（Python）
- 変換：dbt（raw → staging → intermediate → marts）
- BI ツールへのつなぎ口：marts（ダッシュボードのページ単位の小さな実テーブル。Looker Studio / Tableau などから 1 グラフ 1 mart で読める）
- データの流れ：dbt docs（リネージ）で raw から marts までをたどれる
- インフラ：Terraform、CI/CD：GitHub Actions（Workload Identity 連携）

可視化（ダッシュボード）はスコープ外です。Looker Studio はページ 1（サマリ）だけを、marts を BI ツールから読めることの動作確認として作成しました（仕様書 D-22、[構築手順](docs/looker_studio.md)）。

詳細は [仕様書](docs/spec_tourism_data_platform.md) を参照してください。デプロイと運用の手順は [運用手順](docs/operations.md) にあります。

## ディレクトリ構成

| パス | 内容 |
|---|---|
| `ingest/` | 取り込み処理（Python パッケージ、見出し定義、テスト、Dockerfile） |
| `dbt/` | dbt プロジェクト（モデル、シード、テスト、マクロ） |
| `workflows/` | Cloud Workflows の定義（ingest / transform） |
| `terraform/` | GCP リソース（`modules/` と `envs/prod/`） |
| `notebooks/` | 探索・検証用のノートブック |
| `docs/` | 仕様書、運用手順、作業レポート、Looker Studio の構築手順（ページ 1 のみ） |
| `scripts/` | 補助スクリプト（見出し定義の作成、初回の一括アップロードなど） |
| `.github/workflows/` | CI/CD |

## 開発環境の準備

必要なツール：Python 3.12、[uv](https://docs.astral.sh/uv/)、Terraform 1.6 以上、gcloud CLI、Docker

```bash
cp .env.example .env               # 値を埋める
gcloud auth application-default login

# 取り込み処理
cd ingest && uv sync && uv run pytest

# dbt
cd dbt && uv sync && uv run dbt deps && uv run dbt debug

# Terraform（tfstate バケットは事前に手作業で作成：仕様書 10.2）
cd terraform/envs/prod
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars   # 値を埋める
terraform init -backend-config=backend.hcl
terraform plan
```

## データのアップロード

```
gs://{project}-landing/{survey}/{period_type}/{year}[_Q{quarter}][_{release}].{xlsx|xls}
```

例：`overnight/annual/2026.xlsx`、`consumption/quarterly/2026_Q3_preliminary1.xlsx`（ルールの詳細は仕様書 4.2）

アップロードすると Eventarc → Workflows → Cloud Run Job「ingest」で raw に取り込まれ、毎日 04:00 JST の transform で marts に反映されます。

## 出典

- 観光庁「宿泊旅行統計調査」「訪日外国人消費動向調査」（[e-Stat](https://www.e-stat.go.jp/)、[観光庁](https://www.mlit.go.jp/kankocho/)）
