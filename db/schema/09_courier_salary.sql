-- FOOD-107: ночной расчёт зарплаты курьеров (BR-10.2, BR-10.5, BR-10.6)

create or replace procedure gunya_food.courier_salary()
language plpgsql
set search_path = gunya_food, public
as $$
declare
    v_start timestamp := date_trunc('month', localtimestamp);
    v_end   timestamp := date_trunc('month', localtimestamp) + interval '1 month';
    v_year  int       := extract(year  from localtimestamp)::int;
    v_month int       := extract(month from localtimestamp)::int;
begin
    -- 1) выплата за текущий месяц по коэффициенту, действовавшему в этом месяце:
    --    если запись за месяц уже есть (повторный вызов), берём её coefficient_used,
    --    а не courier.coefficient, который уже обновлён на следующий месяц
    insert into courier_pay ("year", "month", courier_id, amount, coefficient_used)
    select v_year, v_month, c.courier_id,
           round(coalesce(sum(o.commission), 0) * coalesce(cp.coefficient_used, c.coefficient), 2),
           coalesce(cp.coefficient_used, c.coefficient)
    from courier c
    left join courier_pay cp on cp.courier_id = c.courier_id
                            and cp."year" = v_year and cp."month" = v_month
    left join "order" o on o.courier_id = c.courier_id
                       and o.status = 'доставлен'
                       and o.delivery_timestamp >= v_start
                       and o.delivery_timestamp <  v_end
    group by c.courier_id, c.coefficient, cp.coefficient_used
    on conflict ("year", "month", courier_id)
    do update set amount = excluded.amount;

    -- 2) новый коэффициент на следующий месяц по числу доставок (только работающим)
    update courier c
    set coefficient = case when s.cnt <= 150 then 0.1
                           when s.cnt <= 250 then 0.2
                           when s.cnt <= 500 then 0.3
                           else 0.5 end
    from (select c2.courier_id, count(o.order_id) as cnt
          from courier c2
          left join "order" o on o.courier_id = c2.courier_id
                             and o.status = 'доставлен'
                             and o.delivery_timestamp >= v_start
                             and o.delivery_timestamp <  v_end
          group by c2.courier_id) s
    where c.courier_id = s.courier_id
      and c.status <> 'уволен';
end;
$$;