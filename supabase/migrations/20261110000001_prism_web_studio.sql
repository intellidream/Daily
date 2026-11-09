-- Migration: 20261110000001_prism_web_studio.sql
-- Description:
--   Create `public.prism_pinned_sites`, `public.prism_clips`, and private storage bucket `prism-clips`
--   for Prism (Assisted Web & Capture Studio) across iOS, macOS, Android, and Windows 11 (WinUI 3).
--   Designed for Lean Egress (`updated_at` watermarks, minimal B-Tree index footprint, initplan-safe RLS,
--   and on-demand compressed image storage).

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
-- 2. Table: `public.prism_pinned_sites` (Cloud-Synced Speed Dial)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prism_pinned_sites (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title text NOT NULL DEFAULT '',
    url text NOT NULL,
    domain text NOT NULL DEFAULT '',
    icon_url text,
    display_order integer NOT NULL DEFAULT 0,
    is_deleted boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_prism_pinned_sites_user_updated_at
    ON public.prism_pinned_sites (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_prism_pinned_sites_user_order_active
    ON public.prism_pinned_sites (user_id, display_order ASC)
    WHERE is_deleted = false;

DROP TRIGGER IF EXISTS trg_touch_prism_pinned_sites_updated_at ON public.prism_pinned_sites;
CREATE TRIGGER trg_touch_prism_pinned_sites_updated_at
    BEFORE INSERT OR UPDATE ON public.prism_pinned_sites
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

-- ============================================================================
-- 3. Table: `public.prism_clips` (Links, Quotes, Images/Crops, AI Summaries)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.prism_clips (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    clip_type text NOT NULL DEFAULT 'link'
        CHECK (clip_type IN ('link', 'quote', 'image', 'ai_summary')),
    title text NOT NULL DEFAULT '',
    source_url text NOT NULL,
    domain text NOT NULL DEFAULT '',
    content_text text NOT NULL DEFAULT '',
    user_note text NOT NULL DEFAULT '',
    tags text[] NOT NULL DEFAULT '{}'::text[],
    preview_image_url text,
    storage_path text,
    image_width integer,
    image_height integer,
    is_favorite boolean NOT NULL DEFAULT false,
    is_deleted boolean NOT NULL DEFAULT false,
    tagdos_note_id uuid REFERENCES public.tagdos_quick_notes(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_prism_clips_user_updated_at
    ON public.prism_clips (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_prism_clips_user_active_created
    ON public.prism_clips (user_id, created_at DESC)
    WHERE is_deleted = false;

DROP TRIGGER IF EXISTS trg_touch_prism_clips_updated_at ON public.prism_clips;
CREATE TRIGGER trg_touch_prism_clips_updated_at
    BEFORE INSERT OR UPDATE ON public.prism_clips
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_fn_touch_updated_at_utc();

-- ============================================================================
-- 4. Row Level Security (InitPlan-Optimized `(select auth.uid())`)
-- ============================================================================

ALTER TABLE public.prism_pinned_sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prism_clips ENABLE ROW LEVEL SECURITY;

-- Policies for prism_pinned_sites
DROP POLICY IF EXISTS "Users can select own prism_pinned_sites" ON public.prism_pinned_sites;
CREATE POLICY "Users can select own prism_pinned_sites"
    ON public.prism_pinned_sites FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own prism_pinned_sites" ON public.prism_pinned_sites;
CREATE POLICY "Users can insert own prism_pinned_sites"
    ON public.prism_pinned_sites FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own prism_pinned_sites" ON public.prism_pinned_sites;
CREATE POLICY "Users can update own prism_pinned_sites"
    ON public.prism_pinned_sites FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can delete own prism_pinned_sites" ON public.prism_pinned_sites;
CREATE POLICY "Users can delete own prism_pinned_sites"
    ON public.prism_pinned_sites FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

-- Policies for prism_clips
DROP POLICY IF EXISTS "Users can select own prism_clips" ON public.prism_clips;
CREATE POLICY "Users can select own prism_clips"
    ON public.prism_clips FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own prism_clips" ON public.prism_clips;
CREATE POLICY "Users can insert own prism_clips"
    ON public.prism_clips FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own prism_clips" ON public.prism_clips;
CREATE POLICY "Users can update own prism_clips"
    ON public.prism_clips FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can delete own prism_clips" ON public.prism_clips;
CREATE POLICY "Users can delete own prism_clips"
    ON public.prism_clips FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

-- ============================================================================
-- 5. Enable Supabase Realtime Publication Safely
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'prism_pinned_sites'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.prism_pinned_sites;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'prism_clips'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.prism_clips;
    END IF;
END $$;

-- ============================================================================
-- 6. Private Storage Bucket `prism-clips` (On-Demand Compressed Images)
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'prism-clips',
    'prism-clips',
    false,
    10485760,
    ARRAY['image/webp', 'image/jpeg', 'image/png', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Users can upload own prism clips" ON storage.objects;
CREATE POLICY "Users can upload own prism clips"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'prism-clips' AND
        (SELECT auth.uid())::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "Users can view own prism clips" ON storage.objects;
CREATE POLICY "Users can view own prism clips"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'prism-clips' AND
        (SELECT auth.uid())::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "Users can update own prism clips" ON storage.objects;
CREATE POLICY "Users can update own prism clips"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'prism-clips' AND
        (SELECT auth.uid())::text = (storage.foldername(name))[1]
    )
    WITH CHECK (
        bucket_id = 'prism-clips' AND
        (SELECT auth.uid())::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "Users can delete own prism clips" ON storage.objects;
CREATE POLICY "Users can delete own prism clips"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'prism-clips' AND
        (SELECT auth.uid())::text = (storage.foldername(name))[1]
    );

COMMIT;
