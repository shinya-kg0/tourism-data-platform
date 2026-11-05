-- 想定したページ「2. 国籍分析」（D-09）：国籍 × 年の外国人延べ宿泊者数・1 人 1 回当たり旅行消費単価・平均泊数

with base as (
    select * from {{ ref('int_nationality_yearly') }}
),

with_share as (
    select
        base.*,
        safe_divide(
            base.foreign_guest_nights,
            max(if(base.nationality_code = 'ALL', base.foreign_guest_nights, null)) over (partition by base.year)
        ) as foreign_guest_nights_share
    from base
)

select
    with_share.nationality_code,
    nat.name_ja as nationality_name,
    nat.region,
    nat.sort_order,
    with_share.nationality_code = 'ALL' as is_total,
    with_share.year,
    date(with_share.year, 1, 1) as year_date,
    with_share.foreign_guest_nights,
    with_share.foreign_guest_nights_share,
    safe_divide(
        with_share.foreign_guest_nights,
        lag(with_share.foreign_guest_nights) over (partition by with_share.nationality_code order by with_share.year)
    ) - 1 as foreign_guest_nights_yoy,
    with_share.spend_per_trip,
    safe_divide(
        with_share.spend_per_trip,
        lag(with_share.spend_per_trip) over (partition by with_share.nationality_code order by with_share.year)
    ) - 1 as spend_per_trip_yoy,
    with_share.avg_nights,
    with_share.consumption_respondents,
    with_share.consumption_respondents < {{ var('min_respondents') }} as is_low_sample,
    with_share.consumption_period_label,
    with_share.year between 2020 and 2022 as is_covid_period
from with_share
inner join {{ ref('seed_nationality') }} as nat using (nationality_code)
