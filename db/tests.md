# Протокол для самопроверки

Заполняется по желанию. 

По данному протоколу работа будет проверяться преподавателем.

**Если на каком-то этапе функционал оказывается нерабочим, значит учащийся проигнорировал обязательное тестирование и работа может быть отправлена на доработку без проверки и комментариев или по работе может быть проставлен незачет, если лимит доработок исчерпан.**

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | PostgreSQL 17.2 on x86_64-windows (`SELECT version();`) |
| Дата проверки | 2026-11-15 |
| Схема | `gunya_food` |
| Роль-аудитор | `inspector` |

Все проверки — под `inspector`, если не указано иное.

Заполняй «Факт» и «Вердикт» по каждой проверке. «Вердикт»: `OK` / `FAIL: <что именно>`.

## Как выполнен прогон

Все проверки ниже выполнены одним скриптом [`db/tests_run.sql`](tests_run.sql) реальным логином `inspector` (`psql -U inspector`) на чистой базе `foodexpress_check`, восстановленной из `db/foodexpress_gunya.backup`. Полный вывод скрипта сохранён в [`db/tests_run.txt`](tests_run.txt).

Отличия от шаблона:

- PostgreSQL не поддерживает подзапросы в аргументах `CALL`, поэтому E.1 и E.2 выполнены блоками `do` с переменными.
- В E.3 и E.4 пересчёт рейтинга проверен через `update` и `delete` существующего отзыва на блюдо (в блоке `do`), а не через вставку нового отзыва.
- После C.9 (10 повторных вызовов) выполнены `erase_test_data()` и `insert_test_data(10)`, чтобы остальные проверки шли на чистых числах.
- При запуске `psql` в Windows нужна переменная `PGCLIENTENCODING=UTF8`, иначе процедуры с русским текстом падают из-за кодировки консоли.
- Сообщения `схема "pg_temp" не существует, пропускается` и `таблица "tmp_..." не существует, пропускается` в выводе — это уведомления (`NOTICE`) от `drop ... if exists` во временных таблицах `insert_test_data`, не ошибки.

---

## A. Подготовка

### A.1. Восстановление бэкапа

Ожидается: без ошибок.
Факт: Бэкап `db/foodexpress_gunya.backup` восстановлен командой `pg_restore --no-owner` в чистую БД `foodexpress_check` (заранее созданы схема `exts` и расширение `uuid-ossp`), затем применён `db/schema/grants.sql`. Ошибок нет.
Вердикт: OK

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO gunya_food, exts;
SELECT current_user;
```

Ожидается: `inspector`.
Факт: Вход выполнен реальным логином `inspector`; `SET ROLE inspector` и `SET search_path TO gunya_food, exts` выполнены, `current_user` = `inspector`.
Вердикт: OK

---

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `gunya_food`.
Факт: `gunya_food`.
Вердикт: OK

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.
Факт: `uuid-ossp`, схема `exts`.
Вердикт: OK

### B.3. Все 12 исходных таблиц + N после нормализации

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'gunya_food'
ORDER BY table_name;
```

Ожидается: `address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` (12 + N штук).
Факт: 12 таблиц: address, client, client_address, courier, courier_pay, order, order_structure, payment, product, product_category, restaurant, review (N = 0 дополнительных таблиц). Представление `how_much_money` в этот список не входит.
Вердикт: OK

### B.4. Все PK — `uuid`

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'gunya_food'
  AND column_name LIKE '%_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.
Факт: Одна строка: `payment.transaction_id`, тип `character varying`. Это поле-идентификатор транзакции, а не PK/FK. Остальные столбцы `*_id` (все PK и FK) имеют тип `uuid`.
Вердикт: OK (исключение: `payment.transaction_id` — не ключ, а varchar-идентификатор транзакции)

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'gunya_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.
Факт: 8 типов: `courier_status` {свободен, занят, на_доставке, уволен}; `order_pay_status` {ожидает, оплачен, ошибка}; `order_status` {создан, готовится, в_доставке, доставлен, отменён}; `payment_status` {успех, ошибка, в_обработке}; `payment_type` {карта, наличные, безнал}; `product_status` {доступно, нет_в_наличии, архив}; `restaurant_status` {активен, неактивен}; `review_entity_type` {блюдо, ресторан, заказ}.
Вердикт: OK

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'gunya_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: не менее 15 FK, все из erd.md.
Факт: 16 FK (требуется не менее 15): client_address→address, client_address→client, courier_pay→courier, order→address, order→client_address, order→client, order→courier, order→restaurant, order_structure→order, order_structure→product, payment→order, product→product_category, product→restaurant, restaurant→address, review→client, review→order.
Вердикт: OK

