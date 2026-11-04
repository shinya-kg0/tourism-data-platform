-- 年・月ごとに、全国 1・都道府県 47・運輸局等 10 の 58 地域がそろっている

select year, month, area_type, count(distinct area_name) as n_areas
from {{ ref('stg_overnight__stays') }}
group by 1, 2, 3
having count(distinct area_name) != case area_type when 'national' then 1 when 'prefecture' then 47 else 10 end
