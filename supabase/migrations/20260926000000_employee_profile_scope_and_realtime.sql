create or replace function public.employee_service_creation_context()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_company_id uuid;
  v_role text;
begin
  v_company_id := private.current_company_id();
  v_role := private.current_role();

  if v_company_id is null or v_role <> 'employee' or auth.uid() is null then
    raise exception 'FORBIDDEN';
  end if;

  return jsonb_build_object(
    'clients',
    coalesce((
      select jsonb_agg(
        jsonb_build_object('id',c.id,'name',c.name)
        order by c.name
      )
      from public.clients c
      where c.company_id = v_company_id
        and c.id in (
          select distinct p.client_id
          from public.properties p
          where p.company_id = v_company_id
            and p.id in (select private.employee_property_ids())
            and p.client_id is not null
        )
    ), '[]'::jsonb),
    'properties',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',p.id,'name',p.name,'code',p.code,'client_id',p.client_id,
          'property_type',p.property_type,'beds_single',p.beds_single,
          'beds_double',p.beds_double,'address',p.address,'city',p.city
        )
        order by p.name
      )
      from public.properties p
      where p.company_id = v_company_id
        and p.id in (select private.employee_property_ids())
    ), '[]'::jsonb)
  );
end;
$function$;

drop policy if exists services_employee_insert_maintenance on public.services;

create policy services_employee_insert_maintenance
on public.services
for insert
to authenticated
with check (
  company_id = private.current_company_id()
  and private.current_role() = 'employee'
  and created_by = auth.uid()
  and assigned_employee_id = auth.uid()
  and service_type = 'mantenimiento'
  and status = 'scheduled'
  and assigned_supervisor_id is null
  and priority = any(array['normal','low','high','urgent'])
  and tax_country = any(array['ES','PT'])
  and exists (
    select 1
    from public.properties p
    where p.id = services.property_id
      and p.company_id = private.current_company_id()
      and p.client_id = services.client_id
      and p.id in (select private.employee_property_ids())
  )
);

do $do$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='occurrences') then
    alter publication supabase_realtime add table public.occurrences;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='properties') then
    alter publication supabase_realtime add table public.properties;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='clients') then
    alter publication supabase_realtime add table public.clients;
  end if;
end
$do$;