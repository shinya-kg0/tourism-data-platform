-- 国籍 × 年：外国人延べ宿泊者数（宿泊旅行統計）と、1 人 1 回当たり旅行消費単価・平均泊数（消費動向調査）を結合する
-- nationality_code = 'ALL' は国籍全体

with nights as (
    select nationality_code, year, foreign_guest_nights
    from {{ ref('stg_overnight__foreign_stays_by_nationality') }}
    where area_type = 'national'
        and month = 0
),

periods as (
    select * from {{ ref('int_consumption_yearly_periods') }}
),

spend as (
    select trip.nationality_code, trip.year, trip.respondents, trip.spend_per_trip
    from {{ ref('stg_consumption__spend_per_trip') }} as trip
    inner join periods using (year, quarter)
    where trip.attribute_category = '全体'
),

stay as (
    select avg_nights.nationality_code, avg_nights.year, avg_nights.avg_nights
    from {{ ref('stg_consumption__avg_nights') }} as avg_nights
    inner join periods using (year, quarter)
    where avg_nights.attribute_category = '全体'
),

consumption as (
    select
        spend.nationality_code,
        spend.year,
        periods.period_label as consumption_period_label,
        spend.respondents as consumption_respondents,
        spend.spend_per_trip,
        stay.avg_nights
    from spend
    inner join periods using (year)
    left join stay using (nationality_code, year)
)

select
    coalesce(nights.nationality_code, consumption.nationality_code) as nationality_code,
    coalesce(nights.year, consumption.year) as year,
    nights.foreign_guest_nights,
    consumption.consumption_period_label,
    consumption.consumption_respondents,
    consumption.spend_per_trip,
    consumption.avg_nights
from nights
full outer join consumption using (nationality_code, year)
