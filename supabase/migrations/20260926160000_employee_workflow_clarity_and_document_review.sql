-- ROMANO PROPERTY CARE · employee workflow hardening
-- 2026-09-26
-- Keeps employee work simple: accept -> on the way -> started -> paused/continue -> final.
-- Employees never receive service financial values through the UI, and terminal states cannot be reversed.

alter table public.employee_documents
  add column if not exists review_status text not null default 'pending',
  add column if not exists reviewed_by uuid,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_notes text;

alter table public.employee_documents
  drop constraint if exists employee_documents_review_status_check;

alter table public.employee_documents
  add constraint employee_documents_review_status_check
  check (review_status in ('pending','verified','needs_correction'));

create index if not exists idx_employee_documents_review
  on public.employee_documents(company_id,employee_profile_id,review_status,created_at desc);

create or replace function private.romano_handle_dispatch_response()
returns trigger
language plpgsql
security definer
set search_path=public,private
as $function$
declare v_service public.services%rowtype;
begin
  select * into v_service from public.services where id=new.service_id;
  if not found then return new; end if;
  if new.response='accepted' and old.response='pending' then
    insert into public.service_events(company_id,service_id,actor_id,event_type,metadata)
    values(v_service.company_id,v_service.id,new.employee_id,'dispatch_accepted',
           jsonb_build_object('dispatch_id',new.id,'distance_m',new.distance_m));
  elsif new.response='rejected' and old.response='pending' then
    insert into public.service_events(company_id,service_id,actor_id,event_type,metadata)
    values(v_service.company_id,v_service.id,new.employee_id,'dispatch_rejected',
           jsonb_build_object('dispatch_id',new.id,'reason',new.reason));
    perform private.romano_dispatch_next(new.service_id);
  end if;
  return new;
end
$function$;