### B.7. Пароль — MD5

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.
Факт: `len = 32` во всех 5 проверенных строках, значения — hex-строки (MD5).
Вердикт: OK

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: `CALL`, без ошибок.
Вердикт: OK

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.
Факт: `CALL`, без ошибок (в выводе только уведомления `NOTICE` про отсутствующие временные таблицы).
Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: 10, 10, 10, 10, 50, 50, 50, 50, 50.
Факт: address 50, client 10, courier 10, order 50, payment 50, product 50, product_category 10, restaurant 10, review 50.
Вердикт: OK

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: 10 ресторанных адресов, 50 всего → 40 клиентских.
Факт: 10 адресов ресторанов, всего 50 адресов → 40 клиентских.
Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT count(*) FROM client WHERE login = '' OR password = '' OR phone_number = '';
-- и аналогично для других varchar-полей с NOT NULL
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT count(*) FROM "order" WHERE client_id IS NULL OR restaurant_id IS NULL
  OR courier_id IS NULL OR address_id IS NULL OR total_amount IS NULL;
-- и аналогично для других NOT NULL полей
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.
Факт: 7 неуволенных курьеров (требуется `>= 1`).
Вердикт: OK

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

```sql
SELECT cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM "order" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year  from o.order_timestamp) = cp.year
             AND extract(month from o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM courier_pay cp
LIMIT 20;
```

Ожидается: `amount = expected_amount` в каждой строке.
Факт: Проверено 60 строк `courier_pay`, расхождений `amount` и `expected_amount`: 0.
Вердикт: OK

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
```

Ожидается: без ошибок, данные добавляются или заменяются (по решению студента, задокументированному в constraints.md).
Факт: 10 повторных вызовов `insert_test_data(10)` выполнены без ошибок; число клиентов выросло с 10 до 110, то есть данные добавляются (накапливаются). После проверки выполнены `erase_test_data()` и `insert_test_data(10)`.
Вердикт: OK

---

## D. Проверки бизнес-правил на сгенерированных данных

### D.1. Все FK валидны (нет orphans)

```sql
SELECT 'order_structure → order' AS fk, count(*) AS orphans
FROM order_structure os
LEFT JOIN "order" o ON os.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_structure → product', count(*)
FROM order_structure os
LEFT JOIN product p ON os.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'payment → order', count(*)
FROM payment pmt
LEFT JOIN "order" o ON pmt.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'review → order', count(*)
FROM review r
LEFT JOIN "order" o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'courier_pay → courier', count(*)
FROM courier_pay cp
LEFT JOIN courier c ON cp.courier_id = c.courier_id
WHERE c.courier_id IS NULL
UNION ALL
SELECT 'client_address → client', count(*)
FROM client_address ca
LEFT JOIN client c ON ca.client_id = c.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'client_address → address', count(*)
FROM client_address ca
LEFT JOIN address a ON ca.address_id = a.address_id
WHERE a.address_id IS NULL;
```

Ожидается: все 0.
Факт: Все 7 связей: 0 «сирот».
Вердикт: OK

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "order" WHERE total_amount < 1000;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "order" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "order"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "order"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "order" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "order" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS cnt
FROM payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) != 1;
```

Ожидается: пусто.
Факт: Пусто (0 rows).
Вердикт: OK

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "order" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: Пусто (0 rows).
Вердикт: OK

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: Пусто (0 rows).
Вердикт: OK

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

```sql
-- product.rating = AVG(review.rating) по отзывам на блюдо
SELECT p.product_id, p.rating,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE p.rating IS NOT NULL
LIMIT 20;
```

Ожидается: `rating = expected`.
Факт: Проверено 14 блюд с рейтингом, расхождений с `avg(review.rating)`: 0.
Вердикт: OK

---

## E. Функции и процедуры

### E.1. `add_product` — успешный вызов

> Примечание: PostgreSQL не поддерживает подзапросы в аргументах `CALL`, поэтому ID ресторана и категории получены заранее в переменные блока `do`.

```sql
SELECT count(*) AS before FROM product;

CALL add_product(
    p_restaurant_id => (SELECT restaurant_id FROM restaurant LIMIT 1),
    p_product_category_id => (SELECT product_category_id FROM product_category LIMIT 1),
    p_name => 'Тестовое блюдо',
    p_price => 250,
    p_rating => 4.5,
    p_status => 'доступно',
    p_description => 'Описание'
    -- + photo_url если есть
);

SELECT count(*) AS after FROM product;
```

Ожидается: `after = before + 1`.
Факт: `before = 50`, `after = 51`.
Вердикт: OK

### E.2. `add_product` — падает на несуществующий ресторан

> Примечание: PostgreSQL не поддерживает подзапросы в аргументах `CALL`, поэтому ID ресторана и категории получены заранее в переменные блока `do`.

