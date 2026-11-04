-- 年計 = 1〜12 月の合計（D-11）
-- 公表値は 10 人泊単位の四捨五入なので、1 セルの誤差は最大 ±5。13 セル分の 65 までは丸めとみなす

with annual as (
    select year, area_name, target, employee_size, purpose, guest_nights
    from {{ ref('stg_overnight__stays') }}
    where month = 0
),

monthly as (
    select year, area_name, target, employee_size, purpose, sum(guest_nights) as guest_nights, count(*) as n_months
    from {{ ref('stg_overnight__stays') }}
    where month between 1 and 12
    group by 1, 2, 3, 4, 5
)

select
    annual.*,
    monthly.guest_nights as monthly_sum,
    monthly.n_months
from annual
inner join monthly using (year, area_name, target, employee_size, purpose)
where monthly.n_months != 12
    or abs(annual.guest_nights - monthly.guest_nights) > 5 * (12 + 1)
