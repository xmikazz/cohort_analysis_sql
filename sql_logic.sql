WITH fbs_model_universe AS (
    select distinct
        date_trunc('month',grass_date) grass_month,
        grass_region,
        shop_id,
        mp_item_id item_id,
        mp_model_id model_id,
        shop_first_inbound_date,
        case when date_trunc('month',mt_sku_first_inbound_date) = date_trunc('month',grass_date)
             then 1 else 0 end is_new_model,
        shop_business_type,
        max(
            case when model_status = 1
                and item_status = 1
                and model_stock > 0
                and sellable_qty > 0
                and whs_id <> 'XXA'
                and substring(whs_id,1,2) = grass_region
            then 1 else 0 end
        ) over(partition by date_trunc('month',grass_date),shop_id) AS is_active_shop
    from dim_shop_registration
    where grass_date >= DATE '2025-01-01'
      and grass_region = 'XX'
      and ((grass_region != 'VN' and lower(shop_business_type) like '%fbs%')
        or (grass_region = 'VN' and shop_business_type = 'LOCAL_FBS'))
),

fbs_shop_from_order_mart AS (
    select distinct
        t1.grass_region,
        date_trunc('MONTH',date(t1.create_datetime)) AS grass_month,
        t1.shop_id,
        t2.shop_business_type
    from fact_order_item t1
    inner join (
        select distinct grass_region,shop_id,shop_business_type
        from fbs_model_universe
    ) t2
        on t1.shop_id = t2.shop_id
       and t1.grass_region = t2.grass_region
    where date(t1.grass_date) >= DATE '2025-01-01'
      and date(t1.create_datetime) >= DATE '2025-01-01'
      and t1.grass_region = 'XX'
      and t1.is_bi_excluded = 0
      and t1.tz_type = 'local'
      and t1.fulfilment_source = 'FULFILLED_BY_PLATFORM'
      and substring(t1.updated_warehouse_code,1,2) = t1.grass_region
      and substring(t1.updated_warehouse_code,1,3) != 'XXA'
),

fbs_shop_universe AS (
    WITH pre_fbs_shop_universe AS (
        select
            grass_region,
            grass_month,
            shop_id,
            shop_business_type,
            null shop_first_inbound_date,
            max(is_active_shop) as is_active_shop
        from (
            select distinct
                grass_region,
                grass_month,
                shop_id,
                shop_business_type,
                null shop_first_inbound_date,
                is_active_shop
            from fbs_model_universe

            union

            select
                grass_region,
                grass_month,
                shop_id,
                shop_business_type,
                null shop_first_inbound_date,
                1 is_active_shop
            from fbs_shop_from_order_mart
        )
        group by 1,2,3,4,5
    )

    select distinct
        t1.grass_region,
        t1.grass_month,
        t1.shop_id,
        t1.shop_business_type,
        t1.shop_first_inbound_date,
        t1.is_active_shop,
        coalesce(t2.is_active_shop,0) is_active_shop_l1m
    from pre_fbs_shop_universe t1
    left join pre_fbs_shop_universe t2
        on t1.grass_region = t2.grass_region
       and t1.grass_month = t2.grass_month + interval '1' month
       and t1.shop_id = t2.shop_id
),

fbs_order AS (
    select
        date_trunc('month',date(t1.create_datetime)) grass_month,
        t1.grass_region,
        t1.shop_id,
        t1.item_id,
        t1.model_id,
        sum(case when t1.fulfilment_source = 'FULFILLED_BY_PLATFORM'
             and substring(t1.updated_warehouse_code,1,2) = t1.grass_region
             and substring(t1.updated_warehouse_code,1,3) != 'XXA'
             then t1.order_fraction end) gross_fbs_order_fraction,
        sum(case when t1.fulfilment_source = 'FULFILLED_BY_PLATFORM'
             and substring(t1.updated_warehouse_code,1,2) = t1.grass_region
             and substring(t1.updated_warehouse_code,1,3) != 'XXA'
             then t1.gmv_usd end) gross_fbs_gmv_usd,
        sum(case when t1.fulfilment_source = 'FULFILLED_BY_PLATFORM'
             and substring(t1.updated_warehouse_code,1,2) = t1.grass_region
             and substring(t1.updated_warehouse_code,1,3) != 'XXA'
             and t1.is_net_order = 1
             then t1.order_fraction end) net_fbs_order_fraction,
        sum(case when t1.fulfilment_source = 'FULFILLED_BY_PLATFORM'
             and substring(t1.updated_warehouse_code,1,2) = t1.grass_region
             and substring(t1.updated_warehouse_code,1,3) != 'XXA'
             and t1.is_net_order = 1
             then t1.gmv_usd end) net_fbs_gmv_usd,
        sum(case when t1.fulfilment_source = 'FULFILLED_BY_PLATFORM'
             and substring(t1.updated_warehouse_code,1,2) = t1.grass_region
             and substring(t1.updated_warehouse_code,1,3) != 'XXA'
             then t1.item_amount end) gross_fbs_item_amount,
        sum(order_fraction) gross_full_shop_order_fraction
    from fact_order_item t1
    where date(t1.grass_date) >= DATE '2025-01-01'
      and date(t1.create_datetime) >= DATE '2025-01-01'
      and t1.grass_region = 'XX'
      and t1.is_bi_excluded = 0
      and t1.tz_type = 'local'
    group by 1,2,3,4,5
),

