-- 前年比が ±80％ を超える年があれば警告する（取り込みミスの早期発見用）
-- コロナの影響期間（2020〜2022 年）と、その翌年の 2023 年（反動で急増）は対象外
{{ config(severity='warn') }}

select
    year,
    total_guest_nights_yoy,
    japanese_guest_nights_yoy,
    foreign_guest_nights_yoy,
    spend_per_trip_yoy
from {{ ref('mart_kpi_yearly') }}
where year not between 2020 and 2023
    and (
        abs(total_guest_nights_yoy) > 0.8
        or abs(japanese_guest_nights_yoy) > 0.8
        or abs(foreign_guest_nights_yoy) > 0.8
        or abs(spend_per_trip_yoy) > 0.8
    )
