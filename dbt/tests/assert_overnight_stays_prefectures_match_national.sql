-- 47 都道府県の合計 = 全国（丸めの誤差は 5 ×（47 + 1）まで）

with prefectures as (
    select year, month, target, employee_size, purpose, sum(guest_nights) as guest_nights, count(*) as n_prefs
    from {{ ref('stg_overnight__stays') }}
    where area_type = 'prefecture'
    group by 1, 2, 3, 4, 5
),

national as (
    select year, month, target, employee_size, purpose, guest_nights
    from {{ ref('stg_overnight__stays') }}
    where area_type = 'national'
)

select
    national.*,
    prefectures.guest_nights as prefecture_sum,
    prefectures.n_prefs
from national
inner join prefectures using (year, month, target, employee_size, purpose)
where prefectures.n_prefs != 47
    or abs(national.guest_nights - prefectures.guest_nights) > 5 * (47 + 1)
