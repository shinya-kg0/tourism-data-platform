from unittest.mock import MagicMock

import pandas as pd
import pytest
from google.api_core import exceptions
from google.cloud import bigquery

from ingest.bq_writer import CONFLICT_RETRY, Warehouse, is_concurrent_update

CONFLICT = exceptions.BadRequest("Transaction is aborted due to concurrent update against table p:raw.overnight_cells")


@pytest.mark.parametrize(
    "exc, expected",
    [
        (CONFLICT, True),
        (exceptions.BadRequest("Syntax error: Unexpected keyword"), False),
        (ValueError("concurrent update"), False),
    ],
)
def test_is_concurrent_update(exc, expected):
    assert is_concurrent_update(exc) is expected


def make_warehouse():
    client = MagicMock()
    client.get_table.return_value.schema = [bigquery.SchemaField("year", "INT64")]
    client.get_table.return_value.full_table_id = "p:raw.overnight_cells"
    wh = Warehouse("p", client=client)
    wh.conflict_retry = CONFLICT_RETRY.with_delay(initial=0.01, maximum=0.01)
    return wh


def test_replace_raw_retries_on_concurrent_update(monkeypatch):
    wh = make_warehouse()
    calls = []

    def query(sql, **params):
        calls.append(sql)
        if len(calls) == 1:
            raise CONFLICT

    monkeypatch.setattr(wh, "_query", query)
    assert wh.replace_raw("overnight", pd.DataFrame({"year": [2025]}), {"year": 2025}) == 1
    assert len(calls) == 2
    wh.client.delete_table.assert_called_once()


def test_replace_raw_does_not_retry_other_errors(monkeypatch):
    wh = make_warehouse()
    calls = []

    def query(sql, **params):
        calls.append(sql)
        raise exceptions.BadRequest("Syntax error")

    monkeypatch.setattr(wh, "_query", query)
    with pytest.raises(exceptions.BadRequest):
        wh.replace_raw("overnight", pd.DataFrame({"year": [2025]}), {"year": 2025})
    assert len(calls) == 1
    wh.client.delete_table.assert_called_once()
