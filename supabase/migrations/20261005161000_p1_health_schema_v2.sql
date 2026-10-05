-- P1: Health Schema v2 Migration
-- Creates canonical health tables, dirty tracking, realtime summary, normalization & deduplication triggers.
-- Date: 2026-10-05

BEGIN;

-- 1. Create health_sources table
CREATE TABLE IF NOT EXISTS public.health_sources (
    id text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    platform text NOT NULL,
    device_kind text NOT NULL,
    vendor text,
    model text,
    display_name text NOT NULL,
    priority_sleep integer DEFAULT 10,
    priority_activity integer DEFAULT 10,
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.health_sources ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_sources' AND policyname = 'Users can manage own health_sources'
    ) THEN
        CREATE POLICY "Users can manage own health_sources"
        ON public.health_sources FOR ALL TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- 2. Evolve health_telemetry columns
ALTER TABLE public.health_telemetry
    ADD COLUMN IF NOT EXISTS external_id text,
    ADD COLUMN IF NOT EXISTS source_id text REFERENCES public.health_sources(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS semantics text DEFAULT 'spot',
    ADD COLUMN IF NOT EXISTS tz_offset_min smallint DEFAULT 0,
    ADD COLUMN IF NOT EXISTS local_date date,
    ADD COLUMN IF NOT EXISTS ingested_at timestamp with time zone DEFAULT now();

-- Ensure UPDATE and DELETE RLS policies on health_telemetry
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_telemetry' AND policyname = 'Users can update their own telemetry'
    ) THEN
        CREATE POLICY "Users can update their own telemetry"
        ON public.health_telemetry FOR UPDATE TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_telemetry' AND policyname = 'Users can delete their own telemetry'
    ) THEN
        CREATE POLICY "Users can delete their own telemetry"
        ON public.health_telemetry FOR DELETE TO authenticated
        USING (auth.uid() = user_id);
    END IF;
END $$;

-- Performance indexes for health_telemetry
CREATE INDEX IF NOT EXISTS idx_health_telemetry_user_type_start 
ON public.health_telemetry (user_id, type, start_time DESC);

CREATE INDEX IF NOT EXISTS idx_health_telemetry_user_local_date 
ON public.health_telemetry (user_id, local_date);

CREATE INDEX IF NOT EXISTS idx_health_telemetry_external_id 
ON public.health_telemetry (user_id, external_id) WHERE external_id IS NOT NULL;

-- 3. Create health_day_dirty tracking table
CREATE TABLE IF NOT EXISTS public.health_day_dirty (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    local_date date NOT NULL,
    dirty_since timestamp with time zone DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
);

ALTER TABLE public.health_day_dirty ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_day_dirty' AND policyname = 'Users can view own dirty days'
    ) THEN
        CREATE POLICY "Users can view own dirty days"
        ON public.health_day_dirty FOR SELECT TO authenticated
        USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_day_dirty' AND policyname = 'Users can manage own dirty days'
    ) THEN
        CREATE POLICY "Users can manage own dirty days"
        ON public.health_day_dirty FOR ALL TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- 4. Create health_daily_summary table (Single Source of Truth)
CREATE TABLE IF NOT EXISTS public.health_daily_summary (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    local_date date NOT NULL,
    computed_at timestamp with time zone DEFAULT now(),
    engine_version text DEFAULT 'v1',
    raw_watermark timestamp with time zone,
    steps integer,
    active_kcal double precision,
    sleep_asleep_s integer,
    sleep_score integer,
    stress_avg integer,
    rhr integer,
    hrv_sdnn double precision,
    hrv_rmssd double precision,
    weight double precision,
    spo2 double precision,
    summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT health_daily_summary_user_date_key UNIQUE (user_id, local_date)
);

ALTER TABLE public.health_daily_summary ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_daily_summary' AND policyname = 'Users can view own daily summary'
    ) THEN
        CREATE POLICY "Users can view own daily summary"
        ON public.health_daily_summary FOR SELECT TO authenticated
        USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_daily_summary' AND policyname = 'Users can manage own daily summary'
    ) THEN
        CREATE POLICY "Users can manage own daily summary"
        ON public.health_daily_summary FOR ALL TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Add health_daily_summary to Realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'health_daily_summary'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.health_daily_summary;
    END IF;
