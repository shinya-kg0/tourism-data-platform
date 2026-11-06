# tourism-data-platform

観光庁の「訪日外国人消費動向調査」と「宿泊旅行統計調査」を BigQuery に蓄積し、BI ツールからそのまま読める集計表（marts）まで整える分析基盤。

- **dbt docs（データの流れと各列の説明）**：https://shinya-kg0.github.io/tourism-data-platform/
- **仕様書**：[docs/spec_tourism_data_platform.md](docs/spec_tourism_data_platform.md)（設計判断 D-01〜D-22 と根拠）
- **運用手順**：[docs/operations.md](docs/operations.md)

| 区分 | 使っているもの |
|---|---|
| 取り込み | GCS への Excel のアップロード → Eventarc → Workflows → Cloud Run Jobs（Python） |
| 変換 | dbt（raw → staging → intermediate → marts）。テストに通ったときだけ marts を更新する |
| BI ツールへのつなぎ口 | marts（想定したページ単位の小さな実テーブル。1 つのグラフに 1 つの mart をつなぐだけで使える） |
| インフラ | Terraform（GCP のリソースをほぼすべて管理） |
| CI/CD | GitHub Actions（Workload Identity 連携でキーなしに認証） |
| 監視 | Cloud Monitoring（取り込みの失敗と Workflows の失敗をメールで通知） |

可視化（ダッシュボード）はスコープ外です。Looker Studio はページ 1（サマリ）だけを、marts を BI ツールから読めることの動作確認として作りました（仕様書 D-22、[構築手順](docs/looker_studio.md)）。

## 設計で工夫したところ

- **冪等な取り込み**：raw は追記せず「調査・年・期・公表区分」の単位で丸ごと入れ替える。同じファイルを何度上げても結果は同じ（D-05）
- **Excel の形式の違いをコードで吸収**：見出しの定義をリポジトリで管理し、取り込むときに照合する。合わないファイルは取り込まずに rejected へ移す（D-06）
- **テストが関所**：dbt のテストに落ちると、その先の marts は更新されない
- **権限を処理ごとに分ける**：サービスアカウントを処理ごと・CI のジョブごとに分ける。本番を変えられるのは、承認を経たデプロイのジョブだけ（D-17、D-18）

## marts を BI ツールにつなぐ

BI ツールが読むのは `marts` データセットだけです（D-15）。結合と推計は BigQuery の中で済ませてあるので、ブレンドや計算フィールドを使わずに、1 つのグラフに 1 つの mart をつなぐだけで作れます（D-09）。

| mart | 想定したページ | 粒度 |
|---|---|---|
| `mart_kpi_yearly` | 1. サマリ | 年 |
| `mart_nationality_yearly` | 2. 国籍分析 | 国籍×年 |
| `mart_nationality_spend_category_yearly` | 2. 国籍分析 | 国籍×費目×年 |
| `mart_prefecture_yearly` | 3. 地域分析 | 都道府県×年 |
| `mart_prefecture_nationality_yearly` | 3. 地域分析 | 都道府県×国籍×年 |
| `mart_seasonality_monthly` | 4. 季節性 | 国籍×年×月 |
| `mart_occupancy_yearly` | 5. 宿泊の受け入れ | 都道府県×施設タイプ×年 |

