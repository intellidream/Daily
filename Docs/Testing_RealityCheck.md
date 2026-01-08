# Reality Check: Stress Testing & Data Seeder

## Overview
To validate the "Thick Client" architecture, performance, and data consolidation strategy, we implemented a **"Reality Check"** mechanism. This involves seeding the application with 3 years of heavy, realistic usage data (2023-2025) to ensure the system behaves correctly under load.

## 1. Implementation: The Seeder

### Service: `SeederService`
Located in `Services/SeederService.cs`.
*   **Goal:** Generate realistic fake history for "Water" and "Smokes".
*   **Period:** Jan 1, 2023 to Dec 31, 2025 (~1,100 days).
*   **Logic:**
    *   **Water:** Simulates random intake (2-12 cups/day) with timestamps spread throughout waking hours.
    *   **Smokes:** Simulates a "Quitting" trend. Starts at 20 cigs/day in 2023 and linearly decreases to 5/day by late 2025, with daily random noise.
*   **IDs:** Uses `MD5` hashing of the simulated timestamp to generate deterministic GUIDs (fixing `SyncService` compatibility).

### UI Trigger (Hidden)
Located in `Components/Pages/Settings.razor`.
*   **Button:** "Populate History (2023-2025)".
*   **State:** Currently **commented out** (hidden) to prevent accidental clicking in production.
*   **Action:** Injects ~15,000 raw logs into the local SQLite database and immediately triggers a Sync.

## 2. Verification Procedure

### A. Performance Stress Test
1.  **Uncomment** the button in `Settings.razor`.
2.  Click **"Populate History"**.
3.  **Navigate to Habits Detail:**
    *   Confirm the **Heatmap** (120 days) loads instantly.
    *   Confirm the **Water Bubble Chart** (7 days) remains snappy.
    *   Confirm the **History Charts** (Smokes) correctly show the 3-year downward trend.

### B. Sync & Consolidation Test
1.  **Trigger:** The Seeder calls `SyncService.SyncAsync()` immediately after insertion.
2.  **Consolidation:** 
    *   Check `habits_daily_summaries` table (Local & Supabase).
    *   Expect ~1,100 summary rows (one per day).
3.  **Pruning (Data Safety):**
    *   Check `habits_logs` table (Supabase).
    *   **Expectation:** Raw logs older than 90 days (i.e., 2023 and most of 2024) should be **deleted** from Supabase.
    *   **Result:** Only recent raw logs (<90 days) and *all* daily summaries persist in the cloud.

## 3. How to Re-Run
If you need to re-verify or debug in the future:
1.  Open `Components/Pages/Settings.razor`.
2.  Search for `Populate History`.
3.  Uncomment the `<MudButton>` block.
4.  Run the app and click the button.
