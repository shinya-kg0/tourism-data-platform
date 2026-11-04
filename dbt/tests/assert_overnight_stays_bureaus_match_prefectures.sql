-- 運輸局等 = 所属する都道府県の合計（seed_prefecture の対応が正しいことの確認も兼ねる）

with prefectures as (
    select
        stays.year, stays.month, stays.target, stays.employee_size, stays.purpose,
        pref.transport_bureau as area_name,
        sum(stays.guest_nights) as guest_nights,
        count(*) as n_prefs
    from {{ ref('stg_overnight__stays') }} as stays
    inner join {{ ref('seed_prefecture') }} as pref using (pref_code)
    where stays.area_type = 'prefecture'
    group by 1, 2, 3, 4, 5, 6
),

bureaus as (
    select year, month, target, employee_size, purpose, area_name, guest_nights
    from {{ ref('stg_overnight__stays') }}
    where area_type = 'transport_bureau'
)

select
    bureaus.*,
    prefectures.guest_nights as prefecture_sum
from bureaus
left join prefectures using (year, month, target, employee_size, purpose, area_name)
where prefectures.area_name is null
    or abs(bureaus.guest_nights - prefectures.guest_nights) > 5 * (prefectures.n_prefs + 1)
