-- 03_triggers.sql
-- FOOD-101: триггеры целостности, которые нельзя выразить ограничениями
set search_path to gunya_food;

-- br-7.3: блюдо в заказе должно быть из ресторана этого заказа
create or replace function order_structure_check()
returns trigger
language plpgsql
as $$
begin
    if not exists (
        select 1
        from gunya_food."order" o
        join gunya_food.product p on p.restaurant_id = o.restaurant_id
        where o.order_id = new.order_id
          and p.product_id = new.product_id
    ) then
        raise exception 'блюдо % не из ресторана заказа %', new.product_id, new.order_id
            using errcode = '23514';
    end if;
    return new;
end;
$$;

create trigger order_structure_check_trg
before insert or update of order_id, product_id on order_structure
for each row execute function order_structure_check();

-- br-7.3: при смене ресторана заказа позиции должны остаться из этого ресторана
create or replace function order_restaurant_check()
returns trigger
language plpgsql
as $$
begin
    if exists (
        select 1
        from gunya_food.order_structure os
        join gunya_food.product p on p.product_id = os.product_id
        where os.order_id = new.order_id
          and p.restaurant_id <> new.restaurant_id
    ) then
        raise exception 'в заказе % есть блюда другого ресторана', new.order_id
            using errcode = '23514';
    end if;
    return new;
end;
$$;

create trigger order_restaurant_check_trg
before update of restaurant_id on "order"
for each row execute function order_restaurant_check();

-- br-9.1: entity_id отзыва должен существовать в таблице, которую задаёт entity_type
create or replace function review_entity_check()
returns trigger
language plpgsql
as $$
begin
    if new.entity_type = 'блюдо' then
        if not exists (select 1 from gunya_food.product where product_id = new.entity_id) then
            raise exception 'блюдо % не существует', new.entity_id using errcode = '23503';
        end if;
    elsif new.entity_type = 'ресторан' then
        if not exists (select 1 from gunya_food.restaurant where restaurant_id = new.entity_id) then
            raise exception 'ресторан % не существует', new.entity_id using errcode = '23503';
        end if;
    elsif new.entity_type = 'заказ' then
        if not exists (select 1 from gunya_food."order" where order_id = new.entity_id) then
            raise exception 'заказ % не существует', new.entity_id using errcode = '23503';
        end if;
    end if;
    return new;
end;
$$;

create trigger review_entity_check_trg
before insert or update of entity_id, entity_type on review
for each row execute function review_entity_check();