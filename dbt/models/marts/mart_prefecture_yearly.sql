-- ダッシュボード 3. 地域分析：都道府県 × 年の延べ宿泊者数・訪問率・1 泊当たり消費単価・推計消費額（色分け地図）

with periods as (
    select * from {{ ref('int_consumption_yearly_periods') }}
),

visit as (
    select visit_rate.year, visit_rate.pref_code, visit_rate.visit_rate
    from {{ ref('stg_consumption__prefecture_visit_rate') }} as visit_rate
    inner join periods using (year, quarter)
    where visit_rate.area_type = 'prefecture'
        and visit_rate.nationality_code = 'ALL'
),

occupancy as (
    select year, pref_code, room_occupancy_rate
    from {{ ref('stg_overnight__occupancy') }}
    where area_type = 'prefecture'
        and month = 0
        and employee_size = '総数'
        and purpose = '計'
        and facility_type = '全体'
)

select
    inbound.pref_code,
    pref.pref_name,
    -- Looker Studio の地図（国の下位区分）で使う ISO 3166-2 のコード
    concat('JP-', inbound.pref_code) as iso_3166_2,
    pref.region,
    pref.transport_bureau,
    inbound.year,
    date(inbound.year, 1, 1) as year_date,
    inbound.total_guest_nights,
    inbound.foreign_guest_nights,
    safe_divide(inbound.foreign_guest_nights, inbound.total_guest_nights) as foreign_share,
    safe_divide(
        inbound.foreign_guest_nights,
        lag(inbound.foreign_guest_nights) over (partition by inbound.pref_code order by inbound.year)
    ) - 1 as foreign_guest_nights_yoy,
    occupancy.room_occupancy_rate,
    visit.visit_rate,
    inbound.spend_respondents,
    inbound.spend_per_night,
    inbound.is_low_sample,
    inbound.estimated_foreign_spend,
    inbound.consumption_period_label,
    inbound.year between 2020 and 2022 as is_covid_period
from {{ ref('int_prefecture_inbound_yearly') }} as inbound
inner join {{ ref('seed_prefecture') }} as pref using (pref_code)
left join occupancy using (year, pref_code)
left join visit using (year, pref_code)
