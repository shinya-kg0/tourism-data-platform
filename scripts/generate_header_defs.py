"""Excel から見出し定義（ingest/header_defs/）を作る（仕様書 5.5、D-06）

宿泊旅行統計：新形式の Excel の、表の全シート（年計・各月）の見出しを読み、列の位置ごとに最も多く出てくる値を
定義にする。シートによって「計」が注記だけになる、グループ名が空欄になる、といった揺れを吸収するため。

消費動向調査：表の列の見出し（国籍・訪問地と指標）を読む。形式のバージョンごとにディレクトリを分ける。
表番号とシート名が違う形式（2017 年の「第N表」）は「表番号=シート名」で指定する。

作った定義は人が確認してからコミットする。

使い方（ingest/ で実行）:
    uv run python ../scripts/generate_header_defs.py overnight path/to/2025.xlsx 第2表 [第8表 ...]
    uv run python ../scripts/generate_header_defs.py consumption path/to/2025.xls 表3-1 [...] --format-version consumption_v2
    uv run python ../scripts/generate_header_defs.py consumption path/to/2017.xls 表3-1=第６表 [...] --format-version consumption_v1
"""

import argparse
import json
import re
from collections import Counter
from pathlib import Path

import pandas as pd

from ingest.parsers import consumption, overnight
from ingest.validation import normalize_label

PARSERS = {"overnight": overnight, "consumption": consumption}

# 消費動向調査の指標の単位（Excel には書かれていない）
CONSUMPTION_UNITS = {
    "回答数": "人",
    "購入率": "％",
    "購入者単価": "円",
    "消費単価": "円",
    "平均泊数": "泊",
    "訪問率": "％",
}
# 地域調査（B1）の表。1 次速報には含まれない（2026 年 7–9 月期の 1 次速報で確認）
REGIONAL_TABLES = {"表3-4", "表6-1"}
RELEASES = ["preliminary1", "preliminary2", "final"]
TITLE_RE = re.compile(r"^\S+?[\s　]+(.+?)（")


def most_common(values):
    present = [v for v in values if v]
    return Counter(present).most_common(1)[0][0] if present else None


def build_overnight_definition(xl: pd.ExcelFile, table_id: str, source_name: str) -> dict:
    headers = {}
    for name in xl.sheet_names:
        m = overnight.SHEET_RE.match(name.strip())
        if m and m[1] == table_id:
            df = pd.read_excel(xl, sheet_name=name, header=None)
            unit_row = overnight.find_unit_row(df)
            if unit_row is None:
                raise SystemExit(f"{name}: 新形式のシートではありません")
            headers[m[2]] = overnight.read_new_header(df, unit_row)
    if not headers:
        raise SystemExit(f"{table_id}: シートが見つかりません")

    counts = {len(h) for h in headers.values()}
    if len(counts) > 1:
        raise SystemExit(f"{table_id}: シートによって列数が違います {counts}")

    columns = []
    for cells in zip(*headers.values()):
        col = {key: most_common([c[key] for c in cells]) for key in ["target", "group", "sub", "item", "unit"]}
        columns.append({"position": len(columns) + 1, **col})

    periods = sorted(headers, key=lambda p: 0 if p == "年計" else int(p.removesuffix("月")))
    return {"table_id": table_id, "generated_from": source_name, "periods": periods, "columns": columns}


def build_consumption_definition(xl: pd.ExcelFile, table_id: str, sheet: str, source_name: str) -> dict:
    names = {s.strip(): s for s in xl.sheet_names}
    if sheet not in names:
        raise SystemExit(f"{sheet}: シートが見つかりません")
    df = pd.read_excel(xl, sheet_name=names[sheet], header=None)

    title = consumption.clean_text(df.iat[1, 1])
    m = TITLE_RE.match(title)
    if not m:
        raise SystemExit(f"{sheet}: 表題から列の区分を読めません（{title!r}）")

    members_list, blocks = [], []
    for row in consumption.find_header_rows(df):
        members, measures = consumption.read_header(df, row)
        members_list.append([name for _, name in members])
        blocks.append({"measures": [{"label": label, "unit": CONSUMPTION_UNITS[label]} for label in measures]})
    if not blocks or any(m != members_list[0] for m in members_list):
        raise SystemExit(f"{sheet}: 見出しの塊が見つからないか、塊によって列の見出しが違います")

    return {
        "table_id": table_id,
        "sheet": sheet,
        "title": title,
        "generated_from": source_name,
        "col_dimension": normalize_label(m[1]),
        "releases": RELEASES[1:] if table_id in REGIONAL_TABLES else RELEASES,
        "members": members_list[0],
        "blocks": blocks,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("survey", choices=PARSERS)
    ap.add_argument("excel", type=Path)
    ap.add_argument("tables", nargs="+", help="表番号（消費動向調査でシート名が違うときは 表番号=シート名）")
    ap.add_argument("--format-version", help="消費動向調査の形式のバージョン（例：consumption_v2）")
    args = ap.parse_args()

    out_dir = PARSERS[args.survey].header_defs_dir()
    if args.survey == "consumption":
        if not args.format_version:
            ap.error("consumption では --format-version が必要です")
        out_dir = out_dir / args.format_version
    out_dir.mkdir(parents=True, exist_ok=True)

    xl = pd.ExcelFile(args.excel)
    for spec in args.tables:
        table_id, _, sheet = spec.partition("=")
        if args.survey == "overnight":
            d = build_overnight_definition(xl, table_id, args.excel.name)
            summary = f"{len(d['columns'])} 列、{len(d['periods'])} シート"
        else:
            d = build_consumption_definition(xl, table_id, sheet or table_id, args.excel.name)
            summary = f"{len(d['members'])} 区分、{len(d['blocks'])} 塊"
        path = out_dir / f"{table_id}.json"
        path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{path}: {summary}")


if __name__ == "__main__":
    main()
