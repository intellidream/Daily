-- Backfill script: 20261102000001_backfill_lean_health.sql
BEGIN;

-- 1. Populate health_sources with known ecosystem hardware
INSERT INTO public.health_sources (id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color)
SELECT 
    'schmitz_oura', 
    '32b8b75f-a0b0-4686-8519-f790f0b3822a'::uuid, 
    'iOS', 
    'smart_ring', 
    'Oura', 
    'Oura Ring Gen 3', 
    'Oura Ring', 
    'Schmitz', 
    1, -- Top priority for sleep
    10, 
    '#5856D6'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.health_sources (id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color)
SELECT 
    'schmitz_ultra2', 
    '32b8b75f-a0b0-4686-8519-f790f0b3822a'::uuid, 
    'watchOS', 
    'smartwatch', 
    'Apple', 
    'Apple Watch Ultra 2', 
    'Apple Watch Ultra 2', 
    'Schmitz', 
    2, 
    1, -- Top priority for activity
    '#FF9500'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.health_sources (id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color)
SELECT 
    'trapper_pw5', 
    '32b8b75f-a0b0-4686-8519-f790f0b3822a'::uuid, 
    'WearOS', 
    'smartwatch', 
    'Google', 
    'Pixel Watch 5', 
    'Pixel Watch 5', 
    'Trapper', 
    3, 
    2, 
    '#FBBC05'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.health_sources (id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color)
SELECT 
    'schmitz_iphone', 
    '32b8b75f-a0b0-4686-8519-f790f0b3822a'::uuid, 
    'iOS', 
    'phone', 
    'Apple', 
    'iPhone 16 Pro Max', 
    'Schmitz (iPhone)', 
    'Schmitz', 
    10, 
    3, 
    '#007AFF'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.health_sources (id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color)
SELECT 
    'trapper_pixel9', 
    '32b8b75f-a0b0-4686-8519-f790f0b3822a'::uuid, 
    'Android', 
    'phone', 
    'Google', 
    'Pixel 9 Pro', 
    'Trapper (Pixel 9 Pro)', 
    'Trapper', 
    10, 
    4, 
    '#34A853'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.health_sources (id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color)
SELECT 
    'radar_fold8', 
    '32b8b75f-a0b0-4686-8519-f790f0b3822a'::uuid, 
    'Android', 
    'phone', 
    'Samsung', 
    'Galaxy Z Fold 8', 
    'Radar (Galaxy Z Fold 8)', 
    'Radar', 
    10, 
    5, 
    '#9C27B0'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.health_sources (id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color)
SELECT 
    'macos_desktop', 
    '32b8b75f-a0b0-4686-8519-f790f0b3822a'::uuid, 
    'macOS', 
    'desktop', 
    'Apple', 
    'MacBook Pro', 
    'Mac (Daily Desktop)', 
    'Mac', 
    20, 
    20, 
    '#5AC8FA'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.health_sources (id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color)
SELECT 
    'windows_desktop', 
    '32b8b75f-a0b0-4686-8519-f790f0b3822a'::uuid, 
    'Windows', 
    'desktop', 
    'Microsoft', 
    'Windows 11 PC', 
    'Windows 11 (Daily WinUI)', 
    'Windows', 
    20, 
    20, 
    '#0078D4'
ON CONFLICT (id) DO NOTHING;

-- 2. Backfill health_sleep_sessions from health_daily_summary
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
    quality_rating,
    stages,
    is_user_selected
)
SELECT 
    'sleep_' || s.user_id || '_' || s.local_date || '_' || COALESCE(s.summary->'sleep'->'primary_session'->>'source_device', 'Unknown') as id,
    s.user_id,
    s.local_date,
    'primary_sleep' as session_type,
    COALESCE(s.summary->'sleep'->'primary_session'->>'source_device', 'Unknown') as source_device_key,
    CASE 
        WHEN s.summary->'sleep'->'primary_session'->>'source_device' ILIKE 'iPhone%' THEN 'Schmitz'
        WHEN s.summary->'sleep'->'primary_session'->>'source_device' ILIKE 'Trapper%' THEN 'Trapper'
        WHEN s.summary->'sleep'->'primary_session'->>'source_device' ILIKE 'Radar%' THEN 'Radar'
        ELSE 'Schmitz'
    END as host_device_name,
    (s.summary->'sleep'->'primary_session'->>'start_time')::timestamptz as start_time,
    (s.summary->'sleep'->'primary_session'->>'end_time')::timestamptz as end_time,
    COALESCE((s.summary->'sleep'->'primary_session'->>'duration_seconds')::int, s.sleep_asleep_s, 0) as duration_seconds,
    COALESCE((s.summary->'sleep'->'primary_session'->>'asleep_seconds')::int + (s.summary->'sleep'->'primary_session'->>'awake_seconds')::int, s.sleep_asleep_s, 0) as time_in_bed_seconds,
    COALESCE((s.summary->'sleep'->'primary_session'->>'efficiency_percent')::double precision, 90.0) as efficiency_percent,
    COALESCE((s.summary->'sleep'->'primary_session'->>'sleep_score')::int, s.sleep_score) as sleep_score,
    COALESCE((s.summary->'sleep'->'primary_session'->>'deep_seconds')::int, 0) as deep_seconds,
    COALESCE((s.summary->'sleep'->'primary_session'->>'rem_seconds')::int, 0) as rem_seconds,
    COALESCE((s.summary->'sleep'->'primary_session'->>'light_seconds')::int, 0) as light_seconds,
    COALESCE((s.summary->'sleep'->'primary_session'->>'awake_seconds')::int, 0) as awake_seconds,
    COALESCE(s.summary->'sleep'->'primary_session'->>'quality_rating', 'Good') as quality_rating,
    COALESCE(s.summary->'sleep'->'primary_session'->'stages', '[]'::jsonb) as stages,
    true as is_user_selected
