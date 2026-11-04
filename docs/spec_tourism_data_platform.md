# 観光統計データ基盤 仕様書

作成日：2026年11月3日
対象：訪日外国人消費動向調査・宿泊旅行統計調査の分析基盤とダッシュボード（学習・ポートフォリオ用）

---

## 1. 概要

### 1.1 目的

観光庁の2つの統計（訪日外国人消費動向調査・宿泊旅行統計調査）を BigQuery にデータウェアハウス（DWH）として蓄積し、Looker Studio のダッシュボードで可視化する。データ変換は dbt で管理し、インフラは Terraform で管理する。新しいExcelファイルを GCS にアップロードするだけでデータが更新される仕組みを作る。

### 1.2 ポートフォリオとして見せたいこと

| 観点 | 実現方法 |
|---|---|
| データモデリング | dbtで raw → staging → intermediate → marts の層を作る |
| データ品質 | dbt testsで品質を確かめてから集計表を更新する。取り込み時にはExcelの構造を検査する |
| イベント駆動の処理 | GCSへのアップロードをきっかけに Eventarc → Workflows → Cloud Run Jobs が動く |
| 冪等性（同じファイルを何度取り込んでも結果が同じ） | 「調査・年・期・公表区分」の単位でデータを丸ごと入れ替える。取り込みの記録で二重処理を防ぐ |
| インフラのコード管理 | Terraformで管理し、GitHub Actionsからキーを使わずに認証する |
| CI/CD | PRごとに検査とdbtのCIを動かし、mainへのマージでデプロイする |

### 1.3 スコープ

| 対象 | 対象外 |
|---|---|
| 宿泊旅行統計調査（年確定値、2016年〜） | 新しい公表の通知・自動検出（D-03） |
| 訪日外国人消費動向調査（暦年・四半期、2016年〜、速報・確報） | 観光庁サイトの読み取り（スクレイピング） |
| 手動アップロードをきっかけにした取り込みとDWHの更新 | 宿泊旅行統計の月次速報（将来の拡張） |
| dbtによる変換・テスト・ドキュメント | JNTOの訪日外客数（将来の拡張） |
| Looker Studioのダッシュボード | Looker StudioのTerraform管理（D-14） |
| TerraformによるGCPリソースの管理 | 開発用と本番用でGCPプロジェクトを分けること（D-13） |
| GitHub ActionsによるCI/CD | リアルタイムでの反映 |

---

## 2. 全体のアーキテクチャ

```
                   ┌───────────────── GCP プロジェクト（asia-northeast1）─────────────────┐
                   │                                                                    │
 人がアップロード ──▶ GCS: landing バケット                                              │
                   │     │ ファイル作成のイベント（object.finalized）                      │
                   │     ▼                                                              │
                   │  Eventarc ──▶ Workflows「ingest」                                  │
                   │                  │                                                 │
                   │                  ▼                                                 │
                   │            Cloud Run Job「ingest」(Python)                          │
                   │              ・パスの検証 → Excelの構造検査 → 縦持ちに変換          │
                   │              ・BigQuery raw層の該当範囲を入れ替え                   │
                   │              ・成功：archive バケットへ移動 / 不正：rejected へ移動 │
                   │              ・ops.ingestion_log に記録                             │
                   │                                                                    │
                   │  Cloud Scheduler（毎日 04:00 JST）──▶ Workflows「transform」        │
                   │                  │ 前回のdbt実行以降に取り込みがあった場合だけ      │
                   │                  ▼                                                 │
                   │            Cloud Run Job「dbt」(dbt build)                          │
                   │              raw → staging → intermediate → marts（テストが関所）  │
                   │                                                                    │
                   │  BigQuery: raw / ops / staging / intermediate / marts              │
                   │                                  │                                 │
                   └──────────────────────────────────┼─────────────────────────────────┘
                                                      ▼
                                              Looker Studio（marts だけを参照）

 GitHub ── Actions（Workload Identity 連携）──▶ Terraform apply / イメージ作成 / dbt CI / dbt docs 公開
```

---

## 3. データソース

### 3.1 対象の統計と表

| 調査 | 集計期間 | 公表区分 | 取り込む表 | 入手先 |
|---|---|---|---|---|
| 宿泊旅行統計調査 | 暦年（1ファイルに年計と1〜12月を含む） | 年確定値のみ | 全21表（第1〜10表、参考第1〜11表） | e-Statのファイル |
| 訪日外国人消費動向調査 | 暦年・四半期 | 1次速報・2次速報・確報 | 表2-1、表3-1、表3-4、表4-1、表6-1 | e-Stat・観光庁サイトのExcel |

- 宿泊旅行統計は、変換処理がすでにあるため全表を取り込む。使うかどうかはdbt側で決める。
- 消費動向調査は、変換処理をこれから作るため、ダッシュボードで使う5表に絞る。表を増やしても、rawのテーブル定義は変わらない（D-07）。

### 3.2 既知の形式の違い

