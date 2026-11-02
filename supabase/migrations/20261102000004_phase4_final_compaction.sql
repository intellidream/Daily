-- Migration: 20261102000004_phase4_final_compaction.sql
-- Description: Phase 4 Final Storage Compaction, Dropping Deprecated Triggers, and Lean Retention
-- Drops legacy dirty triggers, truncates health_day_dirty, updates rolling telemetry retention to 2 days.

-- 1. Drop deprecated mark_health_day_dirty triggers from lean tables
DROP TRIGGER IF EXISTS trigger_mark_dirty_daily_vitals ON public.health_daily_vitals;
DROP TRIGGER IF EXISTS trigger_mark_dirty_sleep_sessions ON public.health_sleep_sessions;
DROP FUNCTION IF EXISTS public.mark_health_day_dirty();

-- 2. Truncate health_day_dirty to guarantee clean queue
TRUNCATE TABLE public.health_day_dirty;

-- 3. Update prune_stale_health_telemetry with 2-day rolling buffer default
CREATE OR REPLACE FUNCTION public.prune_stale_health_telemetry(retention_days integer DEFAULT 2)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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

-- 4. Update apply_health_data_retention to enforce 2-day rolling buffer daily at 3 AM
CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Prune raw telemetry older than 2 days that has been compacted into lean tables
    PERFORM public.prune_stale_health_telemetry(2);

    -- Nullify bulky summary JSON for historical days older than 90 days to conserve space
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;

-- 5. Execute 2-day rolling prune immediately
SELECT public.apply_health_data_retention();
