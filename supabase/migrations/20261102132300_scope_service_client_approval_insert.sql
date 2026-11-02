drop policy if exists service_client_approvals_client_insert on public.service_client_approvals;
create policy service_client_approvals_client_insert
on public.service_client_approvals for insert to authenticated
with check (
 company_id = (select private.current_company_id())
 and client_id = (select private.current_client_id())
 and approved_by = (select auth.uid())
 and exists (
   select 1 from public.services s
   where s.id = service_client_approvals.service_id
     and s.company_id = service_client_approvals.company_id
     and s.client_id = service_client_approvals.client_id
     and exists (
       select 1 from public.service_media sm
       where sm.service_id = s.id
         and sm.company_id = s.company_id
         and sm.media_type in ('photo','image','video')
     )
 )
);