create table if not exists public.service_client_approvals (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  approved_by uuid not null references public.profiles(id),
  approved_at timestamptz not null default now(),
  unique(service_id)
);
alter table public.service_client_approvals enable row level security;
grant select, insert on public.service_client_approvals to authenticated;
create policy service_client_approvals_select_scoped
on public.service_client_approvals for select to authenticated
using (
 company_id = (select private.current_company_id())
 and (
   (select private.current_role()) in ('admin','supervisor')
   or client_id = (select private.current_client_id())
 )
);
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