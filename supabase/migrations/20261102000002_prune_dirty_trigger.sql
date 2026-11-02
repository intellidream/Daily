-- Migration: Prune aggressive telemetry dirty trigger and wire lean health triggers
-- Description: Drops trigger_mark_dirty_telemetry on health_telemetry to stop 382k+ per-row executions.
-- Attaches lean mark_health_day_dirty triggers to health_daily_vitals and health_sleep_sessions.

BEGIN;

-- 1. Drop old per-row trigger on health_telemetry
DROP TRIGGER IF EXISTS trigger_mark_dirty_telemetry ON public.health_telemetry;

-- 2. Ensure mark_health_day_dirty handles both insert and update cleanly
CREATE OR REPLACE FUNCTION public.mark_health_day_dirty()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.local_date IS NOT NULL THEN
    INSERT INTO public.health_day_dirty (user_id, local_date, dirty_since)
    VALUES (NEW.user_id, NEW.local_date, NOW())
    ON CONFLICT (user_id, local_date)
    DO UPDATE SET dirty_since = NOW();
  END IF;
  RETURN NEW;
END;
$$;

-- 3. Attach mark_health_day_dirty to health_daily_vitals (1 row per device per day)
DROP TRIGGER IF EXISTS trigger_mark_dirty_daily_vitals ON public.health_daily_vitals;
CREATE TRIGGER trigger_mark_dirty_daily_vitals
AFTER INSERT OR UPDATE ON public.health_daily_vitals
FOR EACH ROW
EXECUTE FUNCTION public.mark_health_day_dirty();

-- 4. Attach mark_health_day_dirty to health_sleep_sessions (1-2 rows per day)
DROP TRIGGER IF EXISTS trigger_mark_dirty_sleep_sessions ON public.health_sleep_sessions;
CREATE TRIGGER trigger_mark_dirty_sleep_sessions
AFTER INSERT OR UPDATE ON public.health_sleep_sessions
FOR EACH ROW
EXECUTE FUNCTION public.mark_health_day_dirty();

COMMIT;
