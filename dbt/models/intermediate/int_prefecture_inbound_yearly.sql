-- 都道府県 × 年：外国人延べ宿泊者数（宿泊旅行統計 第2表）× 1 人 1 泊当たり旅行消費単価（消費動向調査 表3-4）
-- → 外国人の推計消費額（宿泊を伴う消費の目安。日帰りの消費は含まない）
-- 表3-4 は地域調査（B1）の結果で、回答数が少ない県は値がぶれる（仕様書 17 章）。
-- 回答数が var('min_respondents') 未満の県は is_low_sample を立てる（値がない年は NULL）

with nights as (
    select
        year,
        pref_code,
        max(if(target = '全体', guest_nights, null)) as total_guest_nights,
        max(if(target = '外国人', guest_nights, null)) as foreign_guest_nights
    from {{ ref('stg_overnight__stays') }}
    where area_type = 'prefecture'
        and month = 0
        and employee_size = '総数'
        and purpose = '計'
    group by 1, 2
),

periods as (
    select * from {{ ref('int_consumption_yearly_periods') }}
),

spend as (
    select
        night.year,
        night.pref_code,
        periods.period_label as consumption_period_label,
        periods.quarter as consumption_quarter,
        night.respondents as spend_respondents,
        night.spend_per_night
    from {{ ref('stg_consumption__spend_per_night_by_prefecture') }} as night
    inner join periods using (year, quarter)
    where night.area_type = 'prefecture'
        and night.nationality_code = 'ALL'
)

select
    nights.year,
    nights.pref_code,
    nights.total_guest_nights,
    nights.foreign_guest_nights,
    spend.consumption_period_label,
    spend.spend_respondents,
    spend.spend_per_night,
    spend.spend_respondents < {{ var('min_respondents') }} as is_low_sample,
    -- 宿泊者数は 1 年分なので、消費単価も暦年の値があるときだけ掛け合わせる
    if(spend.consumption_quarter = 0, nights.foreign_guest_nights * spend.spend_per_night, null)
        as estimated_foreign_spend
from nights
left join spend using (year, pref_code)