| 調査 | 期間 | 形式 | 対応 |
|---|---|---|---|
| 宿泊旅行統計 | 2016〜2019年 | 旧形式（結合セル・注記付き・単位の行なし。2016年は地域コードなし） | 新形式の見出し定義を列の位置で当てはめる（D-06） |
| 宿泊旅行統計 | 2020年〜 | 新形式（見出しが4段） | 見出し定義と照合する |
| 消費動向調査 | 2017年（暦年） | 表番号が旧形式（第N表） | シート名の対応表で「表X-Y」にそろえる |
| 消費動向調査 | 2018年〜2024年1–3月期 | 「表X-Y」形式 | 見出し定義と照合する |
| 消費動向調査 | 2024年4–6月期〜 | 新調査（インバウンド消費動向調査） | 形式のバージョンを分けて定義する（**要確認**：8章） |
| 消費動向調査 | 2020・2021年 | 暦年の集計表がなく、四半期1期分だけ | 四半期として取り込み、martsで注記する |

---

## 4. GCSの設計

### 4.1 バケット

| バケット | 用途 | 設定 |
|---|---|---|
| `{project}-landing` | アップロード先。Eventarcの監視対象 | 版の保存：有効、保存期間：30日で削除 |
| `{project}-archive` | 取り込みに成功した元ファイルを保管する | 版の保存：有効、削除しない |
| `{project}-rejected` | 不正なファイルを隔離する | 90日で削除 |
| `{project}-tfstate` | Terraformの状態ファイル | 版の保存：有効（最初の1回だけ手作業で作る） |

> **D-01：フォルダではなくバケットを分ける**
> Eventarcの Cloud Storage トリガーは、絞り込みの条件にバケットしか使えない（フォルダ単位の指定ができない）。同じバケット内で archive/ や rejected/ へ移動すると、それがまた新しいイベントになり、取り込みが繰り返し起動してしまう。用途ごとにバケットを分ければ、landing だけを確実に監視できる。

### 4.2 アップロードするパスのルール

```
gs://{project}-landing/{survey}/{period_type}/{year}[_Q{quarter}][_{release}].{xlsx|xls}
```

| 要素 | 値 | 説明 |
|---|---|---|
| `survey` | `overnight` / `consumption` | 調査の種類 |
| `period_type` | `annual` / `quarterly` | 集計期間 |
| `year` | 4桁の数字 | 対象の年 |
| `_Q{quarter}` | `_Q1`〜`_Q4` | `quarterly` のときは必須。`annual` のときは付けない |
| `_{release}` | `_preliminary1` / `_preliminary2` | 省略したら確報（`final`）として扱う |

**例**

| パス | 意味 |
|---|---|
| `overnight/annual/2026.xlsx` | 宿泊旅行統計 2026年 年確定値 |
| `consumption/annual/2025.xls` | 消費動向調査 2025年 暦年 確報 |
| `consumption/quarterly/2026_Q3_preliminary1.xlsx` | 消費動向調査 2026年7–9月期 1次速報 |

**検証のルール**（ルールに合わないファイルは rejected に移す）
- 正規表現：`^(overnight|consumption)/(annual|quarterly)/(\d{4})(_Q[1-4])?(_preliminary[12])?\.(xlsx|xls)$`
- `quarterly` なのに `_Q` がない、または `annual` なのに `_Q` がある → 取り込まない
- `overnight` で `quarterly` や速報を指定している → 取り込まない（宿泊旅行統計は年確定値だけが対象）

> **D-02：ファイルの種類はパスのルールで見分ける**
> ファイル名やExcelの中身から推測する方法もあるが、元のファイル名は年や配信元によってばらばらで、推測は外れることがある。アップロードする人に決まりを守ってもらい、決まりに合わないものは止める方が、間違ったデータが静かに入り込むことを防げる。人が関わる工程が1つなので、決まりを強制する負担は小さい。

> **D-03：新しい公表の通知・自動検出はスコープ外**
> 公表は年に数回で、手動でアップロードしても負担は小さい。観光庁サイトの読み取りはサイトの作りが変わると壊れやすく、e-Statのカタログには一部の年がない。まずは取り込み以降の仕組みを確実に作ることを優先する。将来、e-Statのカタログ（ファイル一覧）APIで新しい公表を見つけて通知する機能を足せる設計にしておく。

---

## 5. 取り込み（ingest）

### 5.1 処理の流れ

```
Eventarc（バケット・オブジェクト名・世代番号）
  └▶ Workflows「ingest」
        └▶ Cloud Run Job「ingest」（実行時の引数でオブジェクト名と世代番号を渡す）
              1. 二重処理の確認：ingestion_log で (source_uri, generation) が成功済みなら何もしないで終わる
              2. 取り込みの記録を「running」で書き込む
              3. パスを検証し、調査・期間・年・期・公表区分を取り出す        ── 不正なら rejected へ
              4. Excelをダウンロードし、形式のバージョンを判定する
              5. 構造を検査する：シートの有無、列の数、見出しの文字（定義と照合） ── 不正なら rejected へ
              6. 縦持ちに変換し、行ごとに検査する（地域・項目が空でないか、値が数値または記号か）
              7. BigQueryの一時テーブルに読み込む
              8. トランザクションの中で、raw の該当範囲を DELETE → INSERT する
              9. 元ファイルを archive に移す（名前に世代番号を付ける）。landing からは消す
             10. 取り込みの記録を「succeeded」と行数で更新する
```

