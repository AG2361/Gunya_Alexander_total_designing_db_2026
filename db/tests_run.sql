-- tests_run.sql: прогон протокола db/tests.md под ролью inspector (psql)
-- запуск: см. инструкцию в чате; вывод сохраняется в db/tests_run.txt
\set ON_ERROR_STOP off
\pset pager off
\pset null '(null)'
set search_path to gunya_food, exts;

\echo '##### ENV'
select current_user as who, version() as pg_version, current_date as run_date;

\echo '##### A.2'
set role inspector;
set search_path to gunya_food, exts;
select current_user;

\echo '##### B.1'
select schema_name from information_schema.schemata where schema_name like '%_food';
\echo '##### B.2'
select extname, extnamespace::regnamespace as schema from pg_extension where extname = 'uuid-ossp';
\echo '##### B.3'
select table_name from information_schema.tables
where table_schema = 'gunya_food' and table_type = 'BASE TABLE' order by table_name;
\echo '##### B.4'
select table_name, column_name, data_type from information_schema.columns
where table_schema = 'gunya_food' and column_name like '%_id' and data_type != 'uuid';
\echo '##### B.5'
select t.typname, array_agg(e.enumlabel order by e.enumsortorder) as values
from pg_type t join pg_enum e on t.oid = e.enumtypid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'gunya_food' group by t.typname order by t.typname;
\echo '##### B.6'
select conname, conrelid::regclass as tbl, confrelid::regclass as ref
from pg_constraint where contype = 'f' and connamespace = 'gunya_food'::regnamespace
order by tbl, conname;
\echo '##### B.7'
select length(password) as len, password from client limit 5;

\echo '##### C.1'
call erase_test_data();
\echo '##### C.2'
call insert_test_data(10);
\echo '##### C.3'
select 'client' as tbl, count(*) from client
union all select 'courier', count(*) from courier
union all select 'product_category', count(*) from product_category
union all select 'restaurant', count(*) from restaurant
union all select 'address', count(*) from address
union all select 'product', count(*) from product
union all select 'order', count(*) from "order"
union all select 'review', count(*) from review
union all select 'payment', count(*) from payment
order by tbl;
\echo '##### C.4'
select 'restaurant addresses' as cat, count(*) from restaurant where address_id is not null
union all select 'total addresses', count(*) from address;
\echo '##### C.5'
select count(*) from client where login = '' or password = '' or phone_number = '';
\echo '##### C.6'
select count(*) from "order" where client_id is null or restaurant_id is null
  or courier_id is null or address_id is null or total_amount is null;
\echo '##### C.7'
select count(*) from courier where status != 'уволен';
\echo '##### C.8'
with t as (
  select cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
         round(coalesce((select sum(o.commission) from "order" o
            where o.courier_id = cp.courier_id and o.status = 'доставлен'
              and extract(year from o.order_timestamp) = cp.year
              and extract(month from o.order_timestamp) = cp.month), 0) * cp.coefficient_used, 2) as expected_amount
  from courier_pay cp)
select count(*) as rows_checked,
       count(*) filter (where amount is distinct from expected_amount) as mismatches
from t;
\echo '##### C.9'
do $$
begin
    for i in 1..10 loop
        call insert_test_data(10);
    end loop;
end $$;
select count(*) as clients_after_10_calls from client;
\echo '##### C.9 reset: erase + insert(10) для чистых чисел дальше'
call erase_test_data();
call insert_test_data(10);

