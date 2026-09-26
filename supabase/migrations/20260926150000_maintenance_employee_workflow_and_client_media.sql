create or replace function private.employee_is_maintenance()
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.employee_profiles ep
    where ep.profile_id=(select auth.uid())
      and ep.company_id=private.current_company_id()
      and ep.active=true
      and lower(coalesce(ep.function_title,'')) similar to '%(manuten|manten|maintenance)%'
  )
$$;

revoke all on function private.employee_is_maintenance() from public;

create or replace function public.maintenance_employee_cleaning_context()
returns table(
  id uuid,
  code text,
  service_type text,
  typology text,
  status text,
  scheduled_at timestamptz,
  property_id uuid,
  client_id uuid,
  assigned_employee_id uuid
)
language sql
stable
security definer
set search_path=''
as $$
  select s.id,s.code,s.service_type,s.typology,s.status,s.scheduled_at,s.property_id,s.client_id,s.assigned_employee_id
  from public.services s
  where s.company_id=private.current_company_id()
    and lower(coalesce(s.service_type,'')) like '%limp%'
    and exists(
      select 1
      from public.services m
      where m.company_id=s.company_id
        and m.property_id=s.property_id
        and m.assigned_employee_id=(select auth.uid())
        and lower(coalesce(m.service_type,'')) not like '%limp%'
        and lower(coalesce(m.service_type,'')) <> 'cleaning'
    )
    and private.current_role()='employee'
    and private.employee_is_maintenance()
  order by s.scheduled_at nulls last, s.created_at desc
$$;

revoke all on function public.maintenance_employee_cleaning_context() from public;
grant execute on function public.maintenance_employee_cleaning_context() to authenticated;

create or replace function public.employee_finish_maintenance_service(p_service_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_service public.services%rowtype;
  v_media integer;
begin
  if private.current_role() <> 'employee' then
    raise exception 'Solo el funcionario puede finalizar un mantenimiento';
  end if;

  select * into v_service
  from public.services
  where id=p_service_id
    and company_id=private.current_company_id()
    and assigned_employee_id=(select auth.uid())
  for update;

  if not found then
    raise exception 'Mantenimiento no encontrado o no asignado a este funcionario';
  end if;

  if lower(coalesce(v_service.service_type,'')) like '%limp%'
     or lower(coalesce(v_service.service_type,''))='cleaning' then
    raise exception 'Este flujo no aplica a limpieza';
  end if;

  if v_service.status not in ('on_the_way','in_progress','paused') then
    raise exception 'El mantenimiento debe estar en camino, iniciado o pausado';
  end if;

  select count(*) into v_media
  from public.service_media
  where service_id=p_service_id
    and media_type in ('photo','video');

  if v_media < 1 then
    raise exception 'ANEXE_FOTO_VIDEO: Debe anexar al menos una foto o video antes de finalizar';
  end if;

  update public.services
  set status='completed',
      finished_at=now(),
      finished_by=(select auth.uid()),
      updated_at=now()
  where id=p_service_id;

  insert into public.notifications(id,company_id,recipient_id,title,body,severity)
  select gen_random_uuid(),v_service.company_id,c.profile_id,
         'Mantenimiento finalizado',
         'El mantenimiento del servicio '||coalesce(v_service.code,'')||
         ' fue finalizado. Abra el servicio para ver las fotos y vídeos del trabajo realizado.',
         'normal'
  from public.clients c
  where c.id=v_service.client_id
    and c.profile_id is not null;

  return jsonb_build_object('ok',true,'status','completed','media_count',v_media);
end;
$$;

revoke all on function public.employee_finish_maintenance_service(uuid) from public;
grant execute on function public.employee_finish_maintenance_service(uuid) to authenticated;
