-- Migration: 20261102000000_lean_health_architecture_v1.sql
-- Implements Phase 1 of the Lean Health Architecture:
-- 1. health_sources: canonical catalog of hardware devices and wearable sensors.
-- 2. health_sleep_sessions: dedicated discrete sleep sessions with granular hypnogram stages JSONB.
-- 3. health_daily_vitals: consolidated in-place UPSERT metrics per day per device.
-- 4. health_intraday_heart_rate: 5-minute bucketed resolution for intraday evolution charts.
-- 5. Enables RLS and Realtime publications.

BEGIN;

-- 1. Table: health_sources
CREATE TABLE IF NOT EXISTS public.health_sources (
    id text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    platform text NOT NULL, -- 'iOS', 'watchOS', 'Android', 'WearOS', 'macOS', 'Windows'
    device_kind text NOT NULL, -- 'phone', 'smartwatch', 'smart_ring', 'tablet', 'desktop'
    vendor text, -- 'Apple', 'Google', 'Oura', 'Samsung', 'Withings'
    model text,
    display_name text NOT NULL,
    host_device_name text, -- e.g. 'Schmitz', 'Trapper', 'Radar'
    priority_sleep integer DEFAULT 10,
    priority_activity integer DEFAULT 10,
    color text DEFAULT '#3897F0',
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

-- 2. Table: health_sleep_sessions (Dedicated Lean Sleep Domain)
CREATE TABLE IF NOT EXISTS public.health_sleep_sessions (
    id text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    local_date date NOT NULL,
    session_type text NOT NULL DEFAULT 'primary_sleep', -- 'primary_sleep', 'nap'
    source_device_key text NOT NULL, -- e.g. 'Apple Watch Ultra 2', 'Pixel Watch 5', 'Oura Ring'
    host_device_name text, -- e.g. 'Schmitz', 'Trapper'
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone NOT NULL,
    duration_seconds integer NOT NULL,
    time_in_bed_seconds integer NOT NULL,
    efficiency_percent double precision,
    sleep_score integer,
    deep_seconds integer DEFAULT 0,
    rem_seconds integer DEFAULT 0,
    light_seconds integer DEFAULT 0,
    awake_seconds integer DEFAULT 0,
    latency_seconds integer DEFAULT 0,
    quality_rating text, -- 'Optimal', 'Good', 'Fair', 'Poor'
    stages jsonb NOT NULL DEFAULT '[]'::jsonb,
    source_priority integer DEFAULT 10,
    is_user_selected boolean DEFAULT false,
    ingested_at timestamp with time zone DEFAULT now(),
    CONSTRAINT uq_health_sleep_session UNIQUE (user_id, local_date, session_type, source_device_key)
);

ALTER TABLE public.health_sleep_sessions ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_sleep_sessions' AND policyname = 'Users can manage own sleep_sessions'
    ) THEN
        CREATE POLICY "Users can manage own sleep_sessions"
        ON public.health_sleep_sessions FOR ALL TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sleep_sessions_user_date 
ON public.health_sleep_sessions (user_id, local_date DESC);

-- Add to Realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'health_sleep_sessions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.health_sleep_sessions;
    END IF;
END $$;

-- 3. Table: health_daily_vitals (1 row per user per day per device)
CREATE TABLE IF NOT EXISTS public.health_daily_vitals (
    id text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    local_date date NOT NULL,
    source_device_key text NOT NULL,
    host_device_name text,
    steps integer DEFAULT 0,
    active_kcal double precision DEFAULT 0,
    resting_heart_rate integer,
    spo2 double precision,
    respiratory_rate double precision,
    skin_temp_celsius double precision,
    weight_kg double precision,
    hrv_sdnn_nightly double precision,
    hrv_rmssd_nightly double precision,
    hourly_steps jsonb DEFAULT '[]'::jsonb,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT uq_health_daily_vitals UNIQUE (user_id, local_date, source_device_key)
);

ALTER TABLE public.health_daily_vitals ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_daily_vitals' AND policyname = 'Users can manage own daily_vitals'
    ) THEN
        CREATE POLICY "Users can manage own daily_vitals"
        ON public.health_daily_vitals FOR ALL TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_daily_vitals_user_date 
ON public.health_daily_vitals (user_id, local_date DESC);

-- Add to Realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'health_daily_vitals'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.health_daily_vitals;
    END IF;
END $$;

-- 4. Table: health_intraday_heart_rate (5-Minute Buckets, max 288 rows/day/device)
CREATE TABLE IF NOT EXISTS public.health_intraday_heart_rate (
    id text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    local_date date NOT NULL,
    source_device_key text NOT NULL,
    bucket_minute smallint NOT NULL, -- 0, 5, 10, ..., 1435
    bpm_avg smallint NOT NULL,
    bpm_min smallint NOT NULL,
    bpm_max smallint NOT NULL,
    sample_count smallint DEFAULT 1,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT uq_health_intraday_hr UNIQUE (user_id, local_date, source_device_key, bucket_minute)
);

ALTER TABLE public.health_intraday_heart_rate ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'health_intraday_heart_rate' AND policyname = 'Users can manage own intraday_hr'
    ) THEN
        CREATE POLICY "Users can manage own intraday_hr"
        ON public.health_intraday_heart_rate FOR ALL TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_intraday_hr_lookup 
ON public.health_intraday_heart_rate (user_id, local_date, source_device_key, bucket_minute);

COMMIT;
