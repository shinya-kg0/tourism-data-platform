-- 想定したページ「1. サマリ」（D-09）：全国の主要指標（年）

with national as (
    select year, target, guest_nights
    from {{ ref('stg_overnight__stays') }}
    where area_type = 'national'
        and month = 0
        and employee_size = '総数'
        and purpose = '計'
),

pivoted as (
    select
        year,
        max(if(target = '全体', guest_nights, null)) as total_guest_nights,
        max(if(target = '外国人', guest_nights, null)) as foreign_guest_nights
    from national
    group by year
),

with_japanese as (
    select
        *,
        total_guest_nights - foreign_guest_nights as japanese_guest_nights
    from pivoted
),

occupancy as (
    select year, room_occupancy_rate
    from {{ ref('stg_overnight__occupancy') }}
    where area_type = 'national'
        and month = 0
        and employee_size = '総数'
        and purpose = '計'
        and facility_type = '全体'
),

consumption as (
    select year, consumption_period_label, spend_per_trip, avg_nights
    from {{ ref('int_nationality_yearly') }}
    where nationality_code = 'ALL'
        and consumption_period_label is not null
),

joined as (
    select *
    from with_japanese
    left join occupancy using (year)
    left join consumption using (year)
)

select
    year,
    -- BI ツールの時系列グラフ用（年の 1 月 1 日）
    date(year, 1, 1) as year_date,
    total_guest_nights,
    japanese_guest_nights,
    foreign_guest_nights,
    safe_divide(foreign_guest_nights, total_guest_nights) as foreign_share,
    safe_divide(total_guest_nights, lag(total_guest_nights) over (order by year)) - 1 as total_guest_nights_yoy,
    safe_divide(japanese_guest_nights, lag(japanese_guest_nights) over (order by year)) - 1 as japanese_guest_nights_yoy,
    safe_divide(foreign_guest_nights, lag(foreign_guest_nights) over (order by year)) - 1 as foreign_guest_nights_yoy,
    room_occupancy_rate,
    spend_per_trip,
    safe_divide(spend_per_trip, lag(spend_per_trip) over (order by year)) - 1 as spend_per_trip_yoy,
    avg_nights,
    consumption_period_label,
    -- コロナの影響で調査の中止・急減がある期間。グラフで色を分けるのに使う
    year between 2020 and 2022 as is_covid_period
from joined
