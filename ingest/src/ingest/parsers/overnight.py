"""宿泊旅行統計調査（年確定値）の解析。

1 ファイル（1 年分）を、header_defs に定義がある表だけ縦持ちに変換する。
見出しは定義を正とし、シートの見出しとは照合だけを行う（D-06）。

- 新形式（2020 年〜）：見出しが「グループ / 区分 / 項目 / 単位」の 4 段。項目と単位を定義と照合する
- 旧形式（2016〜2019 年）：結合セルで単位の行がない。列数だけを照合し、定義を列の位置で当てはめる
  （列の並びが新形式と同じことは e-Stat API の値との全セル照合で確認済み）

地域コードは Excel にあるものだけを入れる（2016 年と 2020〜2024 年はコードがない）。補完は dbt の staging で行う。
"""

import json
import os
import re
from pathlib import Path

import pandas as pd

from ingest.validation import StructureError, check_column_count, check_labels, check_rows, normalize_label

SURVEY = "overnight"
FORMAT_NEW = "overnight_v2"
FORMAT_OLD = "overnight_v1"

SHEET_RE = re.compile(r"^(.+表)\((年計|\d+月)\)$")
UNITS = {"施設", "人泊", "人", "室", "％", "%"}
FLAG_RE = re.compile(r"([*＊]|^-$|^…$|^x$)")
FOOTNOTE_ROW_RE = re.compile(r"^(\d+\)|※)")
SPACE_RE = re.compile(r"\s+")

OUTPUT_COLUMNS = [
    "year", "month", "table_id", "area_code", "area_name", "target",
    "header_group", "header_sub", "header_item", "unit", "value", "flag",
]  # fmt: skip


def header_defs_dir() -> Path:
    return Path(os.environ.get("HEADER_DEFS_DIR", Path(__file__).parents[3] / "header_defs")) / SURVEY


def load_header_defs() -> dict[str, dict]:
    """表番号 → 見出し定義"""
    defs = {}
    for path in sorted(header_defs_dir().glob("*.json")):
        d = json.loads(path.read_text(encoding="utf-8"))
        defs[d["table_id"]] = d
    return defs


def find_unit_row(df: pd.DataFrame) -> int | None:
    for i in df.index:
        if df.iloc[i, 1:].map(normalize_label).isin(UNITS).any():
            return i
    return None


def read_new_header(df: pd.DataFrame, unit_row: int) -> list[dict]:
    """新形式の見出しを読む（見出し定義の生成にも使う）"""
    item_row, sub_row, group_row = unit_row - 1, unit_row - 2, unit_row - 3
    columns = []
    foreign = False
    for col in df.columns[1:]:
        unit = normalize_label(df.iat[unit_row, col])
        if not unit:
            continue
        item = normalize_label(df.iat[item_row, col])
        # 「うち外国人〜」の列から右は外国人の内訳
        foreign = foreign or item.startswith("うち外国人")
        columns.append({
            "position": len(columns) + 1,
            "target": "外国人" if foreign else "全体",
            "group": (normalize_label(df.iat[group_row, col]) or None) if group_row >= 3 else None,
            "sub": (normalize_label(df.iat[sub_row, col]) or None) if sub_row > group_row >= 3 else None,
            "item": item,
            "unit": unit,
        })  # fmt: skip
    return columns


def _value_columns(df: pd.DataFrame, header_rows: slice) -> list[int]:
    """値が入る列（1 列目以降で、見出しに何か書かれている列）"""
    header = df.iloc[header_rows, 1:]
    return [c for c in header.columns if header[c].notna().any()]


def parse_sheet(df: pd.DataFrame, columns: list[dict], where: str) -> tuple[pd.DataFrame, str]:
    """1 シートを縦持ちに変換する。(縦持ち, 形式のバージョン) を返す"""
    unit_row = find_unit_row(df)
    if unit_row is not None:
        value_cols = [c for c in df.columns[1:] if normalize_label(df.iat[unit_row, c])]
        labels = [(normalize_label(df.iat[unit_row - 1, c]), normalize_label(df.iat[unit_row, c])) for c in value_cols]
        check_labels(labels, columns, where)
        data_start, fmt = unit_row + 1, FORMAT_NEW
    else:
        data_start = next(
            (i for i in df.index[3:] if pd.notna(pd.to_numeric(df.iat[i, 1], errors="coerce"))),
            None,
        )
        if data_start is None:
            raise StructureError(f"{where}: データの開始行が見つかりません")
        value_cols = _value_columns(df, slice(3, data_start))
        check_column_count(len(value_cols), columns, where)
        fmt = FORMAT_OLD

    body = df.iloc[data_start:, [0, *value_cols]]
    label = body[0].map(normalize_label)
    body = body[(label != "") & ~label.str.match(FOOTNOTE_ROW_RE) & body[value_cols].notna().any(axis=1)]
    if body.empty:
        raise StructureError(f"{where}: データ行がありません")
    # 先頭行は全国計（「施設所在地計」「令和7年4月」「平成28年 1～12月 計」など表記が揺れる）
    area = body[0].map(lambda v: SPACE_RE.sub("", str(v)))
    area.iloc[0] = "全国"

    header = pd.DataFrame(columns, index=value_cols)
    long = (
        body.drop(columns=0)
        .assign(area=area)
        .melt(id_vars="area", var_name="col", value_name="raw")
        .join(header, on="col")
    )

    raw = long["raw"].map(lambda v: None if pd.isna(v) else str(v).strip())
    long["area_code"] = long["area"].str.extract(r"^(\d{2})", expand=False)
    long["area_name"] = long["area"].str.replace(r"^\d{2}", "", regex=True)
    long["value"] = pd.to_numeric(raw.str.replace(r"[*＊,\s]", "", regex=True), errors="coerce")
    long["flag"] = raw.str.extract(FLAG_RE, expand=False).replace({"＊": "*"})
    long = long.rename(columns={"group": "header_group", "sub": "header_sub", "item": "header_item"})
    check_rows(long, where)
    return long, fmt


def parse_workbook(source, year: int, header_defs: dict[str, dict]) -> tuple[pd.DataFrame, str]:
    """1 年分の Excel を縦持ちに変換する。(raw に入れる DataFrame, 形式のバージョン) を返す"""
    xl = pd.ExcelFile(source)
    sheets: dict[str, dict[str, str]] = {}
    for name in xl.sheet_names:
        m = SHEET_RE.match(name.strip())
        if m and m[1] in header_defs:
            sheets.setdefault(m[1], {})[m[2]] = name

    frames, formats = [], set()
    for table_id, d in header_defs.items():
        found = sheets.get(table_id, {})
        missing = [p for p in d["periods"] if p not in found]
        if missing:
            raise StructureError(f"{table_id}: シートがありません（{', '.join(missing)}）")
        for period in d["periods"]:
            df = pd.read_excel(xl, sheet_name=found[period], header=None)
            long, fmt = parse_sheet(df, d["columns"], f"{year}年 {found[period]}")
            long["month"] = 0 if period == "年計" else int(period.removesuffix("月"))
            long["table_id"] = table_id
            frames.append(long)
            formats.add(fmt)

    if len(formats) > 1:
        raise StructureError(f"{year}年: 新形式と旧形式のシートが混在しています")
    result = pd.concat(frames, ignore_index=True)
    result["year"] = year
    return result[OUTPUT_COLUMNS], formats.pop()
