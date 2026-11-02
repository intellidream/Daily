-- Migration: 20261102000005_canonical_unification_and_clean_lean.sql
-- Purpose:
--   1. Establish a single deterministic canonical hardware device mapping in PostgreSQL.
--   2. Rescue any remaining sleep sessions, daily vitals, and 5m HR buckets from health_telemetry.
--   3. Deduplicate & unify all historical rows across health_sleep_sessions, health_daily_vitals,
--      health_intraday_heart_rate, and health_sources (removing Host-prefixed duplicates, serial hashes,
--      Google Fit double-echoes, and desktop/virtual entries).
--   4. Add lightweight BEFORE INSERT/UPDATE triggers on lean tables for canonical naming and monotonic
--      multi-phone merge safety (preventing partial deltas or secondary phone syncs from regressing totals).
--   5. Truncate legacy health_telemetry down to 0 rows.

BEGIN;

-- ============================================================================
-- 1. Canonical Hardware Device Name Function
-- ============================================================================
CREATE OR REPLACE FUNCTION public.canonicalize_health_source_key(
    raw_key text,
    host_name text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    k text := lower(trim(coalesce(raw_key, '')));
    h text := lower(trim(coalesce(host_name, '')));
BEGIN
    IF k = '' OR k = 'unknown' THEN
        IF h LIKE '%radar%' OR h LIKE '%fold%' THEN RETURN 'Radar (Galaxy Z Fold 8)'; END IF;
        IF h LIKE '%trapper%' OR h LIKE '%pixel%' THEN RETURN 'Trapper (Pixel 9 Pro)'; END IF;
        IF h LIKE '%schmitz%' OR h LIKE '%iphone%' THEN RETURN 'Schmitz (iPhone)'; END IF;
        RETURN 'Unknown';
    END IF;

    -- Smart Rings
    IF k LIKE '%oura%' THEN
        RETURN 'Oura Ring';
    END IF;

    -- Smartwatches (checked BEFORE phone substrings like 'pixel' or 'iphone'!)
    IF k LIKE '%pixel watch%' OR k LIKE '%fitbit%' OR k LIKE '%google health%'
       OR k LIKE '%wear.companion%' OR k LIKE '%google.android.wearable%' OR k = 'trapper_pw5' THEN
        RETURN 'Pixel Watch 5';
    END IF;

    IF k LIKE '%oneplus%' OR k LIKE '%heytap%' OR k LIKE '%international%' OR k LIKE '%ohealth%' OR k LIKE '%oplus%' THEN
        RETURN 'OnePlus Watch 3';
    END IF;

    IF k LIKE '%apple watch%' OR k LIKE '%watchos%' OR k LIKE '%ultra 2%' OR k = 'schmitz_ultra2' THEN
        RETURN 'Apple Watch Ultra 2';
    END IF;

    IF k LIKE '%amazfit%' OR k LIKE '%zepp%' OR k LIKE '%huami%' OR k LIKE '%balance%' THEN
        RETURN 'Amazfit Balance';
    END IF;

    IF k LIKE '%huawei%' OR k LIKE '%harmony%' OR k LIKE '%gt 5%' OR k LIKE '%gt5%' THEN
        RETURN 'Huawei Watch GT 5 Pro';
    END IF;

    IF k LIKE '%garmin%' THEN RETURN 'Garmin'; END IF;
    IF k LIKE '%whoop%' THEN RETURN 'Whoop'; END IF;
    IF k LIKE '%withings%' THEN RETURN 'Withings'; END IF;
    IF k LIKE '%polar%' THEN RETURN 'Polar'; END IF;
    IF k LIKE '%galaxy watch%' THEN RETURN 'Galaxy Watch'; END IF;

    -- Phones & On-Device System Sensors
    IF k LIKE '%radar%' OR k LIKE '%fold%' OR k LIKE '%sm-f9%' OR k LIKE '%shealth%' OR k LIKE '%samsung%' THEN
        RETURN 'Radar (Galaxy Z Fold 8)';
    END IF;

    IF k LIKE '%trapper%' OR k LIKE '%pixel 9%' OR k LIKE '%j97428%' OR k LIKE '%healthconnect%' OR k LIKE '%health connect%' THEN
        IF h LIKE '%radar%' THEN
            RETURN 'Radar (Galaxy Z Fold 8)';
        END IF;
        RETURN 'Trapper (Pixel 9 Pro)';
    END IF;

    IF k LIKE '%google fit%' OR k LIKE '%apps.fitness%' THEN
        IF h LIKE '%radar%' THEN
            RETURN 'Radar (Galaxy Z Fold 8)';
        END IF;
        RETURN 'Trapper (Pixel 9 Pro)';
    END IF;

    IF k LIKE '%schmitz%' OR k LIKE '%iphone%' OR k LIKE '%apple health%' OR k LIKE '%healthkit%' OR k LIKE '%canonical%' THEN
        RETURN 'Schmitz (iPhone)';
    END IF;

    RETURN trim(raw_key);
END;
$$;

CREATE OR REPLACE FUNCTION public.canonical_sleep_priority(device_key text, session_type text DEFAULT 'primary_sleep')
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN coalesce(session_type, 'primary_sleep') = 'nap' THEN 99
        WHEN device_key = 'Oura Ring' THEN 1
        WHEN device_key = 'Apple Watch Ultra 2' THEN 2
        WHEN device_key = 'Pixel Watch 5' THEN 3
        WHEN device_key = 'OnePlus Watch 3' THEN 4
        WHEN device_key IN ('Amazfit Balance', 'Huawei Watch GT 5 Pro', 'Garmin', 'Whoop', 'Polar', 'Withings', 'Galaxy Watch') THEN 5
        ELSE 10
    END;
$$;

-- ============================================================================
-- 2. Rescue Remaining Data from public.health_telemetry Before Truncation
-- ============================================================================

-- 2A. Rescue granular sleep sessions (e.g. Pixel Watch 5 on Nov 1 & Nov 2)
WITH raw_sleep_stages AS (
    SELECT DISTINCT ON (
        ht.user_id,
        ht.local_date,
        public.canonicalize_health_source_key(ht.source_device, NULL),
        ht.start_time,
        ht.type
    )
        ht.id,
        ht.user_id,
        ht.local_date,
        public.canonicalize_health_source_key(ht.source_device, NULL) AS canonical_key,
        ht.type,
        ht.start_time,
        COALESCE(ht.end_time, ht.start_time + make_interval(secs =>
            CASE
                WHEN lower(coalesce(ht.unit, '')) IN ('minutes', 'minute', 'min', 'm') THEN coalesce(ht.value, 0) * 60.0
                ELSE coalesce(ht.value, 0)
            END
        )) AS end_time,
        GREATEST(0, ROUND(
            CASE
                WHEN lower(coalesce(ht.unit, '')) IN ('minutes', 'minute', 'min', 'm') THEN coalesce(ht.value, 0) * 60.0
                WHEN lower(coalesce(ht.unit, '')) IN ('hours', 'hour', 'h', 'hr') THEN coalesce(ht.value, 0) * 3600.0
                WHEN coalesce(ht.value, 0) > 0 THEN ht.value
                WHEN ht.end_time IS NOT NULL AND ht.end_time > ht.start_time THEN EXTRACT(EPOCH FROM (ht.end_time - ht.start_time))
                ELSE 0
            END
        )::integer) AS dur_sec
    FROM public.health_telemetry ht
    WHERE ht.type IN ('sleep_stage_deep', 'sleep_stage_rem', 'sleep_stage_light', 'sleep_stage_core', 'sleep_stage_awake')
      AND ht.local_date IS NOT NULL
      AND COALESCE(ht.source_device, '') NOT ILIKE '%Google Fit%'
      AND COALESCE(ht.source_device, '') NOT ILIKE '%Google Health%'
    ORDER BY
        ht.user_id,
        ht.local_date,
        public.canonicalize_health_source_key(ht.source_device, NULL),
        ht.start_time,
        ht.type
),
grouped_sleep AS (
    SELECT
        user_id,
        local_date,
        canonical_key,
        MIN(start_time) AS min_start,
        MAX(end_time) AS max_end,
        SUM(CASE WHEN type = 'sleep_stage_deep' THEN dur_sec ELSE 0 END)::integer AS deep_s,
        SUM(CASE WHEN type = 'sleep_stage_rem' THEN dur_sec ELSE 0 END)::integer AS rem_s,
        SUM(CASE WHEN type IN ('sleep_stage_light', 'sleep_stage_core') THEN dur_sec ELSE 0 END)::integer AS light_s,
        SUM(CASE WHEN type = 'sleep_stage_awake' THEN dur_sec ELSE 0 END)::integer AS awake_s,
        jsonb_agg(
            jsonb_build_object(
                'id', id::text,
                'stage_type', CASE
                    WHEN type = 'sleep_stage_deep' THEN 'Deep'
                    WHEN type = 'sleep_stage_rem' THEN 'REM'
                    WHEN type = 'sleep_stage_awake' THEN 'Awake'
                    ELSE 'Light'
                END,
                'start_time', to_char(start_time AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                'end_time', to_char(end_time AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                'duration_seconds', dur_sec,
                'source_device', canonical_key
            )
            ORDER BY start_time ASC
        ) AS stages_json
    FROM raw_sleep_stages
    WHERE dur_sec > 0
    GROUP BY user_id, local_date, canonical_key
    HAVING SUM(CASE WHEN type IN ('sleep_stage_deep', 'sleep_stage_rem', 'sleep_stage_light', 'sleep_stage_core') THEN dur_sec ELSE 0 END) >= 1800
)
INSERT INTO public.health_sleep_sessions (
    id, user_id, local_date, session_type, source_device_key, host_device_name,
    start_time, end_time, duration_seconds, time_in_bed_seconds,
    efficiency_percent, sleep_score, deep_seconds, rem_seconds, light_seconds, awake_seconds,
    latency_seconds, quality_rating, stages, source_priority, is_user_selected, ingested_at
)
SELECT
    'sleep_' || gs.user_id::text || '_' || gs.local_date::text || '_primary_' || regexp_replace(lower(gs.canonical_key), '[^a-z0-9]+', '_', 'g'),
    gs.user_id,
    gs.local_date,
    'primary_sleep',
    gs.canonical_key,
    CASE
        WHEN gs.canonical_key IN ('Oura Ring', 'Apple Watch Ultra 2', 'Schmitz (iPhone)') THEN 'Schmitz'
        ELSE 'Trapper'
    END,
    gs.min_start,
    gs.max_end,
    (gs.deep_s + gs.rem_s + gs.light_s),
    (gs.deep_s + gs.rem_s + gs.light_s + gs.awake_s),
    ROUND(((gs.deep_s + gs.rem_s + gs.light_s)::numeric / GREATEST(1, gs.deep_s + gs.rem_s + gs.light_s + gs.awake_s)::numeric) * 100.0, 1),
    LEAST(100, GREATEST(30, ROUND(
        LEAST(50.0, ((gs.deep_s + gs.rem_s + gs.light_s)::numeric / (8.0 * 3600.0)) * 50.0)
        + LEAST(25.0, ((gs.deep_s + gs.rem_s)::numeric / GREATEST(1, gs.deep_s + gs.rem_s + gs.light_s)::numeric) * 62.5)
        + LEAST(25.0, ((gs.deep_s + gs.rem_s + gs.light_s)::numeric / GREATEST(1, gs.deep_s + gs.rem_s + gs.light_s + gs.awake_s)::numeric) * 25.0)
    )::integer)),
    gs.deep_s,
    gs.rem_s,
    gs.light_s,
    gs.awake_s,
    0,
    CASE
        WHEN (gs.deep_s + gs.rem_s + gs.light_s) >= 25200 THEN 'Optimal'
        WHEN (gs.deep_s + gs.rem_s + gs.light_s) >= 21600 THEN 'Good'
        ELSE 'Fair'
    END,
    gs.stages_json,
    public.canonical_sleep_priority(gs.canonical_key, 'primary_sleep'),
    false,
    now()
FROM grouped_sleep gs
ON CONFLICT (user_id, local_date, session_type, source_device_key) DO UPDATE
SET
    start_time = CASE WHEN jsonb_array_length(health_sleep_sessions.stages) = 0 THEN EXCLUDED.start_time ELSE health_sleep_sessions.start_time END,
    end_time = CASE WHEN jsonb_array_length(health_sleep_sessions.stages) = 0 THEN EXCLUDED.end_time ELSE health_sleep_sessions.end_time END,
    duration_seconds = GREATEST(health_sleep_sessions.duration_seconds, EXCLUDED.duration_seconds),
    time_in_bed_seconds = GREATEST(health_sleep_sessions.time_in_bed_seconds, EXCLUDED.time_in_bed_seconds),
    deep_seconds = CASE WHEN jsonb_array_length(health_sleep_sessions.stages) = 0 THEN EXCLUDED.deep_seconds ELSE health_sleep_sessions.deep_seconds END,
    rem_seconds = CASE WHEN jsonb_array_length(health_sleep_sessions.stages) = 0 THEN EXCLUDED.rem_seconds ELSE health_sleep_sessions.rem_seconds END,
    light_seconds = CASE WHEN jsonb_array_length(health_sleep_sessions.stages) = 0 THEN EXCLUDED.light_seconds ELSE health_sleep_sessions.light_seconds END,
    awake_seconds = CASE WHEN jsonb_array_length(health_sleep_sessions.stages) = 0 THEN EXCLUDED.awake_seconds ELSE health_sleep_sessions.awake_seconds END,
    stages = CASE WHEN jsonb_array_length(health_sleep_sessions.stages) = 0 THEN EXCLUDED.stages ELSE health_sleep_sessions.stages END,
    source_priority = EXCLUDED.source_priority;

-- 2B. Rescue daily vitals (steps, hourly_steps, kcal, RHR, HRV, SpO2, RespRate) from health_telemetry
WITH dedup_telem AS (
    SELECT DISTINCT ON (
        ht.user_id,
        ht.local_date,
        public.canonicalize_health_source_key(ht.source_device, NULL),
        ht.type,
        ht.start_time
    )
        ht.user_id,
        ht.local_date,
        public.canonicalize_health_source_key(ht.source_device, NULL) AS canonical_key,
        ht.type,
        ht.value,
        ht.start_time,
        COALESCE(ht.tz_offset_min, 120) AS tz_min
    FROM public.health_telemetry ht
    WHERE ht.local_date IS NOT NULL
      AND ht.value IS NOT NULL
      AND COALESCE(ht.source_device, '') NOT ILIKE '%Google Fit%'
      AND COALESCE(ht.source_device, '') NOT ILIKE '%Google Health%'
      AND ht.type IN ('steps', 'active_energy', 'resting_heart_rate', 'oxygen_saturation', 'respiratory_rate', 'hrv_sdnn', 'hrv_rmssd', 'weight', 'body_temperature')
    ORDER BY
        ht.user_id,
        ht.local_date,
        public.canonicalize_health_source_key(ht.source_device, NULL),
        ht.type,
        ht.start_time
),
step_hours AS (
    SELECT
        user_id,
        local_date,
        canonical_key,
        EXTRACT(HOUR FROM (start_time AT TIME ZONE 'UTC') + make_interval(mins => tz_min))::integer AS hr,
        ROUND(SUM(value))::integer AS hr_steps
    FROM dedup_telem
    WHERE type = 'steps' AND value > 0
    GROUP BY user_id, local_date, canonical_key, EXTRACT(HOUR FROM (start_time AT TIME ZONE 'UTC') + make_interval(mins => tz_min))::integer
),
step_json AS (
    SELECT
        sh_keys.user_id,
        sh_keys.local_date,
        sh_keys.canonical_key,
        jsonb_agg(
            jsonb_build_object('hour', h.hr, 'steps', COALESCE(sh.hr_steps, 0))
            ORDER BY h.hr ASC
        ) AS hourly_steps_json
    FROM (SELECT DISTINCT user_id, local_date, canonical_key FROM step_hours) sh_keys
    CROSS JOIN generate_series(0, 23) AS h(hr)
    LEFT JOIN step_hours sh
      ON sh.user_id = sh_keys.user_id
     AND sh.local_date = sh_keys.local_date
     AND sh.canonical_key = sh_keys.canonical_key
     AND sh.hr = h.hr
    GROUP BY sh_keys.user_id, sh_keys.local_date, sh_keys.canonical_key
),
agg_vitals AS (
    SELECT
        dt.user_id,
        dt.local_date,
        dt.canonical_key,
        COALESCE(ROUND(SUM(CASE WHEN dt.type = 'steps' THEN dt.value ELSE 0 END))::integer, 0) AS steps,
        COALESCE(ROUND(SUM(CASE WHEN dt.type = 'active_energy' THEN dt.value ELSE 0 END)::numeric, 1)::double precision, 0) AS active_kcal,
        ROUND(AVG(CASE WHEN dt.type = 'resting_heart_rate' AND dt.value > 0 THEN dt.value END))::integer AS rhr,
        ROUND(AVG(CASE WHEN dt.type = 'oxygen_saturation' AND dt.value > 0 THEN dt.value END)::numeric, 1)::double precision AS spo2,
        ROUND(AVG(CASE WHEN dt.type = 'respiratory_rate' AND dt.value > 0 THEN dt.value END)::numeric, 2)::double precision AS resp_rate,
        ROUND(AVG(CASE WHEN dt.type = 'body_temperature' THEN dt.value END)::numeric, 2)::double precision AS skin_temp,
        (ARRAY_AGG(dt.value ORDER BY dt.start_time DESC) FILTER (WHERE dt.type = 'weight' AND dt.value > 0))[1] AS weight_kg,
        ROUND(AVG(CASE WHEN dt.type = 'hrv_sdnn' AND dt.value > 0 THEN dt.value END)::numeric, 1)::double precision AS hrv_sdnn,
        ROUND(AVG(CASE WHEN dt.type = 'hrv_rmssd' AND dt.value > 0 THEN dt.value END)::numeric, 1)::double precision AS hrv_rmssd
    FROM dedup_telem dt
    GROUP BY dt.user_id, dt.local_date, dt.canonical_key
)
INSERT INTO public.health_daily_vitals (
    id, user_id, local_date, source_device_key, host_device_name,
    steps, active_kcal, resting_heart_rate, spo2, respiratory_rate,
    skin_temp_celsius, weight_kg, hrv_sdnn_nightly, hrv_rmssd_nightly, hourly_steps, updated_at
)
SELECT
    'vitals_' || av.user_id::text || '_' || av.local_date::text || '_' || regexp_replace(lower(av.canonical_key), '[^a-z0-9]+', '_', 'g'),
    av.user_id,
    av.local_date,
    av.canonical_key,
    CASE
        WHEN av.canonical_key IN ('Oura Ring', 'Apple Watch Ultra 2', 'Schmitz (iPhone)') THEN 'Schmitz'
        WHEN av.canonical_key = 'Radar (Galaxy Z Fold 8)' THEN 'Radar'
        ELSE 'Trapper'
    END,
    av.steps,
    av.active_kcal,
    av.rhr,
    av.spo2,
    av.resp_rate,
    av.skin_temp,
    av.weight_kg,
    av.hrv_sdnn,
    av.hrv_rmssd,
    COALESCE(sj.hourly_steps_json, '[]'::jsonb),
    now()
FROM agg_vitals av
LEFT JOIN step_json sj
  ON sj.user_id = av.user_id AND sj.local_date = av.local_date AND sj.canonical_key = av.canonical_key
WHERE av.steps > 0 OR av.active_kcal > 0 OR av.rhr IS NOT NULL OR av.spo2 IS NOT NULL
   OR av.resp_rate IS NOT NULL OR av.hrv_sdnn IS NOT NULL OR av.hrv_rmssd IS NOT NULL OR av.weight_kg IS NOT NULL
ON CONFLICT (user_id, local_date, source_device_key) DO UPDATE
SET
    hourly_steps = CASE
        WHEN EXCLUDED.steps >= COALESCE(health_daily_vitals.steps, 0) AND jsonb_array_length(COALESCE(EXCLUDED.hourly_steps, '[]'::jsonb)) > 0
        THEN EXCLUDED.hourly_steps
        ELSE health_daily_vitals.hourly_steps
    END,
    steps = GREATEST(COALESCE(health_daily_vitals.steps, 0), COALESCE(EXCLUDED.steps, 0)),
    active_kcal = GREATEST(COALESCE(health_daily_vitals.active_kcal, 0), COALESCE(EXCLUDED.active_kcal, 0)),
    resting_heart_rate = COALESCE(health_daily_vitals.resting_heart_rate, EXCLUDED.resting_heart_rate),
    spo2 = COALESCE(health_daily_vitals.spo2, EXCLUDED.spo2),
    respiratory_rate = COALESCE(health_daily_vitals.respiratory_rate, EXCLUDED.respiratory_rate),
    skin_temp_celsius = COALESCE(health_daily_vitals.skin_temp_celsius, EXCLUDED.skin_temp_celsius),
    weight_kg = COALESCE(health_daily_vitals.weight_kg, EXCLUDED.weight_kg),
    hrv_sdnn_nightly = COALESCE(health_daily_vitals.hrv_sdnn_nightly, EXCLUDED.hrv_sdnn_nightly),
    hrv_rmssd_nightly = COALESCE(health_daily_vitals.hrv_rmssd_nightly, EXCLUDED.hrv_rmssd_nightly),
    updated_at = now();

-- 2C. Rescue 5-minute intraday HR buckets from health_telemetry
WITH hr_telem AS (
    SELECT
        ht.user_id,
        ht.local_date,
        public.canonicalize_health_source_key(ht.source_device, NULL) AS canonical_key,
        (
            EXTRACT(HOUR FROM (ht.start_time AT TIME ZONE 'UTC') + make_interval(mins => COALESCE(ht.tz_offset_min, 120)))::integer * 60
            + (EXTRACT(MINUTE FROM (ht.start_time AT TIME ZONE 'UTC') + make_interval(mins => COALESCE(ht.tz_offset_min, 120)))::integer / 5) * 5
        )::smallint AS bucket_min,
        ht.value
    FROM public.health_telemetry ht
    WHERE ht.type = 'heart_rate'
      AND ht.local_date IS NOT NULL
      AND ht.value BETWEEN 30 AND 240
      AND COALESCE(ht.source_device, '') NOT ILIKE '%Google Fit%'
      AND COALESCE(ht.source_device, '') NOT ILIKE '%Google Health%'
),
hr_agg AS (
    SELECT
        user_id,
        local_date,
        canonical_key,
        bucket_min,
        ROUND(AVG(value))::smallint AS bpm_avg,
        ROUND(MIN(value))::smallint AS bpm_min,
        ROUND(MAX(value))::smallint AS bpm_max,
        LEAST(32767, COUNT(*))::smallint AS sample_cnt
    FROM hr_telem
    WHERE bucket_min BETWEEN 0 AND 1435
    GROUP BY user_id, local_date, canonical_key, bucket_min
)
INSERT INTO public.health_intraday_heart_rate (
    id, user_id, local_date, source_device_key, bucket_minute, bpm_avg, bpm_min, bpm_max, sample_count, updated_at
)
SELECT
    'hr_' || user_id::text || '_' || local_date::text || '_' || regexp_replace(lower(canonical_key), '[^a-z0-9]+', '_', 'g') || '_' || bucket_min::text,
    user_id,
    local_date,
    canonical_key,
    bucket_min,
    bpm_avg,
    bpm_min,
    bpm_max,
    sample_cnt,
    now()
FROM hr_agg
ON CONFLICT (user_id, local_date, source_device_key, bucket_minute) DO UPDATE
SET
    bpm_min = LEAST(health_intraday_heart_rate.bpm_min, EXCLUDED.bpm_min),
    bpm_max = GREATEST(health_intraday_heart_rate.bpm_max, EXCLUDED.bpm_max),
    sample_count = GREATEST(health_intraday_heart_rate.sample_count, EXCLUDED.sample_count),
    updated_at = now();

-- ============================================================================
-- 3. Unify & Deduplicate Existing Rows Across All Lean Tables
-- ============================================================================

-- 3A. Clean mirrored Google Fit sleep rows on dates where another real session already exists
DELETE FROM public.health_sleep_sessions s
WHERE (s.source_device_key ILIKE '%Google Fit%' OR s.source_device_key ILIKE '%apps.fitness%')
  AND EXISTS (
      SELECT 1 FROM public.health_sleep_sessions s2
      WHERE s2.user_id = s.user_id
        AND s2.local_date = s.local_date
        AND s2.id <> s.id
        AND s2.source_device_key NOT ILIKE '%Google Fit%'
        AND s2.source_device_key NOT ILIKE '%apps.fitness%'
  );

-- Rebuild clean unified sleep sessions into a temp table, then replace
CREATE TEMP TABLE tmp_clean_sleep ON COMMIT DROP AS
SELECT DISTINCT ON (
    s.user_id,
    s.local_date,
    s.session_type,
    public.canonicalize_health_source_key(s.source_device_key, s.host_device_name)
)
    'sleep_' || s.user_id::text || '_' || s.local_date::text || '_' || s.session_type || '_' ||
        regexp_replace(lower(public.canonicalize_health_source_key(s.source_device_key, s.host_device_name)), '[^a-z0-9]+', '_', 'g') AS id,
    s.user_id,
    s.local_date,
    s.session_type,
    public.canonicalize_health_source_key(s.source_device_key, s.host_device_name) AS source_device_key,
    CASE
        WHEN public.canonicalize_health_source_key(s.source_device_key, s.host_device_name) IN ('Oura Ring', 'Apple Watch Ultra 2', 'Schmitz (iPhone)') THEN 'Schmitz'
        WHEN public.canonicalize_health_source_key(s.source_device_key, s.host_device_name) = 'Radar (Galaxy Z Fold 8)' THEN 'Radar'
        ELSE 'Trapper'
    END AS host_device_name,
    s.start_time,
    s.end_time,
    s.duration_seconds,
    s.time_in_bed_seconds,
    s.efficiency_percent,
    s.sleep_score,
    s.deep_seconds,
    s.rem_seconds,
    s.light_seconds,
    s.awake_seconds,
    s.latency_seconds,
    s.quality_rating,
    s.stages,
    public.canonical_sleep_priority(
        public.canonicalize_health_source_key(s.source_device_key, s.host_device_name),
        s.session_type
    ) AS source_priority,
    BOOL_OR(s.is_user_selected) OVER (
        PARTITION BY s.user_id, s.local_date, s.session_type, public.canonicalize_health_source_key(s.source_device_key, s.host_device_name)
    ) AS is_user_selected,
    s.ingested_at
FROM public.health_sleep_sessions s
ORDER BY
    s.user_id,
    s.local_date,
    s.session_type,
    public.canonicalize_health_source_key(s.source_device_key, s.host_device_name),
    jsonb_array_length(COALESCE(s.stages, '[]'::jsonb)) DESC,
    s.duration_seconds DESC;

DELETE FROM public.health_sleep_sessions;
INSERT INTO public.health_sleep_sessions SELECT * FROM tmp_clean_sleep;

-- 3B. Rebuild clean unified daily vitals into a temp table, merging duplicates per canonical key
CREATE TEMP TABLE tmp_clean_vitals ON COMMIT DROP AS
WITH normalized_vitals AS (
    SELECT
        v.*,
        public.canonicalize_health_source_key(v.source_device_key, v.host_device_name) AS canonical_key
    FROM public.health_daily_vitals v
)
SELECT
    'vitals_' || nv.user_id::text || '_' || nv.local_date::text || '_' ||
        regexp_replace(lower(nv.canonical_key), '[^a-z0-9]+', '_', 'g') AS id,
    nv.user_id,
    nv.local_date,
    nv.canonical_key AS source_device_key,
    CASE
        WHEN nv.canonical_key IN ('Oura Ring', 'Apple Watch Ultra 2', 'Schmitz (iPhone)') THEN 'Schmitz'
        WHEN nv.canonical_key = 'Radar (Galaxy Z Fold 8)' THEN 'Radar'
        ELSE 'Trapper'
    END AS host_device_name,
    COALESCE(MAX(nv.steps), 0) AS steps,
    COALESCE(MAX(nv.active_kcal), 0) AS active_kcal,
    MAX(nv.resting_heart_rate) AS resting_heart_rate,
    MAX(nv.spo2) AS spo2,
    MAX(nv.respiratory_rate) AS respiratory_rate,
    MAX(nv.skin_temp_celsius) AS skin_temp_celsius,
    (ARRAY_AGG(nv.weight_kg ORDER BY nv.updated_at DESC) FILTER (WHERE nv.weight_kg IS NOT NULL AND nv.weight_kg > 0))[1] AS weight_kg,
    MAX(nv.hrv_sdnn_nightly) AS hrv_sdnn_nightly,
    MAX(nv.hrv_rmssd_nightly) AS hrv_rmssd_nightly,
    COALESCE(
        (ARRAY_AGG(nv.hourly_steps ORDER BY COALESCE(nv.steps, 0) DESC, jsonb_array_length(COALESCE(nv.hourly_steps, '[]'::jsonb)) DESC)
            FILTER (WHERE jsonb_array_length(COALESCE(nv.hourly_steps, '[]'::jsonb)) > 0))[1],
        '[]'::jsonb
    ) AS hourly_steps,
    MAX(nv.updated_at) AS updated_at
FROM normalized_vitals nv
GROUP BY nv.user_id, nv.local_date, nv.canonical_key
HAVING COALESCE(MAX(nv.steps), 0) > 0
    OR COALESCE(MAX(nv.active_kcal), 0) > 0
    OR MAX(nv.resting_heart_rate) IS NOT NULL
    OR MAX(nv.spo2) IS NOT NULL
    OR MAX(nv.respiratory_rate) IS NOT NULL
    OR MAX(nv.skin_temp_celsius) IS NOT NULL
    OR MAX(nv.weight_kg) IS NOT NULL
    OR MAX(nv.hrv_sdnn_nightly) IS NOT NULL
    OR MAX(nv.hrv_rmssd_nightly) IS NOT NULL;

DELETE FROM public.health_daily_vitals;
INSERT INTO public.health_daily_vitals SELECT * FROM tmp_clean_vitals;

-- 3C. Rebuild clean unified intraday heart rate buckets into a temp table
CREATE TEMP TABLE tmp_clean_hr ON COMMIT DROP AS
WITH normalized_hr AS (
    SELECT
        h.*,
        public.canonicalize_health_source_key(h.source_device_key, NULL) AS canonical_key
    FROM public.health_intraday_heart_rate h
)
SELECT
    'hr_' || nh.user_id::text || '_' || nh.local_date::text || '_' ||
        regexp_replace(lower(nh.canonical_key), '[^a-z0-9]+', '_', 'g') || '_' || nh.bucket_minute::text AS id,
    nh.user_id,
    nh.local_date,
    nh.canonical_key AS source_device_key,
    nh.bucket_minute,
    ROUND(AVG(nh.bpm_avg))::smallint AS bpm_avg,
    MIN(nh.bpm_min)::smallint AS bpm_min,
    MAX(nh.bpm_max)::smallint AS bpm_max,
    MAX(nh.sample_count)::smallint AS sample_count,
    MAX(nh.updated_at) AS updated_at
FROM normalized_hr nh
GROUP BY nh.user_id, nh.local_date, nh.canonical_key, nh.bucket_minute;

DELETE FROM public.health_intraday_heart_rate;
INSERT INTO public.health_intraday_heart_rate SELECT * FROM tmp_clean_hr;

-- 3D. Clean and standardize public.health_sources (remove all 18 polluted/desktop entries)
CREATE TEMP TABLE tmp_distinct_users ON COMMIT DROP AS
SELECT DISTINCT user_id FROM (
    SELECT user_id FROM public.health_sources
    UNION
    SELECT user_id FROM public.health_daily_vitals
    UNION
    SELECT user_id FROM public.health_sleep_sessions
) u;

DELETE FROM public.health_sources;

INSERT INTO public.health_sources (
    id, user_id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color
)
SELECT
    CASE WHEN u.rn = 1 THEN s.id ELSE s.id || '_' || left(u.user_id::text, 8) END,
    u.user_id, s.platform, s.device_kind, s.vendor, s.model, s.display_name, s.host_device_name, s.priority_sleep, s.priority_activity, s.color
FROM (
    SELECT user_id, ROW_NUMBER() OVER (ORDER BY user_id) AS rn
    FROM tmp_distinct_users
) u
CROSS JOIN (
    VALUES
        ('oura_ring',           'iOS',     'smart_ring', 'Oura',    'Oura Ring Gen 3',    'Oura Ring',               'Schmitz', 1,  3,  '#00D09C'),
        ('apple_watch_ultra_2', 'watchOS', 'smartwatch', 'Apple',   'Apple Watch Ultra 2','Apple Watch Ultra 2',     'Schmitz', 2,  1,  '#34C759'),
        ('pixel_watch_5',       'WearOS',  'smartwatch', 'Google',  'Pixel Watch 5',      'Pixel Watch 5',           'Trapper', 3,  2,  '#3897F0'),
        ('oneplus_watch_3',     'WearOS',  'smartwatch', 'OnePlus', 'OnePlus Watch 3',    'OnePlus Watch 3',         'Trapper', 4,  4,  '#FF6B4A'),
        ('schmitz_iphone',      'iOS',     'phone',      'Apple',   'iPhone 16 Pro',      'Schmitz (iPhone)',        'Schmitz', 10, 10, '#AF52DE'),
        ('trapper_pixel9',      'Android', 'phone',      'Google',  'Pixel 9 Pro',        'Trapper (Pixel 9 Pro)',   'Trapper', 10, 11, '#5856D6'),
        ('radar_fold8',         'Android', 'phone',      'Samsung', 'Galaxy Z Fold 8',    'Radar (Galaxy Z Fold 8)', 'Radar',   10, 12, '#00C7BE')
) AS s(id, platform, device_kind, vendor, model, display_name, host_device_name, priority_sleep, priority_activity, color);

-- ============================================================================
-- 4. Install Lightweight Canonicalization & Monotonic-Merge Triggers
-- ============================================================================

-- 4A. Trigger on health_daily_vitals
CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_daily_vitals()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.source_device_key := public.canonicalize_health_source_key(NEW.source_device_key, NEW.host_device_name);

    IF TG_OP = 'INSERT' THEN
        NEW.id := 'vitals_' || NEW.user_id::text || '_' || NEW.local_date::text || '_' ||
                  regexp_replace(lower(NEW.source_device_key), '[^a-z0-9]+', '_', 'g');
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.id := OLD.id;
        IF COALESCE(NEW.steps, 0) >= COALESCE(OLD.steps, 0) THEN
            IF jsonb_array_length(COALESCE(NEW.hourly_steps, '[]'::jsonb)) = 0
               AND jsonb_array_length(COALESCE(OLD.hourly_steps, '[]'::jsonb)) > 0 THEN
                NEW.hourly_steps := OLD.hourly_steps;
            END IF;
        ELSE
            NEW.steps := OLD.steps;
            IF jsonb_array_length(COALESCE(OLD.hourly_steps, '[]'::jsonb)) > 0 THEN
                NEW.hourly_steps := OLD.hourly_steps;
            END IF;
        END IF;

        NEW.active_kcal := GREATEST(COALESCE(OLD.active_kcal, 0), COALESCE(NEW.active_kcal, 0));
        NEW.resting_heart_rate := COALESCE(NEW.resting_heart_rate, OLD.resting_heart_rate);
        NEW.spo2 := COALESCE(NEW.spo2, OLD.spo2);
        NEW.respiratory_rate := COALESCE(NEW.respiratory_rate, OLD.respiratory_rate);
        NEW.skin_temp_celsius := COALESCE(NEW.skin_temp_celsius, OLD.skin_temp_celsius);
        NEW.weight_kg := COALESCE(NEW.weight_kg, OLD.weight_kg);
        NEW.hrv_sdnn_nightly := COALESCE(NEW.hrv_sdnn_nightly, OLD.hrv_sdnn_nightly);
        NEW.hrv_rmssd_nightly := COALESCE(NEW.hrv_rmssd_nightly, OLD.hrv_rmssd_nightly);
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_health_daily_vitals ON public.health_daily_vitals;
CREATE TRIGGER trg_guard_health_daily_vitals
BEFORE INSERT OR UPDATE ON public.health_daily_vitals
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_guard_health_daily_vitals();

-- 4B. Trigger on health_sleep_sessions
CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_sleep_sessions()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.source_device_key := public.canonicalize_health_source_key(NEW.source_device_key, NEW.host_device_name);
    NEW.source_priority := public.canonical_sleep_priority(NEW.source_device_key, NEW.session_type);

    IF TG_OP = 'INSERT' THEN
        NEW.id := 'sleep_' || NEW.user_id::text || '_' || NEW.local_date::text || '_' || NEW.session_type || '_' ||
                  regexp_replace(lower(NEW.source_device_key), '[^a-z0-9]+', '_', 'g');
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.id := OLD.id;
        NEW.is_user_selected := COALESCE(OLD.is_user_selected, false) OR COALESCE(NEW.is_user_selected, false);
        IF jsonb_array_length(COALESCE(NEW.stages, '[]'::jsonb)) = 0
           AND jsonb_array_length(COALESCE(OLD.stages, '[]'::jsonb)) > 0 THEN
            NEW.stages := OLD.stages;
            NEW.deep_seconds := OLD.deep_seconds;
            NEW.rem_seconds := OLD.rem_seconds;
            NEW.light_seconds := OLD.light_seconds;
            NEW.awake_seconds := OLD.awake_seconds;
            NEW.duration_seconds := GREATEST(OLD.duration_seconds, NEW.duration_seconds);
            NEW.time_in_bed_seconds := GREATEST(OLD.time_in_bed_seconds, NEW.time_in_bed_seconds);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_health_sleep_sessions ON public.health_sleep_sessions;
CREATE TRIGGER trg_guard_health_sleep_sessions
BEFORE INSERT OR UPDATE ON public.health_sleep_sessions
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_guard_health_sleep_sessions();

-- 4C. Trigger on health_intraday_heart_rate
CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_intraday_hr()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.source_device_key := public.canonicalize_health_source_key(NEW.source_device_key, NULL);
    IF TG_OP = 'INSERT' THEN
        NEW.id := 'hr_' || NEW.user_id::text || '_' || NEW.local_date::text || '_' ||
                  regexp_replace(lower(NEW.source_device_key), '[^a-z0-9]+', '_', 'g') || '_' || NEW.bucket_minute::text;
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.id := OLD.id;
        NEW.bpm_min := LEAST(OLD.bpm_min, NEW.bpm_min);
        NEW.bpm_max := GREATEST(OLD.bpm_max, NEW.bpm_max);
        NEW.sample_count := GREATEST(OLD.sample_count, NEW.sample_count);
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_health_intraday_hr ON public.health_intraday_heart_rate;
CREATE TRIGGER trg_guard_health_intraday_hr
BEFORE INSERT OR UPDATE ON public.health_intraday_heart_rate
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_guard_health_intraday_hr();

-- 4D. Guard health_sources against desktop/polluted dynamic re-registrations
CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_sources()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    canon text;
BEGIN
    IF lower(coalesce(NEW.device_kind, '')) = 'desktop'
       OR lower(coalesce(NEW.platform, '')) IN ('macos', 'windows') THEN
        RETURN NULL; -- Silently ignore desktop non-sensor entries
    END IF;

    canon := public.canonicalize_health_source_key(NEW.display_name, NEW.host_device_name);
    NEW.display_name := canon;
    NEW.id := CASE canon
        WHEN 'Oura Ring' THEN 'oura_ring'
        WHEN 'Apple Watch Ultra 2' THEN 'apple_watch_ultra_2'
        WHEN 'Pixel Watch 5' THEN 'pixel_watch_5'
        WHEN 'OnePlus Watch 3' THEN 'oneplus_watch_3'
        WHEN 'Schmitz (iPhone)' THEN 'schmitz_iphone'
        WHEN 'Trapper (Pixel 9 Pro)' THEN 'trapper_pixel9'
        WHEN 'Radar (Galaxy Z Fold 8)' THEN 'radar_fold8'
        ELSE regexp_replace(lower(canon), '[^a-z0-9]+', '_', 'g')
    END;

    -- If canonical entry for this user already exists, skip duplicate insert
    IF TG_OP = 'INSERT' AND EXISTS (
        SELECT 1 FROM public.health_sources
        WHERE user_id = NEW.user_id AND display_name = canon
    ) THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'INSERT' AND EXISTS (SELECT 1 FROM public.health_sources WHERE id = NEW.id) THEN
        NEW.id := NEW.id || '_' || left(NEW.user_id::text, 8);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_health_sources ON public.health_sources;
CREATE TRIGGER trg_guard_health_sources
BEFORE INSERT OR UPDATE ON public.health_sources
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_guard_health_sources();

-- ============================================================================
-- 5. Truncate Legacy health_telemetry & Zero-Row Sink Guard
-- ============================================================================
DROP TRIGGER IF EXISTS trigger_normalize_telemetry ON public.health_telemetry;
TRUNCATE TABLE public.health_telemetry;
TRUNCATE TABLE public.health_day_dirty;

-- Silently sink any residual legacy raw telemetry inserts from un-updated background devices
CREATE OR REPLACE FUNCTION public.trg_fn_sink_legacy_health_telemetry()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sink_legacy_health_telemetry ON public.health_telemetry;
CREATE TRIGGER trg_sink_legacy_health_telemetry
BEFORE INSERT ON public.health_telemetry
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_sink_legacy_health_telemetry();

DROP FUNCTION IF EXISTS public.prune_stale_health_telemetry(integer);
CREATE OR REPLACE FUNCTION public.prune_stale_health_telemetry(retention_days integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    deleted_count bigint := 0;
BEGIN
    IF retention_days <= 0 THEN
        WITH deleted AS (
            DELETE FROM public.health_telemetry RETURNING id
        )
        SELECT count(*) INTO deleted_count FROM deleted;
    ELSE
        WITH deleted AS (
            DELETE FROM public.health_telemetry ht
            WHERE ht.local_date < (CURRENT_DATE - make_interval(days => retention_days))
            RETURNING id
        )
        SELECT count(*) INTO deleted_count FROM deleted;
    END IF;
    RETURN jsonb_build_object(
        'status', 'success',
        'deleted_rows', deleted_count
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    PERFORM public.prune_stale_health_telemetry(0);

    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;

COMMIT;