```sql
CALL add_product(
    p_restaurant_id => '00000000-0000-0000-0000-000000000000',
    -- остальные аргументы
);
```

Ожидается: ошибка с внятным сообщением.
Факт: Ошибка получена: `add_product: ресторан с id 00000000-0000-0000-0000-000000000000 не существует`.
Вердикт: OK

### E.3. `rating_change` — пересчитывает рейтинг

> Примечание: вместо вставки нового отзыва использованы `update` и `delete` существующего отзыва на блюдо (блок `do`): триггер `rating_change_trg` срабатывает на изменение таблицы `review`.

```sql
-- Выбрать заказ, блюдо и клиента
SELECT p.product_id, p.rating FROM product p WHERE p.rating IS NOT NULL LIMIT 1;

-- Вставить отзыв на это блюдо
INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
VALUES (
    exts.uuid_generate_v4(),
    (SELECT client_id FROM client LIMIT 1),
    localtimestamp,
    <product_id>,
    'блюдо',
    (SELECT order_id FROM "order" LIMIT 1),
    'Тестовый отзыв',
    5
);

SELECT rating FROM product WHERE product_id = <product_id>;
```

Ожидается: `rating` пересчитан.
Факт: Единственный отзыв на выбранное блюдо обновлён до оценки 5: `product.rating` до = 5.00, после `update` = 5.00, среднее по отзывам = 5.00 (рейтинг совпадает со средним; значение не изменилось, так как оценка уже была 5). Дополнительно при разработке (FOOD-105) отдельным тестом получена последовательность рейтингов 4.00, 4.50, 3.50, NULL.
Вердикт: OK

### E.4. `rating_change` — удаление отзыва

```sql
-- Удалить отзыв из E.3
DELETE FROM review WHERE review_id = <review_id>;

SELECT rating FROM product WHERE product_id = <product_id>;
```

Ожидается: если других отзывов нет — `rating IS NULL`; иначе — пересчитан.
Факт: После `delete` отзыва: `rating = NULL`, среднее по оставшимся отзывам = NULL (других отзывов на блюдо нет).
Вердикт: OK

### E.5. `get_statistic()`

```sql
SELECT * FROM get_statistic();
```

Ожидается:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (не NULL при наличии заказов).

Факт: 10 строк, по одной на ресторан; колонки `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`. У двух ресторанов без доставленных заказов `best_product_name` и `best_user` = NULL, суммы = 0; у остальных восьми `best_user` — `client.login` (например, `user_0fb82561e9a29410`).
Вердикт: OK

### E.6. `courier_salary()`

```sql
-- До
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;

CALL courier_salary();

-- После
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;
SELECT year, month, courier_id, amount, coefficient_used
FROM courier_pay
ORDER BY year DESC, month DESC, courier_id
LIMIT 20;
```

Ожидается:
- `courier.coefficient` пересчитан для работающих (по BR-10.2).
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Факт: До и после вызова коэффициенты всех 10 курьеров равны 0.1 (суммы заказов в диапазоне 0–150, тариф 0.1); у двух уволенных курьеров коэффициент не менялся. В `courier_pay` есть записи за текущий месяц (2026-11) для всех 10 курьеров и за 2026-10.
Вердикт: OK

### E.7. `courier_salary()` — повторный вызов

```sql
CALL courier_salary();
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);
```

Ожидается: количество не изменилось (idempotency / обновление).
Факт: `count(*)` в `courier_pay` до повторного вызова 60, после 60: дубликаты не создаются.
Вердикт: OK

---

## F. Представление `how_much_money`

### F.1. Колонки

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'gunya_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).
Факт: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).
Вердикт: OK

### F.2. Месяцы покрыты

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: месяцы от первого доставленного заказа до последнего (не пропущено ни одного).
Факт: 6 месяцев подряд: 2026-06, 2026-07, 2026-08, 2026-09, 2026-10, 2026-11; пропусков нет.
Вердикт: OK

### F.3. Месяцы без заказов присутствуют (BR-11.9)

```sql
SELECT year_month FROM how_much_money
WHERE sum_no_commission = 0 OR sum_no_commission IS NULL;
```

Ожидается: если в какие-то месяцы заказов не было — они есть в результате.
Факт: Пусто (0 rows): в тестовых данных нет месяцев без заказов между первым и последним месяцем; представление строит все месяцы диапазона рекурсивным CTE, поэтому такой месяц присутствовал бы со значением 0.
Вердикт: OK

### F.4. Корректность сумм

```sql
SELECT year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission_diff,
       courier_pay,
       net_profit
FROM how_much_money
ORDER BY year_month
LIMIT 10;
```