\echo '##### D.1'
select 'order_structure -> order' as fk, count(*) as orphans from order_structure os left join "order" o on os.order_id = o.order_id where o.order_id is null
union all select 'order_structure -> product', count(*) from order_structure os left join product p on os.product_id = p.product_id where p.product_id is null
union all select 'payment -> order', count(*) from payment pmt left join "order" o on pmt.order_id = o.order_id where o.order_id is null
union all select 'review -> order', count(*) from review r left join "order" o on r.order_id = o.order_id where o.order_id is null
union all select 'courier_pay -> courier', count(*) from courier_pay cp left join courier c on cp.courier_id = c.courier_id where c.courier_id is null
union all select 'client_address -> client', count(*) from client_address ca left join client c on ca.client_id = c.client_id where c.client_id is null
union all select 'client_address -> address', count(*) from client_address ca left join address a on ca.address_id = a.address_id where a.address_id is null;
\echo '##### D.2'
select count(*) from "order" where total_amount < 1000;
\echo '##### D.3'
select count(*) from "order" where round(order_amount * 0.10, 2) != commission;
\echo '##### D.4'
select count(*) from "order" where round(order_amount + commission, 2) != total_amount;
\echo '##### D.5'
select count(*) from "order" where delivery_timestamp is not null and delivery_timestamp < order_timestamp;
\echo '##### D.6'
select count(*) from "order" o left join client_address ca
  on ca.client_id = o.client_id and ca.address_id = o.address_id where ca.client_id is null;
\echo '##### D.7'
select count(distinct os.order_id) from order_structure os
join "order" o on os.order_id = o.order_id join product p on os.product_id = p.product_id
where p.restaurant_id != o.restaurant_id;
\echo '##### D.8'
select order_id, count(*) as cnt from payment where status = 'успех'
group by order_id having count(*) != 1;
\echo '##### D.9'
select count(*) from payment p join "order" o on p.order_id = o.order_id where p.amount != o.total_amount;
\echo '##### D.10'
select client_id, address_id, count(*) from client_address group by client_id, address_id having count(*) > 1;
\echo '##### D.11'
select order_id, product_id, count(*) from order_structure group by order_id, product_id having count(*) > 1;
\echo '##### D.12'
select count(*) from restaurant where work_end <= work_start;
\echo '##### D.13'
select count(*) from courier where dismissal_date is not null and dismissal_date < hire_date;
\echo '##### D.14'
with t as (
  select p.product_id, p.rating,
         (select round(avg(r.rating), 2) from review r
          where r.entity_type = 'блюдо' and r.entity_id = p.product_id) as expected
  from product p where p.rating is not null)
select count(*) as rows_checked, count(*) filter (where rating is distinct from expected) as mismatches from t;

\echo '##### E.1'
do $$
declare
    v_rest uuid; v_cat uuid; v_before int; v_after int;
begin
    select restaurant_id into v_rest from restaurant limit 1;
    select product_category_id into v_cat from product_category limit 1;
    select count(*) into v_before from product;
    call add_product(p_name => 'Тестовое блюдо', p_price => 250, p_restaurant_id => v_rest,
                     p_product_category_id => v_cat, p_status => 'доступно',
                     p_description => 'Описание', p_rating => 4.5);
    select count(*) into v_after from product;
    raise notice 'E.1: before=%, after=%', v_before, v_after;
end $$;
\echo '##### E.2'
do $$
declare v_cat uuid;
begin
    select product_category_id into v_cat from product_category limit 1;
    begin
        call add_product(p_name => 'Тест', p_price => 250,
                         p_restaurant_id => '00000000-0000-0000-0000-000000000000',
                         p_product_category_id => v_cat, p_status => 'доступно',
                         p_description => 'x');
        raise notice 'E.2: ошибки НЕ было (FAIL)';
    exception when others then
        raise notice 'E.2: ошибка получена: %', sqlerrm;
    end;
end $$;
\echo '##### E.3 + E.4 (update и delete существующего отзыва на блюдо)'
do $$
declare
    v_review uuid; v_prod uuid; v_before numeric; v_after_upd numeric;
    v_avg_upd numeric; v_after_del numeric; v_avg_del numeric;
begin
    select r.review_id, r.entity_id into v_review, v_prod
    from review r where r.entity_type = 'блюдо' limit 1;
    select rating into v_before from product where product_id = v_prod;
    update review set rating = 5 where review_id = v_review;
    select rating into v_after_upd from product where product_id = v_prod;
    select round(avg(rating), 2) into v_avg_upd from review where entity_type = 'блюдо' and entity_id = v_prod;
    raise notice 'E.3: rating до=%, после update=%, avg по отзывам=%', v_before, v_after_upd, v_avg_upd;
    delete from review where review_id = v_review;
    select rating into v_after_del from product where product_id = v_prod;
    select round(avg(rating), 2) into v_avg_del from review where entity_type = 'блюдо' and entity_id = v_prod;
    raise notice 'E.4: rating после delete=%, avg по оставшимся отзывам=%', v_after_del, v_avg_del;
