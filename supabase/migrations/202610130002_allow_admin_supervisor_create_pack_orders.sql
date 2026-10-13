create or replace function public.romano_create_pack_order(
  p_property_id uuid,
  p_items jsonb,
  p_requested_date date,
  p_customer_notes text default ''
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_property public.properties%rowtype;
  v_total numeric(10,2);
  v_id uuid;
  v_ind integer;
  v_double integer;
  v_single integer;
  v_amenities integer;
begin
  if auth.uid() is null then raise exception 'Autenticación requerida.'; end if;
  select * into v_profile from public.profiles where id = auth.uid() and active = true;
  if not found or v_profile.role not in ('client','admin','supervisor') then
    raise exception 'Este perfil no puede crear pedidos.';
  end if;
  if p_requested_date is null or p_requested_date < (now() at time zone 'Europe/Madrid')::date then
    raise exception 'Seleccione una fecha válida.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'object' then raise exception 'Productos no válidos.'; end if;
  v_ind := coalesce((p_items->>'individual')::integer,0);
  v_double := coalesce((p_items->>'double')::integer,0);
  v_single := coalesce((p_items->>'single_beds')::integer,0);
  v_amenities := coalesce((p_items->>'amenities')::integer,0);
  if v_ind not between 0 and 500 or v_double not between 0 and 500 or v_single not between 0 and 500 or v_amenities not between 0 and 1000
    or v_ind+v_double+v_single+v_amenities <= 0 then raise exception 'Revise las cantidades solicitadas.'; end if;

  if v_profile.role = 'client' then
    select pr.* into v_property
    from public.properties pr
    join public.clients c on c.id = pr.client_id
    where pr.id = p_property_id and c.profile_id = auth.uid() and c.company_id = v_profile.company_id;
  else
    select pr.* into v_property
    from public.properties pr
    where pr.id = p_property_id and pr.company_id = v_profile.company_id;
  end if;
  if not found then raise exception 'No tiene acceso a este apartamento.'; end if;

  v_total := round(v_ind*18.84 + v_double*20.41 + v_single*13.25 + v_amenities*1.50,2);
  insert into public.romano_pack_orders(company_id,client_profile_id,property_id,items,estimated_total,requested_date,customer_notes)
  values(v_profile.company_id,auth.uid(),p_property_id,
    jsonb_build_object('individual',v_ind,'double',v_double,'single_beds',v_single,'amenities',v_amenities),
    v_total,p_requested_date,left(coalesce(p_customer_notes,''),1000))
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.romano_create_pack_order(uuid,jsonb,date,text) to authenticated;
