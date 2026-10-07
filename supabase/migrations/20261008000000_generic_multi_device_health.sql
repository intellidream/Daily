-- Generic Multi-Device Health Architecture & Telemetry Sanitization
-- Migration: 20261008000000_generic_multi_device_health.sql
-- 1. Adds compound source device columns (host_device_name, sensor_source_name, source_device_key, source_color).
-- 2. Deduplicates existing raw telemetry records.
-- 3. Enforces strict unique constraints preventing duplicate insertions.
-- 4. Prunes historical telemetry to keep only current active date in health_telemetry.

BEGIN;

-- 1. Add Compound Source Columns to health_telemetry
ALTER TABLE public.health_telemetry
    ADD COLUMN IF NOT EXISTS host_device_name text,
    ADD COLUMN IF NOT EXISTS sensor_source_name text,
    ADD COLUMN IF NOT EXISTS source_device_key text,
    ADD COLUMN IF NOT EXISTS source_color text;

-- 2. Backfill source_device_key and source_color for existing records where missing
UPDATE public.health_telemetry
SET 
    source_device_key = COALESCE(source_device_key, source_device, 'Unknown Device'),
    sensor_source_name = COALESCE(sensor_source_name, source_device, 'Unknown Sensor'),
    source_color = COALESCE(source_color, '#3897F0')
WHERE source_device_key IS NULL;

-- 3. Deduplicate health_telemetry records by (user_id, external_id)
DELETE FROM public.health_telemetry a
USING public.health_telemetry b
WHERE a.ctid < b.ctid
  AND a.user_id = b.user_id
  AND a.external_id IS NOT NULL
  AND a.external_id = b.external_id;

-- 4. Deduplicate health_telemetry records by (user_id, type, source_device, start_time) where external_id is null
DELETE FROM public.health_telemetry a
USING public.health_telemetry b
WHERE a.ctid < b.ctid
  AND a.user_id = b.user_id
  AND a.type = b.type
  AND COALESCE(a.source_device, '') = COALESCE(b.source_device, '')
  AND a.start_time = b.start_time
  AND (a.external_id IS NULL OR b.external_id IS NULL);

-- 5. Add partial unique index on (user_id, external_id) to guarantee idempotency
DROP INDEX IF EXISTS idx_health_telemetry_external_id;
CREATE UNIQUE INDEX IF NOT EXISTS uq_health_telemetry_user_external 
ON public.health_telemetry (user_id, external_id) 
WHERE external_id IS NOT NULL;

-- 6. Recalibrate local_date on existing rows based on start_time + tz_offset_min
UPDATE public.health_telemetry
SET local_date = (start_time + (COALESCE(tz_offset_min, 180) || ' minutes')::interval)::date
WHERE local_date IS NULL 
   OR local_date != (start_time + (COALESCE(tz_offset_min, 180) || ' minutes')::interval)::date;

-- 7. Prune historical telemetry older than yesterday to enforce lean current-day retention
-- Historical canonical summaries are permanently preserved in health_daily_summary
DELETE FROM public.health_telemetry
WHERE local_date < CURRENT_DATE - INTERVAL '1 day';

-- 8. Create or Replace Automated Purge Function
CREATE OR REPLACE FUNCTION public.purge_expired_health_telemetry()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM public.health_telemetry
    WHERE local_date < CURRENT_DATE - INTERVAL '1 day';
END;
$$;

-- 9. Performance index for active current day queries
CREATE INDEX IF NOT EXISTS idx_health_telemetry_current_active
ON public.health_telemetry (user_id, local_date, type, start_time DESC);

COMMIT;
