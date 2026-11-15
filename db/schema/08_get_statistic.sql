-- FOOD-106: статистика по ресторанам (BR-11.8)
-- Заказы читаются один раз (группировка ресторан + клиент), из неё же считаются
-- total_amount, avg_amount и лучший клиент. Лучшее блюдо считается отдельной
-- агрегацией по order_structure. Выбор лучшего: distinct on вместо оконных функций,
-- при равенстве случайный (random() в order by).


create or replace function gunya_food.get_statistic()
returns table (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
language sql
set search_path = gunya_food, public
as $$
    with by_client as (
        select o.restaurant_id, o.client_id,
               count(*)            as cnt,
               sum(o.total_amount) as amt
        from "order" o
        where o.status = 'доставлен'
        group by o.restaurant_id, o.client_id
    ),
    best_client as (
        select distinct on (restaurant_id) restaurant_id, client_id
        from by_client
        order by restaurant_id, cnt desc, random()
    ),
    totals as (
        select restaurant_id,
               sum(amt)                      as total_amt,
               round(sum(amt) / sum(cnt), 2) as avg_amt
        from by_client
        group by restaurant_id
    ),
    by_product as (
        select o.restaurant_id, os.product_id, sum(os.quantity) as qty
        from "order" o
        join order_structure os on os.order_id = o.order_id
        where o.status = 'доставлен'
        group by o.restaurant_id, os.product_id
    ),
    best_product as (
        select distinct on (restaurant_id) restaurant_id, product_id
        from by_product
        order by restaurant_id, qty desc, random()
    )
    select r.restaurant_name,
           p.product_name,
           coalesce(t.total_amt, 0),
           coalesce(t.avg_amt, 0),
           c.login
    from restaurant r
    left join totals       t  on t.restaurant_id  = r.restaurant_id
    left join best_product bp on bp.restaurant_id = r.restaurant_id
    left join product      p  on p.product_id     = bp.product_id
    left join best_client  bc on bc.restaurant_id = r.restaurant_id
    left join client       c  on c.client_id      = bc.client_id
    order by r.restaurant_name;
$$;