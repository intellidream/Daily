-- ==============================================================================
-- DayOne Orbit: Direct-to-Cloud Wearable Architecture Schema
-- ==============================================================================

-- 1. Create health_telemetry table
-- This table stores the raw time-series data batched from the watches.
CREATE TABLE public.health_telemetry (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  type TEXT NOT NULL, -- e.g., 'steps', 'heart_rate', 'active_energy'
  value DOUBLE PRECISION NOT NULL,
  unit TEXT,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  source_device TEXT, -- e.g., 'Apple Watch Series 9', 'Pixel Watch 2'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast queries
CREATE INDEX idx_health_telemetry_user_time ON public.health_telemetry (user_id, start_time DESC);

-- Enable RLS
ALTER TABLE public.health_telemetry ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can insert their own telemetry" ON public.health_telemetry FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can read their own telemetry" ON public.health_telemetry FOR SELECT USING (auth.uid() = user_id);

-- ==============================================================================

-- 2. Create health_vitals table
-- This table aggregates telemetry data per day (paralleling the existing vitals table).
CREATE TABLE public.health_vitals (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  type TEXT NOT NULL,
  value DOUBLE PRECISION NOT NULL,
  unit TEXT,
  date DATE NOT NULL,
  source_device TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT health_vitals_user_date_type_key UNIQUE (user_id, date, type)
);

-- Enable RLS
ALTER TABLE public.health_vitals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can insert/update their own health_vitals" ON public.health_vitals FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ==============================================================================

-- 3. Create watch_pairing_codes table
-- Stores the temporary 6-digit PIN used to pair a watch.
CREATE TABLE public.watch_pairing_codes (
  pin_code VARCHAR(6) PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  access_token TEXT,
  refresh_token TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '10 minutes',
  claimed BOOLEAN DEFAULT FALSE
);

-- Enable RLS
ALTER TABLE public.watch_pairing_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can create their own pairing codes" ON public.watch_pairing_codes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can read their own pairing codes" ON public.watch_pairing_codes FOR SELECT USING (auth.uid() = user_id);
-- Allow updating (claiming) the pin if it isn't expired or already claimed.
CREATE POLICY "Watches can claim a PIN code" ON public.watch_pairing_codes FOR UPDATE USING (NOT claimed AND expires_at > NOW());

-- ==============================================================================

-- 4. Database Trigger: Aggregate Telemetry to Vitals
-- Automatically sums up cumulative metrics (like steps) or averages spot metrics (like heart_rate)
-- per day into the health_vitals table whenever a new telemetry row is inserted.

CREATE OR REPLACE FUNCTION aggregate_health_telemetry_to_vitals()
RETURNS TRIGGER AS $$
DECLARE
  v_date DATE;
  v_new_value DOUBLE PRECISION;
BEGIN
  -- Determine the local date for the user. (For simplicity, using UTC date of start_time)
  v_date := DATE(NEW.start_time);

  -- Determine aggregation strategy based on type
  IF NEW.type IN ('steps', 'active_energy', 'basal_energy', 'distance') THEN
    -- Cumulative Metrics: sum them up
    INSERT INTO public.health_vitals (user_id, type, value, unit, date, source_device, updated_at)
    VALUES (NEW.user_id, NEW.type, NEW.value, NEW.unit, v_date, NEW.source_device, NOW())
    ON CONFLICT (user_id, date, type)
    DO UPDATE SET 
      value = public.health_vitals.value + EXCLUDED.value,
      source_device = EXCLUDED.source_device,
      updated_at = NOW();

  ELSIF NEW.type IN ('heart_rate', 'respiratory_rate', 'hrv', 'weight') THEN
    -- Spot Metrics: Last Write Wins (can be modified to average if preferred)
    INSERT INTO public.health_vitals (user_id, type, value, unit, date, source_device, updated_at)
    VALUES (NEW.user_id, NEW.type, NEW.value, NEW.unit, v_date, NEW.source_device, NOW())
    ON CONFLICT (user_id, date, type)
    DO UPDATE SET 
      value = EXCLUDED.value,
      source_device = EXCLUDED.source_device,
      updated_at = NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_aggregate_health_telemetry
AFTER INSERT ON public.health_telemetry
FOR EACH ROW
EXECUTE FUNCTION aggregate_health_telemetry_to_vitals();
