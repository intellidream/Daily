-- Migration: 20261105000002_intraday_hr_7d_retention_and_egress.sql
-- Purpose:
--   1. Enforce 7-day rolling retention on `public.health_intraday_heart_rate` inside
--      `public.apply_health_data_retention()` (scheduled daily at 03:00 UTC via `pg_cron`),
--      while preserving 90-day archived `All Devices` cardiovascular curves & zones inside
--      `public.health_daily_summary.summary` and permanent scalar Trends columns.
--   2. Execute `public.apply_health_data_retention()` immediately to purge >7-day intraday HR rows.
--   3. Backfill, default, auto-maintain, and index `updated_at` watermarks on high-frequency sync
--      tables (`habits_daily_summaries`, `habits_logs`, `habits_goals`, `rss_subscriptions`,
--      `rss_saved_articles`, `smart_ledgers`) so incremental delta pulls (`updated_at > lastPull`)
--      never miss rows and never scan full tables.

BEGIN;

-- ============================================================================
-- 1. Update Daily Health Retention Function (7d Intraday HR + 90d Summary JSONB)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- 1. Prune granular 5-minute per-device heart rate buckets older than 7 days.
    --    Historical All-Devices 5-min curves, HR zones, and min/avg/max BPM remain
    --    archived inside public.health_daily_summary.summary.cardiovascular for 90 days.
    DELETE FROM public.health_intraday_heart_rate
    WHERE local_date < (CURRENT_DATE - INTERVAL '7 days')::date;

    -- 2. Compact bulky JSONB summary payloads older than 90 days while preserving all scalar Trends columns.
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;

-- Add date index on health_intraday_heart_rate for O(log N) daily retention sweeps
CREATE INDEX IF NOT EXISTS idx_health_intraday_hr_local_date
    ON public.health_intraday_heart_rate (local_date);

-- Execute retention immediately so existing >7d rows in health_intraday_heart_rate are pruned now
SELECT public.apply_health_data_retention();

-- ============================================================================
-- 2. Guarantee Monotonic `updated_at` Watermarks & Indexes for Incremental Sync
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_fn_touch_updated_at_utc()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

-- 2A. habits_daily_summaries (previously updated_at was NULL on all 2,485 rows)
UPDATE public.habits_daily_summaries
SET updated_at = COALESCE(updated_at, created_at, timezone('utc'::text, now()))
WHERE updated_at IS NULL;

ALTER TABLE public.habits_daily_summaries
    ALTER COLUMN updated_at SET DEFAULT timezone('utc'::text, now());

DROP TRIGGER IF EXISTS trg_touch_habits_daily_summaries_updated_at ON public.habits_daily_summaries;
CREATE TRIGGER trg_touch_habits_daily_summaries_updated_at
    BEFORE INSERT OR UPDATE ON public.habits_daily_summaries
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

CREATE INDEX IF NOT EXISTS idx_habits_daily_summaries_user_updated_at
    ON public.habits_daily_summaries (user_id, updated_at);

-- 2B. habits_logs
UPDATE public.habits_logs
SET updated_at = COALESCE(updated_at, created_at, logged_at, timezone('utc'::text, now()))
WHERE updated_at IS NULL;

ALTER TABLE public.habits_logs
    ALTER COLUMN updated_at SET DEFAULT timezone('utc'::text, now());

DROP TRIGGER IF EXISTS trg_touch_habits_logs_updated_at ON public.habits_logs;
CREATE TRIGGER trg_touch_habits_logs_updated_at
    BEFORE INSERT OR UPDATE ON public.habits_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

CREATE INDEX IF NOT EXISTS idx_habits_logs_user_updated_at
    ON public.habits_logs (user_id, updated_at);

-- 2C. habits_goals
UPDATE public.habits_goals
SET updated_at = COALESCE(updated_at, created_at, timezone('utc'::text, now()))
WHERE updated_at IS NULL;

ALTER TABLE public.habits_goals
    ALTER COLUMN updated_at SET DEFAULT timezone('utc'::text, now());

DROP TRIGGER IF EXISTS trg_touch_habits_goals_updated_at ON public.habits_goals;
CREATE TRIGGER trg_touch_habits_goals_updated_at
    BEFORE INSERT OR UPDATE ON public.habits_goals
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

CREATE INDEX IF NOT EXISTS idx_habits_goals_user_updated_at
    ON public.habits_goals (user_id, updated_at);

-- 2D. rss_subscriptions
UPDATE public.rss_subscriptions
SET updated_at = COALESCE(updated_at, created_at, timezone('utc'::text, now()))
WHERE updated_at IS NULL;

ALTER TABLE public.rss_subscriptions
    ALTER COLUMN updated_at SET DEFAULT timezone('utc'::text, now());

DROP TRIGGER IF EXISTS trg_touch_rss_subscriptions_updated_at ON public.rss_subscriptions;
CREATE TRIGGER trg_touch_rss_subscriptions_updated_at
    BEFORE INSERT OR UPDATE ON public.rss_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

CREATE INDEX IF NOT EXISTS idx_rss_subscriptions_user_updated_at
    ON public.rss_subscriptions (user_id, updated_at);

-- 2E. rss_saved_articles
UPDATE public.rss_saved_articles
SET updated_at = COALESCE(updated_at, created_at, timezone('utc'::text, now()))
WHERE updated_at IS NULL;

ALTER TABLE public.rss_saved_articles
    ALTER COLUMN updated_at SET DEFAULT timezone('utc'::text, now());

DROP TRIGGER IF EXISTS trg_touch_rss_saved_articles_updated_at ON public.rss_saved_articles;
CREATE TRIGGER trg_touch_rss_saved_articles_updated_at
    BEFORE INSERT OR UPDATE ON public.rss_saved_articles
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

CREATE INDEX IF NOT EXISTS idx_rss_saved_articles_user_updated_at
    ON public.rss_saved_articles (user_id, updated_at);

-- 2F. smart_ledgers
UPDATE public.smart_ledgers
SET updated_at = COALESCE(updated_at, created_at, timezone('utc'::text, now()))
WHERE updated_at IS NULL;

ALTER TABLE public.smart_ledgers
    ALTER COLUMN updated_at SET DEFAULT timezone('utc'::text, now());

DROP TRIGGER IF EXISTS trg_touch_smart_ledgers_updated_at ON public.smart_ledgers;
CREATE TRIGGER trg_touch_smart_ledgers_updated_at
    BEFORE INSERT OR UPDATE ON public.smart_ledgers
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

COMMIT;