FROM public.health_daily_summary s
WHERE s.summary->'sleep'->'primary_session' IS NOT NULL
  AND s.summary->'sleep'->'primary_session'->>'start_time' IS NOT NULL
ON CONFLICT (user_id, local_date, session_type, source_device_key) 
DO UPDATE SET
    sleep_score = EXCLUDED.sleep_score,
    duration_seconds = EXCLUDED.duration_seconds,
    efficiency_percent = EXCLUDED.efficiency_percent,
    stages = EXCLUDED.stages,
    deep_seconds = EXCLUDED.deep_seconds,
    rem_seconds = EXCLUDED.rem_seconds,
    light_seconds = EXCLUDED.light_seconds,
    awake_seconds = EXCLUDED.awake_seconds;

-- 3. Backfill health_daily_vitals from health_daily_summary
INSERT INTO public.health_daily_vitals (
    id,
    user_id,
    local_date,
    source_device_key,
    host_device_name,
    steps,
    active_kcal,
    resting_heart_rate,
    spo2,
    hrv_sdnn_nightly,
    hrv_rmssd_nightly,
    weight_kg,
    hourly_steps
)
SELECT 
    'vitals_' || s.user_id || '_' || s.local_date || '_' || COALESCE(s.summary->'activity'->>'source_device', 'Canonical Unified') as id,
    s.user_id,
    s.local_date,
    COALESCE(s.summary->'activity'->>'source_device', 'Canonical Unified') as source_device_key,
    CASE 
        WHEN s.summary->'activity'->>'source_device' ILIKE 'iPhone%' THEN 'Schmitz'
        WHEN s.summary->'activity'->>'source_device' ILIKE 'Trapper%' THEN 'Trapper'
        WHEN s.summary->'activity'->>'source_device' ILIKE 'Radar%' THEN 'Radar'
        ELSE 'Schmitz'
    END as host_device_name,
    COALESCE(s.steps, (s.summary->'activity'->>'total_steps')::int, 0),
    COALESCE(s.active_kcal, (s.summary->'activity'->>'active_calories')::double precision, 0.0),
    s.rhr,
    s.spo2,
    s.hrv_sdnn,
    s.hrv_rmssd,
    s.weight,
    COALESCE(s.summary->'activity'->'hourly_steps', '[]'::jsonb)
FROM public.health_daily_summary s
ON CONFLICT (user_id, local_date, source_device_key) 
DO UPDATE SET
    steps = EXCLUDED.steps,
    active_kcal = EXCLUDED.active_kcal,
    resting_heart_rate = EXCLUDED.resting_heart_rate,
    spo2 = EXCLUDED.spo2,
    hrv_sdnn_nightly = EXCLUDED.hrv_sdnn_nightly,
    hourly_steps = EXCLUDED.hourly_steps;

-- 4. Backfill health_intraday_heart_rate (5-minute buckets) for recent days from health_telemetry
WITH bucketed AS (
    SELECT 
        user_id,
        local_date,
        COALESCE(source_device, 'Unknown') as source_device_key,
        (EXTRACT(HOUR FROM start_time AT TIME ZONE 'UTC') * 60 + (EXTRACT(MINUTE FROM start_time AT TIME ZONE 'UTC')::int / 5) * 5)::smallint as bucket_minute,
        ROUND(AVG(value))::smallint as bpm_avg,
        ROUND(MIN(value))::smallint as bpm_min,
        ROUND(MAX(value))::smallint as bpm_max,
        COUNT(*)::smallint as sample_count
    FROM public.health_telemetry
    WHERE type = 'heart_rate'
      AND local_date >= CURRENT_DATE - INTERVAL '3 days'
      AND value > 30 AND value < 240
    GROUP BY 
        user_id, 
        local_date, 
        COALESCE(source_device, 'Unknown'), 
        (EXTRACT(HOUR FROM start_time AT TIME ZONE 'UTC') * 60 + (EXTRACT(MINUTE FROM start_time AT TIME ZONE 'UTC')::int / 5) * 5)
)
INSERT INTO public.health_intraday_heart_rate (
    id,
    user_id,
    local_date,
    source_device_key,
    bucket_minute,
    bpm_avg,
    bpm_min,
    bpm_max,
    sample_count
)
SELECT 
    'hr_' || user_id || '_' || local_date || '_' || source_device_key || '_' || bucket_minute::text,
    user_id,
    local_date,
    source_device_key,
    bucket_minute,
    bpm_avg,
    bpm_min,
    bpm_max,
    sample_count
FROM bucketed
ON CONFLICT (user_id, local_date, source_device_key, bucket_minute) 
DO UPDATE SET
    bpm_avg = EXCLUDED.bpm_avg,
    bpm_min = EXCLUDED.bpm_min,
    bpm_max = EXCLUDED.bpm_max,
    sample_count = EXCLUDED.sample_count;

COMMIT;