### 5.2 終了の種類とやり直し

| 種類 | 例 | 終了コード | Workflowsの動き | 通知 |
|---|---|---|---|---|
| succeeded | 正常に終わった | 0 | 終わる | なし |
| skipped | 同じ世代のファイルがすでに取り込み済み | 0 | 終わる | なし |
| rejected | パスの違反、構造の不一致、行の検査で不合格 | 0（rejected として記録） | 終わる（やり直さない） | あり |
| failed | BigQueryやGCSの一時的なエラー | 1 | 間隔を広げながら最大3回やり直す | 3回とも失敗したら通知 |

> **D-04：データの誤りと一時的なエラーを分ける**
> 構造が合わないExcelは何度やり直しても失敗するので、やり直すのは無駄である。データの誤りは rejected として隔離し、人に知らせる。やり直しは一時的なエラーのときだけにする。

### 5.3 二重処理を防ぐ仕組み

- GCSのイベントは「少なくとも1回」届く仕組みなので、同じ通知が2回以上届くことがある。`(source_uri, generation)` の組で、成功済みかどうかを確かめる。
- 同じパスにファイルを上げ直すと世代番号が変わるので、上げ直しは新しい取り込みとして扱われる。数値が改定されたファイルを取り込み直すときは、これを使う。

### 5.4 raw層への書き込み（入れ替えの単位）

| 調査 | 入れ替えの単位 |
|---|---|
| overnight | `(year, release_status)` |
| consumption | `(year, quarter, release_status)`（暦年は quarter = 0） |

```sql
BEGIN TRANSACTION;
DELETE FROM raw.consumption_cells WHERE year = @year AND quarter = @quarter AND release_status = @release;
INSERT INTO raw.consumption_cells SELECT * FROM raw._tmp_xxx;
COMMIT TRANSACTION;
```

複数のファイルを一度に上げると、同じテーブルへのトランザクションがぶつかり、BigQuery が片方を中断する（`Transaction is aborted due to concurrent update`）。待てば通るエラーなので、ingest の中で間隔を空けて最大10分やり直す（10年分を同時に上げたときは、21回の中断がすべてこれで解消した）。

> **D-05：追記ではなく、決まった単位で丸ごと入れ替える**
> 追記にすると、上げ直しや数値の改定で同じ期のデータが二重に入る。単位を決めて入れ替えれば、何度実行しても結果は同じになる。トランザクションを使うので、入れ替えの途中の状態が外から見えることもない。
> 公表区分ごとに分けて残すので、1次速報と確報を比べることもできる。どの区分を使うかはstaging層で決める（6.3節）。

### 5.5 見出しの定義ファイル

- 表ごとの見出し定義を `ingest/header_defs/{survey}/{format_version}/{table_id}.json` としてリポジトリに置く。
- 中身：列の位置、target（全体/外国人）、group、sub、item、unit、照合用に正規化した見出しの文字。
- 最新形式のExcelから開発用のスクリプトで作り、人が確認してからコミットする。

> **D-06：見出しの定義をコードとしてリポジトリで管理する**
> 今の `fetch_overnight_trips.py` は、同じ実行の中で新しい年を先に読み、その見出しを旧形式の年に当てはめている。1ファイルずつ処理する方式では、ほかの年のファイルが手元にないので、この方法は使えない。定義をファイルにしておけば1ファイルだけで処理できる。また定義の変更がGitの差分としてレビューできるので、形式の変化に気づきやすくなる。

### 5.6 実行環境

| 項目 | 値 |
|---|---|
| 言語 | Python 3.12（依存ライブラリは uv で管理） |
| 主なライブラリ | pandas、openpyxl、xlrd、google-cloud-storage、google-cloud-bigquery |
| Cloud Run Job | メモリ 2GiB、CPU 1、タイムアウト 15分、タスク 1 |
| コード | 今の `fetch_overnight_trips.py` と `fetch_excel_to_csv.py` を `ingest/` パッケージに移し、1ファイル単位で処理する形に作り直す |

---

## 6. BigQueryの設計

### 6.1 データセット

| データセット | 用途 | 書き込む処理 |
|---|---|---|
| `raw` | 取り込んだ縦持ちのデータ | ingest |
| `ops` | 取り込みとdbt実行の記録 | ingest、Workflows |
| `staging` | 型・表記・公表区分をそろえたもの | dbt |
| `intermediate` | 調査どうしを結合したもの | dbt |
| `marts` | ダッシュボード用の集計表 | dbt |
| `dbt_{開発者名}` / `ci_pr_{番号}` | dbtの開発用・CI用 | dbt（CI用はPRを閉じたら消す） |

保存場所はすべて `asia-northeast1`（東京）。

### 6.2 rawのテーブル

**`raw.overnight_cells`**（年でパーティション分割、`table_id`・`area_name` でクラスタ化）

