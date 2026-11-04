-- 宿泊旅行統計 第2表：延べ宿泊者数（従業者数・宿泊目的割合別。外国人の内訳あり）
-- 1 行 = 年 × 月 × 地域 × 対象（全体/外国人）× 従業者数 × 宿泊目的

with cells as (
    select *
    from {{ source('raw', 'overnight_cells') }}
    where table_id = '第2表'
),

-- 同じ年に複数の公表区分があれば、最も新しいものだけを使う
latest as (
    select cells.*
    from cells
    inner join {{ ref('seed_release_status') }} as rs using (release_status)
    qualify rs.priority = max(rs.priority) over (partition by cells.year)
),

prefectures as (
    select * from {{ ref('seed_prefecture') }}
)

select
    latest.year,
    latest.month,
    case
        when latest.area_name = '全国' then 'national'
        when prefectures.pref_code is not null then 'prefecture'
        else 'transport_bureau'
    end as area_type,
    -- Excel に地域コードがない年（2016・2020〜2024 年）はマスタで補う
    coalesce(latest.area_code, prefectures.pref_code) as pref_code,
    latest.area_name,
    latest.target,
    coalesce(latest.header_sub, '総数') as employee_size,
    -- 「計」は宿泊目的割合が不詳の施設を含むため、50％以上と50％未満の合計とは一致しない
    case
        when latest.header_item in ('延べ宿泊者数', 'うち外国人延べ宿泊者数', '計') then '計'
        else latest.header_item
    end as purpose,
    latest.value as guest_nights,
    latest.flag,
    latest.release_status,
    latest.format_version
from latest
left join prefectures
    on latest.area_name = prefectures.pref_name