create or replace function private.romano_guard_employee_service_update()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,private
as $function$
begin
  if private.current_role() = 'employee' then
    if new.company_id is distinct from old.company_id
       or new.client_id is distinct from old.client_id
       or new.property_id is distinct from old.property_id
       or new.code is distinct from old.code
       or new.service_type is distinct from old.service_type
       or new.typology is distinct from old.typology
       or new.priority is distinct from old.priority
       or new.scheduled_at is distinct from old.scheduled_at
       or new.assigned_employee_id is distinct from old.assigned_employee_id
       or new.assigned_supervisor_id is distinct from old.assigned_supervisor_id
       or new.agreed_amount is distinct from old.agreed_amount
       or new.instructions is distinct from old.instructions
       or new.created_at is distinct from old.created_at
       or (new.accepted_at is distinct from old.accepted_at and not (
            old.status='scheduled' and new.status='on_the_way'
            and new.accepted_by=(select auth.uid()) and new.accepted_at is not null
       ))
       or (new.response_deadline_at is distinct from old.response_deadline_at and new.response_deadline_at is not null)
       or new.client_requested_at is distinct from old.client_requested_at
       or new.supervisor_approved_at is distinct from old.supervisor_approved_at
       or new.pricing_code is distinct from old.pricing_code
       or new.tax_country is distinct from old.tax_country
       or new.requested_items is distinct from old.requested_items then
      raise exception 'Empleado solo puede actualizar estado, jornada y notas del servicio.';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.employee_accept_service_assignment(p_service_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private
as $function$
declare
  v public.services%rowtype;
  a public.service_dispatch_attempts%rowtype;
begin
  if private.current_role()<>'employee' then
    raise exception 'Solo un funcionario puede aceptar una asignación';
  end if;

  select * into v from public.services
  where id=p_service_id and company_id=private.current_company_id()
    and assigned_employee_id=auth.uid() for update;

  if not found then raise exception 'Servicio no asignado a este funcionario'; end if;

  if v.status<>'scheduled' then
    if v.accepted_at is not null and v.status in ('on_the_way','in_progress','paused','supervision_pending','completed','approved')
      then return jsonb_build_object('ok',true,'status',v.status,'already_accepted',true);
    end if;
    raise exception 'Este servicio ya no está pendiente de aceptación';
  end if;

  select * into a from public.service_dispatch_attempts
  where service_id=v.id and employee_id=auth.uid() and response='pending'
  order by assigned_at desc limit 1 for update;

  if not found then
    insert into public.service_dispatch_attempts(company_id,service_id,employee_id,assigned_at,expires_at,response,reason)
    values(v.company_id,v.id,auth.uid(),coalesce(v.assigned_at,now()),null,'pending','legacy_assignment_recovered')
    returning * into a;
  end if;

  update public.service_dispatch_attempts set response='accepted',responded_at=now() where id=a.id;

  update public.services
  set accepted_at=now(),accepted_by=auth.uid(),status='on_the_way',
      response_deadline_at=null,updated_at=now(),updated_by=auth.uid(),updated_by_at=now()
  where id=v.id;

  insert into public.notifications(company_id,recipient_id,title,body,severity)
  select v.company_id,c.profile_id,'Servicio aceptado · funcionario asignado',
         'El servicio '||v.code||' fue aceptado por el funcionario y está en camino.','info'
  from public.clients c where c.id=v.client_id and c.profile_id is not null;

  return jsonb_build_object('ok',true,'status','on_the_way');
end
$function$;

create or replace function public.employee_transition_service_status(p_service_id uuid,p_next_status text)
returns jsonb
language plpgsql
security definer
set search_path=public,private
as $function$
declare v public.services%rowtype; v_next text:=lower(trim(coalesce(p_next_status,'')));
begin
  if private.current_role()<>'employee' then raise exception 'Solo el funcionario puede actualizar el estado'; end if;
  if v_next not in ('on_the_way','in_progress','paused') then raise exception 'Estado no permitido para actualización manual'; end if;

  select * into v from public.services
  where id=p_service_id and company_id=private.current_company_id()
    and assigned_employee_id=auth.uid() for update;

  if not found then raise exception 'Servicio no asignado a este funcionario'; end if;
  if v.status='scheduled' and v_next<>'on_the_way' then raise exception 'Primero acepte la designación'; end if;
  if v.status='on_the_way' and v_next<>'in_progress' then raise exception 'El siguiente estado es Iniciado'; end if;
  if v.status='in_progress' and v_next<>'paused' then raise exception 'Desde Iniciado solo puede Pausar o finalizar mediante el flujo correspondiente'; end if;
  if v.status='paused' and v_next<>'in_progress' then raise exception 'Desde Pausado solo puede Continuar'; end if;
  if v.status in ('supervision_pending','supervised','completed','approved','cancelled','rejected','returned')
    then raise exception 'Este servicio ya está verificado/finalizado y no se puede retroceder'; end if;

  update public.services
  set status=v_next,
      started_at=case when v_next='in_progress' and started_at is null then now() else started_at end,
      started_by=case when v_next='in_progress' then auth.uid() else started_by end,
      updated_at=now(),updated_by=auth.uid(),updated_by_at=now()
  where id=v.id;

  return jsonb_build_object('ok',true,'status',v_next);
end
$function$;

create or replace function public.review_employee_document(p_document_id uuid,p_status text,p_notes text default null)
returns jsonb
language plpgsql
security definer
set search_path=public,private
as $function$
declare v public.employee_documents%rowtype; v_status text:=lower(trim(coalesce(p_status,'')));
begin
  if private.current_role() not in ('admin','supervisor') then raise exception 'Solo Admin/Supervisor puede revisar documentos'; end if;
  if v_status not in ('verified','needs_correction') then raise exception 'Estado de revisión no válido'; end if;

  select * into v from public.employee_documents
  where id=p_document_id and company_id=private.current_company_id() for update;
  if not found then raise exception 'Documento no encontrado'; end if;

  update public.employee_documents
  set review_status=v_status,reviewed_by=auth.uid(),reviewed_at=now(),review_notes=nullif(trim(p_notes),'')
  where id=v.id;

  return jsonb_build_object('ok',true,'status',v_status,'document_id',v.id);
end
$function$;

revoke all on function public.employee_accept_service_assignment(uuid) from public,anon;
grant execute on function public.employee_accept_service_assignment(uuid) to authenticated;
revoke all on function public.employee_transition_service_status(uuid,text) from public,anon;
grant execute on function public.employee_transition_service_status(uuid,text) to authenticated;
revoke all on function public.review_employee_document(uuid,text,text) from public,anon;
grant execute on function public.review_employee_document(uuid,text,text) to authenticated;
