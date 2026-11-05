-- 宿泊旅行統計 第8表：客室稼働率（従業者数・宿泊目的割合別、宿泊施設タイプ別）
-- 1 行 = 年 × 月 × 地域 × 従業者数 × 宿泊目的 × 施設タイプ

with cells as (
    {{ overnight_cells('第8表') }}
)

select
    year,
    month,
    area_type,
    pref_code,
    area_name,
    {{ overnight_breakdown('客室稼働率') }},
    -- Excel は％。Looker Studio で書式を付けやすいよう 0〜1 にする
    value / 100 as room_occupancy_rate,
    flag,
    release_status,
    format_version
from cells
