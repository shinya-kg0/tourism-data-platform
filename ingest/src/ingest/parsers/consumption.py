"""訪日外国人消費動向調査の解析（対象：表2-1、表3-1、表3-4、表4-1、表6-1）

1 ファイル（暦年または四半期の 1 期分）を、header_defs に定義がある表だけ縦持ちに変換する。
列の見出し（国籍・訪問地と指標）は定義と照合し、定義のものを使う（D-06）。
行の見出し（入国空港の一覧など）は年によって増減するため照合せず、シートのものをそのまま使う。

形式のバージョン（header_defs/consumption/{format_version}/）：
- consumption_v1：2017 年。表番号が「第N表」で、表3-4 がない。総数の列が「全体」
- consumption_v2：2018 年〜2025 年。国籍・地域は 21 区分（2024 年 4–6 月期からの新調査も同じ形式）
- consumption_v3：2026 年〜。国籍・地域は 24 区分。1 次速報には表3-4・表6-1 がない

シートの並び：
    3 行目      対象の期間と公表区分（例：2025年7-9月期 【確報】）。パスから取り出した値と照合する
    「調査項目」 列の見出し（国籍・訪問地）。次の行が指標（回答数、消費単価など）
    その下      1 列目が行の大分類、2 列目が項目、3 列目が内訳（例：交通費 > バス）
表2-1 は「購入率」と「購入者単価」の 2 つの塊が縦に並ぶ。
"""

import json
import os
import re
from pathlib import Path

import pandas as pd

from ingest.path_rules import SourceFile
from ingest.validation import StructureError, normalize_label

SURVEY = "consumption"

HEADER_LABEL = "調査項目"
FIRST_VALUE_COL = 4
PERIOD_ROW = 3
FLAG_RE = re.compile(r"^([*＊]|-|－|…|x|X)$")
# 大分類の文字から除くもの：調査の種類（【A1】など）、回答の形式、注記の番号（「１）」）
CATEGORY_NOISE_RE = re.compile(r"【[^】]*】|（(?:単一|複数)回答）|^[0-9０-９]+[)）]$|\s+")
# 大分類の最後の行（この行で大分類の文字が終わる）
CATEGORY_END_RE = re.compile(r"(】|回答）)$")
# 項目の後ろの注記の番号（2017 年以前の「北陸信越運輸局 ２）」など）
ITEM_FOOTNOTE_RE = re.compile(r"\s+[0-9０-９]+[)）]$")
QUARTER_RE = re.compile(r"(\d{1,2})-\d{1,2}月期")
RELEASE_LABELS = {"1次速報": "preliminary1", "2次速報": "preliminary2"}

OUTPUT_COLUMNS = [
    "year", "quarter", "table_id", "row_category", "row_item",
    "col_dimension", "col_member", "measure", "unit", "value", "flag",
]  # fmt: skip


def header_defs_dir() -> Path:
    return Path(os.environ.get("HEADER_DEFS_DIR", Path(__file__).parents[3] / "header_defs")) / SURVEY


def load_header_defs() -> dict[str, dict[str, dict]]:
    """形式のバージョン → 表番号 → 見出し定義（新しいバージョンから順に並べる）"""
    defs = {}
    for version_dir in sorted((p for p in header_defs_dir().iterdir() if p.is_dir()), reverse=True):
        tables = {}
        for path in sorted(version_dir.glob("*.json")):
            d = json.loads(path.read_text(encoding="utf-8"))
            tables[d["table_id"]] = d
        if tables:
            defs[version_dir.name] = tables
    return defs


def clean_text(value) -> str:
    """前後の空白を除き、続く空白を 1 つにする（英字の項目名があるため、空白は消さない）"""
    if value is None or pd.isna(value):
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()


def find_header_rows(df: pd.DataFrame) -> list[int]:
    return [i for i in df.index if normalize_label(df.iat[i, 1]) == HEADER_LABEL]


