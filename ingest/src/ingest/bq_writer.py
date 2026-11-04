"""BigQuery への書き込み：raw の入れ替えと、取り込み記録（ops.ingestion_log）"""

import uuid
from datetime import UTC, datetime, timedelta

import pandas as pd
from google.api_core import exceptions, retry
from google.cloud import bigquery

RAW_TABLES = {"overnight": "raw.overnight_cells", "consumption": "raw.consumption_cells"}
LOG_TABLE = "ops.ingestion_log"


def is_concurrent_update(exc: Exception) -> bool:
    """同じテーブルを入れ替えるトランザクションが同時に走り、片方が中断されたか"""
    return isinstance(exc, exceptions.GoogleAPICallError) and "concurrent update" in str(exc).lower()


# 複数のファイルを一度に上げると、raw の同じテーブルへのトランザクションがぶつかって中断される。
# 待てば通るので、Excel の解析からやり直す（Workflows のやり直し）前に、ここで間隔を空けてやり直す
CONFLICT_RETRY = retry.Retry(predicate=is_concurrent_update, initial=5.0, maximum=60.0, multiplier=2.0, timeout=600.0)


class Warehouse:
    def __init__(self, project: str, client: bigquery.Client | None = None):
        self.project = project
        self.client = client or bigquery.Client(project=project)
        self.conflict_retry = CONFLICT_RETRY

    def _query(self, sql: str, **params) -> bigquery.table.RowIterator:
        query_params = [bigquery.ScalarQueryParameter(k, _bq_type(v), v) for k, v in params.items()]
        job = self.client.query(sql, job_config=bigquery.QueryJobConfig(query_parameters=query_params))
        return job.result()

    def replace_raw(self, survey: str, df: pd.DataFrame, key: dict) -> int:
        """一時テーブルに読み込み、トランザクションで該当範囲を DELETE → INSERT する（仕様書 5.4、D-05）"""
        target = self.client.get_table(f"{self.project}.{RAW_TABLES[survey]}")
        columns = [f.name for f in target.schema]
        tmp_id = f"{self.project}.raw._tmp_{uuid.uuid4().hex}"
        load = bigquery.LoadJobConfig(schema=target.schema, write_disposition="WRITE_TRUNCATE")
        self.client.load_table_from_dataframe(df[columns], tmp_id, job_config=load).result()
        try:
            # 後片付けに失敗しても残らないよう、一時テーブルには有効期限を付ける
            tmp = self.client.get_table(tmp_id)
            tmp.expires = datetime.now(UTC) + timedelta(hours=1)
            self.client.update_table(tmp, ["expires"])

            where = " AND ".join(f"{k} = @{k}" for k in key)
            col_list = ", ".join(columns)
            self.conflict_retry(self._query)(
                f"""
                BEGIN TRANSACTION;
                DELETE FROM `{target.full_table_id.replace(":", ".")}` WHERE {where};
                INSERT INTO `{target.full_table_id.replace(":", ".")}` ({col_list}) SELECT {col_list} FROM `{tmp_id}`;
                COMMIT TRANSACTION;
                """,
                **key,
            )
        finally:
            self.client.delete_table(tmp_id, not_found_ok=True)
        return len(df)

    def already_succeeded(self, source_uri: str, generation: int) -> bool:
        rows = self._query(
            f"SELECT 1 FROM `{self.project}.{LOG_TABLE}` "
            "WHERE source_uri = @source_uri AND generation = @generation AND status = 'succeeded' LIMIT 1",
            source_uri=source_uri,
            generation=generation,
        )
        return rows.total_rows > 0

    def insert_log(self, **fields) -> None:
        # ストリーミング挿入だと直後に UPDATE できないため、DML で入れる
        cols = ", ".join(fields)
        values = ", ".join(f"@{k}" for k in fields)
        self._query(f"INSERT INTO `{self.project}.{LOG_TABLE}` ({cols}) VALUES ({values})", **fields)

    def update_log(self, source_uri: str, generation: int, started_at: datetime, **fields) -> None:
        sets = ", ".join(f"{k} = @{k}" for k in fields)
        self._query(
            f"UPDATE `{self.project}.{LOG_TABLE}` SET {sets} "
            "WHERE source_uri = @source_uri AND generation = @generation AND started_at = @started_at",
            source_uri=source_uri,
            generation=generation,
            started_at=started_at,
            **fields,
        )


def _bq_type(value) -> str:
    if isinstance(value, bool):
        return "BOOL"
    if isinstance(value, int):
        return "INT64"
    if isinstance(value, float):
        return "FLOAT64"
    if isinstance(value, datetime):
        return "TIMESTAMP"
    return "STRING"
