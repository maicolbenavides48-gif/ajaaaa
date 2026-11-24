/*
# Prevent patient schedule conflicts (same date + overlapping time)

## Purpose
A patient can have multiple appointments on the same day at different times,
but must NOT be booked for two appointments at the same time (or overlapping)
with any doctor or role. This migration adds a database-level guard that
prevents conflicting inserts/updates even if the application validation is
bypassed.

## Changes
1. Creates a partial unique index `no_patient_time_conflict` on
   `appointments(patient_cedula, scheduled_date, scheduled_time)` covering
   only active statuses (scheduled, checked-in, rescheduled, called,
   in-attendance). This prevents two active appointments for the same patient
   at the same date+time.

## Important notes
- The index is partial: cancelled/attended/absent appointments are excluded,
  so a patient can re-book a slot after a previous appointment was cancelled.
- Since scheduled_time is stored at 30-minute intervals and consultations
  last `consultation_minutes` (default 15), the exact-time match is the
  primary guard. The application also checks overlap in code for cases where
  consultation duration differs from the slot interval.
- Idempotent: uses IF NOT EXISTS.
*/

CREATE UNIQUE INDEX IF NOT EXISTS no_patient_time_conflict
ON appointments (patient_cedula, scheduled_date, scheduled_time)
WHERE status IN ('scheduled', 'checked-in', 'rescheduled', 'called', 'in-attendance')
  AND scheduled_date IS NOT NULL
  AND scheduled_time IS NOT NULL
  AND scheduled_time <> '--:--';
