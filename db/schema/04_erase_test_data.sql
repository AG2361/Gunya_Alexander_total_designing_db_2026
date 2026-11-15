set search_path to gunya_food;

create or replace procedure gunya_food.erase_test_data()
language plpgsql
as $$
begin
    delete from gunya_food.courier_pay;
    delete from gunya_food.payment;
    delete from gunya_food.review;
    delete from gunya_food.order_structure;
    delete from gunya_food."order";
    delete from gunya_food.product;
    delete from gunya_food.client_address;
    delete from gunya_food.client;
    delete from gunya_food.restaurant;
    delete from gunya_food.address;
    delete from gunya_food.product_category;
    delete from gunya_food.courier;
end;
$$;