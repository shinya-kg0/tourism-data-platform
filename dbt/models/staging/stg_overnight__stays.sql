-- 宿泊旅行統計 第2表：延べ宿泊者数（従業者数・宿泊目的割合別。外国人の内訳あり）
-- 1 行 = 年 × 月 × 地域 × 対象（全体/外国人）× 従業者数 × 宿泊目的

with cells as (
    {{ overnight_cells('第2表') }}
)

select
    year,
    month,
    area_type,
    pref_code,
    area_name,
    target,
    coalesce(header_sub, '総数') as employee_size,
    -- 「計」は宿泊目的割合が不詳の施設を含むため、50％以上と50％未満の合計とは一致しない
    case
        when header_item in ('延べ宿泊者数', 'うち外国人延べ宿泊者数', '計') then '計'
        else header_item
    end as purpose,
    value as guest_nights,
    flag,
    release_status,
    format_version
from cells
