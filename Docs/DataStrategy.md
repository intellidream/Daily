# Data Strategy: Bubbles & Smokes (Local-First)

## Executive Summary
Since we are bypassing server-side aggregation (Edge Functions), our strategy relies on **"Thick Client" Aggregation**. We utilize the device's powerful CPU and the local SQLite database to perform all statistical calculations in real-time. Supabase acts solely as a synchronization backplane for raw data.

## 1. Data Architecture

### Storage
*   **Raw Logs:** Every single "bubble" popped or "smoke" logged is stored as a row in the local SQLite `habits_logs` table.
*   **Sync:** These raw rows are synced bi-directionally with Supabase.
*   **Zero Server Compute:** We do **not** ask Supabase to calculate averages or sums. We only ask for the raw rows.

### Performance & Volume
*   **Capacity:** SQLite can easily handle 500,000+ rows (equivalent to ~50 years of heavy tracking) with sub-millisecond query times on modern phones/desktops, *provided we index correctly*.
*   **Indexing:** We must ensure `habits_logs` has a composite index on `[HabitType, LoggedAt]` to make historical queries instant.

## 2. Specific Feature Strategies

### A. Bubbles (Hydration/Habit Frequency)
*   **Goal:** Show daily counts/volume and streaks.
*   **Implementation:**
    *   *Daily View:* `SELECT SUM(Value) FROM habits_logs WHERE HabitType = 'bubbles' AND date(LoggedAt) = date('now')`
    *   *History/Heatmap:* `SELECT date(LoggedAt), SUM(Value) FROM habits_logs WHERE HabitType = 'bubbles' GROUP BY date(LoggedAt)`

### B. Smokes (Cessation & Reduction)
*   **Goal:** Show reduction over time, money saved, health timelines.
*   **Implementation:**
    *   *Baseline:* Stored in `UserPreferences` (`SmokesBaselineDaily`, `PackCost`).
    *   *Money Saved:* `(Baseline * DaysSinceQuit) - (ActualSmokedCount)` * `CostPerCigarette`.
    *   *Aggregation:* Calculate `Count(Id)` per day locally.

## 3. Scale & Consolidation Strategy (The Limit Fix)
**Problem:** 10,000 users generating 20 logs/day = ~11GB/year. This exceeds the Supabase Free Tier (500MB).
**Solution:** A "Rolling Window" retention policy with **Historical Consolidation**.

### The "90-Day Raw" Rule
We only keep **RAW** logs (individual bubbles/smokes) in Supabase for the last 90 days. Data older than 90 days is **Summarized** into a single row per day, and the raw logs are deleted from the cloud.

### New Table: `habits_daily_summaries`
*   `user_id`
*   `habit_type`
*   `date` (Date only)
*   `total_value` (Sum of volume/count)
*   `log_count` (Number of events)
*   `metadata` (Optional, JSON summary like "most frequent drink")

### The Protocol (Client-Driven)
Clients perform "Housekeeping" during sync:
1.  **Check:** Client identifies local data older than 90 days that isn't summarized yet.
2.  **Summarize:** Client calculates the `DailySummary` row locally.
3.  **Push:** Client uploads the `DailySummary` to Supabase.
4.  **Prune:** Client sends a `DELETE` request for the raw logs of that specific day to Supabase.
    *   *Safety:* Raw logs are NOT deleted from the local device (unless user clears storage), maintaining "thick client" detail locally.
    *   *Reinstall:* A fresh install fetches the `habits_daily_summaries` table to rebuild the history visualization instantly (Heatmap/Charts), then fetches only recent raw logs.

### Storage Savings Math
*   **Raw:** 10k users * 90 days * 20 rows/day * 150 bytes = **~2.7 GB** (Manageable "Rollover" size, might need cleanup cron for inactive users).
*   **Summarized:** 10k users * 365 days * 2 rows/day * 50 bytes = **~365 MB/year**.
*   **Impact:** This strategy fits a large userbase into improved tiers or reasonable Pro limits, whereas raw storage would scale infinitely.

## 4. Why this is better than Edge Functions
1.  **Offline First:** Charts work on an airplane. Deep history works without signal.
2.  **Privacy:** You aren't running analysis code on the server.
3.  **Cost:** Minimizes Supabase Compute hours. You pay only for storage/bandwidth.
4.  **Flexibility:** You can change how you calculate "Money Saved" in a simpler C# update without deploying new SQL functions.
