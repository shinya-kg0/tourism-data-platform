-- 宿泊旅行統計 第1表：施設数（従業者数・宿泊目的割合別、宿泊施設タイプ別）
-- 1 行 = 年 × 月 × 地域 × 従業者数 × 宿泊目的 × 施設タイプ。年計のシートはない

with cells as (
    {{ overnight_cells('第1表') }}
)

select
    year,
    month,
    area_type,
    pref_code,
    area_name,
    {{ overnight_breakdown('総数') }},
    value as facilities,
    flag,
    release_status,
    format_version
from cells
