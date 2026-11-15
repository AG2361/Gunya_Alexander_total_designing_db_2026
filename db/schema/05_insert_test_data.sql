create or replace procedure gunya_food.insert_test_data(value int)
language plpgsql
set search_path = gunya_food, public
as $$
declare
    v_start  timestamp := date_trunc('month', now()) - interval '5 months';
    v_active int;
    v_m      timestamp;
    m        int;
    streets  text[] := array['Ленина','Мира','Советская','Садовая','Центральная',
                             'Лесная','Школьная','Пушкина','Гагарина','Заречная'];
begin
    if value is null or value < 1 then
        raise exception 'insert_test_data: value должен быть положительным числом, получено %', value;
    end if;

    drop table if exists pg_temp.tmp_addr, pg_temp.tmp_client, pg_temp.tmp_cat, pg_temp.tmp_rest,
        pg_temp.tmp_courier, pg_temp.tmp_active, pg_temp.tmp_prod, pg_temp.tmp_ord0,
        pg_temp.tmp_ord, pg_temp.tmp_item;

    -- адреса: первые value под рестораны, остальные value*4 под клиентов
    create temp table tmp_addr as
        select g as n, exts.uuid_generate_v4() as address_id
        from generate_series(1, value * 5) g;
    insert into address (address_id, street, house_number, apartment_office)
    select address_id,
           streets[1 + floor(random() * array_length(streets, 1))::int],
           (1 + floor(random() * 150))::int::text,
           case when random() < 0.3 then null else (1 + floor(random() * 200))::int::text end
    from tmp_addr;

    -- клиенты и их адреса (по 4 на клиента)
    create temp table tmp_client as
        select g as n, exts.uuid_generate_v4() as client_id
        from generate_series(1, value) g;
    insert into client (client_id, login, password, phone_number)
    select client_id,
           'user_' || substr(md5(random()::text || clock_timestamp()::text || n::text), 1, 16),
           md5(random()::text),
           '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0')
    from tmp_client;
    insert into client_address (client_id, address_id)
    select c.client_id, a.address_id
    from tmp_client c
    join tmp_addr a on a.n > value and (a.n - value - 1) / 4 + 1 = c.n;

    -- категории
    create temp table tmp_cat as
        select g as n, exts.uuid_generate_v4() as id from generate_series(1, value) g;
    insert into product_category (product_category_id, product_category_name)
    select id, 'Категория ' || substr(md5(random()::text), 1, 8) from tmp_cat;

    -- рестораны (адрес n-го ресторана = n-й адрес)
    create temp table tmp_rest as
        select g as n, exts.uuid_generate_v4() as id from generate_series(1, value) g;
    insert into restaurant (restaurant_id, restaurant_name, address_id, description,
                            work_start, work_end, company_details, rating, status)
    select r.id,
           'Ресторан ' || substr(md5(random()::text), 1, 8),
           a.address_id,
           'Описание ресторана ' || r.n,
           time '09:00', time '23:00',
           'ИНН ' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'),
           null,
           (enum_range(null::restaurant_status))[1 + floor(random() * cardinality(enum_range(null::restaurant_status)))::int]
    from tmp_rest r
    join tmp_addr a on a.n = r.n;

    -- курьеры: первый всегда работающий (BR-6.6)
    create temp table tmp_courier as
        select g as n, exts.uuid_generate_v4() as id, (g > 1 and random() < 0.3) as fired
        from generate_series(1, value) g;
    insert into courier (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
    select id,
           'Курьер ' || substr(md5(random()::text), 1, 10),
           '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'),
           case when fired then 'уволен'::courier_status
                else (enum_range(null::courier_status))[1 + floor(random() * 3)::int] end,
           v_start::date,
           case when fired then v_start::date + (30 + floor(random() * 100))::int else null end,
           0.1
    from tmp_courier;

    create temp table tmp_active as
        select row_number() over (order by id)::int as k, id from tmp_courier where not fired;
    select count(*) into v_active from tmp_active;

    -- блюда: по 5 на каждый ресторан
    create temp table tmp_prod as
        select g as n, exts.uuid_generate_v4() as id,
               (g - 1) % value + 1 as rn,
               1 + floor(random() * value)::int as cn,
               round((400 + random() * 1100)::numeric, 2) as price
        from generate_series(1, value * 5) g;
    insert into product (product_id, product_name, product_category_id, price, restaurant_id,
                         photo_url, rating, status, description)
    select p.id,
           'Блюдо ' || substr(md5(random()::text), 1, 8),
           c.id, p.price, r.id,
           case when random() < 0.5 then null else 'https://example.com/img/' || p.id end,
           null,
           case when random() < 0.9 then 'доступно'::product_status else 'нет_в_наличии'::product_status end,
           'Описание блюда'
    from tmp_prod p
    join tmp_rest r on r.n = p.rn
    join tmp_cat  c on c.n = p.cn;

    -- заказы: случайные параметры считаем заранее, потом соединяем
    create temp table tmp_ord0 as
        select g as n, exts.uuid_generate_v4() as order_id,
               1 + floor(random() * value)::int as cn,
               1 + floor(random() * 4)::int as ak,
               1 + floor(random() * value)::int as rn,
               1 + floor(random() * v_active)::int as kn,
               v_start + random() * (localtimestamp - interval '1 day' - v_start) as ts,
               case when random() < 0.5 then 'доставлен'::order_status
                    else (enum_range(null::order_status))[1 + floor(random() * 5)::int] end as status,
               (20 + floor(random() * 70))::int as dmin,
               1 + floor(random() * 3)::int as rk
        from generate_series(1, value * 5) g;
    create temp table tmp_ord as
        select o.*, c.client_id, a.address_id, r.id as restaurant_id, cu.id as courier_id
        from tmp_ord0 o
        join tmp_client c  on c.n = o.cn
        join tmp_addr   a  on a.n = value + (o.cn - 1) * 4 + o.ak
        join tmp_rest   r  on r.n = o.rn
        join tmp_active cu on cu.k = o.kn;

    -- позиции: 3 разных блюда ресторана заказа
    create temp table tmp_item as
        select o.order_id, p.id as product_id, p.price, (1 + floor(random() * 3))::int as qty
        from tmp_ord o
        join lateral (select id, price from tmp_prod where rn = o.rn order by random() limit 3) p on true;

    insert into "order" (order_id, courier_id, client_id, address_id, restaurant_id,
                         order_timestamp, delivery_timestamp, order_amount, status, pay_status, description)
    select t.order_id, t.courier_id, t.client_id, t.address_id, t.restaurant_id,
           t.ts,
           case when t.status = 'доставлен' then t.ts + t.dmin * interval '1 minute' else null end,
           s.amount, t.status, 'оплачен'::order_pay_status, 'Тестовый заказ'
    from tmp_ord t
    join (select order_id, sum(price * qty) as amount from tmp_item group by order_id) s
      on s.order_id = t.order_id;

    insert into order_structure (order_id, product_id, quantity)
    select order_id, product_id, qty from tmp_item;

    -- платежи: ровно один успешный на заказ (BR-8.1, BR-8.4, BR-8.7)
    insert into payment (payment_id, order_id, pay_type, amount, transaction_id, payment_timestamp, status)
    select exts.uuid_generate_v4(), o.order_id,
           (enum_range(null::payment_type))[1 + floor(random() * cardinality(enum_range(null::payment_type)))::int],
           o.total_amount,
           'tx_' || md5(random()::text || clock_timestamp()::text || o.order_id::text),
           o.order_timestamp + interval '5 minutes',
           'успех'::payment_status
    from "order" o
    join tmp_ord t on t.order_id = o.order_id;

    -- отзывы: по одному на заказ; блюдо / ресторан / заказ (BR-9.2, BR-9.5)
    insert into review (review_id, client_id, review_timestamp, entity_id, entity_type,
                        order_id, description, photo_url, rating)
    select exts.uuid_generate_v4(), t.client_id, t.ts + interval '2 hours',
           case t.rk
               when 1 then (select i.product_id from tmp_item i
                            where i.order_id = t.order_id order by random() limit 1)
               when 2 then t.restaurant_id
               else t.order_id
           end,
           (enum_range(null::review_entity_type))[t.rk],
           t.order_id,
           'Тестовый отзыв',
           case when random() < 0.7 then null else 'https://example.com/review/' || t.n end,
           (1 + floor(random() * 5))::int
    from tmp_ord t;

    -- courier_pay за 6 месяцев по логике BR-10.2: сначала выплата по текущему коэффициенту,
    -- затем новый коэффициент по числу доставок (уволенным не меняется)
    for m in 0..5 loop
        v_m := v_start + m * interval '1 month';

        insert into courier_pay ("year", "month", courier_id, amount, coefficient_used)
        select extract(year from v_m)::int, extract(month from v_m)::int, c.courier_id,
               round(coalesce(sum(o.commission), 0) * c.coefficient, 2),
               c.coefficient
        from courier c
        join tmp_courier t on t.id = c.courier_id
        left join "order" o on o.courier_id = c.courier_id
                           and o.status = 'доставлен'
                           and o.delivery_timestamp >= v_m
                           and o.delivery_timestamp <  v_m + interval '1 month'
        group by c.courier_id, c.coefficient;

        update courier c
        set coefficient = case when s.cnt <= 150 then 0.1
                               when s.cnt <= 250 then 0.2
                               when s.cnt <= 500 then 0.3
                               else 0.5 end
        from (select t.id, t.fired, count(o.order_id) as cnt
              from tmp_courier t
              left join "order" o on o.courier_id = t.id
                                 and o.status = 'доставлен'
                                 and o.delivery_timestamp >= v_m
                                 and o.delivery_timestamp <  v_m + interval '1 month'
              group by t.id, t.fired) s
        where c.courier_id = s.id and not s.fired;
    end loop;

    drop table if exists pg_temp.tmp_addr, pg_temp.tmp_client, pg_temp.tmp_cat, pg_temp.tmp_rest,
        pg_temp.tmp_courier, pg_temp.tmp_active, pg_temp.tmp_prod, pg_temp.tmp_ord0,
        pg_temp.tmp_ord, pg_temp.tmp_item;
end;
$$;