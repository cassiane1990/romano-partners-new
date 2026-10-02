-- Allow maintenance technicians to register their own work-journal events.
-- This mirrors the production RLS fix applied to work_journal_events.

drop policy if exists "work_journal_events_insert" on public.work_journal_events;

create policy "work_journal_events_insert"
on public.work_journal_events
for insert
to authenticated
with check (
  company_id = private.current_company_id()
  and profile_id = auth.uid()
  and private."current_role"() = any (array[
    'admin'::text,
    'supervisor'::text,
    'employee'::text,
    'maintenance_technician'::text
  ])
  and (
    service_id is null
    or private."current_role"() = any (array['admin'::text,'supervisor'::text])
    or exists (
      select 1
      from public.services s
      where s.id = work_journal_events.service_id
        and s.company_id = private.current_company_id()
        and (
          s.assigned_employee_id = auth.uid()
          or s.assigned_supervisor_id = auth.uid()
          or (
            private."current_role"() = 'maintenance_technician'::text
            and s.assigned_employee_id = auth.uid()
          )
        )
    )
  )
);
