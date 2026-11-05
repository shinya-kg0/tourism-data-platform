-- 消費動向調査 表3-4：訪問地（都道府県・運輸局等）別の 1 人 1 泊当たり旅行消費単価（回答者の属性別）
-- 1 行 = 年 × 期 × 訪問地 × 属性。地域調査（B1）の結果で、2017 年以前と 1 次速報にはない
-- 国籍別の値は attribute_category = '国籍･地域' の行にあり、nationality_code が入る（全体の行は 'ALL'）

with cells as (
    {{ consumption_cells('表3-4') }}
),

pivoted as (
    select
        year,
        quarter,
        col_member as area_name,
        row_category as attribute_category,
        coalesce(row_item, row_category) as attribute_item,
        max(if(measure = '回答数', value, null)) as respondents,
        max(if(measure = '消費単価', value, null)) as spend_per_night,
        max(if(measure = '消費単価', flag, null)) as flag,
        any_value(release_status) as release_status,
        any_value(format_version) as format_version
    from cells
    group by 1, 2, 3, 4, 5
)

select
    pivoted.year,
    pivoted.quarter,
    if(pref.pref_code is not null, 'prefecture', 'transport_bureau') as area_type,
    pref.pref_code,
    pivoted.area_name,
    pivoted.attribute_category,
    pivoted.attribute_item,
    case
        when pivoted.attribute_category = '全体' then 'ALL'
        -- 2026 年からは「国籍・地域」（中黒が全角）
        when pivoted.attribute_category in ('国籍･地域', '国籍・地域') then nat.nationality_code
    end as nationality_code,
    pivoted.respondents,
    pivoted.spend_per_night,
    pivoted.flag,
    pivoted.release_status,
    pivoted.format_version
from pivoted
left join {{ ref('seed_prefecture') }} as pref
    on pivoted.area_name = pref.pref_name
left join {{ ref('seed_nationality') }} as nat
    on pivoted.attribute_item = nat.consumption_label
    and pivoted.attribute_category in ('国籍･地域', '国籍・地域')