| 列 | 型 | 説明 |
|---|---|---|
| year | INT64 | 年 |
| month | INT64 | 月（0＝年計） |
| table_id | STRING | 表番号（例：第2表、参考第1表） |
| area_code | STRING | 都道府県コード（全国・運輸局は NULL） |
| area_name | STRING | 地域名 |
| target | STRING | 全体 / 外国人 |
| header_group / header_sub / header_item | STRING | 見出し（3段） |
| unit | STRING | 単位 |
| value | FLOAT64 | 値 |
| flag | STRING | 記号（`-`、`*` など） |
| release_status | STRING | 公表区分（final） |
| format_version | STRING | 形式のバージョン |
| source_uri / source_generation | STRING / INT64 | 元ファイルとその世代番号 |
| ingested_at | TIMESTAMP | 取り込んだ日時 |

**`raw.consumption_cells`**（年でパーティション分割、`table_id` でクラスタ化）

| 列 | 型 | 説明 |
|---|---|---|
| year / quarter | INT64 | 年、期（0＝暦年） |
| table_id | STRING | 表番号（例：表3-1） |
| row_category / row_item | STRING | 行の見出し（例：入国空港・海港 / 新千歳空港） |
| col_dimension / col_member | STRING | 列の区分とその値（例：国籍･地域 / 韓国） |
| measure | STRING | 指標（回答数、消費単価、購入率など） |
| unit / value / flag | STRING / FLOAT64 / STRING | 単位、値、記号 |
| release_status | STRING | preliminary1 / preliminary2 / final |
| format_version | STRING | 形式のバージョン |
| source_uri / source_generation / ingested_at | — | 宿泊と同じ |

### 6.3 opsのテーブル

**`ops.ingestion_log`**：source_uri、generation、md5、survey、period_type、year、quarter、release_status、status（running/succeeded/skipped/rejected/failed）、row_count、error_message、workflow_execution_id、started_at、finished_at

**`ops.dbt_runs`**：execution_id、status、trigger（schedule/manual）、started_at、finished_at

> **D-07：rawは表ごとではなく、調査ごとに1つの縦持ちテーブルにする**
> 表ごとにテーブルを作ると、表を増やすたびにスキーマの変更とTerraformの変更が必要になる。縦持ちにしておけば、表を増やしてもテーブルの定義は変わらない。表ごとの意味付けはdbtのstaging層で行う。BigQueryではパーティションとクラスタで読む範囲を絞れるので、まとめても費用は増えない。

---

## 7. dbtの設計

### 7.1 層と保存方法

| 層 | 役割 | 保存方法 |
|---|---|---|
| sources | raw・ops の定義 | — |
| staging | 表ごとに分けて意味のある列名にし、型をそろえ、マスタで名前をそろえ、最新の公表区分を選ぶ | view |
| intermediate | 調査どうしの結合と推計 | view |
| marts | ダッシュボードのページごとの集計表 | table |

> **D-08：martsだけを table にする**
> Looker Studioは画面を操作するたびにクエリを投げる。martsを小さな実テーブルにしておけば、表示が速く、クエリの費用も最小限で済む。stagingやintermediateは毎回作り直しても安いので、view にしてデータの複製を減らす。データ量が小さいので、増分更新（incremental）は使わず、毎回全件を作り直す。

### 7.2 モデルの一覧

**staging**

| モデル | 元の表 | 内容 |
|---|---|---|
| `stg_overnight__facilities` | 第1表 | 施設数 |
| `stg_overnight__stays` | 第2表 | 延べ宿泊者数（全体・外国人） |
| `stg_overnight__stays_by_facility_type` | 第4表 | 施設タイプ別の延べ宿泊者数 |
| `stg_overnight__occupancy` | 第8表 | 客室稼働率 |
| `stg_overnight__stays_by_residence` | 第9表 | 県内・県外別の延べ宿泊者数 |
| `stg_overnight__foreign_stays_by_nationality` | 参考第1表 | 国籍別の外国人延べ宿泊者数 |
| `stg_consumption__spend_by_category` | 表2-1 | 費目別の購入率と購入者単価 |
| `stg_consumption__spend_per_trip` | 表3-1 | 1人1回当たり旅行消費単価 |
| `stg_consumption__spend_per_night_by_prefecture` | 表3-4 | 訪問地別の1人1泊当たり消費単価 |
| `stg_consumption__avg_nights` | 表4-1 | 平均泊数 |
| `stg_consumption__prefecture_visit_rate` | 表6-1 | 国籍別の都道府県訪問率 |

公表区分は `seed_release_status` の順位（final ＞ preliminary2 ＞ preliminary1）で、同じ年・期の中から一番上のものを選ぶ。

**intermediate**

| モデル | 内容 |
|---|---|
| `int_nationality_yearly` | 国籍×年で、宿泊者数・消費単価・平均泊数を結合する |
| `int_prefecture_inbound_yearly` | 都道府県×年で、外国人延べ宿泊者数 × 1泊当たり消費単価 → 推計消費額を出す |

**marts**（ダッシュボードのページと1対1）

| モデル | ページ | 粒度 |
|---|---|---|
| `mart_kpi_yearly` | 1. サマリ | 年 |
| `mart_nationality_yearly` | 2. 国籍分析 | 国籍×年 |
| `mart_nationality_spend_category_yearly` | 2. 国籍分析 | 国籍×費目×年 |
| `mart_prefecture_yearly` | 3. 地域分析 | 都道府県×年 |
| `mart_prefecture_nationality_yearly` | 3. 地域分析 | 都道府県×国籍×年 |
| `mart_seasonality_monthly` | 4. 季節性 | 国籍×年×月 |
| `mart_occupancy_yearly` | 5. 宿泊の受け入れ | 都道府県×施設タイプ×年 |

