-- Migration: 20261102000003_prune_old_raw_telemetry.sql
-- Goal: Complete compaction of legacy raw telemetry into lean tables,
--       and establish automated rolling compaction to prevent database bloat & egress.

BEGIN;

-- 1. Backfill any missing sleep sessions from raw telemetry stages
INSERT INTO public.health_sleep_sessions (
    id,
    user_id,
    local_date,
    session_type,
    source_device_key,
    host_device_name,
    start_time,
    end_time,
    duration_seconds,
    time_in_bed_seconds,
    efficiency_percent,
    sleep_score,
    deep_seconds,
    rem_seconds,
    light_seconds,
    awake_seconds,
    latency_seconds,
    quality_rating,
    stages,
    source_priority,
    is_user_selected,
    ingested_at
)
SELECT 
    'sleep_telem_' || ht.user_id || '_' || ht.local_date || '_' || md5(COALESCE(ht.source_device, 'device')) AS id,
    ht.user_id,
    ht.local_date,
    'primary_sleep' AS session_type,
    COALESCE(ht.source_device, 'Android Wearable') AS source_device_key,
    split_part(COALESCE(ht.source_device, 'Trapper'), ' - ', 1) AS host_device_name,
    min(ht.start_time) AS start_time,
    max(ht.end_time) AS end_time,
    GREATEST(0, (COALESCE(SUM(ht.value) FILTER (WHERE ht.type IN ('sleep_stage_deep', 'sleep_stage_rem', 'sleep_stage_light')), EXTRACT(EPOCH FROM (max(ht.end_time) - min(ht.start_time)))))::int) AS duration_seconds,
    GREATEST(0, EXTRACT(EPOCH FROM (max(ht.end_time) - min(ht.start_time)))::int) AS time_in_bed_seconds,
    ROUND(
        (CASE 
            WHEN EXTRACT(EPOCH FROM (max(ht.end_time) - min(ht.start_time))) > 0 
            THEN (COALESCE(SUM(ht.value) FILTER (WHERE ht.type IN ('sleep_stage_deep', 'sleep_stage_rem', 'sleep_stage_light')), 0) * 100.0) / EXTRACT(EPOCH FROM (max(ht.end_time) - min(ht.start_time)))
            ELSE 85.0 
        END)::numeric, 1
    )::double precision AS efficiency_percent,
    80 AS sleep_score,
    COALESCE(SUM(ht.value) FILTER (WHERE ht.type = 'sleep_stage_deep'), 0)::int AS deep_seconds,
    COALESCE(SUM(ht.value) FILTER (WHERE ht.type = 'sleep_stage_rem'), 0)::int AS rem_seconds,
    COALESCE(SUM(ht.value) FILTER (WHERE ht.type = 'sleep_stage_light'), 0)::int AS light_seconds,
    COALESCE(SUM(ht.value) FILTER (WHERE ht.type = 'sleep_stage_awake'), 0)::int AS awake_seconds,
    0 AS latency_seconds,
    'good' AS quality_rating,
    '[]'::jsonb AS stages,
    CASE WHEN ht.source_device ILIKE '%Pixel Watch%' THEN 3 ELSE 10 END AS source_priority,
    false AS is_user_selected,
    NOW() AS ingested_at
FROM public.health_telemetry ht
WHERE (ht.type = 'sleep' OR ht.type LIKE 'sleep%')
  AND NOT EXISTS (
    SELECT 1 FROM public.health_sleep_sessions ss
    WHERE ss.user_id = ht.user_id AND ss.local_date = ht.local_date
  )
GROUP BY ht.user_id, ht.local_date, ht.source_device
ON CONFLICT (id) DO NOTHING;

-- 2. Backfill any missing 5-minute intraday heart rate buckets from raw telemetry
INSERT INTO public.health_intraday_heart_rate (
    id,
    user_id,
    local_date,
    bucket_minute,
    bpm_avg,
    bpm_min,
    bpm_max,
    sample_count,
    source_device_key
)
SELECT 
    'hr_' || ht.user_id || '_' || ht.local_date || '_' || md5(COALESCE(ht.source_device, 'wearable')) || '_' || (EXTRACT(HOUR FROM ht.start_time) * 60 + floor(EXTRACT(MINUTE FROM ht.start_time) / 5) * 5)::int AS id,
    ht.user_id,
    ht.local_date,
    (EXTRACT(HOUR FROM ht.start_time) * 60 + floor(EXTRACT(MINUTE FROM ht.start_time) / 5) * 5)::int AS bucket_minute,
    ROUND(AVG(ht.value)::numeric, 1)::double precision AS bpm_avg,
    MIN(ht.value)::int AS bpm_min,
    MAX(ht.value)::int AS bpm_max,
    COUNT(*)::int AS sample_count,
    COALESCE(ht.source_device, 'wearable') AS source_device_key
FROM public.health_telemetry ht
WHERE ht.type = 'heart_rate' AND ht.value > 0
GROUP BY ht.user_id, ht.local_date, ht.source_device, (EXTRACT(HOUR FROM ht.start_time) * 60 + floor(EXTRACT(MINUTE FROM ht.start_time) / 5) * 5)::int
ON CONFLICT (user_id, local_date, source_device_key, bucket_minute) DO NOTHING;

-- 3. Stored Procedure for Safe Raw Telemetry Pruning
CREATE OR REPLACE FUNCTION public.prune_stale_health_telemetry(retention_days int DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count bigint := 0;
    cutoff_date date;
BEGIN
    cutoff_date := CURRENT_DATE - (retention_days || ' days')::interval;

    -- Only delete from health_telemetry where local_date < cutoff_date
    -- AND an aggregate record exists in health_daily_vitals, health_sleep_sessions, or health_daily_summary
    WITH deleted AS (
        DELETE FROM public.health_telemetry ht
        WHERE ht.local_date < cutoff_date
          AND (
            EXISTS (SELECT 1 FROM public.health_daily_vitals dv WHERE dv.user_id = ht.user_id AND dv.local_date = ht.local_date)
            OR EXISTS (SELECT 1 FROM public.health_sleep_sessions ss WHERE ss.user_id = ht.user_id AND ss.local_date = ht.local_date)
            OR EXISTS (SELECT 1 FROM public.health_daily_summary ds WHERE ds.user_id = ht.user_id AND ds.local_date = ht.local_date)
          )
        RETURNING id
    )
    SELECT count(*) INTO deleted_count FROM deleted;

    RETURN jsonb_build_object(
        'status', 'success',
        'cutoff_date', cutoff_date,
        'deleted_rows', deleted_count
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.prune_stale_health_telemetry(int) TO authenticated, service_role;

-- 4. Update the automated daily retention job function
CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Prune raw telemetry older than 7 days that has been compacted into lean tables
    PERFORM public.prune_stale_health_telemetry(7);

    -- Nullify bulky summary JSON for historical days older than 90 days to conserve space
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;

-- 5. Execute initial compaction pruning older than 7 days
SELECT public.prune_stale_health_telemetry(7);

COMMIT;
