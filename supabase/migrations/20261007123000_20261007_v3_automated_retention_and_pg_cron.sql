-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Update 3-Tier Retention Function to cover legacy telemetry without local_date
CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Tier 1 -> Tier 2: Delete raw telemetry for past days (older than today - 2 days buffer for timezones)
    -- Handles both new records with local_date and legacy records with start_time
    DELETE FROM public.health_telemetry
    WHERE COALESCE(local_date, start_time::date) < (CURRENT_DATE - INTERVAL '2 days')::date;

    -- Tier 3: Nullify heavy JSON summary for historical data (> 90 days)
    -- Preserves scalar columns (steps, active_kcal, rhr, sleep_asleep_s, sleep_score, stress_avg) for long-term Trends
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;

-- Schedule daily cron job at 03:00 UTC if not already scheduled
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-health-retention') THEN
        PERFORM cron.schedule(
            'daily-health-retention',
            '0 3 * * *',
            'SELECT public.apply_health_data_retention()'
        );
    END IF;
END $$;
