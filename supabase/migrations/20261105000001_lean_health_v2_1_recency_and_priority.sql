-- Migration: 20261105000001_lean_health_v2_1_recency_and_priority.sql
-- Lean Health Architecture v2.1:
-- 1. Adds scalar recency tracking (`latest_heart_rate`, `latest_hr_at`, `vitals_timestamps`)
--    directly onto `public.health_daily_vitals` (zero new tables, zero new rows, zero extra Realtime fanout).
-- 2. Unifies `public.health_sources` priority into a single 1-based rank (`1` = highest priority)
--    protected by `is_custom_priority` so background device syncs never overwrite user-chosen ordering.
-- 3. Updates guard triggers (`trg_fn_guard_health_daily_vitals`, `trg_fn_guard_health_sleep_sessions`,
--    `trg_fn_guard_health_sources`) and adds `public.reset_health_source_priorities()` RPC.
-- 4. Adds `public.health_sources` (~5-7 rows/user) to `supabase_realtime` for instant priority sync.

BEGIN;

-- ============================================================================
-- 1. Schema Extensions (Additive Only, Zero Row Growth)
-- ============================================================================

ALTER TABLE public.health_daily_vitals
    ADD COLUMN IF NOT EXISTS latest_heart_rate smallint,
    ADD COLUMN IF NOT EXISTS latest_hr_at timestamptz,
    ADD COLUMN IF NOT EXISTS vitals_timestamps jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.health_sources
    ADD COLUMN IF NOT EXISTS is_custom_priority boolean NOT NULL DEFAULT false;

-- ============================================================================
-- 2. Helper Functions for Unified Default Priority & Per-Vital Timestamp Merge
-- ============================================================================

