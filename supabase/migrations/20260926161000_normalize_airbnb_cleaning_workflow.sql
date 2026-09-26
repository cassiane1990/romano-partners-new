-- ROMANO PROPERTY CARE · normalize Airbnb/hotel as cleaning
-- Prevents maintenance employees from seeing cleaning work as maintenance.

create or replace function public.maintenance_employee_cleaning_context()
returns table(id uuid,code text,service_type text,typology text,status text,scheduled_at timestamptz,property_id uuid,client_id uuid,assigned_employee_id uuid)
language sql stable security definer set search_path=''
as $function$
  select s.id,s.code,s.service_type,s.typology,s.status,s.scheduled_at,s.property_id,s.client_id,s.assigned_employee_id
  from public.services s
  where s.company_id=private.current_company_id()
    and (
      lower(coalesce(s.service_type,'')) like '%limp%'
      or lower(coalesce(s.service_type,''))='airbnb'
      or lower(coalesce(s.service_type,''))='cleaning'
      or lower(coalesce(s.service_type,'')) like '%hotel%'
      or lower(coalesce(s.service_type,'')) like '%housekeeping%'
      or lower(coalesce(s.service_type,'')) like '%alojamiento%'
    )
    and exists(
      select 1 from public.services m
      where m.company_id=s.company_id and m.property_id=s.property_id
        and m.assigned_employee_id=(select auth.uid())
        and not (
          lower(coalesce(m.service_type,'')) like '%limp%'
          or lower(coalesce(m.service_type,''))='airbnb'
          or lower(coalesce(m.service_type,''))='cleaning'
          or lower(coalesce(m.service_type,'')) like '%hotel%'
          or lower(coalesce(m.service_type,'')) like '%housekeeping%'
          or lower(coalesce(m.service_type,'')) like '%alojamiento%'
        )
    )
    and private.current_role()='employee'
    and private.employee_is_maintenance()
  order by s.scheduled_at nulls last,s.created_at desc
$function$;