END $$;

-- 5. Add DELETE policy on vitals for compliance
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'vitals' AND policyname = 'Users can delete own vitals'
    ) THEN
        CREATE POLICY "Users can delete own vitals"
        ON public.vitals FOR DELETE TO authenticated
        USING (auth.uid() = user_id);
    END IF;
END $$;

-- 6. Normalization and Deduplication Triggers
CREATE OR REPLACE FUNCTION public.normalize_and_dedup_telemetry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Normalize metric type aliases to canonical key
  NEW.type := CASE NEW.type
    WHEN 'spo2' THEN 'oxygen_saturation'
    WHEN 'blood_oxygen' THEN 'oxygen_saturation'
    WHEN 'OxygenSaturation' THEN 'oxygen_saturation'
    WHEN 'bo' THEN 'oxygen_saturation'
    WHEN 'hrv' THEN 'hrv_sdnn'
    WHEN 'HeartRateVariabilitySDNN' THEN 'hrv_sdnn'
    WHEN 'Steps' THEN 'steps'
    WHEN 'step_count' THEN 'steps'
    WHEN 'HeartRate' THEN 'heart_rate'
    WHEN 'ActiveEnergy' THEN 'active_energy'
    WHEN 'active_calories' THEN 'active_energy'
    WHEN 'BasalEnergyBurned' THEN 'basal_energy'
    WHEN 'Distance' THEN 'distance'
    WHEN 'FloorsClimbed' THEN 'floors_climbed'
    WHEN 'WalkingSpeed' THEN 'walking_speed'
    WHEN 'RestingHeartRate' THEN 'resting_heart_rate'
    WHEN 'RespiratoryRate' THEN 'respiratory_rate'
    WHEN 'SleepDeep' THEN 'sleep_stage_deep'
    WHEN 'sleep_deep' THEN 'sleep_stage_deep'
    WHEN 'SleepREM' THEN 'sleep_stage_rem'
    WHEN 'sleep_rem' THEN 'sleep_stage_rem'
    WHEN 'SleepLight' THEN 'sleep_stage_light'
    WHEN 'sleep_light' THEN 'sleep_stage_light'
    WHEN 'SleepAwake' THEN 'sleep_stage_awake'
    WHEN 'sleep_awake' THEN 'sleep_stage_awake'
    WHEN 'SleepDuration' THEN 'sleep_duration'
    WHEN 'Hydration' THEN 'hydration'
    WHEN 'Caffeine' THEN 'caffeine'
    WHEN 'Weight' THEN 'weight'
    WHEN 'body_mass' THEN 'weight'
    ELSE NEW.type
  END;

  -- Ensure local_date is set based on timezone offset
  IF NEW.local_date IS NULL THEN
    NEW.local_date := DATE(NEW.start_time + (COALESCE(NEW.tz_offset_min, 0) || ' minutes')::interval);
  END IF;

  -- Deduplication check: silently drop exact duplicates without failing batch
  IF EXISTS (
    SELECT 1 FROM public.health_telemetry
    WHERE user_id = NEW.user_id
      AND type = NEW.type
      AND start_time = NEW.start_time
      AND (
        (NEW.external_id IS NOT NULL AND external_id = NEW.external_id)
        OR (NEW.external_id IS NULL AND ABS(value - NEW.value) < 0.0001)
      )
    LIMIT 1
  ) THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$;

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

-- Drop flawed old trigger
DROP TRIGGER IF EXISTS trigger_aggregate_health_telemetry ON public.health_telemetry;

-- Attach new triggers
DROP TRIGGER IF EXISTS trigger_normalize_telemetry ON public.health_telemetry;
CREATE TRIGGER trigger_normalize_telemetry
BEFORE INSERT ON public.health_telemetry
FOR EACH ROW
EXECUTE FUNCTION public.normalize_and_dedup_telemetry();

DROP TRIGGER IF EXISTS trigger_mark_dirty_telemetry ON public.health_telemetry;
CREATE TRIGGER trigger_mark_dirty_telemetry
AFTER INSERT ON public.health_telemetry
FOR EACH ROW
EXECUTE FUNCTION public.mark_health_day_dirty();

COMMIT;
