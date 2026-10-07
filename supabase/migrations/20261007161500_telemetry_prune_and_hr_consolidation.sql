-- 1. Delete all records strictly older than the 48-hour rolling window
DELETE FROM public.health_telemetry
WHERE start_time < NOW() - INTERVAL '48 hours'
   OR COALESCE(local_date, start_time::date) < (CURRENT_DATE - INTERVAL '1 day')::date;

-- 2. Deduplicate non-heart_rate records (steps, sleep stages, hrv, rhr, etc.)
DELETE FROM public.health_telemetry a
USING public.health_telemetry b
WHERE a.id > b.id
  AND a.type != 'heart_rate'
  AND a.type = b.type
  AND a.user_id = b.user_id
  AND a.start_time = b.start_time
  AND COALESCE(a.source_device, '') = COALESCE(b.source_device, '');

-- 3. Consolidate heart rate records in the last 48 hours into 1 canonical 5-minute bucketed record
-- Create temporary table with canonical 5-minute buckets
CREATE TEMP TABLE temp_canonical_hr AS
SELECT 
    gen_random_uuid() as id,
    user_id,
    'heart_rate' as type,
    ROUND(AVG(value)::numeric, 1) as value,
    'bpm' as unit,
    date_bin(INTERVAL '5 minutes', start_time, TIMESTAMP '2000-01-01') as start_time,
    date_bin(INTERVAL '5 minutes', start_time, TIMESTAMP '2000-01-01') + INTERVAL '5 minutes' as end_time,
    MODE() WITHIN GROUP (ORDER BY source_device) as source_device,
    NOW() as created_at,
    'hr_5m_' || to_char(date_bin(INTERVAL '5 minutes', start_time, TIMESTAMP '2000-01-01'), 'YYYYMMDD_HH24MI') as external_id,
    NULL::uuid as source_id,
    'interval_avg' as semantics,
    COALESCE(MODE() WITHIN GROUP (ORDER BY tz_offset_min), 0) as tz_offset_min,
    (date_bin(INTERVAL '5 minutes', start_time, TIMESTAMP '2000-01-01'))::date as local_date
FROM public.health_telemetry
WHERE type = 'heart_rate'
GROUP BY user_id, date_bin(INTERVAL '5 minutes', start_time, TIMESTAMP '2000-01-01');

-- Delete all raw/overlapping heart rate records
DELETE FROM public.health_telemetry
WHERE type = 'heart_rate';

-- Re-insert canonical 5-minute bucketed heart rate records
INSERT INTO public.health_telemetry (
    id, user_id, type, value, unit, start_time, end_time, 
    source_device, created_at, external_id, source_id, semantics, tz_offset_min, local_date
)
SELECT 
    id, user_id, type, value, unit, start_time, end_time, 
    source_device, created_at, external_id, source_id, semantics, tz_offset_min, local_date
FROM temp_canonical_hr;

DROP TABLE temp_canonical_hr;

-- 4. Update apply_health_data_retention to strictly enforce 48-hour rolling retention
CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Tier 1 -> Tier 2: Delete raw telemetry strictly older than 48 hours (anything before yesterday)
    DELETE FROM public.health_telemetry
    WHERE start_time < NOW() - INTERVAL '48 hours'
       OR COALESCE(local_date, start_time::date) < (CURRENT_DATE - INTERVAL '1 day')::date;

    -- Tier 3: Nullify heavy JSON summary for historical data (> 90 days)
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;