def read_header(df: pd.DataFrame, row: int) -> tuple[list[tuple[int, str]], list[str]]:
    """列の見出しを読む。([(列の位置, 国籍・訪問地)], 1 つ目の国籍・訪問地の指標) を返す"""
    members = [
        (c, normalize_label(df.iat[row, c])) for c in df.columns[FIRST_VALUE_COL:] if normalize_label(df.iat[row, c])
    ]
    if not members:
        return [], []
    first, second = members[0][0], members[1][0] if len(members) > 1 else len(df.columns)
    measures = [normalize_label(df.iat[row + 1, c]) for c in range(first, second)]
    return members, measures


def check_period(df: pd.DataFrame, src: SourceFile, where: str) -> None:
    """シートに書かれた期間・公表区分が、パスから取り出したものと同じか（取り違えたファイルを止める）"""
    text = "".join(clean_text(v) for v in df.iloc[PERIOD_ROW])
    year = re.search(r"(\d{4})年", text)
    if "暦年" in text:
        quarter = 0
    else:
        m = QUARTER_RE.search(text)
        quarter = (int(m[1]) - 1) // 3 + 1 if m else None
    release = next((v for k, v in RELEASE_LABELS.items() if k in text), "final")
    actual = (int(year[1]) if year else None, quarter, release)
    expected = (src.year, src.quarter, src.release_status)
    if actual != expected:
        raise StructureError(f"{where}: シートの期間・公表区分がパスと違います（{text!r}）")


def check_header(df: pd.DataFrame, d: dict, where: str) -> list[tuple[int, list[tuple[int, str]]]]:
    """列の見出しを定義と照合する。塊ごとに (見出しの行, [(列の位置, 国籍・訪問地)]) を返す"""
    header_rows = find_header_rows(df)
    if len(header_rows) != len(d["blocks"]):
        raise StructureError(f"{where}: 見出しの塊の数が定義と違います（{len(header_rows)} != {len(d['blocks'])}）")

    blocks = []
    for row, block in zip(header_rows, d["blocks"]):
        members, measures = read_header(df, row)
        labels = [m for _, m in members]
        if labels != d["members"]:
            diff = sorted(set(labels) ^ set(d["members"])) or "並び順"
            raise StructureError(f"{where}: {row + 1}行目の{d['col_dimension']}が定義と違います（{diff}）")
        expected = [m["label"] for m in block["measures"]]
        if measures != expected:
            raise StructureError(f"{where}: {row + 2}行目の指標が定義と違います（{measures} != {expected}）")
        blocks.append((row, members))
    return blocks


def read_rows(df: pd.DataFrame, start: int, stop: int, value_cols: list[int]) -> list[tuple[int, str, str]]:
    """行の見出しを読む。値のある行ごとに (行の位置, 大分類, 項目) を返す。

    大分類の文字は 1 列目に数行に分けて書かれている（例：「日本滞在中の」「費目別支出」「【A1】」）。
    文字が途切れたとき、【A1】や（単一回答）で終わったとき、項目のない行（「全体」など）のあとで区切る。
    ただし「【A1】」だけの行は区切りのあとでも直前の大分類に含める。
    内訳の行（3 列目）は「親の項目／内訳」とする。
    """
    rows = []
    groups: list[list[str]] = []  # 大分類ごとの文字の行
    closed = True
    parent = ""
    for i in range(start, stop):
        line, item, sub = (clean_text(df.iat[i, c]) for c in (1, 2, 3))
        item, sub = ITEM_FOOTNOTE_RE.sub("", item), ITEM_FOOTNOTE_RE.sub("", sub)
        # 値のない行（空行・注記）と、見出しのない行（2017 年は注記が値の列にある）は読まない
        if not (line or item or sub) or df.iloc[i, value_cols].isna().all():
            continue
        if line:
            text = CATEGORY_NOISE_RE.sub("", line)
            # 「【A1】」だけの行は、直前の大分類の続き
            if (closed and text) or not groups:
                groups.append([])
            groups[-1].append(text)
            closed = bool(CATEGORY_END_RE.search(line)) or not (item or sub)
        else:
            closed = True
        label = item or (f"{parent}／{sub}" if sub else None)
        parent = item or parent
        rows.append((i, len(groups) - 1, label))
    # 大分類の文字は、最後の行まで読んでからつなげる
    return [(i, "".join(groups[g]) if g >= 0 else "", label) for i, g, label in rows]


