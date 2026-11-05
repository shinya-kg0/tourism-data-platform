#!/usr/bin/env bash
# ingest・dbt のコンテナイメージを作り、Artifact Registry に送る（仕様書 12 章）
# ふだんは main へのマージで GitHub Actions の build-push が行う。これは GitHub Actions が使えないときの、手元からのデプロイ用。
#
#   GCP_PROJECT_ID=tourism-data-platform scripts/build_push.sh
#
# タグはコミットの短い SHA。コードとタグがずれないよう、未コミットの変更があれば止める。
# 送ったら、表示されたタグを terraform apply の image_tag に渡す。
set -euo pipefail

project="${GCP_PROJECT_ID:?GCP_PROJECT_ID を指定してください}"
region="${REGION:-asia-northeast1}"
gcloud="${GCLOUD:-gcloud}"
root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -n "$(git -C "$root" status --porcelain -- ingest dbt)" ]]; then
  echo "ingest/ または dbt/ に未コミットの変更があります。コミットしてから実行してください" >&2
  exit 1
fi

tag="$(git -C "$root" rev-parse --short=12 HEAD)"
registry="${region}-docker.pkg.dev"
repo="${registry}/${project}/tourism"

"$gcloud" auth print-access-token | docker login -u oauth2accesstoken --password-stdin "https://${registry}"

for name in ingest dbt; do
  # Cloud Run は linux/amd64 のイメージだけを動かせる
  docker buildx build --platform linux/amd64 --tag "${repo}/${name}:${tag}" --push "${root}/${name}"
done

echo "image_tag = \"${tag}\""
