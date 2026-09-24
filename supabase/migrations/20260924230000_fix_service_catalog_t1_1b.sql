-- ROMANO PROPERTY CARE · restore the T1-1B cleaning price code used by the service form
insert into public.service_catalog (company_id, category, code, name, description, unit, price, tax_included, active)
select c.id,
       'cleaning',
       'T1-1B',
       'T1 · 1 dormitorio + 1 baño',
       'Limpieza Airbnb / Alojamiento Local · T1 · 1 baño',
       'unidad',
       30,
       false,
       true
from public.companies c
where c.id = '11111111-1111-4111-8111-111111111111'
  and not exists (
    select 1
    from public.service_catalog sc
    where sc.company_id = c.id
      and sc.category = 'cleaning'
      and sc.code = 'T1-1B'
  );