- 各列の意味・単位・注意点（コロナ期間の欠損、サンプルの少ない県の `is_low_sample` など）は [dbt docs](https://shinya-kg0.github.io/tourism-data-platform/) の各 mart のページにあります。
- 読み取りには `marts` だけを読めるサービスアカウント `sa-looker`（`marts` のデータ閲覧者とジョブユーザー）を使います。個人の認証でつなぐと raw まで読めてしまうためです。
- カスタムクエリは使わず、テーブルをそのままつなぎます。データの更新は 1 日 1 回以下なので、キャッシュは長め（例：12 時間）で十分です。
- どの mart にも `year` があり、国籍・都道府県の mart にはコードと名前の列があるので、年・国籍・都道府県の絞り込みをページ全体にかけられます。
- Looker Studio での具体的な手順は [docs/looker_studio.md](docs/looker_studio.md) にあります。

## CI/CD

| きっかけ | 動くもの |
|---|---|
| PR | `lint-test`（ruff・pytest）、`terraform-plan`（結果を PR にコメント）、`dbt-ci`（本番の raw を読み、`ci_pr_{番号}` に `dbt build`） |
| PR を閉じたとき | `ci_pr_{番号}` を消す |
| main へのマージ | イメージの作成 → plan → **承認** → `terraform apply`。あわせて dbt docs を GitHub Pages に公開 |

- main はブランチの保護をかけていて、PR の 3 つのチェックが通らないとマージできません。
- 詳しくは仕様書 12 章と、運用手順の 1 節・6 節を見てください。

## ディレクトリ構成

| パス | 内容 |
|---|---|
| `ingest/` | 取り込み処理（Python パッケージ、見出し定義、テスト、Dockerfile） |
| `dbt/` | dbt プロジェクト（モデル、シード、テスト、マクロ、Dockerfile） |
| `workflows/` | Cloud Workflows の定義（ingest / transform） |
| `terraform/` | GCP リソース（`modules/` と `envs/prod/`） |
| `docs/` | 仕様書、運用手順、Looker Studio の構築手順（ページ 1 のみ）、作業レポート（`reports/`） |
| `scripts/` | 見出し定義の作成（`generate_header_defs.py`）、手元からのイメージの作成（`build_push.sh`） |
| `notebooks/` | 探索・検証用のノートブックの置き場所 |
| `.github/workflows/` | CI（`ci.yml`）とデプロイ（`deploy.yml`） |

## 開発環境の準備

必要なツール：Python 3.12、[uv](https://docs.astral.sh/uv/)、Terraform 1.6 以上（CI では 1.15.5）、gcloud CLI、Docker、GitHub CLI（`gh`）

```bash
cp .env.example .env               # 値を埋める
gcloud auth application-default login

# 取り込み処理
cd ingest && uv sync && uv run pytest

# dbt（dev ターゲットは dbt_{DBT_USER} データセットに作る）
cd dbt && uv sync && uv run dbt deps && uv run dbt build
```

## 基盤をゼロから作り直す

新しい GCP プロジェクトとリポジトリに作り直すときの順番です。コマンドの詳細は[運用手順](docs/operations.md)にあります。

1. **手作業の準備**（Terraform の管理外。仕様書 10.2）
   - GCP プロジェクトを作り、課金アカウントを紐付ける
   - tfstate を置くバケット `{project}-tfstate` を作る
   - 課金アカウントに予算アラートを設定する
2. **Terraform の設定**
   ```bash
   cd terraform/envs/prod
   cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars   # 値を埋める
   terraform init -backend-config=backend.hcl
   ```
   - `github_oidc_subject_prefix` は、`gh api repos/{owner}/{repo}/actions/oidc/customization/sub` の `sub_claim_prefix` で確かめる（運用手順 6 節）
3. **最初の apply（手元から）**。Cloud Run Job はイメージがないと作れず、イメージは Artifact Registry がないと送れないので、3 回に分けます（運用手順 1 節）
   1. API と Artifact Registry だけを `-target` で apply する
   2. `scripts/build_push.sh` でイメージを作って送る
   3. 表示されたタグを `image_tag` に渡して、全体を apply する
4. **GitHub の設定**（運用手順 6 節）
   - リポジトリの変数 `GCP_PROJECT_ID`・`GCP_WORKLOAD_IDENTITY_PROVIDER` と、シークレット `ALERT_EMAIL`
   - 環境 `production`（承認者を付け、main だけにする）
   - Pages の公開元を GitHub Actions にする
   - main のブランチの保護
5. **データを上げる**：観光庁や e-Stat から Excel を取得し、下のパスのルールで landing に上げる。翌朝 04:00 の transform で marts まで反映されます（すぐ反映するなら運用手順 3 節）

これ以降の変更は、PR を作ってマージすれば GitHub Actions がデプロイします。

## データのアップロード

```
gs://{project}-landing/{survey}/{period_type}/{year}[_Q{quarter}][_{release}].{xlsx|xls}
```

例：`overnight/annual/2026.xlsx`、`consumption/quarterly/2026_Q3_preliminary1.xlsx`（ルールの詳細は仕様書 4.2）

アップロードすると Eventarc → Workflows → Cloud Run Job「ingest」で raw に取り込まれ、毎日 04:00 JST の transform で marts に反映されます。

## 出典

- 観光庁「宿泊旅行統計調査」「訪日外国人消費動向調査」（[e-Stat](https://www.e-stat.go.jp/)、[観光庁](https://www.mlit.go.jp/kankocho/)）
