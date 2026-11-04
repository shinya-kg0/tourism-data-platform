"""Excel の構造検査（列数・見出しの照合）と行ごとの検査（仕様書 5.1）

検査に落ちたファイルは StructureError として rejected 扱いにする（D-04）。
"""

import re

import pandas as pd

FOOTNOTE_RE = re.compile(r"[0-9０-９]+[)）]")
SPACE_RE = re.compile(r"\s+")


class StructureError(ValueError):
    """Excel の構造が見出し定義と合わない（rejected として扱う）"""


def normalize_label(value) -> str:
    """改行・空白・注記（「1)」など）を除いた見出しの文字。空なら空文字"""
    if value is None or pd.isna(value):
        return ""
    return FOOTNOTE_RE.sub("", SPACE_RE.sub("", str(value)))


def check_column_count(actual: int, columns: list[dict], where: str) -> None:
    if actual != len(columns):
        raise StructureError(f"{where}: 列数が見出し定義と一致しません（{actual} != {len(columns)}）")


def check_labels(labels: list[tuple[str, str]], columns: list[dict], where: str) -> None:
    """シートの (項目, 単位) を見出し定義と照合する。

    シートによって「計」が注記だけになっていたり空欄だったりするため、空のラベルは許容し、
    文字が入っていて定義と違う場合だけ不一致とする。
    """
    check_column_count(len(labels), columns, where)
    for col, (item, unit) in zip(columns, labels):
        for name, actual, expected in [("項目", item, col["item"]), ("単位", unit, col["unit"])]:
            if actual and expected and actual != normalize_label(expected):
                raise StructureError(
                    f"{where}: {col['position']}列目の{name}が定義と違います（{actual!r} != {expected!r}）"
                )


def check_rows(long: pd.DataFrame, where: str) -> None:
    if long["area_name"].isna().any():
        raise StructureError(f"{where}: 地域名が空の行があります")
    unexplained = long["value"].isna() & long["flag"].isna()
    if unexplained.any():
        raise StructureError(f"{where}: 数値でも記号でもない値が {int(unexplained.sum())} 件あります")
