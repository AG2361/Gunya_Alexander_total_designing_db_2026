create or replace procedure gunya_food.add_product(
    p_name                varchar,
    p_price               numeric,
    p_restaurant_id       uuid,
    p_product_category_id uuid,
    p_status              gunya_food.product_status,
    p_description         text,
    p_rating              numeric default null,
    p_photo_url           text    default null
)
language plpgsql
set search_path = gunya_food, public
as $$
begin
    if p_name is null or length(trim(p_name)) = 0 then
        raise exception 'add_product: название блюда не может быть пустым';
    end if;
    if length(p_name) > 100 then
        raise exception 'add_product: название блюда длиннее 100 символов (%)', length(p_name);
    end if;
    if p_price is null or p_price < 0 then
        raise exception 'add_product: цена должна быть неотрицательной, получено: %', p_price;
    end if;
    if p_rating is not null and (p_rating < 0 or p_rating > 5) then
        raise exception 'add_product: рейтинг должен быть от 0 до 5, получено: %', p_rating;
    end if;
    if p_status is null then
        raise exception 'add_product: статус блюда обязателен';
    end if;
    if p_description is null then
        raise exception 'add_product: описание блюда обязательно';
    end if;

    if not exists (select 1 from restaurant where restaurant_id = p_restaurant_id) then
        raise exception 'add_product: ресторан с id % не существует', p_restaurant_id;
    end if;
    if not exists (select 1 from product_category where product_category_id = p_product_category_id) then
        raise exception 'add_product: категория блюда с id % не существует', p_product_category_id;
    end if;

    insert into product (product_name, product_category_id, price, restaurant_id,
                         photo_url, rating, status, description)
    values (p_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_rating, p_status, p_description);
exception
    when check_violation then
        raise exception 'add_product: нарушено ограничение CHECK (%): %', sqlerrm, p_name;
end;
$$;