> **D-09：martsはダッシュボードのページ単位で作る**
> Looker Studioでデータを結合する機能（ブレンド）は、結合できるデータの数や結合の種類に制約が多い。結合はすべてBigQueryの中で済ませ、Looker Studioは1つのグラフに1つのmartを並べるだけにする。こうすると、グラフの数字がどこから来たのかをdbtのデータの流れの図（リネージ）でたどれる。

### 7.3 シード（CSVで持つマスタ）

| シード | 列 | 用途 |
|---|---|---|
| `seed_nationality` | nationality_code、name_ja、overnight_label、consumption_label、region | 「米国/アメリカ」「英国/イギリス」の違いを吸収し、2つの調査を結合する |
| `seed_prefecture` | pref_code、name_ja、region、transport_bureau | 都道府県と地方・運輸局の対応 |
| `seed_release_status` | release_status、rank、label_ja | 公表区分の優先順位 |

> **D-10：名前の対応はシードで持つ**
> 国籍名の違いは20件程度で、ほとんど変わらない。SQLのCASE文に埋め込むと、どこで対応させているのかが分かりにくい。CSVにすればレビューしやすく、dbt docsにも載る。

### 7.4 テスト

| 種類 | 対象 | 内容 |
|---|---|---|
| 標準テスト | 全staging | 主キーに `not_null` と `unique`、`target`・`release_status` に `accepted_values` |
| リレーション | 国籍・都道府県 | 国籍名と都道府県コードが、すべてシードにあること |
| 独自テスト | `stg_overnight__stays` | 年計と月別合計の差が、全国で±10×12以内 |
| 独自テスト | overnight全般 | 年ごとの地域の数が58であること |
| 独自テスト | raw全般 | `value` が空なら、必ず `flag` が入っていること |
| 独自テスト | marts | 主要な数字（延べ宿泊者数など）の前年比が±80％を超えたら警告（コロナ期間は除く。`severity: warn`） |

> **D-11：今回手作業でした検証を、dbt testsにする**
> 宿泊旅行統計の整備では、年計＝月合計、58地域、欠けている値に必ず記号があること、を手作業で確かめた。テストにしておけば、毎回自動で確かめられる。`dbt build` はテストに失敗するとその先のモデルを更新しないので、おかしなデータがダッシュボードに出ない。

### 7.5 実行の方式（Aパターン）

```
Cloud Scheduler（毎日 04:00 JST）
  └▶ Workflows「transform」
        1. ops.ingestion_log を確認：最後に成功したdbt実行より後に、成功した取り込みがあるか
        2. なければ終わる（手動で force=true を指定したときは続ける）
        3. Cloud Run Job「dbt」を実行：dbt build --target prod（シードも含む。dbt deps はイメージを作るときに済ませる）
        4. ops.dbt_runs に結果を記録する
        5. 失敗したら通知する
```

> **D-12：dbtは1日1回、新しいデータがあるときだけ実行する（Aパターン）**
> ファイルごとにdbtを動かすと、10年分を一度に上げたときにdbtが10回同時に動き、テーブルの更新がぶつかる。取り込みはファイルごと、変換は1日1回にまとめる、と分ければ、同時に動くことによる問題が起きない。公表は年に数回なので、最大1日の遅れは問題にならない。新しいデータがない日は何もしないので、無駄な実行もない。

### 7.6 ドキュメント

- `dbt docs generate` で作ったページを、GitHub Actions で GitHub Pages に公開する。
- 全モデルと全列に説明を書く（日本語）。データの断絶や注意点は、該当するモデルの説明に書いておく。

---

## 8. Looker Studio

### 8.1 ページ構成

| ページ | 使うmart | 主なグラフ | 優先度 |
|---|---|---|---|
| 1. サマリ | `mart_kpi_yearly` | 主要な数字のカード（前年比付き）、10年の推移（コロナ期間に色を付ける） | 最初に作る |
| 2. 国籍分析 | `mart_nationality_yearly`、`mart_nationality_spend_category_yearly` | 散布図（宿泊者数×消費単価、円の大きさ＝平均泊数）、推移、費目別の積み上げ棒 | 最初に作る |
| 3. 地域分析 | `mart_prefecture_yearly`、`mart_prefecture_nationality_yearly` | 都道府県の色分け地図、都道府県×国籍のヒートマップ、推計消費額 | 最初に作る |
| 4. 季節性 | `mart_seasonality_monthly` | 月×国籍のヒートマップ、年ごとの月別推移 | 後から追加 |
| 5. 宿泊の受け入れ | `mart_occupancy_yearly` | 施設タイプ別の稼働率、都道府県別の稼働率の地図 | 後から追加 |
| 6. データについて | — | 出典、欠けている期間、調査の変更、推計の方法 | 最初に作る |

全ページ共通の絞り込み：年、国籍、都道府県

### 8.2 データへの接続と公開

