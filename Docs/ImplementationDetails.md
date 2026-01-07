# Implementation Details

## Overview
This document outlines the key technical implementations for the Daily application features including Heatmaps, Data Logic, and Synchronization.

## 1. Feature: Heatmap Visualization
*   **Location:** `HabitsDetail.razor`
*   **Logic:**
    *   **Data Source:** `HabitsService.GetHistoryAsync` fetches `DailySummary` objects for the last 120 days.
    *   **Data Aggregation:** Raw logs are aggregated locally in `HabitsRepository`.
    *   **UI:** Custom CSS Grid/Flexbox implementation using `MudTooltip` for interactivity.
    *   **Scales:**
        *   **Water (Consistency):** Blue Scale (Light to Dark based on % of Goal).
        *   **Smokes (Intensity):** Green-to-Red Scale (Green=Good/0, Red=Bad/High).

## 2. Feature: Background Synchronization Service
*   **Location:** `SyncService.cs`
*   **Architecture:**
    *   Bi-directional sync with Supabase using "Last Last-Write-Wins" (Upsert) strategy at the row level.
    *   **Background Timer:** Runs every 60 seconds (when app is active/foreground in .NET MAUI lifecycle).
    *   **Push:** Uploads dirty local records (`SyncedAt == null`).
    *   **Pull:** Downloads new remote records.

## 3. Remote Log Pruning (Cost Management)
To manage Supabase storage limits:
*   **Protocol:** "90-Day Raw Retention"
*   **Consolidation:** Old raw logs (>90 days) are summarized into `DailySummary` rows.
*   **Pruning:** Once a `DailySummary` is synced to Supabase, the `SyncService` triggers a DELETE command for raw `HabitLog` entries for that day.
*   **Safety:** Pruning strictly checks `Min(90Days, LatestSummaryDate)` to ensure no un-summarized data is lost.

## 4. Code Structure & Refactoring
*   **Mappers:** Centralized in `Services/Mappers.cs` as Extension Methods to prevent duplication between Repository and SyncService.
*   **Repository:** `HabitsRepository` handles all local SQLite interactions and logic migration (e.g. Guest -> User).
*   **Sync:** `SyncService` handles all Supabase interactions and consolidation logic.

## 5. UI Components
*   **MudBlazor:** Primary UI library.
*   **Custom Widgets:** `Heatmap`, `DateFilmStrip`, `SystemInfoWidget`.
