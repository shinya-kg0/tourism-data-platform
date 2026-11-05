import pandas as pd
import pytest

from ingest.parsers.consumption import detect_format, parse_sheet, parse_workbook, read_rows
from ingest.path_rules import parse_path
from ingest.validation import StructureError

MEASURES = [{"label": "回答数", "unit": "人"}, {"label": "消費単価", "unit": "円"}]
DEF = {
    "table_id": "表3-1",
    "sheet": "表3-1",
    "col_dimension": "国籍･地域",
    "releases": ["preliminary1", "preliminary2", "final"],
    "members": ["全国籍･地域", "韓国"],
    "blocks": [{"measures": MEASURES}],
}
REGIONAL_DEF = {**DEF, "table_id": "表6-1", "sheet": "表6-1", "releases": ["preliminary2", "final"]}


def sheet(period="2025年7-9月期 【確報】", member2="韓国", measure="消費単価"):
    """表3-1 の形を小さくしたもの（大分類が数行に分かれる、内訳の行がある、注記がある）"""
    return pd.DataFrame([
        [None, None, None, None, None, None, None, None],
        [None, "表3-1　国籍･地域（21区分）別　１人１回当たり旅行消費単価", None, None, None, None, None, None],
        [None, None, None, None, None, None, None, None],
        [None, period, None, None, None, None, None, None],
        [None, "調査項目", None, None, "全国籍･地域", None, member2, None],
        [None, None, None, None, "回答数", measure, "回答数", measure],
        [None, "全体　【A1】", None, None, 100, 200000.5, 10, 98000],
        [None, "性別・年代", "男性", None, 50, 210000, 5, "-"],
        [None, "（単一回答）", None, "15～19歳", 3, 190000, 0, "-"],
        [None, "【A1】", "女性", None, 50, 190000, 5, 97000],
        [None, None, None, None, None, None, None, None],
        [None, "帰国に利用した", "FSA", None, 80, 230000, 8, 99000],
        [None, "交通手段", "LCC", None, 20, 150000, 2, 90000],
        [None, "注１　参考値", None, None, None, None, None, None],
    ])  # fmt: skip


def test_parse_sheet():
    long = parse_sheet(sheet(), DEF, "test")
    assert set(long["col_member"]) == {"全国籍･地域", "韓国"}
    assert set(long["measure"]) == {"回答数", "消費単価"}

    total = long[(long["row_category"] == "全体") & (long["col_member"] == "全国籍･地域")].set_index("measure")
    assert total.loc["消費単価", "value"] == 200000.5 and total.loc["消費単価", "unit"] == "円"
    assert total["row_item"].isna().all()


def test_parse_sheet_joins_category_lines_and_sub_items():
    long = parse_sheet(sheet(), DEF, "test")
    items = long.groupby("row_category", sort=False)["row_item"].unique().map(list).to_dict()
    assert items["性別・年代"] == ["男性", "男性／15～19歳", "女性"]  # 【A1】の行も同じ大分類
    assert items["帰国に利用した交通手段"] == ["FSA", "LCC"]


def test_parse_sheet_keeps_flag():
    long = parse_sheet(sheet(), DEF, "test")
    korea = long[(long["col_member"] == "韓国") & (long["row_item"] == "男性") & (long["measure"] == "消費単価")]
    assert korea["value"].isna().all() and (korea["flag"] == "-").all()


def test_parse_sheet_rejects_different_member():
    with pytest.raises(StructureError, match="国籍･地域が定義と違います"):
        parse_sheet(sheet(member2="台湾"), DEF, "test")


def test_parse_sheet_rejects_different_measure():
    with pytest.raises(StructureError, match="指標が定義と違います"):
        parse_sheet(sheet(measure="平均泊数"), DEF, "test")


def test_parse_sheet_rejects_unexplained_value():
    df = sheet()
    df.iat[7, 5] = "abc"
    with pytest.raises(StructureError, match="数値でも記号でもない"):
        parse_sheet(df, DEF, "test")


