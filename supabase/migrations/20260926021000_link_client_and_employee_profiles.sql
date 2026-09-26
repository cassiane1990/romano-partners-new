update public.clients c
set profile_id = p.id
from public.profiles p
where c.profile_id is null
  and p.role='client' and p.active=true and p.company_id=c.company_id
  and (select count(*) from public.clients c2 where c2.company_id=c.company_id)=1;

update public.employee_profiles ep
set profile_id=p.id, updated_at=now()
from public.profiles p
where ep.profile_id is null
  and p.company_id=ep.company_id and p.active=true
  and (
    lower(coalesce(ep.email,''))=lower(coalesce(p.email,''))
    or (ep.full_name ilike '%'||split_part(coalesce(p.full_name,''),' ',1)||'%' and p.role='supervisor' and ep.function_title ilike '%supervisor%')
  );