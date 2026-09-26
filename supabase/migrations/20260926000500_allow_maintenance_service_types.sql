alter table public.services drop constraint if exists services_typology_check;

alter table public.services add constraint services_typology_check
check (
  typology ~ '^T[1-5](-[1-4]B)?$'
  or typology = any(array[
    'none','preventive','corrective','silicone','painting',
    'assembly','installation','hydraulic','electric','other'
  ])
);