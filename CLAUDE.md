# CLAUDE.md

観光統計（訪日外国人消費動向調査・宿泊旅行統計調査）の BigQuery データ基盤。学習・ポートフォリオ用。
可視化はスコープ外（D-22）。marts を BI ツールから読める「つなぎ口」として整えるところまでが対象で、Looker Studio はページ 1 のみ作成済み。

## 最初に読むもの

- 仕様書：`docs/spec_tourism_data_platform.md`（設計判断 D-01〜D-22 と根拠を含む）
- 仕様と違う実装をするときは、先に仕様書を更新するか、ユーザーに確認する

## 構成と担当

| ディレクトリ | 担当 | メモ |
|---|---|---|
| `ingest/` | Excel の取得・解析・raw への書き込み（Python 3.12、uv） | 1 ファイル単位で処理する。見出しは `header_defs/` の定義と照合（D-06） |
| `dbt/` | raw → staging → intermediate → marts | prod 以外は `target.schema` の 1 データセットにまとめる（`macros/generate_schema_name.sql`） |
| `workflows/` | Workflows の YAML | ingest はイベント駆動、transform は毎日 04:00 JST（D-12） |
| `terraform/` | GCP リソース | Looker Studio・プロジェクト作成・tfstate バケットは管理外（10.2） |

## よく使うコマンド

```bash
cd ingest && uv run pytest            # 取り込みのテスト
cd ingest && uv run ruff check .      # 静的検査
cd dbt && uv run dbt build            # dev（dbt_{DBT_USER}）にビルド
cd terraform/envs/prod && terraform fmt -recursive ../.. && terraform validate
```

## 守ること

- 秘密情報（`.env`、tfvars、サービスアカウントキー）はコミットしない。GitHub Actions はキーなし認証（D-18）
- raw は追記せず「調査・年・期・公表区分」単位で入れ替える（D-05）
- BI ツール（Looker Studio など）が参照するのは marts だけ（D-15）。marts はページ単位のまま残し、BI ツールの都合で作り直さない（D-09）
- ドキュメント・コメント・dbt の説明は日本語

## データの注意点

- 宿泊旅行統計：2016〜2019 年は旧形式（結合セル・単位行なし）。新形式の見出し定義を列位置で当てはめる
- 消費動向調査：2017 年以前は表番号が「第N表」で表3-4 がない。2024 年 4–6 月期からの新調査も形式は同じ。2026 年から国籍が 24 区分（仕様書 3.2）
- 宿泊旅行統計の国籍別（参考第1表）は従業者数 10 人以上の施設だけ。全施設の外国人延べ宿泊者数は第2表
- 2020〜2022 年はコロナで欠損・試算値あり
- 公表値は 10 単位で丸められているため、年計と月合計に ±10 の差が出る
