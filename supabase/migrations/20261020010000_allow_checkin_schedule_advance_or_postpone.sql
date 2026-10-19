-- Allow check-in time change requests to move the cleaning earlier OR later.
-- The requested time must differ from the current schedule and remain in the future.
CREATE OR REPLACE FUNCTION public.validate_romano_change_request_schedule()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  scheduled_time timestamptz;
BEGIN
  IF NEW.request_type <> 'checkin_advance' THEN
    RETURN NEW;
  END IF;

  SELECT s.scheduled_at INTO scheduled_time
  FROM public.services s
  WHERE s.id = NEW.service_id;

  IF scheduled_time IS NULL THEN
    RAISE EXCEPTION 'ROMANO_ADVANCE_SERVICE_TIME_MISSING: El servicio no tiene horario programado.';
  END IF;

  IF NEW.requested_for = scheduled_time THEN
    RAISE EXCEPTION 'ROMANO_ADVANCE_MUST_DIFFER: El nuevo horario debe ser diferente al horario actual del servicio.';
  END IF;

  IF NEW.requested_for <= now() THEN
    RAISE EXCEPTION 'ROMANO_ADVANCE_MUST_BE_FUTURE: El nuevo horario debe ser futuro.';
  END IF;

  RETURN NEW;
END;
$$;
