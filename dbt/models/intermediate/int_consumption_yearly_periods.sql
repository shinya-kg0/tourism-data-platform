-- 消費動向調査で、年ごとの集計にどの期を使うか（1 行 = 年）
-- 暦年の集計表があれば暦年（quarter = 0）を使う。
-- 2020・2021 年はコロナで調査が中止され、暦年の集計表がなく四半期 1 期分しかない（仕様書 3.2）。
-- そのような「暦年の集計表が出る見込みのない過去の年」は、その 1 期分を使い、period_label で注記する。
-- 公表途中の年（暦年の確報がまだなく、最新の暦年より後の年）は使わない。

with periods as (
    select distinct year, quarter
    from {{ ref('stg_consumption__spend_per_trip') }}
),

by_year as (
    select
        year,
        logical_or(quarter = 0) as has_annual,
        count(distinct if(quarter > 0, quarter, null)) as n_quarters,
        max(if(quarter > 0, quarter, null)) as only_quarter
    from periods
    group by year
),

latest_annual as (
    select max(year) as year from by_year where has_annual
)

select
    by_year.year,
    if(by_year.has_annual, 0, by_year.only_quarter) as quarter,
    case
        when by_year.has_annual then '暦年'
        else format('%d–%d月期のみ', by_year.only_quarter * 3 - 2, by_year.only_quarter * 3)
    end as period_label
from by_year
cross join latest_annual
where by_year.has_annual
    or (by_year.n_quarters = 1 and by_year.year < latest_annual.year)
