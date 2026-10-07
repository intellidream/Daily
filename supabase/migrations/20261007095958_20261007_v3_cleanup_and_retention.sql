-- 1. Drop Legacy Tables and Views (vitals & health_vitals)
DROP TABLE IF EXISTS public.health_vitals CASCADE;
DROP VIEW IF EXISTS public.health_vitals CASCADE;
DROP TABLE IF EXISTS public.vitals CASCADE;
DROP VIEW IF EXISTS public.vitals CASCADE;

-- 2. Create the 3-Tier Retention Function
CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Tier 2: Delete raw telemetry for past days (older than today - 2 days buffer for timezones)
    DELETE FROM public.health_telemetry
    WHERE local_date < (CURRENT_DATE - INTERVAL '2 days')::date;

    -- Tier 3: Nullify JSON summary for historical data (> 90 days)
    -- We keep the scalar values for Trends, but clear the heavy JSON object
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;