- データの読み取りには、**martsだけを読める専用のサービスアカウント（`sa-looker`）を使う**。
- 公開範囲：リンクを知っている人なら誰でも見られる（閲覧のみ）。
- キャッシュの更新間隔：12時間（データの更新は1日1回以下のため）。
- カスタムクエリは使わない（martsのテーブルを直接つなぐ）。

> **D-14：Looker StudioはTerraformで管理せず、手順を文書に残す**
> Looker StudioにはTerraformのプロバイダーも、レポートを作るための公式APIもない。作り方、データソースの設定、ページの構成を `docs/looker_studio.md` に残し、もう一度作れるようにする。

> **D-15：Looker Studioはサービスアカウントでデータを読む**
> 公開したダッシュボードを「オーナーの権限」で動かすと、オーナー個人の権限でBigQueryが読まれ、raw層まで読めてしまう。martsを読む権限だけを持つサービスアカウントを使えば、ダッシュボードから触れる範囲を最小にできる。クエリの費用はプロジェクトに付き、予算アラートで見張れる。
>
> **現状（2026-11-04）**：個人の Google アカウントでは、データの認証情報に「サービス アカウント」を選べなかったため、オーナーの認証情報で接続している。閲覧者が読めるのはデータソースが指す marts のテーブルだけで、データソースを編集できるのはオーナーだけにしている。`sa-looker` と権限は残しておき、サービスアカウントが使える環境に移したら切り替える（手順は `docs/looker_studio.md`）。

---

## 9. 処理の実行（Workflows）

| ワークフロー | きっかけ | 処理 | やり直し |
|---|---|---|---|
| `ingest` | Eventarc（landing へのファイル作成） | Cloud Run Job「ingest」を、引数を上書きして実行し、終わるまで待つ | failed のときだけ、間隔を広げながら最大3回 |
| `transform` | Cloud Scheduler（毎日 04:00 JST）、手動 | ingestion_log を確認 → Cloud Run Job「dbt」→ dbt_runs に記録 | 1回 |

> **D-16：処理の制御には Workflows を使う**
> EventarcからCloud Run Jobsを直接起動することはできない。Workflowsは、実行の順番・やり直し・待ち合わせ・BigQueryへの問い合わせを設定ファイル（YAML）で書け、Terraformで管理でき、使用量も無料枠に収まる。Cloud Composer（Airflow）は常に動いているため月数万円かかり、この規模には大げさである。

---

## 10. Terraform

### 10.1 管理する範囲

| 区分 | リソース |
|---|---|
| 基盤 | 必要なAPIの有効化、Artifact Registry |
| ストレージ | GCSバケット（landing / archive / rejected） |
| DWH | BigQueryのデータセット（raw / ops / staging / intermediate / marts）、raw・ops のテーブル |
| 処理 | Cloud Run Jobs（ingest / dbt）、Workflows（ingest / transform）、Eventarcのトリガー、Cloud Scheduler |
| 権限 | サービスアカウント、IAMの割り当て、GitHub Actions用のWorkload Identity連携 |
| 監視 | ログに基づく指標、アラートの設定、通知先（メール） |

### 10.2 管理しない範囲

| 対象 | 理由 |
|---|---|
| GCPプロジェクトの作成と課金の紐付け | 最初の1回だけの作業で、課金アカウントへの権限が必要なため手作業にする |
| `{project}-tfstate` バケット | Terraformの状態ファイルを置く場所なので、Terraformより先に必要（鶏と卵の問題） |
| staging / intermediate / marts のテーブル | dbtが作る |
| Looker Studio | D-14 |
| 予算アラート | フェーズ0で課金アカウント側に手作業で設定済み。予算は課金アカウントに属し、プロジェクト用の権限だけでは管理できないため、当面は手作業のままにする |

### 10.3 構成

- 状態ファイルの置き場所：GCS（`{project}-tfstate`）
- 環境：本番だけ（`terraform/envs/prod`）。共通部分は `terraform/modules/` に分ける。

> **D-13：GCPプロジェクトは1つにし、開発用はデータセットで分ける**
> 学習・ポートフォリオ用なので、開発用と本番用でプロジェクトを分けると、管理と費用の手間がかかる割に得るものが小さい。dbtの開発やCIはデータセット（`dbt_{開発者名}`、`ci_pr_{番号}`）で分ければ十分に切り離せる。将来プロジェクトを分ける場合も、モジュールに分けた構成ならそのまま使い回せる。

---

## 11. 権限（IAM）

| サービスアカウント | 用途 | 主な権限 |
|---|---|---|
| `sa-ingest` | 取り込み処理 | 3つのバケットのオブジェクト管理者、`raw`・`ops` のデータ編集者、プロジェクトのジョブユーザー |
| `sa-dbt` | dbt | `raw`・`ops` のデータ閲覧者、`staging`・`intermediate`・`marts` のデータ編集者、ジョブユーザー |
| `sa-workflows` | Workflows | ジョブ単位の実行権限（ingest は引数の上書きあり、dbt はなし）、ジョブの終了を待つためのカスタムロール（`run.operations.get`・`run.executions.get`）、`ops` のデータ編集者、ジョブユーザー、ログの書き込み |
| `sa-eventarc` | Eventarcのトリガー | Workflowsの起動者、イベントの受信者 |
| `sa-scheduler` | Cloud Scheduler | Workflowsの起動者 |
| `sa-looker` | Looker Studio | `marts` のデータ閲覧者、ジョブユーザー |
| `sa-github-deployer` | GitHub Actions | Terraformの適用とイメージの送信に必要な権限（GitHubのmainブランチと本番環境だけに限定） |
| （GCSのサービスエージェント） | Eventarcへのイベント送信 | **`pubsub.publisher`**（付け忘れるとイベントが届かない） |

