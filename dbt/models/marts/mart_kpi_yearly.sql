-- ダッシュボード 1. サマリ：全国の主要指標（年）
-- フェーズ2では延べ宿泊者数のみ。消費単価・客室稼働率はフェーズ4で追加する

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
)

select
    year,
    -- Looker Studio の時系列グラフ用（年の 1 月 1 日）
    date(year, 1, 1) as year_date,
    total_guest_nights,
    japanese_guest_nights,
    foreign_guest_nights,
    safe_divide(foreign_guest_nights, total_guest_nights) as foreign_share,
    safe_divide(total_guest_nights, lag(total_guest_nights) over (order by year)) - 1 as total_guest_nights_yoy,
    safe_divide(japanese_guest_nights, lag(japanese_guest_nights) over (order by year)) - 1 as japanese_guest_nights_yoy,
    safe_divide(foreign_guest_nights, lag(foreign_guest_nights) over (order by year)) - 1 as foreign_guest_nights_yoy,
    -- コロナの影響で調査の中止・急減がある期間。グラフで色を分けるのに使う
    year between 2020 and 2022 as is_covid_period
from with_japanese