full_fbs_ado AS (
    WITH shop_order AS (
        select
            grass_month,
            grass_region,
            shop_id,
            sum(gross_fbs_order_fraction) gross_fbs_order_fraction,
            sum(gross_fbs_gmv_usd) gross_fbs_gmv_usd,
            sum(net_fbs_order_fraction) net_fbs_order_fraction,
            sum(net_fbs_gmv_usd) net_fbs_gmv_usd,
            sum(gross_fbs_item_amount) gross_fbs_item_amount,
            sum(gross_full_shop_order_fraction) gross_full_shop_order_fraction,
            IF(sum(gross_fbs_order_fraction) > 0,1,0) have_fbs_order
        from fbs_order
        group by 1,2,3
    )

    select
        t1.grass_region,
        t1.grass_month,
        t1.shop_business_type,
        t1.shop_id,
        sum(t2.gross_fbs_order_fraction) gross_fbs_order_fraction,
        sum(t2.gross_fbs_gmv_usd) gross_fbs_gmv_usd,
        sum(t2.net_fbs_order_fraction) net_fbs_order_fraction,
        sum(t2.net_fbs_gmv_usd) net_fbs_gmv_usd,
        sum(t2.gross_fbs_item_amount) gross_fbs_item_amount,
        sum(t2.gross_full_shop_order_fraction) gross_full_shop_order_fraction,
        IF(sum(have_fbs_order) > 0,1,0) have_fbs_order
    from fbs_shop_universe t1
    left join shop_order t2
        on t1.grass_region = t2.grass_region
       and t1.grass_month = t2.grass_month
       and t1.shop_id = t2.shop_id
    where t1.is_active_shop = 1
    group by 1,2,3,4
),

existing_universe_model AS (
    select
        t1.grass_month,
        t1.grass_region,
        t1.shop_id,
        t1.item_id,
        t1.model_id,
        t1.is_new_model is_new_model_m0,
        case when t2.model_id is not null then 1 else 0 end is_exist_both_month,
        t1.shop_business_type
    from fbs_model_universe t1
    left join fbs_model_universe t2
        on t1.grass_month = t2.grass_month + interval '1' month
       and t1.model_id = t2.model_id
    where t1.is_active_shop = 1
      and t2.is_active_shop = 1
),

existing_fbs_ado AS (
    select
        t1.grass_month,
        t1.grass_region,
        t1.shop_business_type,
        t1.shop_id,
        sum(t2.gross_fbs_order_fraction) gross_fbs_order_fraction_existing_m0,
        sum(t3.gross_fbs_order_fraction) gross_fbs_order_fraction_existing_l1m
    from existing_universe_model t1
    left join fbs_order t2
        on t1.grass_region = t2.grass_region
       and t1.grass_month = t2.grass_month
       and t1.model_id = t2.model_id
    left join fbs_order t3
        on t1.grass_region = t3.grass_region
       and t1.grass_month = t3.grass_month + interval '1' month
       and t1.model_id = t3.model_id
    where is_new_model_m0 = 0
      and is_exist_both_month = 1
    group by 1,2,3,4
),

final AS (
    select
        t1.grass_region,
        t1.grass_month,
        t1.shop_business_type,
        t1.shop_id,
        case
            when t1.is_active_shop = 1 then 1
            when t2.shop_id is not null then 1
            else 0 end is_active_shop,
        t1.is_active_shop_l1m,
        t1.shop_first_inbound_date,
        t2.have_fbs_order,
        t2.gross_fbs_order_fraction,
        t2.gross_fbs_gmv_usd,
        t2.net_fbs_order_fraction,
        t2.net_fbs_gmv_usd,
        t2.gross_fbs_item_amount,
        t2.gross_full_shop_order_fraction,
        coalesce(t2.gross_fbs_order_fraction/nullif(t2.gross_full_shop_order_fraction,0),0) fbs_share,
        t3.gross_fbs_order_fraction_existing_m0,
        t3.gross_fbs_order_fraction_existing_l1m
    from fbs_shop_universe t1
    left join full_fbs_ado t2
        on t1.grass_region = t2.grass_region
       and t1.grass_month = t2.grass_month
       and t1.shop_id = t2.shop_id
    left join existing_fbs_ado t3
        on t1.grass_region = t3.grass_region
       and t1.grass_month = t3.grass_month
       and t1.shop_id = t3.shop_id
)

-- Final output: shops that churned this month (active last month, inactive this month)

SELECT
    grass_region,
    grass_month,
    shop_id,
    shop_business_type,
    is_active_shop,
    is_active_shop_l1m,
    fbs_share,
    'CHURN' AS churn_flag
FROM final
WHERE grass_month = DATE '2025-11-01'
  AND is_active_shop = 0
  AND coalesce(is_active_shop_l1m,0) = 1
ORDER BY shop_id;
