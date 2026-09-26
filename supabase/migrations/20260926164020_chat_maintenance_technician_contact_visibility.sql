-- ROMANO: allow maintenance technicians to see their permitted chat contacts.
-- Chat rules remain role-specific:
--   admin -> supervisor, cleaning staff, maintenance technicians, clients
--   supervisor -> admin, cleaning staff, maintenance technicians
--   employee -> admin, supervisor
--   maintenance_technician -> admin, supervisor
--   client -> admin, supervisor
--
-- The existing chat RPC already enforces this matrix. This policy fixes the
-- directory visibility gap for maintenance_technician users.

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
