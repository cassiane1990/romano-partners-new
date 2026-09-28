create or replace function public.romano_guard_service_status_progression()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op='UPDATE' and new.status is distinct from old.status then
    if old.status in ('completed','approved','cancelled','rejected','returned') then
      raise exception 'SERVICIO_BLOQUEADO: El servicio ya está finalizado/verificado y no puede volver atrás';
    end if;

    if not (
      (old.status='requested' and new.status in ('scheduled','rejected','cancelled')) or
      (old.status='scheduled' and new.status in ('on_the_way','rejected','cancelled')) or
      (old.status='on_the_way' and new.status='in_progress') or
      (old.status='in_progress' and new.status in ('paused','supervision_pending','completed','cancelled')) or
      (old.status='paused' and new.status in ('in_progress','supervision_pending','completed','cancelled')) or
      (old.status='supervision_pending' and new.status in ('completed','supervised','cancelled')) or
      (old.status='supervised' and new.status='approved')
    ) then
      raise exception 'TRANSICION_ESTADO_NO_PERMITIDA: % → %', old.status, new.status;
    end if;
  end if;
  return new;
end;
$$;
