-- 想定したページ「5. 宿泊の受け入れ」（D-09）：地域（全国・都道府県）× 施設タイプ × 年の客室稼働率・延べ宿泊者数・施設数

with occupancy as (
    select year, area_type, pref_code, area_name, facility_type, room_occupancy_rate
    from {{ ref('stg_overnight__occupancy') }}
    where month = 0
        and area_type != 'transport_bureau'
        and employee_size = '総数'
        and purpose = '計'
),

stays as (
    select
        year,
        area_name,
        facility_type,
        max(if(target = '全体', guest_nights, null)) as guest_nights,
        max(if(target = '外国人', guest_nights, null)) as foreign_guest_nights
    from {{ ref('stg_overnight__stays_by_facility_type') }}
    where month = 0
        and area_type != 'transport_bureau'
    group by 1, 2, 3
),

-- 第1表には年計がないため、12 月の施設数を使う
facilities as (
    select year, area_name, facility_type, facilities
    from {{ ref('stg_overnight__facilities') }}
    where month = 12
        and area_type != 'transport_bureau'
        and employee_size = '総数'
        and purpose = '計'
)

select
    occupancy.area_type,
    occupancy.pref_code,
    occupancy.area_name,
    if(occupancy.pref_code is not null, concat('JP-', occupancy.pref_code), null) as iso_3166_2,
    occupancy.facility_type,
    occupancy.year,
    date(occupancy.year, 1, 1) as year_date,
    occupancy.room_occupancy_rate,
    stays.guest_nights,
    stays.foreign_guest_nights,
    safe_divide(stays.foreign_guest_nights, stays.guest_nights) as foreign_share,
    facilities.facilities as facilities_december,
    occupancy.year between 2020 and 2022 as is_covid_period
from occupancy
left join stays using (year, area_name, facility_type)
left join facilities using (year, area_name, facility_type)
