# GitHub Actions からキーなしで認証する（仕様書 12 章、D-18）
# プールは消しても 30 日間は同じ ID で作り直せないため、ID は変えない

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  # このリポジトリ以外から来たトークンは受け付けない
  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# PR の CI で使うサービスアカウント。PR のブランチからも使うため、リポジトリ単位で許可する。
resource "google_service_account_iam_member" "github_ci" {
  for_each = toset(["sa-github-plan", "sa-github-dbt-ci"])

  service_account_id = google_service_account.this[each.value].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# main へのマージで動くジョブ（イメージの送信、dbt docs）。main ブランチからのトークンだけを許可する
resource "google_service_account_iam_member" "github_main" {
  for_each = toset(["sa-github-builder", "sa-github-docs"])

  service_account_id = google_service_account.this[each.value].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.ref/refs/heads/main"
}

# 本番を変える deployer は、環境 production のジョブだけに許可する。環境は main だけ・承認が必要（GitHub 側の設定）。
# 環境のジョブはトークンの sub が「{subject の接頭辞}:environment:{環境}」になる。このリポジトリは変わらない subject
# （名前の変更に左右されない形式。repo:{owner}@{owner の ID}/{repo}@{repo の ID}）を使っている
resource "google_service_account_iam_member" "github_deployer" {
  service_account_id = google_service_account.this["sa-github-deployer"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/${var.github_oidc_subject_prefix}:environment:production"
}

# plan で状態ファイルを読む（-lock=false で実行するので、書き込みは要らない）
resource "google_storage_bucket_iam_member" "github_plan_tfstate" {
  bucket = var.tfstate_bucket
  role   = "roles/storage.objectViewer"
  member = google_service_account.this["sa-github-plan"].member
}
