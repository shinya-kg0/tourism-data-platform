import pandas as pd
import pytest

from ingest.parsers.overnight import FORMAT_NEW, FORMAT_OLD, parse_sheet, parse_workbook, read_new_header
from ingest.path_rules import parse_path
from ingest.validation import StructureError

COLUMNS = [
    {"position": 1, "target": "全体", "group": "G", "sub": None, "item": "延べ宿泊者数", "unit": "人泊"},
    {"position": 2, "target": "全体", "group": "G", "sub": "A", "item": "計", "unit": "人泊"},
    {"position": 3, "target": "外国人", "group": None, "sub": None, "item": "うち外国人延べ宿泊者数", "unit": "人泊"},
]


def new_format_sheet(item2="計"):
    return pd.DataFrame([
        ["第２表 タイトル", None, None, None],
        [None, None, None, None],
        [None, None, None, None],
        [None, "G", "G", None],
        [None, None, "A", None],
        ["施設所在地", "延べ宿泊者数", item2, "うち外国人延べ宿泊者数"],
        [None, "人泊", "人泊", "人泊"],
        ["令和7年4月", 100, 60, "*20,520"],
        ["　01北海道", 10, "-", 5],
        ["1)宿泊目的割合不詳を含む。", None, None, None],
    ])  # fmt: skip


def old_format_sheet(extra_column=False):
    rows = [
        ["第２表 タイトル", None, None, None],
        [None, None, None, None],
        [None, None, None, None],
        ["施設所在地", "延べ\n宿泊者数\n1)", "G", "うち外国人"],
        [None, None, "A", None],
        [None, None, "1)", None],
        ["平成28年 1～12月 計", 100, 60, 7],
        ["　北海道", 10, 5, 1],
    ]
    if extra_column:
        rows = [r + (["X"] if i == 3 else [None]) for i, r in enumerate(rows)]
    return pd.DataFrame(rows)


def test_read_new_header_matches_definition():
    df = new_format_sheet()
    assert read_new_header(df, 6) == COLUMNS


def test_parse_new_format():
    long, fmt = parse_sheet(new_format_sheet(), COLUMNS, "test")
    assert fmt == FORMAT_NEW
    assert len(long) == 6  # 2 地域 × 3 列（注記の行は除く）
    assert set(long["area_name"]) == {"全国", "北海道"}

    hokkaido = long[long["area_name"] == "北海道"].set_index("header_item")
    assert hokkaido["area_code"].iloc[0] == "01"
    assert pd.isna(hokkaido.loc["計", "value"]) and hokkaido.loc["計", "flag"] == "-"

    zenkoku_foreign = long[(long["area_name"] == "全国") & (long["target"] == "外国人")].iloc[0]
    assert zenkoku_foreign["value"] == 20520 and zenkoku_foreign["flag"] == "*"


def test_parse_new_format_accepts_footnote_only_label():
    long, _ = parse_sheet(new_format_sheet(item2="1)"), COLUMNS, "test")
    assert "計" in set(long["header_item"])  # 見出しは定義のものを使う


def test_parse_new_format_rejects_different_label():
    with pytest.raises(StructureError, match="2列目の項目"):
        parse_sheet(new_format_sheet(item2="観光目的の宿泊者が50％以上"), COLUMNS, "test")


def test_parse_old_format():
    long, fmt = parse_sheet(old_format_sheet(), COLUMNS, "test")
    assert fmt == FORMAT_OLD
    zenkoku = long[long["area_name"] == "全国"].set_index("header_item")["value"]
    assert zenkoku.to_dict() == {"延べ宿泊者数": 100, "計": 60, "うち外国人延べ宿泊者数": 7}
    assert long.loc[long["area_name"] == "北海道", "area_code"].isna().all()  # 2016 年はコードなし


def test_parse_old_format_rejects_column_count_mismatch():
    with pytest.raises(StructureError, match="列数"):
        parse_sheet(old_format_sheet(extra_column=True), COLUMNS, "test")


def test_parse_rejects_unexplained_value():
    df = new_format_sheet()
    df.iat[8, 1] = "abc"
    with pytest.raises(StructureError, match="数値でも記号でもない"):
        parse_sheet(df, COLUMNS, "test")


@pytest.fixture
def workbook(tmp_path):
    path = tmp_path / "2025.xlsx"
    with pd.ExcelWriter(path) as writer:
        for name in ["第2表(年計)", "第2表(1月)", "第3表(年計)"]:
            new_format_sheet().to_excel(writer, sheet_name=name, header=False, index=False)
    return path


def test_parse_workbook(workbook):
    defs = {"第2表": {"table_id": "第2表", "periods": ["年計", "1月"], "columns": COLUMNS}}
    df, fmt = parse_workbook(workbook, parse_path("overnight/annual/2025.xlsx"), defs)
    assert fmt == FORMAT_NEW
    assert set(df["table_id"]) == {"第2表"}  # 定義のない第3表は読まない
    assert sorted(df["month"].unique()) == [0, 1]
    assert (df["year"] == 2025).all()


def test_parse_workbook_rejects_missing_sheet(workbook):
    defs = {"第2表": {"table_id": "第2表", "periods": ["年計", "1月", "2月"], "columns": COLUMNS}}
    with pytest.raises(StructureError, match="2月"):
        parse_workbook(workbook, parse_path("overnight/annual/2025.xlsx"), defs)