> **D-17：処理ごとにサービスアカウントを分け、権限を最小限にする**
> 1つのサービスアカウントにまとめると、どこか1か所に問題が起きたとき、すべてに影響が広がる。分けておけば、たとえばLooker Studio経由でrawを読まれることも、dbtが元ファイルを消すことも、構造的に起こらない。またIAMの設計そのものがポートフォリオの見せ場になる。

> **D-18：GitHub Actionsはキーを使わずに認証する（Workload Identity連携）**
> サービスアカウントのキー（JSON）をGitHubのシークレットに置くと、漏れたときの被害が大きく、定期的な更新も必要になる。Workload Identity連携ならキーが存在しない。さらに、認証できるのは特定のリポジトリとブランチだけに限定できる。

> **D-19：取り込み処理ではe-Stat APIを使わない**
> 取り込みの対象はアップロードされたExcelだけで、APIキーは必要ない。そのためSecret Managerも使わない。APIは、手元のノートブックで探したり検証したりするときにだけ使う。

---

## 12. CI/CD（GitHub Actions）

| きっかけ | ジョブ | 内容 |
|---|---|---|
| PR | `lint-test` | Pythonの静的検査（ruff）、ingestの単体テスト（pytest。小さなExcelの見本で、変換と構造検査を確かめる） |
| PR | `terraform-plan` | `fmt` → `validate` → `plan`。plan の結果をPRにコメントする |
| PR | `dbt-ci` | `ci_pr_{番号}` データセットに対して `dbt build` を実行する（rawは本番のものを読むだけ） |
| PRを閉じたとき | `dbt-ci-cleanup` | `ci_pr_{番号}` データセットを消す |
| mainへのマージ | `build-push` | ingest用・dbt用のコンテナイメージを作り、コミットのSHAをタグにしてArtifact Registryへ送る |
| mainへのマージ | `terraform-apply` | GitHubの本番環境の承認を経てから apply する（新しいイメージのタグを渡す） |
| mainへのマージ | `dbt-docs` | dbt docsを作り、GitHub Pagesに公開する |

> **D-20：dbtのCIは、本番のrawを読み、PR専用のデータセットに書き出す**
> 見本データだけでテストすると、本物のデータでしか起きない問題を見逃す。rawは読むだけにすれば本番に影響はない。PRごとにデータセットを分けるので、複数のPRが同時に動いてもぶつからない。

---

## 13. 監視と通知

| 監視の対象 | 方法 | 通知 |
|---|---|---|
| ingest の rejected / failed | ログに基づく指標 → アラート | メール |
| transform の失敗（dbtテストの不合格を含む） | Workflowsの実行失敗 → アラート | メール |
| 費用 | 予算アラート（手作業で設定。10.2） | メール |

---

## 14. 費用の見込み

| サービス | 使用量の見込み | 月額の目安 |
|---|---|---|
| BigQuery | 保存 1GB未満、クエリ 数GB/月 | 無料枠内 |
| Cloud Storage | 元ファイル 数十MB | ほぼ0円 |
| Cloud Run Jobs | 月に数回〜数十回、各数分 | 無料枠内 |
| Workflows / Eventarc / Scheduler | 毎日1回＋アップロード時 | 無料枠内 |
| Artifact Registry | イメージ 1GB程度 | 数十円 |
| **合計** | | **0〜数百円** |

---

## 15. リポジトリの構成

```
.
├── ingest/                     # 取り込み処理（Pythonパッケージ）
│   ├── src/ingest/
│   │   ├── main.py             # 入口（引数：オブジェクト名・世代番号）
│   │   ├── path_rules.py       # パスの検証（4.2節）
│   │   ├── parsers/            # overnight.py / consumption.py
│   │   ├── validation.py       # 構造の検査
│   │   └── bq_writer.py        # 一時テーブルへの読み込みとトランザクションでの入れ替え
│   ├── header_defs/            # 見出しの定義（D-06）
│   ├── tests/                  # 単体テストと小さなExcelの見本
│   └── Dockerfile
├── dbt/
│   ├── models/{staging,intermediate,marts}/
│   ├── seeds/
│   ├── tests/                  # 独自テスト
│   ├── macros/
│   ├── dbt_project.yml / profiles.yml
│   └── Dockerfile
├── workflows/                  # ingest.yaml / transform.yaml
├── terraform/
│   ├── modules/                # storage / bigquery / pipeline / iam / monitoring
│   └── envs/prod/
├── notebooks/                  # 今あるノートブック（探索・検証用）
├── docs/                       # 仕様書、作業レポート、looker_studio.md
├── scripts/                    # 見出し定義の作成、初回の一括アップロード
└── .github/workflows/
```