create or replace function public.employee_finish_maintenance_service(p_service_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_service public.services%rowtype; v_media integer;
begin
  if private.current_role()<>'employee' then raise exception 'Solo el funcionario puede finalizar un mantenimiento'; end if;
  select * into v_service from public.services where id=p_service_id and company_id=private.current_company_id() and assigned_employee_id=(select auth.uid()) for update;
  if not found then raise exception 'Mantenimiento no encontrado o no asignado a este funcionario'; end if;
  if lower(coalesce(v_service.service_type,'')) like '%limp%' or lower(coalesce(v_service.service_type,''))='airbnb' or lower(coalesce(v_service.service_type,''))='cleaning' or lower(coalesce(v_service.service_type,'')) like '%hotel%' or lower(coalesce(v_service.service_type,'')) like '%housekeeping%' or lower(coalesce(v_service.service_type,'')) like '%alojamiento%' then
    raise exception 'Este flujo no aplica a limpieza';
  end if;
  if v_service.status not in ('on_the_way','in_progress','paused') then raise exception 'El mantenimiento debe estar en camino, iniciado o pausado'; end if;
  select count(*) into v_media from public.service_media where service_id=p_service_id and media_type in ('photo','video');
  if v_media<1 then raise exception 'ANEXE_FOTO_VIDEO: Debe anexar al menos una foto o video antes de finalizar'; end if;
  update public.services set status='completed',finished_at=now(),finished_by=(select auth.uid()),updated_at=now(),updated_by=(select auth.uid()),updated_by_at=now() where id=p_service_id;
  return jsonb_build_object('ok',true,'status','completed','media_count',v_media);
end
$function$;

create or replace function private.notify_employee_completed_maintenance()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if old.status is distinct from new.status and new.status='completed'
     and lower(coalesce(new.service_type,'')) not like '%limp%'
     and lower(coalesce(new.service_type,''))<>'airbnb'
     and lower(coalesce(new.service_type,''))<>'cleaning'
     and lower(coalesce(new.service_type,'')) not like '%hotel%'
     and lower(coalesce(new.service_type,'')) not like '%housekeeping%'
     and lower(coalesce(new.service_type,'')) not like '%alojamiento%'
     and new.finished_by=(select auth.uid()) then
    insert into public.notifications(company_id,recipient_id,title,body,severity)
    select new.company_id,c.profile_id,'Mantenimiento finalizado',
           'El mantenimiento del servicio '||coalesce(new.code,'')||' fue finalizado. Abra el servicio para ver las fotos y vídeos del trabajo realizado.',
           'normal'
    from public.clients c where c.id=new.client_id and c.profile_id is not null;
  end if;
  return new;
end
$function$;

create or replace function private.enforce_employee_service_update()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_role text; v_media integer:=0;
begin
  select p.role into v_role from public.profiles p where p.id=(select auth.uid()) and p.company_id=old.company_id;
  if v_role<>'employee' then return new; end if;
  if old.assigned_employee_id is distinct from (select auth.uid()) then raise exception 'Servicio no asignado a este funcionario'; end if;
  if new.assigned_employee_id is distinct from old.assigned_employee_id or new.company_id is distinct from old.company_id or new.client_id is distinct from old.client_id or new.property_id is distinct from old.property_id or new.code is distinct from old.code or new.service_type is distinct from old.service_type or new.typology is distinct from old.typology or new.priority is distinct from old.priority or new.scheduled_at is distinct from old.scheduled_at or new.agreed_amount is distinct from old.agreed_amount or new.instructions is distinct from old.instructions or new.requested_items is distinct from old.requested_items or new.additional_items is distinct from old.additional_items or new.laundry is distinct from old.laundry or new.pricing is distinct from old.pricing or new.tax_country is distinct from old.tax_country or new.assigned_supervisor_id is distinct from old.assigned_supervisor_id or new.supervisor_approved_at is distinct from old.supervisor_approved_at or new.supervision_approved_at is distinct from old.supervision_approved_at or new.supervision_approved_by is distinct from old.supervision_approved_by then
    raise exception 'El funcionario solo puede actualizar el estado y los datos operativos permitidos';
  end if;
  if new.status is distinct from old.status then
    if old.status='scheduled' and new.status<>'on_the_way' then raise exception 'No se puede volver atrás: acepte la designación para pasar a A camino'; end if;
    if old.status='on_the_way' and new.status<>'in_progress' then raise exception 'No se puede volver atrás: el siguiente estado es Iniciado'; end if;
    if old.status='in_progress' and new.status not in ('paused','supervision_pending','completed') then raise exception 'No se puede volver atrás desde Iniciado'; end if;
    if old.status='paused' and new.status not in ('in_progress','completed') then raise exception 'Desde Pausado solo se puede Continuar o finalizar mantenimiento'; end if;
    if old.status in ('supervision_pending','supervised','completed','approved','cancelled','rejected','returned') then raise exception 'Este servicio ya está verificado/finalizado y no se puede retroceder'; end if;
    if new.status='completed' then
      if lower(coalesce(new.service_type,'')) like '%limp%' or lower(coalesce(new.service_type,''))='airbnb' or lower(coalesce(new.service_type,''))='cleaning' or lower(coalesce(new.service_type,'')) like '%hotel%' or lower(coalesce(new.service_type,'')) like '%housekeeping%' or lower(coalesce(new.service_type,'')) like '%alojamiento%' then
        raise exception 'La limpieza no puede ser finalizada por el funcionario';
      end if;
      select count(*) into v_media from public.service_media where service_id=old.id and media_type in ('photo','video');
      if v_media<1 then raise exception 'ANEXE_FOTO_VIDEO: Debe anexar al menos una foto o video antes de finalizar'; end if;
    end if;
  end if;
  return new;
end
$function$;
