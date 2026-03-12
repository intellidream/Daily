-- Health Feature Improvements Migration
-- Run this on Supabase SQL Editor

-- 1. Add synced_at column to vitals table (tracks local device time when metric was synced)
ALTER TABLE public.vitals ADD COLUMN IF NOT EXISTS synced_at timestamptz;
