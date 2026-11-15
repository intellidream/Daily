-- Migration: Conditional ingested_at update + suppress no-op UPDATEs on health_sleep_sessions
-- Purpose:
--   1. Only bump `ingested_at` when meaningful sleep columns or `stages` actually changed
--      (after `trg_guard_health_sleep_sessions` runs normalization). Otherwise preserve `OLD.ingested_at`.
--   2. Attach `pg_catalog.suppress_redundant_updates_trigger()` alphabetically AFTER
--      `trg_z_touch_sleep_ingested_at` so redundant UPSERTs write 0 WAL/dead tuples and
--      emit 0 `supabase_realtime` broadcasts.

CREATE OR REPLACE FUNCTION public.trg_fn_touch_sleep_ingested_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
BEGIN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.local_date IS DISTINCT FROM OLD.local_date
       OR NEW.session_type IS DISTINCT FROM OLD.session_type
       OR NEW.source_device_key IS DISTINCT FROM OLD.source_device_key
       OR NEW.host_device_name IS DISTINCT FROM OLD.host_device_name
       OR NEW.start_time IS DISTINCT FROM OLD.start_time
       OR NEW.end_time IS DISTINCT FROM OLD.end_time
       OR NEW.duration_seconds IS DISTINCT FROM OLD.duration_seconds
       OR NEW.time_in_bed_seconds IS DISTINCT FROM OLD.time_in_bed_seconds
       OR NEW.efficiency_percent IS DISTINCT FROM OLD.efficiency_percent
       OR NEW.sleep_score IS DISTINCT FROM OLD.sleep_score
       OR NEW.deep_seconds IS DISTINCT FROM OLD.deep_seconds
       OR NEW.rem_seconds IS DISTINCT FROM OLD.rem_seconds
       OR NEW.light_seconds IS DISTINCT FROM OLD.light_seconds
       OR NEW.awake_seconds IS DISTINCT FROM OLD.awake_seconds
       OR NEW.latency_seconds IS DISTINCT FROM OLD.latency_seconds
       OR NEW.quality_rating IS DISTINCT FROM OLD.quality_rating
       OR NEW.stages IS DISTINCT FROM OLD.stages
       OR NEW.source_priority IS DISTINCT FROM OLD.source_priority
       OR NEW.is_user_selected IS DISTINCT FROM OLD.is_user_selected
    THEN
        NEW.ingested_at := now();
    ELSE
        NEW.ingested_at := OLD.ingested_at;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_z_touch_sleep_ingested_at ON public.health_sleep_sessions;
CREATE TRIGGER trg_z_touch_sleep_ingested_at
BEFORE UPDATE ON public.health_sleep_sessions
FOR EACH ROW EXECUTE FUNCTION public.trg_fn_touch_sleep_ingested_at();

DROP TRIGGER IF EXISTS trg_zz_suppress_redundant_sleep_updates ON public.health_sleep_sessions;
CREATE TRIGGER trg_zz_suppress_redundant_sleep_updates
BEFORE UPDATE ON public.health_sleep_sessions
FOR EACH ROW EXECUTE FUNCTION pg_catalog.suppress_redundant_updates_trigger();
