-- FOOD-109: пользователь inspector и его права (пароль из задания)

-- роль уровня сервера: создаём, а если уже есть, обновляем пароль
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'inspector') then
        create role inspector login password 'NetoSQL2025';
    else
        alter role inspector with login password 'NetoSQL2025';
    end if;
end;
$$;

-- подключение к текущей базе
do $$
begin
    execute format('grant connect on database %I to inspector', current_database());
end;
$$;

-- схема gunya_food: полный доступ к самой схеме (usage + create)
grant all privileges on schema gunya_food to inspector;

-- права на схему не дают прав на объекты внутри неё, выдаём отдельно
grant all privileges on all tables    in schema gunya_food to inspector;
grant all privileges on all sequences in schema gunya_food to inspector;
grant execute on all functions  in schema gunya_food to inspector;
grant execute on all procedures in schema gunya_food to inspector;

-- то же самое для объектов, которые появятся позже
-- (functions покрывает и процедуры)
alter default privileges in schema gunya_food grant all privileges on tables    to inspector;
alter default privileges in schema gunya_food grant all privileges on sequences to inspector;
alter default privileges in schema gunya_food grant execute on functions to inspector;

-- расширение uuid-ossp в схеме exts (exts.uuid_generate_v4())
grant usage on schema exts to inspector;
grant execute on all functions in schema exts to inspector;

-- системные схемы: по умолчанию доступны всем, фиксируем явно
grant usage on schema information_schema to inspector;
grant usage on schema pg_catalog to inspector;