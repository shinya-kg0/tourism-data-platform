-- 値が空なら、必ず記号（- など）が入っている。理由の分からない欠損がないこと

select *
from {{ ref('stg_overnight__stays') }}
where guest_nights is null
    and flag is null
