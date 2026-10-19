-- Repair client-to-profile association and support case-insensitive email matching.
-- Rita's login was incorrectly linked to ALEHOST; move the link to Rita's own client row.
begin;
update public.clients
set profile_id = null
where id = '9ea22348-9d61-47dc-89b0-c0dfbd5fc56a'
  and company_id = '11111111-1111-4111-8111-111111111111'
  and profile_id = 'cc47cc88-7da1-496b-a553-776af7fc3a98';

update public.clients
set profile_id = 'cc47cc88-7da1-496b-a553-776af7fc3a98',
    email = 'ritalimaromano2008@gmail.com'
where id = '614c030f-a54a-454d-a7ec-48472ca2037e'
  and company_id = '11111111-1111-4111-8111-111111111111';

create or replace function private.current_client_id()
returns uuid
language sql
stable
security definer
set search_path = public, private
as $$
  select c.id
  from public.clients c
  join public.profiles p on p.id = auth.uid()
  where c.company_id = p.company_id
    and p.active = true
    and p.role = 'client'
    and (
      c.profile_id = auth.uid()
      or (
        c.profile_id is null
        and c.email is not null
        and lower(trim(c.email)) = lower(trim(p.email))
      )
    )
  order by (c.profile_id = auth.uid()) desc
  limit 1
$$;
commit;
