"""Cloud Run Job「ingest」の入口。

引数で GCS のオブジェクト名と世代番号を受け取り、1 ファイルを raw 層へ取り込む（仕様書 5.1）。

    ingest overnight/annual/2025.xlsx --generation 1730000000000000

環境変数:
    GCP_PROJECT_ID          必須
    LANDING_BUCKET など     省略時は {project}-landing / -archive / -rejected
    WORKFLOW_EXECUTION_ID   Workflows から渡される実行 ID（任意）

終了コード（仕様書 5.2、D-04）:
    0  succeeded / skipped / rejected（データの誤りはやり直さない）
    1  failed（一時的なエラー。Workflows がやり直す）
"""

import argparse
import json
import logging
import os
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from ingest.bq_writer import Warehouse
from ingest.gcs import Store
from ingest.parsers import overnight
from ingest.path_rules import PathRuleError, parse_path
from ingest.validation import StructureError

PARSERS = {"overnight": overnight}

log = logging.getLogger("ingest")


def run(object_name: str, generation: int, store, warehouse, execution_id: str | None = None) -> int:
    source_uri = store.uri(object_name)
    started_at = datetime.now(UTC)
    base = {"source_uri": source_uri, "generation": generation, "started_at": started_at}

    if warehouse.already_succeeded(source_uri, generation):
        warehouse.insert_log(**base, status="skipped", finished_at=datetime.now(UTC))
        return _report("skipped", source_uri, generation)

    warehouse.insert_log(**base, status="running", workflow_execution_id=execution_id)
    try:
        src = parse_path(object_name)
        if src.survey not in PARSERS:
            raise PathRuleError(f"{src.survey} の取り込みはまだ実装されていません")
        parser = PARSERS[src.survey]

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / Path(object_name).name
            md5 = store.download(object_name, generation, path)
            df, format_version = parser.parse_workbook(path, src.year, parser.load_header_defs())

        df = df.assign(
            release_status=src.release_status,
            format_version=format_version,
            source_uri=source_uri,
            source_generation=generation,
            ingested_at=datetime.now(UTC),
        )
        rows = warehouse.replace_raw(src.survey, df, src.replace_key)
        store.move(object_name, generation, "archive")
        warehouse.update_log(
            source_uri, generation, started_at,
            status="succeeded", md5=md5, survey=src.survey, period_type=src.period_type, year=src.year,
            quarter=src.quarter, release_status=src.release_status, row_count=rows,
            finished_at=datetime.now(UTC),
        )  # fmt: skip
        return _report("succeeded", source_uri, generation, rows=rows)

    except (PathRuleError, StructureError) as e:
        moved_to = store.move(object_name, generation, "rejected")
        warehouse.update_log(
            source_uri, generation, started_at,
            status="rejected", error_message=str(e), finished_at=datetime.now(UTC),
        )  # fmt: skip
        return _report("rejected", source_uri, generation, error=str(e), moved_to=moved_to)

    except Exception as e:
        log.exception("取り込みに失敗しました")
        try:
            warehouse.update_log(
                source_uri, generation, started_at,
                status="failed", error_message=f"{type(e).__name__}: {e}", finished_at=datetime.now(UTC),
            )  # fmt: skip
        except Exception:
            log.exception("取り込み記録の更新にも失敗しました")
        _report("failed", source_uri, generation, error=str(e))
        return 1


def _report(status: str, source_uri: str, generation: int, **extra) -> int:
    """結果を 1 行の JSON で出す（Cloud Logging の構造化ログ。rejected / failed は監視の対象）"""
    severity = {"rejected": "WARNING", "failed": "ERROR"}.get(status, "INFO")
    record = {"severity": severity, "status": status, "source_uri": source_uri, "generation": generation, **extra}
    print(json.dumps(record, ensure_ascii=False), flush=True)
    return 0


def main(argv: list[str] | None = None) -> None:
    logging.basicConfig(level=logging.INFO)
    ap = argparse.ArgumentParser(description="GCS の Excel を raw 層に取り込む")
    ap.add_argument("object_name", help="landing バケット内のオブジェクト名")
    ap.add_argument("--generation", type=int, required=True, help="オブジェクトの世代番号")
    args = ap.parse_args(argv)

    project = os.environ["GCP_PROJECT_ID"]
    buckets = {k: os.environ.get(f"{k.upper()}_BUCKET", f"{project}-{k}") for k in ["landing", "archive", "rejected"]}
    code = run(
        args.object_name,
        args.generation,
        Store(project, buckets),
        Warehouse(project),
        execution_id=os.environ.get("WORKFLOW_EXECUTION_ID"),
    )
    sys.exit(code)


if __name__ == "__main__":
    main()
