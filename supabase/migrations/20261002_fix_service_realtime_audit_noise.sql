-- Reduce audit noise and realtime refreshes caused by internal service updates.
-- The DB function was also applied directly to the connected Supabase project.

create or replace function public.romano_service_lifecycle_audit()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
 actor uuid:=auth.uid();
 safe_actor uuid;
 meaningful_change boolean:=false;
begin
 if tg_op='INSERT' then
   if new.created_by is null then new.created_by:=actor; end if;
   if new.created_by_at is null then new.created_by_at:=now(); end if;
   if new.updated_by is null then new.updated_by:=actor; end if;
   if new.updated_by_at is null then new.updated_by_at:=now(); end if;
   if new.client_requested_at is null then new.client_requested_at:=coalesce(new.created_at,now()); end if;
   return new;
 end if;

 if tg_op='UPDATE' then
   new.updated_by:=coalesce(actor,new.updated_by,old.updated_by);
   new.updated_by_at:=now();

   select p.id into safe_actor
     from public.profiles p
    where p.id=coalesce(actor,new.updated_by,old.updated_by)
      and p.company_id=new.company_id
    limit 1;

   if new.assigned_employee_id is distinct from old.assigned_employee_id
      or new.assigned_supervisor_id is distinct from old.assigned_supervisor_id then
     new.assigned_by:=coalesce(actor,new.assigned_by);
     new.assigned_at:=coalesce(new.assigned_at,now());
     insert into public.service_events(company_id,service_id,actor_id,event_type,metadata)
     values(new.company_id,new.id,safe_actor,'assigned',
            jsonb_build_object('employee_id',new.assigned_employee_id,'supervisor_id',new.assigned_supervisor_id));
     meaningful_change:=true;
   end if;

   if new.accepted_at is not null and old.accepted_at is null then
     new.accepted_by:=actor;
     insert into public.service_events(company_id,service_id,actor_id,event_type,metadata)
     values(new.company_id,new.id,safe_actor,'accepted','{}'::jsonb);
     meaningful_change:=true;
   end if;

   if new.started_at is not null and old.started_at is null then
     new.started_by:=actor;
     insert into public.service_events(company_id,service_id,actor_id,event_type,metadata)
     values(new.company_id,new.id,safe_actor,'started','{}'::jsonb);
     meaningful_change:=true;
   end if;

   if new.finished_at is not null and old.finished_at is null then
     new.finished_by:=actor;
     insert into public.service_events(company_id,service_id,actor_id,event_type,metadata)
     values(new.company_id,new.id,safe_actor,'finished','{}'::jsonb);
     meaningful_change:=true;
   end if;

   if new.status='supervised' and old.status is distinct from new.status then
     new.supervised_by:=actor;
     new.supervised_at:=now();
     insert into public.service_events(company_id,service_id,actor_id,event_type,metadata)
     values(new.company_id,new.id,safe_actor,'supervised','{}'::jsonb);
     meaningful_change:=true;
   end if;

   if new.status is distinct from old.status
      or new.scheduled_at is distinct from old.scheduled_at
      or new.service_type is distinct from old.service_type
      or new.typology is distinct from old.typology
      or new.priority is distinct from old.priority
      or new.client_id is distinct from old.client_id
      or new.property_id is distinct from old.property_id
      or new.instructions is distinct from old.instructions
      or new.assigned_employee_id is distinct from old.assigned_employee_id
      or new.assigned_supervisor_id is distinct from old.assigned_supervisor_id
      or new.accepted_at is distinct from old.accepted_at
      or new.started_at is distinct from old.started_at
      or new.finished_at is distinct from old.finished_at
      or new.supervised_at is distinct from old.supervised_at
      or new.pricing is distinct from old.pricing
      or new.agreed_amount is distinct from old.agreed_amount then
     meaningful_change:=true;
   end if;

   if meaningful_change then
     insert into public.audit_logs(company_id,actor_id,action,object_type,object_id,metadata)
     values(new.company_id,safe_actor,'service_updated','service',new.id,
            jsonb_build_object('from_status',old.status,'to_status',new.status));
   end if;
   return new;
 end if;

 return new;
end
$function$;

drop trigger if exists trg_romano_audit_services on public.services;
create trigger trg_romano_audit_services
after insert or delete on public.services
for each row execute function private.romano_audit_service();
