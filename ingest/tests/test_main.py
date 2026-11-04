from pathlib import Path

import pandas as pd
import pytest

from ingest import main
from ingest.gcs import suffixed_name
from ingest.validation import StructureError


class FakeStore:
    def __init__(self):
        self.moved = []

    def uri(self, name):
        return f"gs://landing/{name}"

    def download(self, name, generation, dest: Path):
        dest.write_bytes(b"dummy")
        return "md5=="

    def move(self, name, generation, to):
        self.moved.append(to)
        return f"gs://{to}/{suffixed_name(name, generation)}"


class FakeWarehouse:
    def __init__(self, succeeded=False):
        self.succeeded = succeeded
        self.logs = []
        self.replaced = None

    def already_succeeded(self, uri, generation):
        return self.succeeded

    def insert_log(self, **fields):
        self.logs.append(dict(fields))

    def update_log(self, uri, generation, started_at, **fields):
        self.logs[-1].update(fields)

    def replace_raw(self, survey, df, key):
        self.replaced = (survey, df, key)
        return len(df)


@pytest.fixture
def fake_parser(monkeypatch):
    def parse_workbook(path, year, defs):
        return pd.DataFrame({"year": [year], "value": [1.0]}), "overnight_v2"

    monkeypatch.setattr(main.overnight, "parse_workbook", parse_workbook)
    monkeypatch.setattr(main.overnight, "load_header_defs", dict)


def test_suffixed_name():
    assert suffixed_name("overnight/annual/2025.xlsx", 123) == "overnight/annual/2025__123.xlsx"


def test_run_succeeded(fake_parser):
    store, wh = FakeStore(), FakeWarehouse()
    assert main.run("overnight/annual/2025.xlsx", 7, store, wh) == 0
    survey, df, key = wh.replaced
    assert survey == "overnight" and key == {"year": 2025, "release_status": "final"}
    assert df["source_generation"].iloc[0] == 7 and df["format_version"].iloc[0] == "overnight_v2"
    assert store.moved == ["archive"]
    assert wh.logs[-1]["status"] == "succeeded" and wh.logs[-1]["row_count"] == 1


def test_run_skipped_when_already_succeeded(fake_parser):
    store, wh = FakeStore(), FakeWarehouse(succeeded=True)
    assert main.run("overnight/annual/2025.xlsx", 7, store, wh) == 0
    assert wh.replaced is None and store.moved == []
    assert wh.logs[-1]["status"] == "skipped"


def test_run_rejected_on_bad_path():
    store, wh = FakeStore(), FakeWarehouse()
    assert main.run("overnight/2025.xlsx", 7, store, wh) == 0
    assert store.moved == ["rejected"]
    assert wh.logs[-1]["status"] == "rejected" and "ルール" in wh.logs[-1]["error_message"]


def test_run_rejected_on_structure_error(monkeypatch, fake_parser):
    def broken(path, year, defs):
        raise StructureError("列数が一致しません")

    monkeypatch.setattr(main.overnight, "parse_workbook", broken)
    store, wh = FakeStore(), FakeWarehouse()
    assert main.run("overnight/annual/2025.xlsx", 7, store, wh) == 0
    assert store.moved == ["rejected"] and wh.logs[-1]["status"] == "rejected"


def test_run_failed_on_unexpected_error(fake_parser):
    class BrokenWarehouse(FakeWarehouse):
        def replace_raw(self, survey, df, key):
            raise RuntimeError("BigQuery unavailable")

    store, wh = FakeStore(), BrokenWarehouse()
    assert main.run("overnight/annual/2025.xlsx", 7, store, wh) == 1
    assert store.moved == []  # 一時的なエラーでは landing に残し、やり直しを待つ
    assert wh.logs[-1]["status"] == "failed"
