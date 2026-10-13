alter table public.romano_pack_orders
  add column if not exists accepted_at timestamptz,
  add column if not exists delivered_at timestamptz;

create index if not exists romano_pack_orders_accepted_idx
  on public.romano_pack_orders(company_id, accepted_at desc);
create index if not exists romano_pack_orders_delivered_idx
  on public.romano_pack_orders(company_id, delivered_at desc);

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
declare
  v_profile public.profiles%rowtype;
  v_order public.romano_pack_orders%rowtype;
  v_assignee public.profiles%rowtype;
  v_now timestamptz := now();
begin
  select * into v_profile from public.profiles where id=auth.uid() and active=true;
  if not found or v_profile.role not in ('admin','supervisor') then raise exception 'No autorizado.'; end if;
  select * into v_order from public.romano_pack_orders where id=p_order_id and company_id=v_profile.company_id for update;
  if not found then raise exception 'Pedido no disponible.'; end if;
  if p_status not in ('submitted','under_review','confirmed','organizing','ready','delivered','rejected') then raise exception 'Estado no válido.'; end if;
  if p_confirmed_total is null or p_confirmed_total<0 then raise exception 'Precio confirmado no válido.'; end if;
  if p_assigned_to is not null then
    select * into v_assignee from public.profiles where id=p_assigned_to and company_id=v_profile.company_id and active=true and role in ('employee','maintenance_technician','supervisor');
    if not found then raise exception 'Responsable no válido para esta empresa.'; end if;
  end if;
  update public.romano_pack_orders set
    status=p_status, confirmed_total=p_confirmed_total, assigned_to=p_assigned_to,
    admin_notes=left(coalesce(p_admin_notes,''),1000), updated_at=v_now,
    accepted_at=case when p_status in ('under_review','confirmed','organizing','ready','delivered') then coalesce(accepted_at,v_now) else accepted_at end,
    delivered_at=case when p_status='delivered' then coalesce(delivered_at,v_now) else delivered_at end
  where id=p_order_id;
end;
$$;

create or replace function public.romano_update_pack_order_status(p_order_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_order public.romano_pack_orders%rowtype;
  v_now timestamptz := now();
begin
  select * into v_profile from public.profiles where id=auth.uid() and active=true;
  if not found then raise exception 'No autorizado.'; end if;
  select * into v_order from public.romano_pack_orders where id=p_order_id and company_id=v_profile.company_id for update;
  if not found then raise exception 'Pedido no disponible.'; end if;
  if v_profile.role not in ('admin','supervisor') and v_order.assigned_to <> auth.uid() then raise exception 'Este pedido no está asignado a su perfil.'; end if;
  if p_status not in ('submitted','under_review','confirmed','organizing','ready','delivered','rejected') then raise exception 'Estado no válido.'; end if;
  if v_profile.role not in ('admin','supervisor') and p_status not in ('ready','delivered') then raise exception 'No autorizado para este cambio de estado.'; end if;
  update public.romano_pack_orders set
    status=p_status, updated_at=v_now,
    accepted_at=case when p_status in ('under_review','confirmed','organizing','ready','delivered') then coalesce(accepted_at,v_now) else accepted_at end,
    delivered_at=case when p_status='delivered' then coalesce(delivered_at,v_now) else delivered_at end
  where id=p_order_id;
end;
$$;

grant execute on function public.romano_review_pack_order(uuid,text,numeric,uuid,text) to authenticated;
grant execute on function public.romano_update_pack_order_status(uuid,text) to authenticated;