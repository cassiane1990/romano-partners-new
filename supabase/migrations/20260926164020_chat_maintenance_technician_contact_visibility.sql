-- ROMANO: technician chat contacts + emergency context.

create policy "profiles_maintenance_technician_contact_staff"
on public.profiles
for select
to authenticated
using (
  company_id = private.current_company_id()
  and active = true
  and private."current_role"() = 'maintenance_technician'
  and role in ('admin','supervisor')
);

create or replace function public.maintenance_technician_emergency_context()
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

  if v_company_id is null
     or v_role <> 'maintenance_technician'
     or auth.uid() is null then
    raise exception 'FORBIDDEN';
  end if;

  return jsonb_build_object(
    'clients',
    coalesce((
      select jsonb_agg(
        jsonb_build_object('id',c.id,'name',c.name,'client_code',c.client_code)
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
          'beds_double',p.beds_double,'address',p.address,'city',p.city,
          'country',p.country,'latitude',p.latitude,'longitude',p.longitude
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

revoke execute on function public.maintenance_technician_emergency_context() from anon;
grant execute on function public.maintenance_technician_emergency_context() to authenticated;