def parse_sheet(df: pd.DataFrame, d: dict, where: str) -> pd.DataFrame:
    """1 シートを縦持ちに変換する"""
    blocks = check_header(df, d, where)
    frames = []
    for n, ((row, members), block) in enumerate(zip(blocks, d["blocks"])):
        measures = block["measures"]
        stop = blocks[n + 1][0] if n + 1 < len(blocks) else len(df)
        value_cols = [c + k for c, _ in members for k in range(len(measures))]
        labels = read_rows(df, row + 2, stop, value_cols)
        if not labels:
            raise StructureError(f"{where}: {row + 1}行目の見出しの下にデータ行がありません")

        index = [i for i, _, _ in labels]
        cols = pd.MultiIndex.from_tuples(
            [(member, m["label"], m["unit"]) for _, member in members for m in measures],
            names=["col_member", "measure", "unit"],
        )
        body = pd.DataFrame(df.iloc[index, value_cols].to_numpy(), index=index, columns=cols)
        long = (
            body.stack(["col_member", "measure", "unit"], future_stack=True).rename("raw").reset_index(level=[1, 2, 3])
        )
        head = pd.DataFrame([(c, item) for _, c, item in labels], index=index, columns=["row_category", "row_item"])
        frames.append(long.join(head))

    long = pd.concat(frames, ignore_index=True)
    raw = long["raw"].map(lambda v: None if pd.isna(v) else str(v).strip())
    long["value"] = pd.to_numeric(raw.str.replace(",", "", regex=False), errors="coerce")
    long["flag"] = raw.where(raw.str.match(FLAG_RE, na=False)).replace({"＊": "*", "－": "-"})
    long["col_dimension"] = d["col_dimension"]

    if (long["row_category"] == "").any():
        raise StructureError(f"{where}: 行の大分類が空の行があります")
    unexplained = long["value"].isna() & long["flag"].isna() & raw.notna()
    if unexplained.any():
        examples = sorted(set(raw[unexplained]))[:3]
        raise StructureError(f"{where}: 数値でも記号でもない値が {int(unexplained.sum())} 件あります（{examples}）")
    # 空のセルは値も記号もないので取り込まない
    return long[raw.notna()]


def detect_format(xl: pd.ExcelFile, header_defs: dict[str, dict[str, dict]], src: SourceFile) -> str:
    """どの形式のバージョンの定義に合うか。新しいバージョンから順に、先頭の表の見出しで判定する"""
    sheets = {s.strip(): s for s in xl.sheet_names}
    errors = []
    for version, tables in header_defs.items():
        d = next(iter(tables.values()))
        if d["sheet"] not in sheets:
            errors.append(f"{version}: {d['sheet']} がありません")
            continue
        try:
            check_header(pd.read_excel(xl, sheet_name=sheets[d["sheet"]], header=None), d, d["sheet"])
        except StructureError as e:
            errors.append(f"{version}: {e}")
            continue
        return version
    raise StructureError(f"{src.year}年: どの形式の見出し定義にも合いません（{'; '.join(errors)}）")


def parse_workbook(source, src: SourceFile, header_defs: dict[str, dict[str, dict]]) -> tuple[pd.DataFrame, str]:
    """1 期分の Excel を縦持ちに変換する。(raw に入れる DataFrame, 形式のバージョン) を返す"""
    xl = pd.ExcelFile(source)
    version = detect_format(xl, header_defs, src)
    sheets = {s.strip(): s for s in xl.sheet_names}

    frames = []
    for table_id, d in header_defs[version].items():
        if src.release_status not in d["releases"]:
            continue  # 1 次速報には地域調査の表がない
        if d["sheet"] not in sheets:
            raise StructureError(f"{table_id}: シート {d['sheet']} がありません")
        df = pd.read_excel(xl, sheet_name=sheets[d["sheet"]], header=None)
        where = f"{src.year}年 {d['sheet']}"
        check_period(df, src, where)
        long = parse_sheet(df, d, where)
        long["table_id"] = table_id
        frames.append(long)

    result = pd.concat(frames, ignore_index=True)
    result["year"] = src.year
    result["quarter"] = src.quarter
    return result[OUTPUT_COLUMNS], version
