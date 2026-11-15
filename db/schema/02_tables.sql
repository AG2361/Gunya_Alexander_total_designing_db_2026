-- 02_tables.sql
-- FOOD-101: таблицы, ключи, проверки
set search_path to gunya_food;

-- адреса (BR-3.1, BR-3.2: квартира/офис необязательна)
create table address (
    address_id       uuid         not null default exts.uuid_generate_v4(),
    street           varchar(100) not null,
    house_number     varchar(10)  not null,
    apartment_office varchar(10),
    constraint address_pk primary key (address_id)
);

-- клиенты (BR-2.1..2.3, BR-2.6: фио не хранится)
create table client (
    client_id    uuid        not null default exts.uuid_generate_v4(),
    login        varchar(50) not null,
    password     varchar(32) not null,
    phone_number varchar(12) not null,
    constraint client_pk primary key (client_id),
    constraint client_login_uq unique (login),
    constraint client_phone_uq unique (phone_number),
    constraint client_password_md5_ck check (password ~ '^[0-9a-f]{32}$')
);

-- адреса клиентов, связь m:n (BR-2.4, BR-2.5)
create table client_address (
    client_id  uuid not null,
    address_id uuid not null,
    constraint client_address_pk primary key (client_id, address_id),
    constraint client_address_client_fk  foreign key (client_id)  references client (client_id)   on delete restrict,
    constraint client_address_address_fk foreign key (address_id) references address (address_id) on delete restrict
);

-- рестораны (BR-3.3, BR-4.1..4.5; рейтинг null, пока нет отзывов, BR-9.7)
create table restaurant (
    restaurant_id   uuid         not null default exts.uuid_generate_v4(),
    restaurant_name varchar(100) not null,
    address_id      uuid         not null,
    description     text         not null,
    work_start      time         not null,
    work_end        time         not null,
    company_details text         not null,
    rating          numeric(3,2),
    status          restaurant_status not null,
    constraint restaurant_pk primary key (restaurant_id),
    constraint restaurant_address_uq unique (address_id),
    constraint restaurant_address_fk foreign key (address_id) references address (address_id) on delete restrict,
    constraint restaurant_rating_ck check (rating between 0 and 5),
    constraint restaurant_work_time_ck check (work_end > work_start)
);

-- категории блюд, справочник (BR-5.7)
create table product_category (
    product_category_id   uuid         not null default exts.uuid_generate_v4(),
    product_category_name varchar(100) not null,
    constraint product_category_pk primary key (product_category_id)
);

-- блюда (BR-5.1..5.6)
create table product (
    product_id          uuid          not null default exts.uuid_generate_v4(),
    product_name        varchar(100)  not null,
    product_category_id uuid          not null,
    price               numeric(10,2) not null,
    restaurant_id       uuid          not null,
    photo_url           text,
    rating              numeric(3,2),
    status              product_status not null,
    description         text          not null,
    constraint product_pk primary key (product_id),
    constraint product_category_fk foreign key (product_category_id) references product_category (product_category_id) on delete restrict,
    constraint product_restaurant_fk foreign key (restaurant_id) references restaurant (restaurant_id) on delete restrict,
    constraint product_price_ck check (price >= 0),
    constraint product_rating_ck check (rating between 0 and 5)
);

-- курьеры (BR-6.1..6.5)
create table courier (
    courier_id     uuid         not null default exts.uuid_generate_v4(),
    fio            varchar(150) not null,
    phone_number   varchar(12)  not null,
    status         courier_status not null,
    hire_date      date         not null,
    dismissal_date date,
    coefficient    numeric(2,1) not null default 0.1,
    constraint courier_pk primary key (courier_id),
    constraint courier_coefficient_ck check (coefficient between 0.1 and 0.5),
    constraint courier_dismissal_ck check (status <> 'уволен' or dismissal_date is not null),
    constraint courier_dates_ck check (dismissal_date is null or dismissal_date >= hire_date)
);

