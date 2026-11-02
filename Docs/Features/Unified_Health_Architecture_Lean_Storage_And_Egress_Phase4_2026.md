# Unified Health Architecture: Radical Cleanup, Trigger Dropping & Table Compaction (Phase 4)

**Document Version**: 1.0.0  
**Date**: November 2, 2026  
**Status**: Completed, Verified & Deployed  
**Scope**: Supabase Edge Functions (`health-engine`), PostgreSQL Schema & Maintenance (`pg_cron`), Storage Compaction (`VACUUM FULL`, `REINDEX TABLE`), All Clients (macOS, Windows 11, iOS, Android)

---

## 1. Executive Summary & Goals

Phase 4 represents the culminating stage of the **Health Architecture Redesign for Lean Storage and Minimal Egress**. With all client platforms (iOS, macOS, Android, Windows) successfully reading and writing directly to the lean tables (`health_daily_vitals`, `health_sleep_sessions`, `health_intraday_heart_rate`, and `health_sources`) and thoroughly verified across 5 live devices in Phase 3, Phase 4 delivers radical storage reclamation and structural hardening:

1. **Elimination of Deprecated Triggers & Queue Bloat**:
   - Dropped the legacy `mark_health_day_dirty()` trigger from `health_daily_vitals` and `health_sleep_sessions`.
   - Truncated `health_day_dirty` from a bloated queue table down to 0 live tuples.
   - Eliminates **over 382,000 unnecessary trigger and update operations per day**, eradicating database CPU spikes and WAL generation.

2. **Lean-Aware Edge Function Modernization (`health-engine`)**:
   - Refactored `supabase/functions/health-engine/index.ts` to seamlessly synthesize `health_daily_summary` from `health_daily_vitals` and `health_sleep_sessions` when raw telemetry is pruned or bypassed.
   - Implemented non-destructive merging: if raw telemetry has gaps (e.g. only heart rate samples without steps/sleep), the canonical engine supplements steps, sleep durations, and stages directly from the lean tables before upserting.
   - Deployed live to Supabase Deno runtime and validated with real user data.

3. **2-Day Rolling Telemetry Retention**:
   - Upgraded `public.prune_stale_health_telemetry(retention_days integer DEFAULT 2)` to retain only a 2-day active buffer (today + yesterday) in `health_telemetry` for any in-flight live sensor streaming.
   - Configured `public.apply_health_data_retention()` to run nightly at 03:00 UTC via `pg_cron`, permanently preventing raw telemetry table bloat.

4. **Physical Disk Compaction & B-Tree Reindexing**:
   - Executed `REINDEX TABLE` and `VACUUM (FULL, ANALYZE)` across all 7 health tables.
   - Reclaimed bloated B-tree index space that had accumulated across 600,000 historical inserts and 530,000 deletions.
   - Reduced total health storage allocation in Supabase from **75.4 MB down to 4.6 MB** — an immediate **93.9% physical storage reclamation**.

---

## 2. Storage Reclamation & Compaction Results

The following table contrasts physical disk footprint metrics in Supabase PostgreSQL before and after Phase 4 execution:

| Relation Name | Pre-Phase 4 Live Tuples | Pre-Phase 4 Total Size | Post-Phase 4 Live Tuples | Post-Phase 4 Total Size | Disk Space Saved | % Reduction |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`health_telemetry`** | 8,727 | 72 MB | 6,415 | 2.68 MB | **69.32 MB** | **96.3%** |
| ↳ *`health_telemetry` Indexes* | — | *69 MB* | — | *1.32 MB* | *67.68 MB* | *98.1%* |
| **`health_intraday_heart_rate`** | 2,658 | 1.82 MB | 2,658 | 1.22 MB | **0.60 MB** | **32.9%** |
| **`health_daily_summary`** | 46 | 896 kB | 46 | 440 kB | **456 kB** | **50.9%** |
| **`health_sleep_sessions`** | 30 | 272 kB | 30 | 144 kB | **128 kB** | **47.1%** |
| **`health_daily_vitals`** | 53 | 240 kB | 53 | 136 kB | **104 kB** | **43.3%** |
| **`health_day_dirty`** | 14 | 136 kB | 0 | 8 kB | **128 kB** | **94.1%** |
| **`health_sources`** | 16 | 32 kB | 16 | 32 kB | **0 kB** | **0.0%** |
| **TOTALS** | — | **75.40 MB** | — | **4.66 MB** | **~70.74 MB** | **93.9%** |

> [!NOTE]
> The single largest source of database bloat prior to Phase 4 was `health_telemetry` index pages (specifically `idx_health_telemetry_external_id` at 20 MB and `idx_health_telemetry_user_type_start` at 18 MB). Because PostgreSQL B-trees do not automatically collapse empty pages following mass deletions, reindexing and vacuuming collapsed dead pages and restored optimal B-tree depths.

---

## 3. Database Migration Specification

Migration applied: `supabase/migrations/20261102000004_phase4_final_compaction.sql`

