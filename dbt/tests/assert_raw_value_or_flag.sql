-- 値が空なら、必ず記号（- など）が入っている。理由の分からない欠損がないこと（D-11）
-- 取り込みの検査でも止めているが、raw 全体を毎回確かめる

select 'overnight_cells' as source_table, table_id, year, count(*) as n_cells
from {{ source('raw', 'overnight_cells') }}
where value is null
    and flag is null
group by 1, 2, 3

union all

select 'consumption_cells', table_id, year, count(*)
from {{ source('raw', 'consumption_cells') }}
where value is null
    and flag is null
group by 1, 2, 3