CREATE OR REPLACE FUNCTION public.canonical_default_source_priority(device_key text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN device_key = 'Oura Ring' THEN 1
        WHEN device_key = 'Apple Watch Ultra 2' THEN 2
        WHEN device_key = 'Pixel Watch 5' THEN 3
        WHEN device_key = 'OnePlus Watch 3' THEN 4
        WHEN device_key IN ('Amazfit Balance', 'Huawei Watch GT 5 Pro', 'Garmin', 'Whoop', 'Polar', 'Withings', 'Galaxy Watch') THEN 5
        WHEN device_key = 'Schmitz (iPhone)' THEN 10
        WHEN device_key = 'Trapper (Pixel 9 Pro)' THEN 11
        WHEN device_key = 'Radar (Galaxy Z Fold 8)' THEN 12
        ELSE 15
    END;
$$;

CREATE OR REPLACE FUNCTION public.merge_vitals_timestamps(old_ts jsonb, new_ts jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    merged jsonb := COALESCE(old_ts, '{}'::jsonb);
    k text;
    v_new text;
    v_old text;
    t_new timestamptz;
    t_old timestamptz;
BEGIN
    IF new_ts IS NULL OR jsonb_typeof(new_ts) <> 'object' THEN
        RETURN merged;
    END IF;

    FOR k, v_new IN SELECT key, value #>> '{}' FROM jsonb_each(new_ts) LOOP
        IF v_new IS NULL OR length(trim(v_new)) = 0 THEN
            CONTINUE;
        END IF;
        v_old := merged ->> k;
        IF v_old IS NULL OR length(trim(v_old)) = 0 THEN
            merged := jsonb_set(merged, ARRAY[k], to_jsonb(v_new), true);
        ELSE
            BEGIN
                t_new := v_new::timestamptz;
                t_old := v_old::timestamptz;
                IF t_new >= t_old THEN
                    merged := jsonb_set(merged, ARRAY[k], to_jsonb(v_new), true);
                END IF;
            EXCEPTION WHEN OTHERS THEN
                merged := jsonb_set(merged, ARRAY[k], to_jsonb(v_new), true);
            END;
        END IF;
    END LOOP;

    RETURN merged;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_vital_ts_older(old_ts jsonb, new_ts jsonb, vital_key text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    s_old text;
    s_new text;
BEGIN
    s_old := COALESCE(old_ts, '{}'::jsonb) ->> vital_key;
    s_new := COALESCE(new_ts, '{}'::jsonb) ->> vital_key;
    IF s_old IS NULL OR s_new IS NULL THEN
        RETURN false;
    END IF;
    RETURN (s_new::timestamptz) < (s_old::timestamptz);
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END;
$$;

-- ============================================================================
-- 3. Normalize Existing Non-Custom Priorities & Backfill Latest HR on Recent Vitals
-- ============================================================================

UPDATE public.health_sources
SET
    priority_sleep = public.canonical_default_source_priority(display_name),
    priority_activity = public.canonical_default_source_priority(display_name)
WHERE COALESCE(is_custom_priority, false) = false;

WITH latest_buckets AS (
    SELECT DISTINCT ON (user_id, local_date, source_device_key)
        user_id,
        local_date,
        source_device_key,
        bpm_avg,
        -- Reconstruct synthetic bucket wall-clock if exact sample timestamp wasn't captured yet,
        -- bounded by row updated_at so we never synthesize a future timestamp.
        LEAST(
            updated_at,
            ((local_date::text || ' 00:00:00')::timestamp AT TIME ZONE 'Europe/Bucharest')
                + make_interval(mins => bucket_minute)
        ) AS approx_hr_at
    FROM public.health_intraday_heart_rate
    WHERE bpm_avg > 0
    ORDER BY user_id, local_date, source_device_key, bucket_minute DESC, updated_at DESC
)
UPDATE public.health_daily_vitals v
SET
    latest_heart_rate = lb.bpm_avg,
    latest_hr_at = lb.approx_hr_at
FROM latest_buckets lb
WHERE v.user_id = lb.user_id
  AND v.local_date = lb.local_date
  AND v.source_device_key = lb.source_device_key
  AND v.latest_heart_rate IS NULL;

-- ============================================================================
-- 4. Updated Guard Triggers
-- ============================================================================

-- 4A. Guard on health_daily_vitals (recency-preserving on latest_heart_rate & vitals_timestamps)
CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_daily_vitals()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    old_vts jsonb;
    new_vts jsonb;
BEGIN
    NEW.source_device_key := public.canonicalize_health_source_key(NEW.source_device_key, NEW.host_device_name);
    NEW.vitals_timestamps := COALESCE(NEW.vitals_timestamps, '{}'::jsonb);

    IF TG_OP = 'INSERT' THEN
        NEW.id := 'vitals_' || NEW.user_id::text || '_' || NEW.local_date::text || '_' ||
                  regexp_replace(lower(NEW.source_device_key), '[^a-z0-9]+', '_', 'g');
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.id := OLD.id;
        old_vts := COALESCE(OLD.vitals_timestamps, '{}'::jsonb);
        new_vts := COALESCE(NEW.vitals_timestamps, '{}'::jsonb);

        -- Cumulative Steps & Hourly Steps guard
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

        -- Recency-guarded Latest Heart Rate
        IF NEW.latest_heart_rate IS NOT NULL AND NEW.latest_heart_rate > 0 THEN
            IF OLD.latest_heart_rate IS NOT NULL AND OLD.latest_hr_at IS NOT NULL THEN
                IF NEW.latest_hr_at IS NULL OR NEW.latest_hr_at < OLD.latest_hr_at THEN
                    NEW.latest_heart_rate := OLD.latest_heart_rate;
                    NEW.latest_hr_at := OLD.latest_hr_at;
                END IF;
            END IF;
        ELSE
            NEW.latest_heart_rate := OLD.latest_heart_rate;
            NEW.latest_hr_at := OLD.latest_hr_at;
        END IF;

        -- Timestamp-aware scalar vitals preservation
        IF NEW.resting_heart_rate IS NULL OR public.is_vital_ts_older(old_vts, new_vts, 'rhr') THEN
            NEW.resting_heart_rate := COALESCE(OLD.resting_heart_rate, NEW.resting_heart_rate);
        END IF;
        IF NEW.spo2 IS NULL OR public.is_vital_ts_older(old_vts, new_vts, 'spo2') THEN
            NEW.spo2 := COALESCE(OLD.spo2, NEW.spo2);
        END IF;
        IF NEW.respiratory_rate IS NULL OR public.is_vital_ts_older(old_vts, new_vts, 'resp') THEN
            NEW.respiratory_rate := COALESCE(OLD.respiratory_rate, NEW.respiratory_rate);
        END IF;
        IF NEW.skin_temp_celsius IS NULL OR public.is_vital_ts_older(old_vts, new_vts, 'temp') THEN
            NEW.skin_temp_celsius := COALESCE(OLD.skin_temp_celsius, NEW.skin_temp_celsius);
        END IF;
        IF NEW.weight_kg IS NULL OR public.is_vital_ts_older(old_vts, new_vts, 'weight') THEN
            NEW.weight_kg := COALESCE(OLD.weight_kg, NEW.weight_kg);
        END IF;
        IF NEW.hrv_sdnn_nightly IS NULL OR public.is_vital_ts_older(old_vts, new_vts, 'hrv') THEN
            NEW.hrv_sdnn_nightly := COALESCE(OLD.hrv_sdnn_nightly, NEW.hrv_sdnn_nightly);
        END IF;
        IF NEW.hrv_rmssd_nightly IS NULL OR public.is_vital_ts_older(old_vts, new_vts, 'hrv') THEN
            NEW.hrv_rmssd_nightly := COALESCE(OLD.hrv_rmssd_nightly, NEW.hrv_rmssd_nightly);
        END IF;

        NEW.vitals_timestamps := public.merge_vitals_timestamps(old_vts, new_vts);
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- 4B. Guard on health_sleep_sessions (honors user's custom priority in health_sources)
CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_sleep_sessions()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    user_prio integer;
BEGIN
    NEW.source_device_key := public.canonicalize_health_source_key(NEW.source_device_key, NEW.host_device_name);

    IF coalesce(NEW.session_type, 'primary_sleep') = 'nap' THEN
        NEW.source_priority := 99;
    ELSE
        SELECT hs.priority_sleep INTO user_prio
        FROM public.health_sources hs
        WHERE hs.user_id = NEW.user_id
          AND hs.display_name = NEW.source_device_key
        LIMIT 1;

        NEW.source_priority := COALESCE(
            user_prio,
            public.canonical_sleep_priority(NEW.source_device_key, NEW.session_type)
        );
    END IF;

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

-- 4C. Guard on health_sources (protects user custom priority from background re-registration)
CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_sources()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    canon text;
    def_prio integer;
BEGIN
    IF TG_OP = 'INSERT' AND (
        lower(coalesce(NEW.device_kind, '')) = 'desktop'
        OR lower(coalesce(NEW.platform, '')) IN ('macos', 'windows')
    ) THEN
        RETURN NULL;
    END IF;

    canon := public.canonicalize_health_source_key(NEW.display_name, NEW.host_device_name);
    NEW.display_name := canon;
    def_prio := public.canonical_default_source_priority(canon);

    IF TG_OP = 'INSERT' THEN
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

        IF EXISTS (
            SELECT 1 FROM public.health_sources
            WHERE user_id = NEW.user_id AND display_name = canon
        ) THEN
            RETURN NULL;
        END IF;

        IF EXISTS (SELECT 1 FROM public.health_sources WHERE id = NEW.id) THEN
            NEW.id := NEW.id || '_' || left(NEW.user_id::text, 8);
        END IF;

        IF NOT COALESCE(NEW.is_custom_priority, false) THEN
            NEW.priority_sleep := def_prio;
            NEW.priority_activity := def_prio;
        ELSE
            NEW.priority_activity := COALESCE(NEW.priority_sleep, def_prio);
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.id := OLD.id;
        IF COALESCE(OLD.is_custom_priority, false) AND NOT COALESCE(NEW.is_custom_priority, false) THEN
            -- Background phone sync must NOT clobber user's saved custom priority!
            NEW.priority_sleep := OLD.priority_sleep;
            NEW.priority_activity := OLD.priority_activity;
            NEW.is_custom_priority := true;
        ELSIF COALESCE(NEW.is_custom_priority, false) THEN
            -- Unified single priority list: keep sleep & activity ranks identical
            NEW.priority_sleep := COALESCE(NEW.priority_sleep, OLD.priority_sleep, def_prio);
            NEW.priority_activity := NEW.priority_sleep;
        ELSE
            NEW.priority_sleep := def_prio;
            NEW.priority_activity := def_prio;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 5. RPCs for Atomic Priority Save & Reset (Single Unified Priority List)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.save_health_source_priorities(ordered_source_ids text[])
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    uid uuid := auth.uid();
    idx integer;
    sid text;
BEGIN
    IF uid IS NULL OR ordered_source_ids IS NULL THEN
        RETURN;
    END IF;

    FOR idx IN 1 .. COALESCE(array_length(ordered_source_ids, 1), 0) LOOP
        sid := ordered_source_ids[idx];
        UPDATE public.health_sources
        SET
            is_custom_priority = true,
            priority_sleep = idx,
            priority_activity = idx
        WHERE user_id = uid
          AND (id = sid OR display_name = sid);
    END LOOP;

    -- Keep sleep sessions' cached source_priority aligned for recent days
    UPDATE public.health_sleep_sessions ss
    SET source_priority = hs.priority_sleep
    FROM public.health_sources hs
    WHERE ss.user_id = uid
      AND hs.user_id = uid
      AND ss.source_device_key = hs.display_name
      AND ss.session_type <> 'nap'
      AND ss.local_date >= CURRENT_DATE - 14;
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_health_source_priorities()
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    uid uuid := auth.uid();
BEGIN
    IF uid IS NULL THEN
        RETURN;
    END IF;

    -- Temporarily clear custom flag in a direct update by setting both false simultaneously:
    -- Note: trg_fn_guard_health_sources checks OLD.is_custom_priority; disable guard branch via session setting.
    PERFORM set_config('daily.allow_priority_reset', 'true', true);

    UPDATE public.health_sources
    SET
        is_custom_priority = false,
        priority_sleep = public.canonical_default_source_priority(display_name),
        priority_activity = public.canonical_default_source_priority(display_name)
    WHERE user_id = uid;

    UPDATE public.health_sleep_sessions ss
    SET source_priority = public.canonical_sleep_priority(ss.source_device_key, ss.session_type)
    WHERE ss.user_id = uid
      AND ss.session_type <> 'nap'
      AND ss.local_date >= CURRENT_DATE - 14;
END;
$$;

-- Allow explicit reset via session config in trg_fn_guard_health_sources
CREATE OR REPLACE FUNCTION public.trg_fn_guard_health_sources()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    canon text;
    def_prio integer;
    allow_reset boolean := (current_setting('daily.allow_priority_reset', true) = 'true');
BEGIN
    IF TG_OP = 'INSERT' AND (
        lower(coalesce(NEW.device_kind, '')) = 'desktop'
        OR lower(coalesce(NEW.platform, '')) IN ('macos', 'windows')
    ) THEN
        RETURN NULL;
    END IF;

    canon := public.canonicalize_health_source_key(NEW.display_name, NEW.host_device_name);
    NEW.display_name := canon;
    def_prio := public.canonical_default_source_priority(canon);

    IF TG_OP = 'INSERT' THEN
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

        IF EXISTS (
            SELECT 1 FROM public.health_sources
            WHERE user_id = NEW.user_id AND display_name = canon
        ) THEN
            RETURN NULL;
        END IF;

        IF EXISTS (SELECT 1 FROM public.health_sources WHERE id = NEW.id) THEN
            NEW.id := NEW.id || '_' || left(NEW.user_id::text, 8);
        END IF;

        IF NOT COALESCE(NEW.is_custom_priority, false) THEN
            NEW.priority_sleep := def_prio;
            NEW.priority_activity := def_prio;
        ELSE
            NEW.priority_activity := COALESCE(NEW.priority_sleep, def_prio);
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.id := OLD.id;
        IF COALESCE(OLD.is_custom_priority, false) AND NOT COALESCE(NEW.is_custom_priority, false) AND NOT allow_reset THEN
            NEW.priority_sleep := OLD.priority_sleep;
            NEW.priority_activity := OLD.priority_activity;
            NEW.is_custom_priority := true;
        ELSIF COALESCE(NEW.is_custom_priority, false) THEN
            NEW.priority_sleep := COALESCE(NEW.priority_sleep, OLD.priority_sleep, def_prio);
            NEW.priority_activity := NEW.priority_sleep;
        ELSE
            NEW.priority_sleep := def_prio;
            NEW.priority_activity := def_prio;
            NEW.is_custom_priority := false;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_health_source_priorities(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_health_source_priorities() TO authenticated;

-- ============================================================================
-- 6. Enable Realtime on health_sources (~5-7 tiny rows per user)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'health_sources'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.health_sources;
    END IF;
END $$;

COMMIT;
