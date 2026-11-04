"""新形式の Excel から見出し定義（ingest/header_defs/）を作る（仕様書 5.5、D-06）

表の全シート（年計・各月）の見出しを読み、列の位置ごとに最も多く出てくる値を定義にする。
シートによって「計」が注記だけになる、グループ名が空欄になる、といった揺れを吸収するため。
作った定義は人が確認してからコミットする。

使い方（ingest/ で実行）:
    uv run python ../scripts/generate_header_defs.py overnight path/to/2025.xlsx 第2表 [第8表 ...]
"""

import argparse
import json
from collections import Counter
from pathlib import Path

import pandas as pd

from ingest.parsers import overnight

PARSERS = {"overnight": overnight}


def most_common(values):
    present = [v for v in values if v]
    return Counter(present).most_common(1)[0][0] if present else None


def build_definition(xl: pd.ExcelFile, parser, table_id: str, source_name: str) -> dict:
    headers = {}
    for name in xl.sheet_names:
        m = parser.SHEET_RE.match(name.strip())
        if m and m[1] == table_id:
            df = pd.read_excel(xl, sheet_name=name, header=None)
            unit_row = parser.find_unit_row(df)
            if unit_row is None:
                raise SystemExit(f"{name}: 新形式のシートではありません")
            headers[m[2]] = parser.read_new_header(df, unit_row)
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("survey", choices=PARSERS)
    ap.add_argument("excel", type=Path)
    ap.add_argument("tables", nargs="+")
    args = ap.parse_args()

    parser = PARSERS[args.survey]
    out_dir = parser.header_defs_dir()
    out_dir.mkdir(parents=True, exist_ok=True)
    xl = pd.ExcelFile(args.excel)
    for table_id in args.tables:
        d = build_definition(xl, parser, table_id, args.excel.name)
        path = out_dir / f"{table_id}.json"
        path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{path}: {len(d['columns'])} 列、{len(d['periods'])} シート")


if __name__ == "__main__":
    main()
