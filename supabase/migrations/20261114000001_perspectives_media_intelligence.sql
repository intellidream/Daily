-- Migration: 20261114000001_perspectives_media_intelligence.sql
-- Description:
--   Lean Cloud Infrastructure for Daily News "Perspectives", "Blindspots", "Source Transparency",
--   and "Media Diet" across macOS, iOS, Android, and Windows 11 (WinUI 3).
--
--   Strict Storage & Egress Guarantees:
--     1. Zero raw RSS articles or ephemeral clusters stored in PostgreSQL.
--     2. Zero new `supabase_realtime` WebSocket publication tables (0 WAL / Realtime fan-out).
--     3. `public.media_outlet_profiles`: Global delta catalog (~0 KB/day egress via 24h `updated_at` watermark).
--     4. `public.news_perspective_cache`: Shared 72h AI comparison cache auto-pruned daily at 03:00 UTC by `pg_cron`.
--     5. `public.news_reading_stats`: Single aggregated JSONB row per user per month (`YYYY-MM`, ~350 B/month),
--        InitPlan-safe RLS `((SELECT auth.uid()) = user_id)`, written with `Prefer: return=minimal`.

BEGIN;

-- ============================================================================
-- 1. Ensure Monotonic UTC `updated_at` Trigger Function Exists
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_fn_touch_updated_at_utc()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
    NEW.updated_at := timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

-- ============================================================================
-- 2. Table: `public.media_outlet_profiles` (Global Delta Overrides Catalog)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.media_outlet_profiles (
    domain text PRIMARY KEY,
    name text NOT NULL,
    aliases text[] NOT NULL DEFAULT '{}'::text[],
    bias text NOT NULL DEFAULT 'center'
        CHECK (bias IN ('left', 'lean_left', 'center', 'lean_right', 'right', 'independent_creator', 'unrated')),
    bias_context text NOT NULL DEFAULT '',
    factuality text NOT NULL DEFAULT 'high'
        CHECK (factuality IN ('very_high', 'high', 'mixed', 'low')),
    ownership_type text NOT NULL DEFAULT 'corporation'
        CHECK (ownership_type IN (
            'independent',
            'non_profit',
            'public_broadcaster',
            'corporation',
            'conglomerate',
            'billionaire_individual',
            'private_equity',
            'state_affiliated'
        )),
    owner_label text NOT NULL DEFAULT '',
    country_code text NOT NULL DEFAULT 'INT',
    editorial_note text NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_media_outlet_profiles_updated_at
    ON public.media_outlet_profiles (updated_at DESC);

DROP TRIGGER IF EXISTS trg_touch_media_outlet_profiles_updated_at ON public.media_outlet_profiles;
CREATE TRIGGER trg_touch_media_outlet_profiles_updated_at
    BEFORE INSERT OR UPDATE ON public.media_outlet_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

ALTER TABLE public.media_outlet_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can select media_outlet_profiles" ON public.media_outlet_profiles;
CREATE POLICY "Authenticated users can select media_outlet_profiles"
    ON public.media_outlet_profiles FOR SELECT
    TO authenticated
    USING (true);

-- ============================================================================
-- 3. Table: `public.news_perspective_cache` (Shared 72h Multi-Source AI Synthesis)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.news_perspective_cache (
    cluster_hash text PRIMARY KEY,
    story_title text NOT NULL DEFAULT '',
    summary_text text NOT NULL DEFAULT '',
    common_facts jsonb NOT NULL DEFAULT '[]'::jsonb,
    framing_differences jsonb NOT NULL DEFAULT '[]'::jsonb,
    omissions jsonb NOT NULL DEFAULT '[]'::jsonb,
    language_code text NOT NULL DEFAULT 'en',
    source_count integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_news_perspective_cache_created_at
    ON public.news_perspective_cache (created_at);

DROP TRIGGER IF EXISTS trg_touch_news_perspective_cache_updated_at ON public.news_perspective_cache;
CREATE TRIGGER trg_touch_news_perspective_cache_updated_at
    BEFORE INSERT OR UPDATE ON public.news_perspective_cache
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

ALTER TABLE public.news_perspective_cache ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can select news_perspective_cache" ON public.news_perspective_cache;
CREATE POLICY "Authenticated users can select news_perspective_cache"
    ON public.news_perspective_cache FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert news_perspective_cache" ON public.news_perspective_cache;
CREATE POLICY "Authenticated users can insert news_perspective_cache"
    ON public.news_perspective_cache FOR INSERT
    TO authenticated
    WITH CHECK (char_length(cluster_hash) BETWEEN 8 AND 128);

DROP POLICY IF EXISTS "Authenticated users can update news_perspective_cache" ON public.news_perspective_cache;
CREATE POLICY "Authenticated users can update news_perspective_cache"
    ON public.news_perspective_cache FOR UPDATE
    TO authenticated
    USING (char_length(cluster_hash) BETWEEN 8 AND 128)
    WITH CHECK (char_length(cluster_hash) BETWEEN 8 AND 128);

-- ============================================================================
-- 4. Table: `public.news_reading_stats` (1 Row / Month / User Media Diet)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.news_reading_stats (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    year_month text NOT NULL CHECK (char_length(year_month) = 7),
    counts jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_news_reading_stats_user_month UNIQUE (user_id, year_month)
);

CREATE INDEX IF NOT EXISTS idx_news_reading_stats_user_updated_at
    ON public.news_reading_stats (user_id, updated_at DESC);

DROP TRIGGER IF EXISTS trg_touch_news_reading_stats_updated_at ON public.news_reading_stats;
CREATE TRIGGER trg_touch_news_reading_stats_updated_at
    BEFORE INSERT OR UPDATE ON public.news_reading_stats
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

ALTER TABLE public.news_reading_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can select own news_reading_stats" ON public.news_reading_stats;
CREATE POLICY "Users can select own news_reading_stats"
    ON public.news_reading_stats FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own news_reading_stats" ON public.news_reading_stats;
CREATE POLICY "Users can insert own news_reading_stats"
    ON public.news_reading_stats FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own news_reading_stats" ON public.news_reading_stats;
CREATE POLICY "Users can update own news_reading_stats"
    ON public.news_reading_stats FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can delete own news_reading_stats" ON public.news_reading_stats;
CREATE POLICY "Users can delete own news_reading_stats"
    ON public.news_reading_stats FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

-- ============================================================================
-- 5. Extend Daily `pg_cron` Retention Function (Preserve 7d HR + 90d Summary + Add 72h Perspective Cache)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- 1. Prune granular 5-minute per-device heart rate buckets older than 7 days.
    DELETE FROM public.health_intraday_heart_rate
    WHERE local_date < (CURRENT_DATE - INTERVAL '7 days')::date;

    -- 2. Compact bulky JSONB summary payloads older than 90 days while preserving all scalar Trends columns.
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;

    -- 3. Prune ephemeral AI multi-perspective comparison cache older than 72 hours.
    DELETE FROM public.news_perspective_cache
    WHERE created_at < (timezone('utc'::text, now()) - INTERVAL '72 hours');
END;
$$;

COMMIT;