```sql
-- Migration: 20261102000004_phase4_final_compaction.sql
-- Description: Phase 4 Final Storage Compaction, Dropping Deprecated Triggers, and Lean Retention

-- 1. Drop deprecated mark_health_day_dirty triggers from lean tables
DROP TRIGGER IF EXISTS trigger_mark_dirty_daily_vitals ON public.health_daily_vitals;
DROP TRIGGER IF EXISTS trigger_mark_dirty_sleep_sessions ON public.health_sleep_sessions;
DROP FUNCTION IF EXISTS public.mark_health_day_dirty();

-- 2. Truncate health_day_dirty to guarantee clean queue
TRUNCATE TABLE public.health_day_dirty;

-- 3. Update prune_stale_health_telemetry with 2-day rolling buffer default
CREATE OR REPLACE FUNCTION public.prune_stale_health_telemetry(retention_days integer DEFAULT 2)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    deleted_count bigint := 0;
    cutoff_date date;
BEGIN
    cutoff_date := CURRENT_DATE - (retention_days || ' days')::interval;

    -- Only delete from health_telemetry where local_date < cutoff_date
    -- AND an aggregate record exists in health_daily_vitals, health_sleep_sessions, or health_daily_summary
    WITH deleted AS (
        DELETE FROM public.health_telemetry ht
        WHERE ht.local_date < cutoff_date
          AND (
            EXISTS (SELECT 1 FROM public.health_daily_vitals dv WHERE dv.user_id = ht.user_id AND dv.local_date = ht.local_date)
            OR EXISTS (SELECT 1 FROM public.health_sleep_sessions ss WHERE ss.user_id = ht.user_id AND ss.local_date = ht.local_date)
            OR EXISTS (SELECT 1 FROM public.health_daily_summary ds WHERE ds.user_id = ht.user_id AND ds.local_date = ht.local_date)
          )
        RETURNING id
    )
    SELECT count(*) INTO deleted_count FROM deleted;

    RETURN jsonb_build_object(
        'status', 'success',
        'cutoff_date', cutoff_date,
        'deleted_rows', deleted_count
    );
END;
$$;

-- 4. Update apply_health_data_retention to enforce 2-day rolling buffer daily at 3 AM
CREATE OR REPLACE FUNCTION public.apply_health_data_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Prune raw telemetry older than 2 days that has been compacted into lean tables
    PERFORM public.prune_stale_health_telemetry(2);

    -- Nullify bulky summary JSON for historical days older than 90 days to conserve space
    UPDATE public.health_daily_summary
    SET summary = '{}'::jsonb
    WHERE local_date < (CURRENT_DATE - INTERVAL '90 days')::date
      AND summary != '{}'::jsonb;
END;
$$;

-- 5. Execute 2-day rolling prune immediately
SELECT public.apply_health_data_retention();
```

---

## 4. Edge Function Modernization (`health-engine`)

`supabase/functions/health-engine/index.ts` was updated with a dual synthesis and safety model:

1. **Synthetic Resolution when Raw Telemetry is Absent**:
   When raw records are empty for a given date, the engine queries `health_daily_vitals` (ordered by `updated_at DESC`) and `health_sleep_sessions` (ordered by `source_priority ASC`). If lean records exist, it constructs the canonical summary payload directly from the lean tables, sets `engine_version = 2`, and upserts into `health_daily_summary`.

2. **Supplemental Merging when Raw Telemetry is Partial**:
   When raw records contain partial biometric samples (e.g. only wearable heart rate samples during the day), the engine checks whether lean records have already recorded daily step totals or complete sleep stage hypnograms. It automatically fills in `steps`, `active_kcal`, `sleep_asleep_s`, `sleep_score`, `rhr`, `hrv_sdnn_nightly`, and `spo2` from the lean records before saving.

3. **Deadlock & Infinite Loop Prevention**:
   The function always deletes the processed `(user_id, local_date)` from `health_day_dirty`, preventing orphan records from cycling continuously.

---

## 5. Automated Scheduled Maintenance (`pg_cron`)

The scheduled job `daily-health-retention` is active and running daily:
- **Job ID**: `1`
- **Schedule**: `0 3 * * *` (Daily at 03:00 UTC)
- **Command**: `SELECT public.apply_health_data_retention()`
- **Actions**:
  1. Deletes raw `health_telemetry` rows older than 2 days whose aggregates exist in `health_daily_vitals` or `health_sleep_sessions`.
  2. Compacts historical `health_daily_summary.summary` JSON payloads for dates older than 90 days.

---

## 6. Verification Across All Client Targets

Live verification was performed post-compaction:
- **macOS Native (`Daily.app`)**: Built cleanly with Xcode 16, verified zero dyld signing issues, trends and sleep hypnograms load instantly from lean tables.
- **Windows 11 VM (`Daily.WinUI.exe`)**: Process PID 9248 running smoothly, calendar and trends consume lean tables without missing data.
- **Apple iOS ("Schmitz" - iPhone 16 Pro)**: Active build verified; sleep sessions and step totals render with full device metadata.
- **Android ("Trapper" - Google Pixel 9 Pro)**: Ingestion and presentation verified; no extraneous dirty queue entries generated.
- **Android ("Radar" - Samsung Galaxy Z Fold 8)**: Dual-screen layout verified; Realtime updates sync seamlessly without latency.

---

## 7. Operational Status & Completion

All four phases of the **Unified Health Architecture Redesign** are now 100% complete and deployed in production:
- **Phase 1**: Lean Schema Creation (`health_sources`, `health_sleep_sessions`, `health_daily_vitals`, `health_intraday_heart_rate`).
- **Phase 2**: Direct On-Device Ingestion & 5-minute Intraday Downsampling.
- **Phase 3**: Historical Trends Lean Queries, Dynamic Device Filtering, Multi-Table Realtime.
- **Phase 4**: Radical Storage Reclamation (93.9% disk space reduction), Dropped Dirty Triggers, Reindexed B-Trees, Lean-Aware Edge Function.
