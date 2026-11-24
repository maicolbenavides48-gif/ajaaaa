/*
# Seed initial checkin_codes row

The checkin_codes table exists but has no rows. The pg_cron rotation
job was never set up. This migration inserts an initial code so the
TV screens show a PIN/QR immediately, and sets up the rotation job.
*/

INSERT INTO checkin_codes (id, pin, qr_code, expires_at, updated_at)
VALUES (
  1,
  '4821',
  'AJA7K9X2M4PQ',
  now() + interval '5 minutes',
  now()
)
ON CONFLICT (id) DO NOTHING;

-- Create rotation function (if not exists)
CREATE OR REPLACE FUNCTION public.rotate_checkin_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  new_pin text;
  new_qr text;
  chars text[] := ARRAY['0','1','2','3','4','5','6','7','8','9'];
BEGIN
  new_pin := '';
  FOR i IN 1..4 LOOP
    new_pin := new_pin || chars[1 + floor(random() * 10)::int];
  END LOOP;

  new_qr := '';
  FOR i IN 1..12 LOOP
    new_qr := new_qr || substr('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
                              1 + floor(random() * 36)::int, 1);
  END LOOP;

  INSERT INTO checkin_codes (id, pin, qr_code, expires_at, updated_at)
  VALUES (1, new_pin, new_qr, now() + interval '5 minutes', now())
  ON CONFLICT (id) DO UPDATE
  SET pin = new_pin,
      qr_code = new_qr,
      expires_at = now() + interval '5 minutes',
      updated_at = now();

  RETURN new_pin;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.rotate_checkin_code() FROM PUBLIC, anon, authenticated;

-- Schedule rotation every 5 minutes (if pg_cron available)
DO $do$
DECLARE
  existing_job_id bigint;
  cron_available boolean;
BEGIN
  SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') INTO cron_available;
  IF cron_available THEN
    SELECT jobid INTO existing_job_id FROM cron.job WHERE jobname = 'rotate_checkin_code';
    IF existing_job_id IS NOT NULL THEN
      PERFORM cron.unschedule(existing_job_id);
    END IF;
    PERFORM cron.schedule('rotate_checkin_code', '*/5 * * * *', 'SELECT public.rotate_checkin_code();');
  END IF;
END
$do$;

-- Also set up the close_unattended_queue function and cron job
CREATE OR REPLACE FUNCTION public.close_unattended_queue()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  updated_count integer;
BEGIN
  IF COALESCE(
    (SELECT test_mode FROM public.sede_config WHERE id = 1),
    false
  ) THEN
    RETURN 0;
  END IF;

  UPDATE public.appointments
  SET status = 'absent'
  WHERE status IN ('checked-in', 'rescheduled', 'called');

  GET DIAGNOSTICS updated_count = ROW_COUNT;

  UPDATE public.queue_state
  SET current_called_id = NULL,
      countdown_ends_at_ms = NULL,
      updated_at = now()
  WHERE id = 1;

  RETURN updated_count;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.close_unattended_queue() FROM PUBLIC, anon, authenticated;

DO $do$
DECLARE
  existing_job_id bigint;
  cron_available boolean;
BEGIN
  SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') INTO cron_available;
  IF cron_available THEN
    SELECT jobid INTO existing_job_id FROM cron.job WHERE jobname = 'close_unattended_queue';
    IF existing_job_id IS NOT NULL THEN
      PERFORM cron.unschedule(existing_job_id);
    END IF;
    PERFORM cron.schedule('close_unattended_queue', '0 22 * * *', 'SELECT public.close_unattended_queue();');
  END IF;
END
$do$;
