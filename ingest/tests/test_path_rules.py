import pytest

from ingest.path_rules import PathRuleError, SourceFile, parse_path


@pytest.mark.parametrize(
    "path, expected",
    [
        ("overnight/annual/2026.xlsx", SourceFile("overnight", "annual", 2026, 0, "final")),
        ("consumption/annual/2025.xls", SourceFile("consumption", "annual", 2025, 0, "final")),
        (
            "consumption/quarterly/2026_Q3_preliminary1.xlsx",
            SourceFile("consumption", "quarterly", 2026, 3, "preliminary1"),
        ),
        ("consumption/quarterly/2026_Q1.xlsx", SourceFile("consumption", "quarterly", 2026, 1, "final")),
    ],
)
def test_parse_path(path, expected):
    assert parse_path(path) == expected


@pytest.mark.parametrize(
    "path",
    [
        "overnight/annual/2026.csv",  # 拡張子
        "overnight/2026.xlsx",  # period_type がない
        "landing/overnight/annual/2026.xlsx",  # 先頭に余計なフォルダ
        "consumption/quarterly/2026.xlsx",  # quarterly なのに _Q がない
        "consumption/annual/2026_Q1.xlsx",  # annual なのに _Q がある
        "consumption/quarterly/2026_Q5.xlsx",  # 期の範囲外
        "overnight/quarterly/2026_Q1.xlsx",  # 宿泊は annual だけ
        "overnight/annual/2026_preliminary1.xlsx",  # 宿泊は確報だけ
        "consumption/annual/2026_final.xlsx",  # final は省略で表す
    ],
)
def test_parse_path_rejects(path):
    with pytest.raises(PathRuleError):
        parse_path(path)


def test_replace_key():
    assert parse_path("overnight/annual/2026.xlsx").replace_key == {"year": 2026, "release_status": "final"}
    assert parse_path("consumption/quarterly/2026_Q3_preliminary2.xlsx").replace_key == {
        "year": 2026,
        "release_status": "preliminary2",
        "quarter": 3,
    }
