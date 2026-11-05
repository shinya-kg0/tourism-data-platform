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
# 本番を変える deployer は、main と本番環境だけに絞る（CI/CD の 2 つ目の PR で追加する）
resource "google_service_account_iam_member" "github_ci" {
  for_each = toset(["sa-github-plan", "sa-github-dbt-ci"])

  service_account_id = google_service_account.this[each.value].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# plan で状態ファイルを読む（-lock=false で実行するので、書き込みは要らない）
resource "google_storage_bucket_iam_member" "github_plan_tfstate" {
  bucket = var.tfstate_bucket
  role   = "roles/storage.objectViewer"
  member = google_service_account.this["sa-github-plan"].member
}
