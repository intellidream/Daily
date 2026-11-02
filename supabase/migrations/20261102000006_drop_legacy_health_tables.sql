-- Migration: 20261102000006_drop_legacy_health_tables.sql
-- Purpose:
--   1. Permanently retire legacy raw telemetry (`public.health_telemetry`) and obsolete dirty queue (`public.health_day_dirty`)
--      following full Lean Health Architecture v2.0 rollout across all client platforms and `health-engine`.
--   2. Drop associated legacy triggers and maintenance functions (`trg_fn_sink_legacy_health_telemetry`,
--      `normalize_and_dedup_telemetry`, `prune_stale_health_telemetry`, `purge_expired_health_telemetry`, `mark_health_day_dirty`).
--   3. Simplify `public.apply_health_data_retention()` (invoked daily at 03:00 UTC by `pg_cron`) so it cleanly
--      compacts >90-day `summary` JSONB payloads in `public.health_daily_summary` without referencing dropped tables.

BEGIN;

-- 1. Detach legacy tables from supabase_realtime publication if still listed
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'health_telemetry'
    ) THEN
        ALTER PUBLICATION supabase_realtime DROP TABLE public.health_telemetry;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'health_day_dirty'
    ) THEN
        ALTER PUBLICATION supabase_realtime DROP TABLE public.health_day_dirty;
    END IF;
END $$;

-- 2. Drop legacy triggers and functions tied to retired tables
DROP TRIGGER IF EXISTS trg_sink_legacy_health_telemetry ON public.health_telemetry;
DROP TRIGGER IF EXISTS trigger_normalize_telemetry ON public.health_telemetry;
DROP TRIGGER IF EXISTS trigger_mark_dirty_telemetry ON public.health_telemetry;

DROP FUNCTION IF EXISTS public.trg_fn_sink_legacy_health_telemetry();
DROP FUNCTION IF EXISTS public.normalize_and_dedup_telemetry() CASCADE;
DROP FUNCTION IF EXISTS public.prune_stale_health_telemetry(integer);
DROP FUNCTION IF EXISTS public.purge_expired_health_telemetry();
DROP FUNCTION IF EXISTS public.mark_health_day_dirty() CASCADE;

-- 3. Drop obsolete tables (leaving strictly the 5 canonical Lean Health v2.0 tables)
DROP TABLE IF EXISTS public.health_telemetry CASCADE;
DROP TABLE IF EXISTS public.health_day_dirty CASCADE;

-- 4. Update daily retention function for Lean Architecture v2.0
CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Compact bulky JSONB summary payloads older than 90 days while preserving all scalar Trends columns
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;

COMMIT;
