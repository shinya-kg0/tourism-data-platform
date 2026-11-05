-- 消費動向調査 表4-1：国籍・地域別の平均泊数（回答者の属性別）
-- 1 行 = 年 × 期 × 国籍 × 属性（attribute_category = '全体' の行が国籍全体の値）

with cells as (
    {{ consumption_cells('表4-1') }}
)

select
    cells.year,
    cells.quarter,
    nat.nationality_code,
    cells.row_category as attribute_category,
    coalesce(cells.row_item, cells.row_category) as attribute_item,
    max(if(cells.measure = '回答数', cells.value, null)) as respondents,
    max(if(cells.measure = '平均泊数', cells.value, null)) as avg_nights,
    max(if(cells.measure = '平均泊数', cells.flag, null)) as flag,
    any_value(cells.release_status) as release_status,
    any_value(cells.format_version) as format_version
from cells
left join {{ ref('seed_nationality') }} as nat
    on cells.col_member = nat.consumption_label
group by 1, 2, 3, 4, 5