end $$;
\echo '##### E.5'
select * from get_statistic();
\echo '##### E.6 до'
select courier_id, coefficient, status from courier order by courier_id;
call courier_salary();
\echo '##### E.6 после'
select courier_id, coefficient, status from courier order by courier_id;
select year, month, courier_id, amount, coefficient_used from courier_pay
order by year desc, month desc, courier_id limit 20;
\echo '##### E.7'
select count(*) as before_cnt from courier_pay;
call courier_salary();
select count(*) as after_cnt from courier_pay;

\echo '##### F.1'
select column_name, data_type from information_schema.columns
where table_schema = 'gunya_food' and table_name = 'how_much_money' order by ordinal_position;
\echo '##### F.2'
select * from how_much_money order by year_month;
\echo '##### F.3'
select year_month from how_much_money where sum_no_commission = 0 or sum_no_commission is null;
\echo '##### F.4 (проверка формул)'
select count(*) as rows_checked,
       count(*) filter (where abs(commission - (sum_with_commission - sum_no_commission)) > 0.01
                          or abs(net_profit - (commission - courier_pay)) > 0.01) as bad_formulas,
       count(*) filter (where prev_commission is null) as null_prev_rows
from how_much_money;

\echo '##### G.1'
select nspname as schema_name,
       has_schema_privilege('inspector', nspname, 'USAGE')  as usage,
       has_schema_privilege('inspector', nspname, 'CREATE') as create
from pg_namespace where nspname in ('gunya_food', 'exts') order by nspname;
\echo '##### G.2'
select table_name, string_agg(privilege_type, ', ' order by privilege_type) as privs
from information_schema.role_table_grants
where grantee = 'inspector' and table_schema = 'gunya_food'
group by table_name order by table_name;
\echo '##### G.3'
set role inspector;
select count(*) from information_schema.tables where table_schema = 'gunya_food';
reset role;
\echo '##### G.4'
set role inspector;
select count(*) from pg_catalog.pg_tables where schemaname = 'gunya_food';
reset role;
\echo '##### G.5'
set role inspector;
set search_path to gunya_food, exts;
call erase_test_data();
call insert_test_data(10);
call courier_salary();
select count(*) as statistic_rows from get_statistic();
select * from how_much_money limit 5;
reset role;

\echo '##### H.1'
explain analyze
select c.courier_id,
       (select count(*) from "order" o where o.courier_id = c.courier_id and o.status = 'доставлен') as cnt,
       (select coalesce(sum(commission), 0) from "order" o where o.courier_id = c.courier_id and o.status = 'доставлен') as commission_sum
from courier c;
\echo '##### H.2'
explain analyze
select c.courier_id, count(o.order_id) as cnt, coalesce(sum(o.commission), 0) as commission_sum
from courier c left join "order" o on o.courier_id = c.courier_id and o.status = 'доставлен'
group by c.courier_id;
\echo '##### H.3'
explain analyze select * from get_statistic();

\echo '##### I.1'
call erase_test_data();
select 'client' as tbl, count(*) from client
union all select 'courier', count(*) from courier
union all select 'product_category', count(*) from product_category
union all select 'restaurant', count(*) from restaurant
union all select 'address', count(*) from address
union all select 'product', count(*) from product
union all select 'order', count(*) from "order"
union all select 'review', count(*) from review
union all select 'payment', count(*) from payment
union all select 'order_structure', count(*) from order_structure
union all select 'client_address', count(*) from client_address
union all select 'courier_pay', count(*) from courier_pay;
\echo '##### I.2'
call erase_test_data();
\echo '##### I.3'
call insert_test_data(10);
select count(*) from "order";
\echo '##### END'
