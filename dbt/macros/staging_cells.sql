{#
  staging で使う raw の読み方（表ごとの staging モデルで共通の部分）

  overnight_cells(table_id)
    宿泊旅行統計の 1 表を読み、同じ年に複数の公表区分があれば最も新しいものだけを残す。
    地域の種類（全国・都道府県・運輸局等）と、Excel にない年の都道府県コードを補う。

  consumption_cells(table_id)
    消費動向調査の 1 表を読み、同じ年・期に複数の公表区分があれば最も新しいものだけを残す
    （仕様書 7.2：final ＞ preliminary2 ＞ preliminary1）。
#}

{% macro overnight_cells(table_id) %}
    select
        cells.year,
        cells.month,
        case
            when cells.area_name = '全国' then 'national'
            when pref.pref_code is not null then 'prefecture'
            else 'transport_bureau'
        end as area_type,
        -- Excel に地域コードがない年（2016・2020〜2024 年）はマスタで補う
        coalesce(cells.area_code, pref.pref_code) as pref_code,
        cells.area_name,
        cells.target,
        cells.header_group,
        cells.header_sub,
        cells.header_item,
        cells.value,
        cells.flag,
        cells.release_status,
        cells.format_version
    from {{ source('raw', 'overnight_cells') }} as cells
    inner join {{ ref('seed_release_status') }} as rs using (release_status)
    left join {{ ref('seed_prefecture') }} as pref
        on cells.area_name = pref.pref_name
    where cells.table_id = '{{ table_id }}'
    qualify rs.priority = max(rs.priority) over (partition by cells.year)
{% endmacro %}

{% macro consumption_cells(table_id) %}
    select
        cells.year,
        cells.quarter,
        cells.row_category,
        cells.row_item,
        -- 2017 年以前は総数の列が「全体」
        if(cells.col_member = '全体', '全国籍･地域', cells.col_member) as col_member,
        cells.measure,
        cells.value,
        cells.flag,
        cells.release_status,
        cells.format_version
    from {{ source('raw', 'consumption_cells') }} as cells
    inner join {{ ref('seed_release_status') }} as rs using (release_status)
    where cells.table_id = '{{ table_id }}'
    qualify rs.priority = max(rs.priority) over (partition by cells.year, cells.quarter)
{% endmacro %}

{#
  overnight_breakdown(total_item)
    第1表・第8表の列（従業者数 × 宿泊目的割合の 15 列と、宿泊施設タイプの 6 列）を、
    employee_size / purpose / facility_type の 3 列に分ける。total_item は先頭の列（総数）の項目名。
    施設タイプの列は従業者数「総数」・宿泊目的「計」、従業者数の列は施設タイプ「全体」として扱う。
#}
{% macro overnight_breakdown(total_item) %}
    case
        when header_group like '宿泊施設タイプ%' then '総数'
        else coalesce(header_sub, '総数')
    end as employee_size,
    case
        when header_group like '宿泊施設タイプ%' then '計'
        when header_item in ('{{ total_item }}', '計') then '計'
        else header_item
    end as purpose,
    if(header_group like '宿泊施設タイプ%', header_item, '全体') as facility_type
{% endmacro %}
