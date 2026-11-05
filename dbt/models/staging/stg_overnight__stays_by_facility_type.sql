-- 宿泊旅行統計 第4表：宿泊施設タイプ別の延べ宿泊者数（外国人の内訳あり）
-- 1 行 = 年 × 月 × 地域 × 対象（全体/外国人）× 施設タイプ

with cells as (
    {{ overnight_cells('第4表') }}
)

select
    year,
    month,
    area_type,
    pref_code,
    area_name,
    target,
    if(header_item in ('延べ宿泊者数', 'うち外国人延べ宿泊者数'), '全体', header_item) as facility_type,
    value as guest_nights,
    flag,
    release_status,
    format_version
from cells