def test_read_rows_old_format_footnote_marker():
    """2017 年：大分類に注記の番号（「１）」）が付き、【A1】がない"""
    df = pd.DataFrame([
        [None, "旅行前支出", "団体パッケージツアー", None, 1, 2],
        [None, "１）", "個人旅行向けパッケージ商品", None, 1, 2],
        [None, None, "往復航空（船舶）運賃", None, 1, 2],
        [None, "日本滞在中の", "宿泊料金", None, 1, 2],
        [None, "費目別支出", "飲食費 ２）", None, 1, 2],
        [None, None, None, None, "１）回答者１人当たりの支出額を円に換算", None],
    ])  # fmt: skip
    rows = read_rows(df, 0, len(df), [4, 5])
    assert [(c, i) for _, c, i in rows] == [
        ("旅行前支出", "団体パッケージツアー"),
        ("旅行前支出", "個人旅行向けパッケージ商品"),
        ("旅行前支出", "往復航空（船舶）運賃"),
        ("日本滞在中の費目別支出", "宿泊料金"),
        ("日本滞在中の費目別支出", "飲食費"),
    ]  # 注記の行は読まず、項目の後ろの注記の番号は除く


@pytest.fixture
def workbook(tmp_path):
    def make(name="2025_Q3.xlsx", sheets=("表3-1", "表6-1"), **kwargs):
        path = tmp_path / name
        with pd.ExcelWriter(path) as writer:
            for s in sheets:
                sheet(**kwargs).to_excel(writer, sheet_name=s, header=False, index=False)
        return path

    return make


DEFS = {
    "consumption_v3": {"表3-1": {**DEF, "members": ["全国籍･地域", "韓国", "中東"]}},
    "consumption_v2": {"表3-1": DEF, "表6-1": REGIONAL_DEF},
}


def test_parse_workbook(workbook):
    df, version = parse_workbook(workbook(), parse_path("consumption/quarterly/2025_Q3.xlsx"), DEFS)
    assert version == "consumption_v2"  # v3 は国籍が合わない
    assert set(df["table_id"]) == {"表3-1", "表6-1"}
    assert (df["year"] == 2025).all() and (df["quarter"] == 3).all()


def test_parse_workbook_preliminary1_skips_regional_tables(workbook):
    path = workbook(sheets=("表3-1",), period="2025年7-9月期 【1次速報】")
    df, _ = parse_workbook(path, parse_path("consumption/quarterly/2025_Q3_preliminary1.xlsx"), DEFS)
    assert set(df["table_id"]) == {"表3-1"}


def test_parse_workbook_rejects_missing_sheet(workbook):
    with pytest.raises(StructureError, match="表6-1"):
        parse_workbook(workbook(sheets=("表3-1",)), parse_path("consumption/quarterly/2025_Q3.xlsx"), DEFS)


@pytest.mark.parametrize(
    "object_name",
    [
        "consumption/quarterly/2024_Q3.xlsx",  # 年が違う
        "consumption/quarterly/2025_Q2.xlsx",  # 期が違う
        "consumption/annual/2025.xlsx",  # 暦年ではない
        "consumption/quarterly/2025_Q3_preliminary2.xlsx",  # 公表区分が違う
    ],
)
def test_parse_workbook_rejects_period_mismatch(workbook, object_name):
    with pytest.raises(StructureError, match="パスと違います"):
        parse_workbook(workbook(), parse_path(object_name), DEFS)


def test_parse_workbook_annual(workbook):
    path = workbook(period="2025年（令和7年）  暦年　【確報】")
    df, _ = parse_workbook(path, parse_path("consumption/annual/2025.xls"), DEFS)
    assert (df["quarter"] == 0).all()


def test_detect_format_rejects_unknown(workbook):
    path = workbook(member2="台湾")
    with pytest.raises(StructureError, match="どの形式"):
        detect_format(pd.ExcelFile(path), DEFS, parse_path("consumption/quarterly/2025_Q3.xlsx"))
