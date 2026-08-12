-- 1. One review per order (latest by answer timestamp)

create or replace table `Olist.reviews_clean` as

    select order_id, review_score
    from `Olist.olist_order_reviews_dataset`
    qualify row_number() over (partition by order_id order by review_answer_timestamp desc) = 1;
-- qualify row_number()=1 залишає лише найостанніший відгук для кожного замовлення


-- 2. ORDER-LEVEL table
-- 1 row per order_id

create or replace table `Olist.dashboard_orders` as

    with order_revenue as (
    select
        order_id,                                           
        count(order_item_id)as items_count,
        sum(price) as order_revenue
    from `Olist.olist_order_items_dataset`
    group by order_id
    )

    select
    o.order_id,
    o.order_status,
    date(o.order_purchase_timestamp)as purchase_date,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    r.review_score,
    -- revenue aggregated up from items, one number per order
    ore.items_count,
    ore.order_revenue,
    -- time metrics
    timestamp_diff(o.order_approved_at, o.order_purchase_timestamp, hour) as processing_hours,
    timestamp_diff(o.order_approved_at, o.order_purchase_timestamp, second) / 60 as processing_minutes,
    -- total time customer actually waited: purchase -> delivered
    date_diff(date(o.order_delivered_customer_date), date(o.order_purchase_timestamp), day) as delivery_days,
    date_diff(date(o.order_delivered_customer_date), date(o.order_estimated_delivery_date), day) as delay_days,
    case
        when date(o.order_delivered_customer_date) < date(o.order_estimated_delivery_date) then 'Early'
        when date(o.order_delivered_customer_date) = date(o.order_estimated_delivery_date) then 'On Time'
        when date(o.order_delivered_customer_date) > date(o.order_estimated_delivery_date) then 'Late'
    end as delivery_status,
    case when o.order_status = 'delivered' then 1 else 0 end as is_delivered,
    case when o.order_status = 'canceled'  then 1 else 0 end as is_canceled,
    case when date(o.order_delivered_customer_date) > date(o.order_estimated_delivery_date) then 1 else 0 end as is_late

    from `Olist.olist_orders_dataset` o

    join `Olist.olist_customers_dataset` c
    on o.customer_id = c.customer_id

    left join order_revenue ore
    on o.order_id = ore.order_id

    left join `Olist.reviews_clean` r
    on o.order_id = r.order_id;

-- 3. ORDER-ITEM-LEVEL table
-- Grain = 1 row per order_item_id
create or replace table `Olist.dashboard_order_items` as

    select
    o.order_id,
    oi.order_item_id,
    o.order_status,
    date(o.order_purchase_timestamp) as purchase_date,
    c.customer_unique_id,
    c.customer_state,
    p.product_id,
    coalesce(t.product_category_name_english, 'Unknown') as product_category,
    oi.price,
    oi.freight_value

    from `Olist.olist_orders_dataset` o

    join `Olist.olist_customers_dataset` c
    on o.customer_id = c.customer_id

    join `Olist.olist_order_items_dataset` oi
    on o.order_id = oi.order_id

    join `Olist.olist_products_dataset` p
    on oi.product_id = p.product_id

    left join `Olist.product_category_translation` t
    on p.product_category_name = t.product_category_name