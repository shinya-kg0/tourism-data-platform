"""アップロードされたパスの検証と、調査・期間・年・期・公表区分の取り出し（仕様書 4.2、D-02）

{survey}/{period_type}/{year}[_Q{quarter}][_{release}].{xlsx|xls}
例: overnight/annual/2026.xlsx、consumption/quarterly/2026_Q3_preliminary1.xlsx
"""

import re
from dataclasses import dataclass

PATH_RE = re.compile(
    r"^(?P<survey>overnight|consumption)/(?P<period_type>annual|quarterly)/"
    r"(?P<year>\d{4})(?:_Q(?P<quarter>[1-4]))?(?:_(?P<release>preliminary[12]))?\.(?:xlsx|xls)$"
)


class PathRuleError(ValueError):
    """パスがルールに合わない（rejected として扱う）"""


@dataclass(frozen=True)
class SourceFile:
    survey: str
    period_type: str
    year: int
    quarter: int  # 0＝暦年
    release_status: str  # preliminary1 / preliminary2 / final

    @property
    def replace_key(self) -> dict:
        """raw を入れ替える単位（仕様書 5.4、D-05）"""
        key = {"year": self.year, "release_status": self.release_status}
        if self.survey == "consumption":
            key["quarter"] = self.quarter
        return key


def parse_path(object_name: str) -> SourceFile:
    m = PATH_RE.match(object_name)
    if not m:
        raise PathRuleError(f"パスがルールに合いません: {object_name}")

    survey, period_type = m["survey"], m["period_type"]
    quarter = int(m["quarter"]) if m["quarter"] else 0
    if period_type == "quarterly" and quarter == 0:
        raise PathRuleError(f"quarterly には _Q1〜_Q4 が必要です: {object_name}")
    if period_type == "annual" and quarter != 0:
        raise PathRuleError(f"annual に _Q は付けられません: {object_name}")
    if survey == "overnight" and (period_type != "annual" or m["release"]):
        raise PathRuleError(f"宿泊旅行統計は年確定値（annual・確報）だけが対象です: {object_name}")

    return SourceFile(
        survey=survey,
        period_type=period_type,
        year=int(m["year"]),
        quarter=quarter,
        release_status=m["release"] or "final",
    )
