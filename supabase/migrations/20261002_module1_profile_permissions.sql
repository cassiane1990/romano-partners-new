-- ROMANO PARTNERS · Module 1 profile permissions
-- Applied to production project ztjfvqcutwlfbqmtclyv on 2026-10-02.

drop policy if exists invoices_admin_manage on public.invoices;
create policy invoices_admin_manage on public.invoices
for all to authenticated
using (company_id = private.current_company_id() and private.current_role() = 'admin')
with check (company_id = private.current_company_id() and private.current_role() = 'admin');

drop policy if exists invoices_supervisor_select on public.invoices;

drop policy if exists payments_admin_manage on public.payments;
create policy payments_admin_manage on public.payments
for all to authenticated
using (company_id = private.current_company_id() and private.current_role() = 'admin')
with check (company_id = private.current_company_id() and private.current_role() = 'admin');

drop policy if exists quotes_admin_manage on public.quotes;
create policy quotes_admin_manage on public.quotes
for all to authenticated
using (company_id = private.current_company_id() and private.current_role() = 'admin')
with check (company_id = private.current_company_id() and private.current_role() = 'admin');

drop policy if exists catalog_manage on public.service_catalog;
create policy catalog_manage on public.service_catalog
for all to authenticated
using (company_id = private.current_company_id() and private.current_role() = 'admin')
with check (company_id = private.current_company_id() and private.current_role() = 'admin');

drop policy if exists service_costs_scoped_select on public.service_costs;
create policy service_costs_scoped_select on public.service_costs
for select to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = (select auth.uid())
      and p.company_id = service_costs.company_id
      and (
        p.role = 'admin'
        or exists (
          select 1 from services s
          where s.id = service_costs.service_id
            and s.assigned_employee_id = p.id
        )
      )
  )
);

drop policy if exists service_items_manage on public.service_items;
create policy service_items_manage on public.service_items
for all to authenticated
using (
  service_id in (select s.id from services s where s.company_id = private.current_company_id())
  and private.current_role() = 'admin'
)
with check (
  service_id in (select s.id from services s where s.company_id = private.current_company_id())
  and private.current_role() = 'admin'
);

drop policy if exists service_items_select_scoped on public.service_items;
create policy service_items_select_scoped on public.service_items
for select to authenticated
using (
  exists (
    select 1 from services s
    where s.id = service_items.service_id
      and s.company_id = private.current_company_id()
      and (
        private.current_role() = 'admin'
        or s.client_id in (select c.id from clients c where c.profile_id = (select auth.uid()))
        or s.assigned_employee_id = (select auth.uid())
      )
  )
);

drop policy if exists services_employee_insert_maintenance on public.services;

create or replace function public.create_maintenance_service(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_company uuid;
  v_id uuid;
  v_payload jsonb := coalesce(p_payload,'{}'::jsonb);
begin
  v_role := private.current_role();
  v_company := private.current_company_id();

  if v_role not in ('admin','supervisor','maintenance_technician') then
    raise exception 'Solo Admin, Supervisor o Técnico de Mantenimiento puede crear mantenimiento';
  end if;

  if (v_payload->>'company_id')::uuid is distinct from v_company then
    raise exception 'Empresa no válida';
  end if;

  if v_role='maintenance_technician' then
    if coalesce(v_payload->>'priority','') <> 'urgent'
       or coalesce(v_payload->'pricing'->>'rate_key','') <> 'emergency' then
      raise exception 'El Técnico de Mantenimiento solo puede crear Mantenimiento de Urgencia 24H';
    end if;
    v_payload := jsonb_set(v_payload,'{assigned_employee_id}',to_jsonb(auth.uid()),true);
  end if;

  v_payload := jsonb_set(v_payload,'{id}',to_jsonb(gen_random_uuid()),true);
  v_payload := jsonb_set(v_payload,'{created_by}',to_jsonb(auth.uid()),true);
  v_payload := jsonb_set(v_payload,'{updated_by}',to_jsonb(auth.uid()),true);
  v_payload := jsonb_set(v_payload,'{service_type}',to_jsonb('mantenimiento'::text),true);
  v_payload := jsonb_set(v_payload,'{status}',to_jsonb('scheduled'::text),true);
  v_payload := jsonb_set(v_payload,'{supervisor_approved_at}',to_jsonb(now()),true);

  if not exists (
    select 1 from public.clients c
    where c.id=(v_payload->>'client_id')::uuid and c.company_id=v_company
  ) then
    raise exception 'Cliente no válido para esta empresa';
  end if;

  if not exists (
    select 1 from public.properties p
    where p.id=(v_payload->>'property_id')::uuid
      and p.company_id=v_company
      and p.client_id=(v_payload->>'client_id')::uuid
  ) then
    raise exception 'Apartamento no válido para este cliente';
  end if;

  insert into public.services
  select (jsonb_populate_record(null::public.services,v_payload)).*
  returning id into v_id;

  return v_id;
end
$function$;

create or replace function public.romano_catalog_stock_guard()
returns table(company_id uuid, role text)
language sql
stable
security definer
set search_path to ''
as $function$
  select p.company_id,p.role
  from public.profiles p
  where p.id=auth.uid()
    and p.active=true
    and p.role='admin'
  limit 1
$function$;

revoke execute on function public.create_maintenance_service(jsonb) from anon;
revoke execute on function public.create_maintenance_service(jsonb) from public;
grant execute on function public.create_maintenance_service(jsonb) to authenticated;