-- выплаты курьерам (BR-10.2..10.4)
create table courier_pay (
    year             int           not null,
    month            int           not null,
    courier_id       uuid          not null,
    amount           numeric(12,2) not null,
    coefficient_used numeric(2,1)  not null,
    constraint courier_pay_pk primary key (year, month, courier_id),
    constraint courier_pay_courier_fk foreign key (courier_id) references courier (courier_id) on delete restrict,
    constraint courier_pay_month_ck check (month between 1 and 12),
    constraint courier_pay_amount_ck check (amount >= 0),
    constraint courier_pay_coef_ck check (coefficient_used between 0.1 and 0.5)
);

-- заказы (BR-7.1..7.13, BR-1.4, BR-1.8)
create table "order" (
    order_id           uuid          not null default exts.uuid_generate_v4(),
    courier_id         uuid          not null,
    client_id          uuid          not null,
    address_id         uuid          not null,
    restaurant_id      uuid          not null,
    order_timestamp    timestamp     not null,
    delivery_timestamp timestamp,
    order_amount       numeric(12,2) not null,
    commission         numeric(12,2) generated always as (round(order_amount * 0.10, 2)) stored,
    total_amount       numeric(12,2) generated always as (order_amount + round(order_amount * 0.10, 2)) stored,
    status             order_status     not null,
    pay_status         order_pay_status not null,
    description        text          not null,
    constraint order_pk primary key (order_id),
    constraint order_total_uq unique (order_id, total_amount),
    constraint order_courier_fk    foreign key (courier_id)    references courier (courier_id)       on delete restrict,
    constraint order_client_fk     foreign key (client_id)     references client (client_id)         on delete restrict,
    constraint order_address_fk    foreign key (address_id)    references address (address_id)       on delete restrict,
    constraint order_restaurant_fk foreign key (restaurant_id) references restaurant (restaurant_id) on delete restrict,
    constraint order_client_address_fk foreign key (client_id, address_id)
        references client_address (client_id, address_id) on delete restrict,
    constraint order_min_total_ck check (total_amount >= 1000),
    constraint order_delivery_time_ck check (delivery_timestamp is null or delivery_timestamp >= order_timestamp),
    constraint order_delivered_ck check (status <> 'доставлен' or delivery_timestamp is not null)
);

-- позиции заказа (BR-7.14..7.16)
create table order_structure (
    order_id   uuid         not null,
    product_id uuid         not null,
    quantity   numeric(8,2) not null,
    constraint order_structure_pk primary key (order_id, product_id),
    constraint order_structure_order_fk   foreign key (order_id)   references "order" (order_id)   on delete restrict,
    constraint order_structure_product_fk foreign key (product_id) references product (product_id) on delete restrict,
    constraint order_structure_quantity_ck check (quantity > 0)
);

-- попытки оплаты (BR-8.1..8.6)
create table payment (
    payment_id        uuid          not null default exts.uuid_generate_v4(),
    order_id          uuid          not null,
    pay_type          payment_type  not null,
    amount            numeric(12,2) not null,
    transaction_id    varchar(64)   not null,
    payment_timestamp timestamp     not null,
    status            payment_status not null,
    constraint payment_pk primary key (payment_id),
    constraint payment_transaction_uq unique (transaction_id),
    constraint payment_order_amount_fk foreign key (order_id, amount)
        references "order" (order_id, total_amount) on delete restrict
);

-- не более одной успешной попытки на заказ (BR-8.1)
create unique index payment_one_success_uq on payment (order_id) where status = 'успех';

-- отзывы (BR-9.1..9.5; entity_id полиморфный, без fk)
create table review (
    review_id        uuid          not null default exts.uuid_generate_v4(),
    client_id        uuid          not null,
    review_timestamp timestamp     not null,
    entity_id        uuid          not null,
    entity_type      review_entity_type not null,
    order_id         uuid          not null,
    description      text          not null,
    photo_url        text,
    rating           numeric(3,2)  not null,
    constraint review_pk primary key (review_id),
    constraint review_once_uq unique (order_id, entity_type, entity_id),
    constraint review_client_fk foreign key (client_id) references client (client_id) on delete restrict,
    constraint review_order_fk  foreign key (order_id)  references "order" (order_id) on delete restrict,
    constraint review_rating_ck check (rating between 1 and 5)
);