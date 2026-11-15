-- FOOD-105: пересчёт агрегированного рейтинга блюда и ресторана (BR-9.6, BR-9.7)

-- вспомогательная функция: пересчёт рейтинга одной сущности
create or replace function gunya_food.rating_recalc(p_type gunya_food.review_entity_type, p_id uuid)
returns void
language plpgsql
set search_path = gunya_food, public
as $$
begin
    if p_type = 'блюдо' then
        update product
        set rating = (select round(avg(r.rating), 2)
                      from review r
                      where r.entity_type = 'блюдо' and r.entity_id = p_id)
        where product_id = p_id;
    elsif p_type = 'ресторан' then
        update restaurant
        set rating = (select round(avg(r.rating), 2)
                      from review r
                      where r.entity_type = 'ресторан' and r.entity_id = p_id)
        where restaurant_id = p_id;
    end if;
    -- для 'заказ' агрегата нет (BR-9.6)
end;
$$;

-- триггерная функция
create or replace function gunya_food.rating_change()
returns trigger
language plpgsql
set search_path = gunya_food, public
as $$
begin
    if tg_op in ('UPDATE', 'DELETE') then
        perform gunya_food.rating_recalc(old.entity_type, old.entity_id);
    end if;
    if tg_op in ('INSERT', 'UPDATE') then
        perform gunya_food.rating_recalc(new.entity_type, new.entity_id);
    end if;
    return null;  -- AFTER-триггер: возвращаемое значение игнорируется
end;
$$;

-- триггер
drop trigger if exists rating_change_trg on gunya_food.review;

create trigger rating_change_trg
after insert or update or delete on gunya_food.review
for each row execute function gunya_food.rating_change();