# 運用手順

イベント駆動の処理（仕様書 9 章）のデプロイと、日々の運用の手順。

```
landing へのアップロード → Eventarc「ingest-on-upload」→ Workflows「ingest」→ Cloud Run Job「ingest」
Cloud Scheduler「transform-daily」（毎日 04:00 JST）→ Workflows「transform」→ Cloud Run Job「dbt」
```

以下のコマンドは、リポジトリの直下で実行する。

## 1. デプロイ

ふだんは main へのマージで `.github/workflows/deploy.yml` が動く（仕様書 12 章）。

1. `build-push`：ingest・dbt のイメージを作り、コミットの短い SHA（12 桁）をタグにして送る
2. `terraform-plan`：新しいタグで plan し、結果をジョブのまとめ（Summary）に出す
3. `terraform-apply`：環境 `production` の**承認待ち**になる。Actions の実行の画面で plan のまとめを見てから
   「Review deployments」→ 承認すると、apply される
4. `dbt-docs` → `pages`：本番を target に dbt docs を作り、GitHub Pages
   （https://shinya-kg0.github.io/tourism-data-platform/）に公開する。デプロイとは並行して動く

デプロイだけをやり直すときは、Actions の「Deploy」→「Run workflow」（main）。

### 手元からデプロイする（GitHub Actions が使えないとき・最初の 1 回）

GitHub Actions の認証（Workload Identity 連携とサービスアカウント）を変えるときや、新しい環境を作るときは、手元から行う。

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

- `local.services` に API を足すときは、先に API だけを apply する（`-target='google_project_service.this["<API名>"]'`）。
  まとめて apply すると、`module.iam` が API の有効化を待つため GCS のサービスエージェントのアドレスが apply のときまで決まらず、
  `gcs_pubsub_publisher` が置き換え（いったん外して付け直す）になる。その間のアップロードはイベントが届かないおそれがある。
- `terraform.tfvars` の `image_tag` は古いことがある。イメージを変えない apply でも、本番のジョブが今使っているタグを `-var` で渡す
  （`gcloud run jobs describe dbt --region=asia-northeast1 --format='value(spec.template.spec.template.spec.containers[0].image)'`）。
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

## 5. GitHub Actions（PR の CI とデプロイの設定）

`.github/workflows/ci.yml`（仕様書 12 章）。PR を開く・更新すると次が動く。

| ジョブ | 認証（D-18） | 内容 |
|---|---|---|
| `lint-test` | なし | ingest の `ruff check` と `pytest` |
| `terraform-plan` | `sa-github-plan` | `fmt -check` → `validate` → `plan -lock=false`。結果はジョブのログで見る |
| `dbt-ci` | `sa-github-dbt-ci` | 本番の raw を読み、`ci_pr_{番号}` に `dbt build --target ci` |
| `dbt-ci-cleanup` | `sa-github-dbt-ci` | PR を閉じたら `ci_pr_{番号}` を消す |

- フォークからの PR は認証のトークンを受け取れないため、`lint-test` だけが動く。
- `terraform-plan` の `image_tag` は、本番のジョブが今使っているタグ。イメージの差分は出ない。

### GitHub 側の設定（手作業。リポジトリの Settings → Secrets and variables → Actions）

| 種類 | 名前 | 値 |
|---|---|---|
| 変数 | `GCP_PROJECT_ID` | `tourism-data-platform` |
| 変数 | `GCP_WORKLOAD_IDENTITY_PROVIDER` | `terraform output -raw github_workload_identity_provider` の値 |
| シークレット | `ALERT_EMAIL` | `terraform.tfvars` の `alert_email`（plan に渡すだけ。`sensitive` なので表示されない） |

```bash
gh variable set GCP_PROJECT_ID --body tourism-data-platform
gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$(cd terraform/envs/prod && terraform output -raw github_workload_identity_provider)"
gh secret set ALERT_EMAIL   # 値を入力する
```

### GitHub 側の設定（デプロイ）

| 設定 | 内容 |
|---|---|
| 環境 `production` | 承認者：リポジトリのオーナー。デプロイできるブランチ：main だけ |
| Pages | Settings → Pages → Source を「GitHub Actions」 |
| ブランチの保護（main） | PR を必須（承認の数は 0）、必須のチェック：`lint-test`・`terraform-plan`・`dbt-ci`、force push と削除を禁止、管理者にも当てはめる |

`sa-github-deployer` は環境 `production` のジョブからしか使えない（トークンの sub が `{接頭辞}:environment:production` のとき）。
環境の名前を変えると、デプロイが認証で失敗する。

- このリポジトリの sub は、名前の変更に左右されない形式（`repo:{owner}@{owner の ID}/{repo}@{repo の ID}`）になっている。
  接頭辞は `gh api repos/shinya-kg0/tourism-data-platform/actions/oidc/customization/sub` の `sub_claim_prefix` で確かめられる。
- Terraform には変数 `github_oidc_subject_prefix` で渡す。手元は `terraform.tfvars`、GitHub Actions は
  `github.repository_owner_id`・`github.repository_id` から組み立てる。

### `ci_pr_*` が残ったとき

`dbt-ci-cleanup` が失敗したり、ワークフローができる前に閉じた PR があったりすると、データセットが残る。

```bash
bq ls --project_id=tourism-data-platform | grep ci_pr_
bq rm -r -f -d tourism-data-platform:ci_pr_<番号>
```
