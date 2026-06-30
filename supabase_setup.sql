-- ═══════════════════════════════════════════════════════════════
-- NeuroClip — настройка глобальной базы обучения
-- ═══════════════════════════════════════════════════════════════
-- Скопируй ВЕСЬ этот файл и вставь в Supabase → SQL Editor → New query
-- Затем нажми RUN (или Ctrl+Enter). Выполнится один раз, создаст всё нужное.
-- ═══════════════════════════════════════════════════════════════

-- 1) Таблица сырых исправлений (журнал — для прозрачности и будущей аналитики)
create table if not exists corrections (
  id bigint generated always as identity primary key,
  from_type text,
  to_type text,
  fp_sub real,
  fp_bass real,
  fp_voice real,
  fp_high real,
  game text default 'warzone',
  created_at timestamptz default now()
);

alter table corrections enable row level security;

-- ВАЖНО: с конца мая 2026 Supabase требует явных GRANT для новых проектов
-- в дополнение к RLS-политикам, иначе таблица не будет видна через REST API
grant select, insert on corrections to anon;

drop policy if exists "Anyone can insert corrections" on corrections;
create policy "Anyone can insert corrections"
  on corrections for insert
  to anon
  with check (true);

drop policy if exists "Anyone can read corrections" on corrections;
create policy "Anyone can read corrections"
  on corrections for select
  to anon
  using (true);

-- 2) Таблица итоговых множителей — то, что реально читает сайт перед анализом
create table if not exists global_multipliers (
  type text primary key,
  multiplier real not null default 1.0,
  sample_count integer not null default 0,
  updated_at timestamptz default now()
);

alter table global_multipliers enable row level security;

-- Явный GRANT для новых проектов (см. примечание выше)
grant select on global_multipliers to anon;

drop policy if exists "Anyone can read multipliers" on global_multipliers;
create policy "Anyone can read multipliers"
  on global_multipliers for select
  to anon
  using (true);

-- Намеренно НЕТ insert/update policy для anon — прямая запись запрещена.
-- Изменение множителей возможно только через функцию ниже (security definer),
-- со встроенными ограничениями min/max — это защита от случайной
-- или злонамеренной порчи общих данных одним пользователем.

-- 3) Функция атомарной калибровки множителя
create or replace function adjust_multiplier(p_type text, p_direction text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cur real;
begin
  insert into global_multipliers(type, multiplier, sample_count)
  values (p_type, 1.0, 0)
  on conflict (type) do nothing;

  select multiplier into cur from global_multipliers where type = p_type;

  if p_direction = 'strict' then
    update global_multipliers
      set multiplier = least(2.6, cur * 1.06),
          sample_count = sample_count + 1,
          updated_at = now()
      where type = p_type;
  elsif p_direction = 'loosen' then
    update global_multipliers
      set multiplier = greatest(0.42, cur * 0.95),
          sample_count = sample_count + 1,
          updated_at = now()
      where type = p_type;
  end if;
end;
$$;

grant execute on function adjust_multiplier(text, text) to anon;

-- 4) Предзаполняем все известные типы значением 1.0, чтобы сайт сразу
--    получал полный список при первом запросе (не обязательно, но аккуратнее)
insert into global_multipliers (type, multiplier, sample_count)
values
  ('kills',1.0,0), ('multikill',1.0,0), ('sniper',1.0,0), ('exp',1.0,0),
  ('react',1.0,0), ('laugh',1.0,0), ('neardeath',1.0,0), ('squadwipe',1.0,0),
  ('gulag',1.0,0), ('victory',1.0,0), ('eyecontact',1.0,0), ('vehicle',1.0,0),
  ('action',1.0,0)
on conflict (type) do nothing;

-- ═══════════════════════════════════════════════════════════════
-- Готово. Дальше: Settings → API → скопируй Project URL и anon public key
-- и пришли их мне — я вставлю в код сайта.
-- ═══════════════════════════════════════════════════════════════
