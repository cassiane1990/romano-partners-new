-- ROMANO PARTNERS · Gestão de equipas por serviço
create table if not exists public.service_team_assignments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  service_id uuid not null references public.services(id) on delete cascade,
  employee_profile_id uuid not null references public.employee_profiles(id) on delete cascade,
  team_name text not null check (team_name in ('ÁGUIA','ALFA','BRAVO','DELTA')),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint service_team_assignments_service_employee_key unique (service_id, employee_profile_id)
);
create index if not exists service_team_assignments_company_service_idx
  on public.service_team_assignments(company_id, service_id);
alter table public.service_team_assignments enable row level security;
drop policy if exists service_team_assignments_management on public.service_team_assignments;
create policy service_team_assignments_management on public.service_team_assignments
for all to authenticated
using (company_id = private.current_company_id() and private.current_role() in ('admin','supervisor'))
with check (company_id = private.current_company_id() and private.current_role() in ('admin','supervisor'));

create or replace function public.set_service_team_assignments(
  p_service_id uuid,
  p_team_name text,
  p_employee_profile_ids uuid[]
) returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_company uuid;
  v_role text;
  v_expected integer;
  v_found integer;
begin
  v_company := private.current_company_id();
  v_role := private.current_role();
  if v_role not in ('admin','supervisor') then
    raise exception 'Apenas Administrador ou Supervisor pode gerir equipas';
  end if;
  if p_team_name not in ('ÁGUIA','ALFA','BRAVO','DELTA') then
    raise exception 'Equipa inválida';
  end if;
  if not exists (select 1 from public.services s where s.id = p_service_id and s.company_id = v_company) then
    raise exception 'Serviço não encontrado nesta empresa';
  end if;
  v_expected := coalesce(cardinality(p_employee_profile_ids),0);
  select count(distinct ep.id)::integer into v_found
  from public.employee_profiles ep
  where ep.id = any(coalesce(p_employee_profile_ids, array[]::uuid[]))
    and ep.company_id = v_company and ep.active = true
    and (ep.profile_id is null or exists (
      select 1 from public.profiles p where p.id = ep.profile_id
        and p.company_id = v_company and p.active = true
        and p.role in ('employee','maintenance_technician')
    ));
  if v_found <> v_expected then
    raise exception 'Um ou mais funcionários não estão ativos ou não pertencem à empresa';
  end if;
  delete from public.service_team_assignments where service_id = p_service_id and company_id = v_company;
  if v_expected > 0 then
    insert into public.service_team_assignments(company_id,service_id,employee_profile_id,team_name,created_by)
    select v_company,p_service_id,ep.id,p_team_name,auth.uid()
    from public.employee_profiles ep
    where ep.id = any(coalesce(p_employee_profile_ids, array[]::uuid[]))
      and ep.company_id = v_company and ep.active = true;
  end if;
end
$function$;
revoke all on function public.set_service_team_assignments(uuid,text,uuid[]) from public;
grant execute on function public.set_service_team_assignments(uuid,text,uuid[]) to authenticated;