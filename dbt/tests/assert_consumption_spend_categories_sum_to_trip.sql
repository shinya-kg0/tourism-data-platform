-- 表2-1 の日本滞在中の費目別「購入率 × 購入者単価」の合計 = 表3-1 の 1 人 1 回当たり旅行消費単価
-- 2018 年以降の公表値はこの関係がちょうど成り立つため、行や列の読み違いがあれば見つかる。
-- 2017 年以前（consumption_v1）は費目の集計対象が違い、数％ずれるため対象外

with categories as (
    select year, quarter, nationality_code, sum(spend_per_visitor) as in_japan_spend
    from {{ ref('stg_consumption__spend_by_category') }}
    where spend_stage = '日本滞在中'
        and sub_category is null
        and format_version != 'consumption_v1'
    group by 1, 2, 3
),

trip as (
    select year, quarter, nationality_code, spend_per_trip
    from {{ ref('stg_consumption__spend_per_trip') }}
    where attribute_category = '全体'
        and spend_per_trip > 0
)

select
    trip.*,
    categories.in_japan_spend
from trip
inner join categories using (year, quarter, nationality_code)
where abs(categories.in_japan_spend / trip.spend_per_trip - 1) > 0.01
