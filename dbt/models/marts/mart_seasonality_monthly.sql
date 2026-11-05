-- ダッシュボード 4. 季節性：国籍 × 年 × 月の外国人延べ宿泊者数（全国、従業者数 10 人以上の施設）

with nights as (
    select year, month, nationality_code, foreign_guest_nights
    from {{ ref('stg_overnight__foreign_stays_by_nationality') }}
    where area_type = 'national'
)

select
    monthly.nationality_code,
    nat.name_ja as nationality_name,
    nat.region,
    nat.sort_order,
    monthly.nationality_code = 'ALL' as is_total,
    monthly.year,
    monthly.month,
    date(monthly.year, monthly.month, 1) as month_date,
    monthly.foreign_guest_nights,
    -- 年計に占める割合（公表値の丸めのため、12 か月の合計はちょうど 1 にならない）
    safe_divide(monthly.foreign_guest_nights, annual.foreign_guest_nights) as share_of_year,
    safe_divide(
        monthly.foreign_guest_nights,
        lag(monthly.foreign_guest_nights, 12) over (partition by monthly.nationality_code order by monthly.year, monthly.month)
    ) - 1 as foreign_guest_nights_yoy,
    monthly.year between 2020 and 2022 as is_covid_period
from nights as monthly
inner join nights as annual
    on monthly.nationality_code = annual.nationality_code
    and monthly.year = annual.year
    and annual.month = 0
inner join {{ ref('seed_nationality') }} as nat
    on monthly.nationality_code = nat.nationality_code
where monthly.month between 1 and 12
