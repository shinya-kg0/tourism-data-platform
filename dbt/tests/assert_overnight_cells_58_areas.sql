-- 宿泊旅行統計の全表で、年・月ごとに 58 地域（全国 1・都道府県 47・運輸局等 10）がそろっている（D-11）

select table_id, year, month, count(distinct area_name) as n_areas
from {{ source('raw', 'overnight_cells') }}
group by 1, 2, 3
having count(distinct area_name) != 58
