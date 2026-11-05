-- 宿泊旅行統計 参考第1表：国籍（出身地）別の外国人延べ宿泊者数（従業者数 10 人以上の施設）
-- 1 行 = 年 × 月 × 地域 × 国籍。nationality_code = 'ALL' は 21 区分の合計（表の「外国人延べ宿泊者数」）

with cells as (
    {{ overnight_cells('参考第1表') }}
)

select
    cells.year,
    cells.month,
    cells.area_type,
    cells.pref_code,
    cells.area_name,
    nat.nationality_code,
    cells.header_item as nationality_label,
    cells.value as foreign_guest_nights,
    cells.flag,
    cells.release_status,
    cells.format_version
from cells
left join {{ ref('seed_nationality') }} as nat
    on cells.header_item = nat.overnight_label
