-- 宿泊旅行統計 第9表：宿泊者の居住地（県内・県外）別の延べ宿泊者数（宿泊目的割合別）
-- 1 行 = 年 × 月 × 地域 × 宿泊目的 × 居住地

with cells as (
    {{ overnight_cells('第9表') }}
)

select
    year,
    month,
    area_type,
    pref_code,
    area_name,
    coalesce(header_sub, '計') as purpose,
    case header_item
        when '延べ宿泊者数' then '計'
        when '県内計' then '県内'
        when '県外計' then '県外'
        else header_item
    end as residence,
    value as guest_nights,
    flag,
    release_status,
    format_version
from cells
