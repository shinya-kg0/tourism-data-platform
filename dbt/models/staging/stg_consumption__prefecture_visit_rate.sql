-- 消費動向調査 表6-1：国籍・地域別の都道府県訪問率（複数回答）
-- 1 行 = 年 × 期 × 国籍 × 訪問地（都道府県・運輸局等）。地域調査（B1）の結果で、1 次速報にはない

with cells as (
    {{ consumption_cells('表6-1') }}
),

pivoted as (
    select
        year,
        quarter,
        col_member,
        row_item as area_name,
        max(if(measure = '回答数', value, null)) as visitors,
        max(if(measure = '訪問率', value, null)) as visit_rate_pct,
        max(if(measure = '訪問率', flag, null)) as flag,
        any_value(release_status) as release_status,
        any_value(format_version) as format_version
    from cells
    -- 全体の行と、訪問率の延べ合計の行は除く
    where row_item is not null
        and row_item != '延べ合計'
    group by 1, 2, 3, 4
)

select
    pivoted.year,
    pivoted.quarter,
    nat.nationality_code,
    if(pref.pref_code is not null, 'prefecture', 'transport_bureau') as area_type,
    pref.pref_code,
    pivoted.area_name,
    pivoted.visitors,
    pivoted.visit_rate_pct / 100 as visit_rate,
    pivoted.flag,
    pivoted.release_status,
    pivoted.format_version
from pivoted
left join {{ ref('seed_nationality') }} as nat
    on pivoted.col_member = nat.consumption_label
left join {{ ref('seed_prefecture') }} as pref
    on pivoted.area_name = pref.pref_name
