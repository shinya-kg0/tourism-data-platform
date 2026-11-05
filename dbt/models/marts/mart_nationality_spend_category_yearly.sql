-- ダッシュボード 2. 国籍分析：国籍 × 費目 × 年の購入率・購入者単価・1 人当たり支出（費目別の積み上げ棒）

with periods as (
    select * from {{ ref('int_consumption_yearly_periods') }}
),

spend as (
    select category.*, periods.period_label as consumption_period_label
    from {{ ref('stg_consumption__spend_by_category') }} as category
    inner join periods using (year, quarter)
    where category.sub_category is null
)

select
    spend.nationality_code,
    nat.name_ja as nationality_name,
    nat.region,
    nat.sort_order as nationality_sort_order,
    spend.nationality_code = 'ALL' as is_total,
    spend.year,
    date(spend.year, 1, 1) as year_date,
    spend.spend_stage,
    spend.spend_category,
    cat.sort_order as category_sort_order,
    spend.purchasers,
    spend.purchase_rate,
    spend.spend_per_purchaser,
    spend.spend_per_visitor,
    -- 日本滞在中の支出に占める割合（旅行前支出は対象外）
    if(
        spend.spend_stage = '日本滞在中',
        safe_divide(
            spend.spend_per_visitor,
            sum(if(spend.spend_stage = '日本滞在中', spend.spend_per_visitor, null))
                over (partition by spend.nationality_code, spend.year)
        ),
        null
    ) as in_japan_spend_share,
    spend.consumption_period_label,
    spend.year between 2020 and 2022 as is_covid_period
from spend
inner join {{ ref('seed_nationality') }} as nat using (nationality_code)
inner join (
    select distinct spend_category, sort_order from {{ ref('seed_spend_category') }}
) as cat using (spend_category)
