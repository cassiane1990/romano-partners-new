-- ROMANO PARTNERS: Packs de ropa y amenities
-- Apply in Supabase SQL Editor before enabling the module in production.
create table if not exists public.romano_pack_orders (
  id uuid primary key default gen_random_uuid(),
  order_code text not null unique default ('PACK-' || to_char(now() at time zone 'Europe/Madrid','YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6))),
  company_id uuid not null,
  client_profile_id uuid not null references auth.users(id) on delete restrict,
  property_id uuid not null references public.properties(id) on delete restrict,
  items jsonb not null check (
    jsonb_typeof(items) = 'object'
    and coalesce((items->>'individual')::integer,0) between 0 and 500
    and coalesce((items->>'double')::integer,0) between 0 and 500
    and coalesce((items->>'single_beds')::integer,0) between 0 and 500
    and coalesce((items->>'amenities')::integer,0) between 0 and 1000
    and (
      coalesce((items->>'individual')::integer,0)
      + coalesce((items->>'double')::integer,0)
      + coalesce((items->>'single_beds')::integer,0)
      + coalesce((items->>'amenities')::integer,0)
    ) > 0
  ),
  estimated_total numeric(10,2) not null check (estimated_total >= 0),
  confirmed_total numeric(10,2) check (confirmed_total is null or confirmed_total >= 0),
  requested_date date not null,
  status text not null default 'submitted' check (status in ('submitted','under_review','confirmed','organizing','ready','delivered','rejected')),
  customer_notes text not null default '' check (char_length(customer_notes) <= 1000),
  admin_notes text not null default '' check (char_length(admin_notes) <= 1000),
  assigned_to uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists romano_pack_orders_company_created_idx on public.romano_pack_orders(company_id, created_at desc);
create index if not exists romano_pack_orders_client_created_idx on public.romano_pack_orders(client_profile_id, created_at desc);
create index if not exists romano_pack_orders_assignee_idx on public.romano_pack_orders(assigned_to, requested_date);

alter table public.romano_pack_orders enable row level security;

drop policy if exists romano_pack_orders_read on public.romano_pack_orders;
create policy romano_pack_orders_read on public.romano_pack_orders
for select to authenticated
using (
  client_profile_id = auth.uid()
  or assigned_to = auth.uid()
  or exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.company_id = romano_pack_orders.company_id
      and p.active = true
      and p.role in ('admin','supervisor')
  )
);

-- Direct client writes are deliberately not permitted. Requests go through the validated RPC.
drop policy if exists romano_pack_orders_no_direct_insert on public.romano_pack_orders;
create policy romano_pack_orders_no_direct_insert on public.romano_pack_orders
for insert to authenticated with check (false);
drop policy if exists romano_pack_orders_no_direct_update on public.romano_pack_orders;
create policy romano_pack_orders_no_direct_update on public.romano_pack_orders
for update to authenticated using (false) with check (false);
drop policy if exists romano_pack_orders_no_direct_delete on public.romano_pack_orders;
create policy romano_pack_orders_no_direct_delete on public.romano_pack_orders
for delete to authenticated using (false);

create or replace function public.romano_create_pack_order(
  p_property_id uuid,
  p_items jsonb,
  p_requested_date date,
  p_customer_notes text default ''
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_property public.properties%rowtype;
  v_total numeric(10,2);
  v_id uuid;
  v_ind integer;
  v_double integer;
  v_single integer;
  v_amenities integer;
begin
  if auth.uid() is null then raise exception 'Autenticación requerida.'; end if;
  select * into v_profile from public.profiles where id = auth.uid() and active = true;
  if not found or v_profile.role <> 'client' then raise exception 'Solo los clientes pueden crear pedidos.'; end if;
  if p_requested_date is null or p_requested_date < (now() at time zone 'Europe/Madrid')::date then
    raise exception 'Seleccione una fecha válida.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'object' then raise exception 'Productos no válidos.'; end if;
  v_ind := coalesce((p_items->>'individual')::integer,0);
  v_double := coalesce((p_items->>'double')::integer,0);
  v_single := coalesce((p_items->>'single_beds')::integer,0);
  v_amenities := coalesce((p_items->>'amenities')::integer,0);
  if v_ind not between 0 and 500 or v_double not between 0 and 500 or v_single not between 0 and 500 or v_amenities not between 0 and 1000
    or v_ind+v_double+v_single+v_amenities <= 0 then raise exception 'Revise las cantidades solicitadas.'; end if;
  select pr.* into v_property
  from public.properties pr
  join public.clients c on c.id = pr.client_id
  where pr.id = p_property_id and c.profile_id = auth.uid() and c.company_id = v_profile.company_id;
  if not found then raise exception 'No tiene acceso a este apartamento.'; end if;
  v_total := round(v_ind*18.84 + v_double*20.41 + v_single*13.25 + v_amenities*1.50,2);
  insert into public.romano_pack_orders(company_id,client_profile_id,property_id,items,estimated_total,requested_date,customer_notes)
  values(v_profile.company_id,auth.uid(),p_property_id,jsonb_build_object('individual',v_ind,'double',v_double,'single_beds',v_single,'amenities',v_amenities),v_total,p_requested_date,left(coalesce(p_customer_notes,''),1000))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.romano_review_pack_order(
  p_order_id uuid,
  p_status text,
  p_confirmed_total numeric,
  p_assigned_to uuid default null,
  p_admin_notes text default ''
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_profile public.profiles%rowtype; v_order public.romano_pack_orders%rowtype; v_assignee public.profiles%rowtype;
begin
  select * into v_profile from public.profiles where id=auth.uid() and active=true;
  if not found or v_profile.role not in ('admin','supervisor') then raise exception 'No autorizado.'; end if;
  select * into v_order from public.romano_pack_orders where id=p_order_id and company_id=v_profile.company_id for update;
  if not found then raise exception 'Pedido no disponible.'; end if;
  if p_status not in ('submitted','under_review','confirmed','organizing','ready','delivered','rejected') then raise exception 'Estado no válido.'; end if;
  if p_confirmed_total is null or p_confirmed_total < 0 then raise exception 'Precio confirmado no válido.'; end if;
  if p_assigned_to is not null then
    select * into v_assignee from public.profiles where id=p_assigned_to and company_id=v_profile.company_id and active=true and role in ('employee','maintenance_technician','supervisor');
    if not found then raise exception 'Responsable no válido para esta empresa.'; end if;
  end if;
  update public.romano_pack_orders set status=p_status,confirmed_total=p_confirmed_total,assigned_to=p_assigned_to,admin_notes=left(coalesce(p_admin_notes,''),1000),updated_at=now()
  where id=p_order_id;
end;
$$;

create or replace function public.romano_update_pack_order_status(p_order_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_profile public.profiles%rowtype; v_order public.romano_pack_orders%rowtype;
begin
  select * into v_profile from public.profiles where id=auth.uid() and active=true;
  if not found then raise exception 'No autorizado.'; end if;
  select * into v_order from public.romano_pack_orders where id=p_order_id and company_id=v_profile.company_id for update;
  if not found then raise exception 'Pedido no disponible.'; end if;
  if v_profile.role not in ('admin','supervisor') and v_order.assigned_to <> auth.uid() then raise exception 'Este pedido no está asignado a su perfil.'; end if;
  if p_status not in ('submitted','under_review','confirmed','organizing','ready','delivered','rejected') then raise exception 'Estado no válido.'; end if;
  if v_profile.role not in ('admin','supervisor') and p_status not in ('ready','delivered') then raise exception 'No autorizado para este cambio de estado.'; end if;
  update public.romano_pack_orders set status=p_status,updated_at=now() where id=p_order_id;
end;
$$;

revoke all on function public.romano_create_pack_order(uuid,jsonb,date,text) from public;
revoke all on function public.romano_review_pack_order(uuid,text,numeric,uuid,text) from public;
revoke all on function public.romano_update_pack_order_status(uuid,text) from public;
grant execute on function public.romano_create_pack_order(uuid,jsonb,date,text) to authenticated;
grant execute on function public.romano_review_pack_order(uuid,text,numeric,uuid,text) to authenticated;
grant execute on function public.romano_update_pack_order_status(uuid,text) to authenticated;

comment on table public.romano_pack_orders is 'Pedidos de packs de ropa y amenities de ROMANO PARTNERS; los cambios operativos se realizan mediante RPC autorizadas.';
