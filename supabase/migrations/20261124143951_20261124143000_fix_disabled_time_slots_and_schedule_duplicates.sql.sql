/*
# Fix disabled_time_slots: make date/time nullable, add unique constraint on doctor_schedule
#
# Root causes fixed:
# 1. disabled_time_slots has NOT NULL "date" and "time" columns that the app
#    never populates (it uses schedule_date/slot_time instead). Every INSERT
#    failed with a NOT NULL violation, silently swallowed by the app.
# 2. doctor_schedule has no unique constraint on (doctor_cedula, schedule_date),
#    so the check-then-insert race creates duplicate rows.
# 3. Clean up existing duplicate doctor_schedule rows.
*/

-- 1. Make date/time nullable on disabled_time_slots (they're legacy columns)
ALTER TABLE public.disabled_time_slots ALTER COLUMN date DROP NOT NULL;
ALTER TABLE public.disabled_time_slots ALTER COLUMN time DROP NOT NULL;

-- 2. Add unique constraint on doctor_schedule to prevent duplicates
-- First remove duplicates: keep the row with the smallest id per (doctor_cedula, schedule_date)
DELETE FROM public.doctor_schedule
WHERE id NOT IN (
  SELECT DISTINCT ON (doctor_cedula, schedule_date) id
  FROM public.doctor_schedule
  ORDER BY doctor_cedula, schedule_date, created_at ASC
);

-- Now add the unique constraint
ALTER TABLE public.doctor_schedule
  ADD CONSTRAINT doctor_schedule_cedula_date_unique
  UNIQUE (doctor_cedula, schedule_date);

-- 3. Backfill date/time from schedule_date/slot_time for any existing rows
UPDATE public.disabled_time_slots
SET date = schedule_date::text, time = slot_time
WHERE date IS NULL AND schedule_date IS NOT NULL;
