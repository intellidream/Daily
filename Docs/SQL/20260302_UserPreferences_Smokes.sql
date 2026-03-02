-- Add missing columns to user_preferences for Smokes Configuration and Weather settings

ALTER TABLE public.user_preferences
ADD COLUMN IF NOT EXISTS wind_unit text DEFAULT 'km/h',
ADD COLUMN IF NOT EXISTS visibility_unit text DEFAULT 'km',
ADD COLUMN IF NOT EXISTS precipitation_unit text DEFAULT 'mm',
ADD COLUMN IF NOT EXISTS notifications_enabled boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS daily_forecast_alert boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS precipitation_alert boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS smokes_baseline integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS smokes_pack_size integer DEFAULT 20,
ADD COLUMN IF NOT EXISTS smokes_pack_cost numeric DEFAULT 0,
ADD COLUMN IF NOT EXISTS smokes_currency text DEFAULT 'USD',
ADD COLUMN IF NOT EXISTS smokes_quit_date timestamp with time zone;
