-- FOOD-108: отчёт «сколько денег» по месяцам (BR-11.9)


create or replace view gunya_food.how_much_money as
with recursive bounds as (
    select date_trunc('month', min(o.delivery_timestamp)) as first_m,
           date_trunc('month', max(o.delivery_timestamp)) as last_m
    from gunya_food."order" o
    where o.status = 'доставлен'
),
months as (
    select b.first_m as m, b.last_m
    from bounds b
    where b.first_m is not null
    union all
    select ms.m + interval '1 month', ms.last_m
    from months ms
    where ms.m < ms.last_m
),
orders_m as (
    select date_trunc('month', o.delivery_timestamp) as m,
           sum(o.order_amount) as s_no,
           sum(o.total_amount) as s_with
    from gunya_food."order" o
    where o.status = 'доставлен'
    group by 1
),
pay_m as (
    select make_date(cp."year", cp."month", 1) as m,
           sum(cp.amount) as pay
    from gunya_food.courier_pay cp
    group by 1
),
monthly as (
    select to_char(ms.m, 'YYYY-MM') as year_month,
           coalesce(o.s_no, 0)::numeric as sum_no_commission,
           coalesce(o.s_with, 0)::numeric as sum_with_commission,
           (coalesce(o.s_with, 0) - coalesce(o.s_no, 0))::numeric as commission,
           coalesce(p.pay, 0)::numeric as courier_pay
    from months ms
    left join orders_m o on o.m = ms.m
    left join pay_m p on p.m = ms.m::date
)
select m.year_month,
       m.sum_no_commission,
       m.sum_with_commission,
       m.commission,
       lag(m.commission) over (order by m.year_month) as prev_commission,
       m.commission - lag(m.commission) over (order by m.year_month) as commission_diff,
       m.courier_pay,
       m.commission - m.courier_pay as net_profit
from monthly m
order by m.year_month;