Ожидается:
- `commission = sum_with_commission - sum_no_commission`.
- `commission_diff = commission - prev_commission` (NULL для первого месяца).
- `net_profit = commission - courier_pay`.

Факт: Проверено 6 строк, расхождений в формулах 0 (`commission = sum_with_commission - sum_no_commission`, `net_profit = commission - courier_pay`); `prev_commission` и `commission_diff` равны NULL только в первом месяце (1 строка).
Вердикт: OK

---

## G. Права `inspector`

### G.1. Права на схему

```sql
SELECT
    nspname AS schema_name,
    has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
    has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = 'gunya_food';
```

Ожидается: `gunya_food`, `true`, `true` (полный доступ).
Факт: `gunya_food`: `usage = true`, `create = true`; дополнительно `exts`: `usage = true`, `create = false`.
Вердикт: OK

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = 'gunya_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).
Факт: У всех 12 таблиц и у представления `how_much_money` (13 строк) права `DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE`.
Вердикт: OK

### G.3. `information_schema` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'gunya_food';
RESET ROLE;
```

Ожидается: 12 + N (количество таблиц).
Факт: 13 (12 таблиц + представление `how_much_money`; `information_schema.tables` включает представления).
Вердикт: OK

### G.4. `pg_catalog` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = 'gunya_food';
RESET ROLE;
```

Ожидается: 12 + N.
Факт: 12 (`pg_tables` содержит только таблицы).
Вердикт: OK

### G.5. Все процедуры/функции работают под `inspector`

```sql
SET ROLE inspector;
SET search_path TO gunya_food, exts;

CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;

RESET ROLE;
```

Ожидается: без `permission denied`.
Факт: `erase_test_data`, `insert_test_data(10)`, `courier_salary` — `CALL`; `get_statistic()` — 10 строк; `how_much_money` — 5 строк (`limit 5`). Ни одного `permission denied`.
Вердикт: OK

---

## H. Оптимизация `get_statistic` (BR-11.8)

### H.1. `EXPLAIN ANALYZE` — паттерн «избыточные подзапросы»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS cnt,
       (SELECT coalesce(sum(commission), 0) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS commission_sum
FROM courier c;
```

Ожидается: два SubPlan, каждый — скан `"order"`. Время растёт линейно от числа курьеров.
Факт: Execution Time 0.637 ms; план: два `SubPlan`, каждый со `Seq Scan on "order"` (loops = 10).
Вердикт: OK (ожидаемое поведение: два скана `order` на каждого курьера)

### H.2. `EXPLAIN ANALYZE` — паттерн «один JOIN»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS cnt,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM courier c
LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один `Hash Right Join` / `Hash Left Join`, один скан `"order"`. Время меньше, чем в H.1.
Факт: Execution Time 0.200 ms; план: один `Hash Left Join` и один `Seq Scan on "order"`.
Вердикт: OK (быстрее варианта H.1: 0.200 мс против 0.637 мс)

### H.3. Применить к `get_statistic`

```sql
EXPLAIN ANALYZE SELECT * FROM get_statistic();
```

Ожидается: без `LATERAL`, без множественных подзапросов к одной таблице, без оконных функций там, где хватает агрегата.
Факт: `EXPLAIN ANALYZE SELECT * FROM get_statistic()` показывает только `Function Scan` (около 2.5 мс), поэтому план тела функции снят отдельно: запрос из `db/schema/08_get_statistic.sql` выполнен под `inspector` с `EXPLAIN ANALYZE` (скрипт `db/tests_h3.sql`, вывод `db/tests_h3.txt`). Результат: Execution Time 11.373 ms (Planning Time 35.497 ms) на 50 заказах, 10 строк. Структура: пять CTE (`by_client`, `best_client`, `totals`, `by_product`, `best_product`) и `left join` к `restaurant`. Таблица `"order"` читается двумя `Seq Scan` (по одному в `by_client` и в `by_product`, `loops=1`), `order_structure` — одним; `by_client` вычисляется один раз и переиспользуется (`CTE Scan` в `best_client` и в `totals`). `SubPlan` и `LATERAL` в плане нет; оконных функций нет (поиск `lateral|over \(` по файлу ничего не нашёл): лучший клиент и лучшее блюдо выбираются через `select distinct on`, суммы — через `sum` с `group by`.
Вердикт: OK (нет `LATERAL`, коррелированных подзапросов и оконных функций; каждый CTE читает исходные таблицы за один проход)

---

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.
Факт: Все 12 таблиц: 0 строк.
Вердикт: OK

### I.2. Повторный `erase_test_data` не падает

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: `CALL`, без ошибок.
Вердикт: OK

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.
Факт: `CALL`, `count(*) = 50`.
Вердикт: OK

