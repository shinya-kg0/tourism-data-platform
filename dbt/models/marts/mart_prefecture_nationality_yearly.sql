-- ダッシュボード 3. 地域分析：都道府県 × 国籍 × 年（都道府県 × 国籍のヒートマップ）
-- 宿泊者数は参考第1表（従業者数 10 人以上の施設）のため、第2表の外国人延べ宿泊者数（全施設）より小さい

with periods as (
    select * from {{ ref('int_consumption_yearly_periods') }}
),

nights as (
    select year, pref_code, nationality_code, foreign_guest_nights
    from {{ ref('stg_overnight__foreign_stays_by_nationality') }}
    where area_type = 'prefecture'
        and month = 0
),

visit as (
    select visit_rate.year, visit_rate.pref_code, visit_rate.nationality_code, visit_rate.visitors, visit_rate.visit_rate
    from {{ ref('stg_consumption__prefecture_visit_rate') }} as visit_rate
    inner join periods using (year, quarter)
    where visit_rate.area_type = 'prefecture'
),

spend as (
    select night.year, night.pref_code, night.nationality_code, night.respondents, night.spend_per_night
    from {{ ref('stg_consumption__spend_per_night_by_prefecture') }} as night
    inner join periods using (year, quarter)
    where night.area_type = 'prefecture'
        and night.nationality_code is not null
),

joined as (
    select *
    from nights
    full outer join visit using (year, pref_code, nationality_code)
    full outer join spend using (year, pref_code, nationality_code)
)

select
    joined.pref_code,
    pref.pref_name,
    concat('JP-', joined.pref_code) as iso_3166_2,
    pref.region,
    joined.nationality_code,
    nat.name_ja as nationality_name,
    nat.region as nationality_region,
    nat.sort_order as nationality_sort_order,
    joined.nationality_code = 'ALL' as is_total,
    joined.year,
    date(joined.year, 1, 1) as year_date,
    joined.foreign_guest_nights,
    -- その県に泊まった外国人のうち、この国籍が占める割合
    safe_divide(
        joined.foreign_guest_nights,
        max(if(joined.nationality_code = 'ALL', joined.foreign_guest_nights, null))
            over (partition by joined.pref_code, joined.year)
    ) as nationality_share_in_prefecture,
    joined.visitors,
    joined.visit_rate,
    joined.respondents as spend_respondents,
    joined.spend_per_night,
    joined.respondents < {{ var('min_respondents') }} as is_low_sample,
    joined.year between 2020 and 2022 as is_covid_period
from joined
inner join {{ ref('seed_prefecture') }} as pref using (pref_code)
inner join {{ ref('seed_nationality') }} as nat using (nationality_code)
