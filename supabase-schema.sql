-- =====================================================================
-- Economía familiar: esquema para Supabase (PostgreSQL)
-- Ejecutar completo en Supabase > SQL Editor > New query > Run.
-- Se puede volver a ejecutar sin perder datos.
--
-- Modelo:
--   familias          una por hogar, con un código para invitar a la pareja
--   familia_miembros  qué usuario pertenece a qué familia
--   config            preferencias compartidas de la familia
--   ingresos, gastos, inversiones, ... una tabla por entidad de la app,
--                     con el registro completo en "datos" (jsonb)
-- Seguridad: Row Level Security. Cada usuario solo puede leer y escribir
-- los datos de la familia a la que pertenece.
-- =====================================================================

-- Familias y miembros ---------------------------------------------------
create table if not exists public.familias (
  id                uuid primary key default gen_random_uuid(),
  nombre            text not null default 'Mi familia',
  codigo_invitacion text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  creada            timestamptz not null default now()
);

create table if not exists public.familia_miembros (
  familia_id uuid not null references public.familias(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  rol        text not null default 'miembro' check (rol in ('titular', 'miembro')),
  email      text,
  unido      timestamptz not null default now(),
  primary key (familia_id, user_id)
);
create index if not exists familia_miembros_user_idx on public.familia_miembros (user_id);

-- ¿El usuario actual pertenece a esta familia? (security definer evita recursión en las políticas)
create or replace function public.es_miembro(p_familia uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.familia_miembros
    where familia_id = p_familia and user_id = auth.uid()
  );
$$;

alter table public.familias enable row level security;
alter table public.familia_miembros enable row level security;

drop policy if exists "ver mi familia" on public.familias;
create policy "ver mi familia" on public.familias
  for select to authenticated using (public.es_miembro(id));

drop policy if exists "ver integrantes de mi familia" on public.familia_miembros;
create policy "ver integrantes de mi familia" on public.familia_miembros
  for select to authenticated using (public.es_miembro(familia_id));

grant select on public.familias, public.familia_miembros to authenticated;
revoke all on public.familias, public.familia_miembros from anon;

-- Crear una familia (quien la crea queda como titular)
create or replace function public.crear_familia(p_nombre text default 'Mi familia')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Necesitás iniciar sesión';
  end if;
  if exists (select 1 from public.familia_miembros where user_id = auth.uid()) then
    raise exception 'Ya pertenecés a una familia';
  end if;
  insert into public.familias (nombre)
    values (coalesce(nullif(trim(p_nombre), ''), 'Mi familia'))
    returning id into v_id;
  insert into public.familia_miembros (familia_id, user_id, rol, email)
    values (v_id, auth.uid(), 'titular', auth.jwt() ->> 'email');
  return v_id;
end;
$$;

-- Sumarse a una familia existente con su código de invitación
create or replace function public.unirse_familia(p_codigo text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Necesitás iniciar sesión';
  end if;
  if exists (select 1 from public.familia_miembros where user_id = auth.uid()) then
    raise exception 'Ya pertenecés a una familia';
  end if;
  select id into v_id from public.familias where codigo_invitacion = upper(trim(p_codigo));
  if v_id is null then
    raise exception 'El código de invitación no es válido';
  end if;
  insert into public.familia_miembros (familia_id, user_id, rol, email)
    values (v_id, auth.uid(), 'miembro', auth.jwt() ->> 'email')
    on conflict do nothing;
  return v_id;
end;
$$;

-- Generar un código nuevo (por ejemplo, si el anterior se compartió de más). Solo el titular.
create or replace function public.regenerar_codigo()
returns text
language plpgsql security definer set search_path = public
as $$
declare v_fam uuid; v_codigo text;
begin
  select familia_id into v_fam from public.familia_miembros
    where user_id = auth.uid() and rol = 'titular' limit 1;
  if v_fam is null then
    raise exception 'Solo el titular de la familia puede cambiar el código';
  end if;
  v_codigo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  update public.familias set codigo_invitacion = v_codigo where id = v_fam;
  return v_codigo;
end;
$$;

revoke execute on function public.crear_familia(text), public.unirse_familia(text), public.regenerar_codigo() from public, anon;
grant execute on function public.crear_familia(text), public.unirse_familia(text), public.regenerar_codigo() to authenticated;
grant execute on function public.es_miembro(uuid) to authenticated;

-- Auditoría: quién y cuándo modificó cada registro --------------------
create or replace function public.marcar_actualizacion()
returns trigger
language plpgsql
as $$
begin
  new.actualizado := now();
  new.actualizado_por := auth.uid();
  return new;
end;
$$;

-- Preferencias compartidas de la familia ------------------------------
create table if not exists public.config (
  familia_id      uuid primary key references public.familias(id) on delete cascade,
  settings        jsonb not null default '{}'::jsonb,
  actualizado     timestamptz not null default now(),
  actualizado_por uuid
);
alter table public.config enable row level security;
drop policy if exists "solo mi familia" on public.config;
create policy "solo mi familia" on public.config
  for all to authenticated
  using (public.es_miembro(familia_id))
  with check (public.es_miembro(familia_id));
drop trigger if exists marcar_actualizacion on public.config;
create trigger marcar_actualizacion before insert or update on public.config
  for each row execute function public.marcar_actualizacion();
grant select, insert, update, delete on public.config to authenticated;
revoke all on public.config from anon;

-- Una tabla por entidad de la aplicación ------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'usuarios', 'ingresos', 'gastos', 'categorias', 'presupuestos', 'tarjetas', 'cuotas',
    'inversiones', 'activos', 'deudas', 'objetivos', 'cotizaciones', 'inflacion', 'cierres_mensuales'
  ] loop
    execute format($f$
      create table if not exists public.%I (
        familia_id      uuid not null references public.familias(id) on delete cascade,
        id              text not null,
        fecha           text,
        demo            boolean not null default false,
        datos           jsonb not null,
        actualizado     timestamptz not null default now(),
        actualizado_por uuid,
        primary key (familia_id, id)
      )$f$, t);
    execute format('create index if not exists %I on public.%I (familia_id, fecha)', t || '_familia_fecha_idx', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "solo mi familia" on public.%I', t);
    execute format('create policy "solo mi familia" on public.%I for all to authenticated using (public.es_miembro(familia_id)) with check (public.es_miembro(familia_id))', t);
    execute format('drop trigger if exists marcar_actualizacion on public.%I', t);
    execute format('create trigger marcar_actualizacion before insert or update on public.%I for each row execute function public.marcar_actualizacion()', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end;
$$;

-- Vistas para consultar desde el SQL Editor o un cliente externo -------
-- security_invoker hace que respeten las mismas reglas de acceso.
create or replace view public.v_gastos with (security_invoker = true) as
select g.familia_id,
       g.fecha,
       substr(g.fecha, 1, 7)                    as mes,
       c.datos ->> 'name'                       as categoria,
       g.datos ->> 'subcategory'                as subcategoria,
       g.datos ->> 'description'                as descripcion,
       (g.datos ->> 'amount')::numeric          as monto,
       g.datos ->> 'currency'                   as moneda,
       g.datos ->> 'kind'                       as tipo,
       g.datos ->> 'paymentMethod'              as medio_pago,
       g.datos ->> 'person'                     as persona,
       g.demo
from public.gastos g
left join public.categorias c
  on c.familia_id = g.familia_id and c.id = g.datos ->> 'categoryId';

create or replace view public.v_ingresos with (security_invoker = true) as
select familia_id,
       fecha,
       substr(fecha, 1, 7)               as mes,
       datos ->> 'type'                  as tipo,
       datos ->> 'description'           as descripcion,
       (datos ->> 'amount')::numeric     as monto,
       datos ->> 'currency'              as moneda,
       datos ->> 'person'                as persona,
       datos ->> 'recurrence'            as frecuencia,
       demo
from public.ingresos;

-- Solo movimientos en pesos: la conversión de USD la hace la app con la cotización de cada fecha.
create or replace view public.v_resumen_mensual_ars with (security_invoker = true) as
select familia_id,
       mes,
       sum(ingresos)                 as ingresos,
       sum(gastos)                   as gastos,
       sum(ingresos) - sum(gastos)   as ahorro
from (
  select familia_id, substr(fecha, 1, 7) as mes, (datos ->> 'amount')::numeric as ingresos, 0::numeric as gastos
  from public.ingresos where datos ->> 'currency' = 'ARS'
  union all
  select familia_id, substr(fecha, 1, 7), 0, (datos ->> 'amount')::numeric
  from public.gastos where datos ->> 'currency' = 'ARS'
) x
group by familia_id, mes;

grant select on public.v_gastos, public.v_ingresos, public.v_resumen_mensual_ars to authenticated;
revoke all on public.v_gastos, public.v_ingresos, public.v_resumen_mensual_ars from anon;
