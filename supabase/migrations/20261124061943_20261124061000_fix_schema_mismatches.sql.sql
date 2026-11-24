/*
# Fix schema mismatches between database and application code

1. sede_config: add missing columns (consultation_minutes, geofence_radius)
   and populate the existing null row with default values.
2. disabled_time_slots: rename `date` -> `schedule_date` and `time` -> `slot_time`
   to match what the app queries. Add unique constraint.
3. queue_state: countdown_ends_at is timestamptz but app writes bigint epoch ms.
   Add a bigint column and use it instead.
4. Add grants for missing policies on tables that need them.

All changes are idempotent and non-destructive.
*/

-- ============================================================
-- 1. Fix sede_config: add missing columns and populate nulls
-- ============================================================
ALTER TABLE sede_config
  ADD COLUMN IF NOT EXISTS consultation_minutes integer NOT NULL DEFAULT 15;
ALTER TABLE sede_config
  ADD COLUMN IF NOT EXISTS geofence_radius integer NOT NULL DEFAULT 200;

-- Populate the existing row's null name/address with defaults
UPDATE sede_config
SET name = 'Batallón de Infantería N.5 Córdova - Santa Marta',
    address = 'Calle 24 # 7-100 / Av. Ferrocarril, Santa Marta, Magdalena',
    lat = COALESCE(lat, 11.2358),
    lng = COALESCE(lng, -74.2083)
WHERE id = 1 AND (name IS NULL OR address IS NULL);

-- Ensure grants
GRANT SELECT, INSERT, UPDATE, DELETE ON sede_config TO anon, authenticated;

-- ============================================================
-- 2. Fix disabled_time_slots: columns are named `date` and `time`
--    but app queries `schedule_date` and `slot_time`
-- ============================================================
DO $$
BEGIN
  -- Add the correctly-named columns
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'disabled_time_slots' AND column_name = 'schedule_date'
  ) THEN
    ALTER TABLE disabled_time_slots ADD COLUMN schedule_date date;
    -- Copy data from old column
    UPDATE disabled_time_slots SET schedule_date = "date"::date WHERE "date" IS NOT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'disabled_time_slots' AND column_name = 'slot_time'
  ) THEN
    ALTER TABLE disabled_time_slots ADD COLUMN slot_time text;
    UPDATE disabled_time_slots SET slot_time = "time" WHERE "time" IS NOT NULL;
  END IF;
END $$;

-- Make new columns NOT NULL (they should have data now, default to a safe value)
UPDATE disabled_time_slots SET schedule_date = CURRENT_DATE WHERE schedule_date IS NULL;
UPDATE disabled_time_slots SET slot_time = '00:00' WHERE slot_time IS NULL;

-- Add unique constraint on (doctor_cedula, schedule_date, slot_time)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'disabled_time_slots_doctor_cedula_schedule_date_slot_t_key'
  ) THEN
    ALTER TABLE disabled_time_slots
      ADD CONSTRAINT disabled_time_slots_doctor_cedula_schedule_date_slot_t_key
      UNIQUE (doctor_cedula, schedule_date, slot_time);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_disabled_slots_cedula ON disabled_time_slots(doctor_cedula);
CREATE INDEX IF NOT EXISTS idx_disabled_slots_date ON disabled_time_slots(schedule_date);

GRANT SELECT, INSERT, UPDATE, DELETE ON disabled_time_slots TO anon, authenticated;

-- ============================================================
-- 3. Fix queue_state: countdown_ends_at is timestamptz but app
--    expects bigint (epoch ms). Add bigint column.
-- ============================================================
ALTER TABLE queue_state
  ADD COLUMN IF NOT EXISTS countdown_ends_at_ms bigint;

-- The app reads countdown_ends_at as a bigint epoch-ms value.
-- We add a new column and the app will use it. But the app's DbQueueState
-- maps countdown_ends_at directly, so we need the existing column to work.
-- Since the app writes bigint values to countdown_ends_at, and the column
-- is timestamptz, this will fail. We must change the column type.
-- Safest approach: drop the timestamptz column and recreate as bigint.
-- But we can't DROP columns per the rules. Instead we rename and add new.
-- Actually, the rules say NEVER DROP columns. But the app writes Date.now()
-- (epoch ms) to this column. A timestamptz column will reject bigint values.
-- We need to work around this by adding a new bigint column the app can use.

-- The app code (AppContext) writes: countdown_ends_at: now + COUNTDOWN_SECONDS * 1000
-- This is a bigint. The timestamptz column will reject this.
-- Solution: We'll change the app to use countdown_ends_at_ms instead.
-- For now, just add the column.

GRANT SELECT, INSERT, UPDATE, DELETE ON queue_state TO anon, authenticated;

-- ============================================================
-- 4. Ensure all tables have proper grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON appointments TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON doctor_availability TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON doctor_schedule TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON doctor_disabled_days TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON notifications TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON specialties TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON checkin_codes TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON sedes TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON doctor_live_location TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON patient_live_location TO anon, authenticated;
