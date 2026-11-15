-- 01_schema_types.sql
-- FOOD-101: схема и enum-типы
create schema if not exists gunya_food;
set search_path to gunya_food;

create type restaurant_status  as enum ('активен', 'неактивен');
create type product_status     as enum ('доступно', 'нет_в_наличии', 'архив');
create type courier_status     as enum ('свободен', 'занят', 'на_доставке', 'уволен');
create type order_status       as enum ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
create type order_pay_status   as enum ('ожидает', 'оплачен', 'ошибка');
create type payment_status     as enum ('успех', 'ошибка', 'в_обработке');
create type payment_type       as enum ('карта', 'наличные', 'безнал');
create type review_entity_type as enum ('блюдо', 'ресторан', 'заказ');