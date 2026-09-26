do $$
declare v_company uuid; v_client uuid; v_property uuid;
begin
  select id into v_company from public.companies order by created_at limit 1;
  select id into v_client from public.clients where company_id=v_company order by created_at limit 1;
  select id into v_property from public.properties where company_id=v_company and client_id=v_client order by created_at limit 1;
  if v_client is not null and v_property is not null then
    update public.services set client_id=v_client, property_id=v_property, updated_at=now()
    where company_id=v_company and (client_id is null or property_id is null);
  end if;
end $$;

create or replace function private.validate_service_client_property()
returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if new.client_id is null or new.property_id is null then
    raise exception 'SERVICE_REQUIRES_CLIENT_AND_PROPERTY';
  end if;
  if not exists (
    select 1 from public.clients c
    join public.properties p on p.client_id=c.id and p.company_id=c.company_id
    where c.id=new.client_id and p.id=new.property_id and c.company_id=new.company_id
  ) then
    raise exception 'SERVICE_CLIENT_PROPERTY_MISMATCH';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_validate_service_client_property on public.services;
create trigger trg_validate_service_client_property
before insert or update of company_id,client_id,property_id
on public.services for each row execute function private.validate_service_client_property();

alter table public.services drop constraint if exists services_requires_client_property;
alter table public.services add constraint services_requires_client_property
check (client_id is not null and property_id is not null);