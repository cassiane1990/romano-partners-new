-- Employee-safe service detail: no agreed amount, pricing, tax or financial fields.
create or replace function public.employee_service_detail(p_service_id uuid)
returns table(
 id uuid, code text, company_id uuid, client_id uuid, property_id uuid,
 service_type text, typology text, status text, priority text,
 scheduled_at timestamptz, instructions text, assigned_employee_id uuid,
 assigned_supervisor_id uuid, accepted_at timestamptz, accepted_by uuid,
 started_at timestamptz, started_by uuid, finished_at timestamptz, finished_by uuid,
 created_at timestamptz, updated_at timestamptz, requested_items jsonb, additional_items jsonb
)
language sql stable security definer set search_path=''
as $function$
  select s.id,s.code,s.company_id,s.client_id,s.property_id,s.service_type,s.typology,s.status,s.priority,
         s.scheduled_at,s.instructions,s.assigned_employee_id,s.assigned_supervisor_id,s.accepted_at,s.accepted_by,
         s.started_at,s.started_by,s.finished_at,s.finished_by,s.created_at,s.updated_at,
         coalesce((select jsonb_agg(jsonb_build_object('name',x->>'name','quantity',coalesce((x->>'quantity')::numeric,1),'category',x->>'category','detail',x->>'detail')) from jsonb_array_elements(coalesce(s.requested_items,'[]'::jsonb)) x),'[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('name',x->>'name','quantity',coalesce((x->>'quantity')::numeric,1),'category',x->>'category','detail',x->>'detail')) from jsonb_array_elements(coalesce(s.additional_items,'[]'::jsonb)) x),'[]'::jsonb)
  from public.services s
  where s.id=p_service_id and s.company_id=private.current_company_id()
    and s.assigned_employee_id=(select auth.uid()) and private.current_role()='employee'
$function$;

revoke all on function public.employee_service_detail(uuid) from public,anon;
grant execute on function public.employee_service_detail(uuid) to authenticated;