- `.env`、`data/`、`*.tfstate` はGitで管理しない。
- 今あるスクリプトとレポートは、それぞれ `ingest/` と `docs/` に移す。

---

## 16. 開発の進め方

| フェーズ | 内容 | 終わったと言える状態 |
|---|---|---|
| 0. 準備 | Gitリポジトリ、Python 3.12と uv、ディレクトリ構成、GCPプロジェクトとtfstateバケットを手作業で作る | GitHubにリポジトリがある |
| 1. 基盤 | Terraformでバケット・データセット・raw/opsのテーブル・サービスアカウントを作る | `terraform apply` で環境ができる |
| 2. 1本通す | 宿泊の第2表だけで、ingest（手元から実行）→ raw → dbt（staging・marts 1つずつ）→ Looker Studioのページ1 | ダッシュボードに数字が出る |
| 3. イベント駆動にする | Eventarc・Workflows・Cloud Run Jobs・Scheduler を作り、アップロードをきっかけに動かす | 10年分をアップロードすると、翌日にはmartsが更新されている |
| 4. 広げる | 消費動向の変換処理（5表）、シード、全モデル、ページ2・3・6 | 最初に作るページがそろう |
| 5. 品質とCI/CD | dbt tests、PRでのCI、mainでのデプロイ、dbt docsの公開、監視 | PRでテストが動き、マージするとデプロイされる |
| 6. 仕上げ | ページ4・5、README、アーキテクチャ図、`docs/looker_studio.md` | 第三者が読んで再現できる |

> **D-21：最初に「1本の細い流れ」を最後まで通す**
> 層ごとに横へ広げていくと、最後の可視化までたどり着かないまま時間を使い切りやすい。フェーズ2で全部の層がつながるので、それ以降はどこで止めても成果物として成り立つ。設計の問題（列が足りない、粒度が合わない、など）も早く見つかる。

---

## 17. 未確定事項とリスク

| 項目 | 内容 | 対応 |
|---|---|---|
| 消費動向調査の2024年以降の形式 | 2024年4–6月期からの新調査で表の構成が変わったかどうか、まだ確かめていない（暦年の2024・2025年は旧調査と同じ44シートだった） | フェーズ4の最初に、四半期ファイルも含めて確認する |
| 消費動向調査の四半期ファイルの形式 | 暦年ファイルしか中身を見ていない | 同上 |
| 消費動向の変換処理 | まだ作っていない（今はシートを写したCSVだけ） | フェーズ4で作る。宿泊の見出し定義の考え方を使う |
| 都道府県別の推計消費額 | 1泊当たり消費単価のサンプル数が少ない県では値がぶれる | 回答数が一定以下の県には印を付け、ダッシュボードに注記する |
| 報道発表の値と一致しない | 表3-1はパッケージツアー代金の内訳を含まない | 将来「参考1」を取り込む対象に加えることを検討する |
| 宿泊旅行統計の旧形式の検証 | 2017〜2019年は列の対応だけを確かめている | 主要な値を公表値と照らし合わせるテストを足す |
| 公開ダッシュボードの費用 | 閲覧が増えるとクエリの費用が増える | martsを小さく保ち、キャッシュを効かせ、予算アラートで見張る |

---

## 付録：設計判断の一覧

| ID | 判断 | 節 |
|---|---|---|
| D-01 | フォルダではなくバケットを分ける | 4.1 |
| D-02 | ファイルの種類はパスのルールで見分ける | 4.2 |
| D-03 | 新しい公表の通知・自動検出はスコープ外 | 4.2 |
| D-04 | データの誤りと一時的なエラーを分ける | 5.2 |
| D-05 | 追記ではなく、決まった単位で丸ごと入れ替える | 5.4 |
| D-06 | 見出しの定義をコードとしてリポジトリで管理する | 5.5 |
| D-07 | rawは表ごとではなく、調査ごとに1つの縦持ちテーブルにする | 6.3 |
| D-08 | martsだけを table にする | 7.1 |
| D-09 | martsはダッシュボードのページ単位で作る | 7.2 |
| D-10 | 名前の対応はシードで持つ | 7.3 |
| D-11 | 今回手作業でした検証を、dbt testsにする | 7.4 |
| D-12 | dbtは1日1回、新しいデータがあるときだけ実行する（Aパターン） | 7.5 |
| D-13 | GCPプロジェクトは1つにし、開発用はデータセットで分ける | 10.3 |
| D-14 | Looker StudioはTerraformで管理せず、手順を文書に残す | 8.2 |
| D-15 | Looker Studioはサービスアカウントでデータを読む | 8.2 |
| D-16 | 処理の制御には Workflows を使う | 9 |
| D-17 | 処理ごとにサービスアカウントを分け、権限を最小限にする | 11 |
| D-18 | GitHub Actionsはキーを使わずに認証する | 11 |
| D-19 | 取り込み処理ではe-Stat APIを使わない | 11 |
| D-20 | dbtのCIは、本番のrawを読み、PR専用のデータセットに書き出す | 12 |
| D-21 | 最初に「1本の細い流れ」を最後まで通す | 16 |
