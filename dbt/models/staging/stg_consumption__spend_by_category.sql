-- 消費動向調査 表2-1：国籍・地域別の費目別購入率と購入者単価
-- 1 行 = 年 × 期 × 国籍 × 費目（内訳の行は sub_category に内訳名が入る）

with cells as (
    {{ consumption_cells('表2-1') }}
),

pivoted as (
    select
        year,
        quarter,
        col_member,
        row_item,
        -- 購入率と購入者単価は別の塊に並び、どちらにも同じ回答数（購入者数）が付く
        max(if(measure = '回答数', value, null)) as purchasers,
        max(if(measure = '購入率', value, null)) as purchase_rate_pct,
        max(if(measure = '購入者単価', value, null)) as spend_per_purchaser,
        max(if(measure = '購入者単価', flag, null)) as flag,
        any_value(release_status) as release_status,
        any_value(format_version) as format_version
    from cells
    group by 1, 2, 3, 4
)

select
    pivoted.year,
    pivoted.quarter,
    nat.nationality_code,
    cat.spend_stage,
    cat.spend_category,
    -- 内訳の行は「交通費／バス」の形で入っている
    nullif(split(pivoted.row_item, '／')[safe_offset(1)], '') as sub_category,
    pivoted.purchasers,
    pivoted.purchase_rate_pct / 100 as purchase_rate,
    pivoted.spend_per_purchaser,
    -- 回答者全体で割った 1 人当たりの支出（購入しなかった人を 0 円として平均したもの）
    pivoted.purchase_rate_pct / 100 * pivoted.spend_per_purchaser as spend_per_visitor,
    pivoted.flag,
    pivoted.release_status,
    pivoted.format_version
from pivoted
left join {{ ref('seed_nationality') }} as nat
    on pivoted.col_member = nat.consumption_label
-- 2017 年以前は「宿泊料金」「娯楽サービス費」なので、シードで今の名前にそろえる
left join {{ ref('seed_spend_category') }} as cat
    on split(pivoted.row_item, '／')[offset(0)] = cat.consumption_label
