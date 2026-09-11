# Feature: iOS Habits — Bubbles (Hydration) & Smokes (Tobacco Cessation)

This document details the architecture, clinical and behavioral protocols, offline synchronization mechanics, HealthKit integration, and Liquid Glass visual implementation of the **Habits Tracker** feature for the native DayOne iOS application and its shared multiplatform foundation (`DailyCore`).

---

## 1. Executive Summary & Design Goals

The Habits Tracker implements full parity with the DayOne WinUI 3 desktop application and companion smartwatch ecosystem (watchOS, WearOS, HarmonyOS, ZeppOS) while embracing native iOS 26/27 design language:

| Feature Dimension | DayOne WinUI 3 Implementation | DayOne iOS / DailyCore Implementation |
| :--- | :--- | :--- |
| **Response Latency** | Network-dependent or async database write. | **0ms Instant Feedback**: Writes immediately to local App Group cache (`group.com.intellidream.daily`), updates UI reactively, then queues background Supabase synchronization. |
| **Offline Resilience** | Limited offline queueing. | **Durable Offline Queue**: Serialized FIFO disk queue with automatic retry, exponential backoff, and idempotent deduplication. |
| **Apple Health Integration** | N/A (Windows platform). | **HealthKit Dietary Water**: Automatic background write sync for `HKQuantityTypeIdentifier.dietaryWater` with millilitre-to-liter metric conversion. |
| **Hydration Science** | Simple total ml counter. | **Circadian Diurnal Timing**: 5-slot circadian hydration schedule, Drink Hydration Index (DHI/BHI), and clinical Armstrong 4-tier urine hydration assessment. |
| **Smoking Cessation** | Counter and basic financial savings. | **4D Craving Emergency Protocol**: Real-time 5-minute craving countdown timer (Delay, Deep Breathe, Drink Water, Distract), 6-stage clinical recovery milestones, and live "Craving-Free" duration counter. |
| **Visual Design** | Desktop card layouts with WinUI Mica/Acrylic. | **Tactile Liquid Glass Design**: Dynamic double sine-wave fluid animation for Bubbles; chromatic lungs silhouette with radial arc gauge for Smokes; 120-day GitHub-style consistency heatmap. |

---

## 2. Architecture & Data Flow

```mermaid
graph TD
    User(["User Tap (Preset / Quick Log)"]) --> Cache["Local Fast Cache (UserDefaults: group.com.intellidream.daily)"]
    Cache --> UI["SwiftUI Views (0ms Re-render)"]
    
    User --> HKSync{"Water Logged?"}
    HKSync -- Yes --> HK["Apple HealthKit (HKQuantityTypeIdentifier.dietaryWater)"]
    
    User --> Q["Offline Queue (Disk Serialized)"]
    Q --> NetCheck{"Network Connected?"}
    NetCheck -- Yes --> SB["Supabase PostgREST (habits_logs, habits_goals)"]
    NetCheck -- No (Offline) --> Retry["Retain in Queue & Flush on Reconnect"]
    
    SB --> Realtime["Realtime / Fetch Remote Changes"]
    Realtime --> Core["DailyCore: HabitsService (MainActor)"]
    Core --> HeatmapEngine["120-Day Heatmap & 7-Day Trend Engine"]
    HeatmapEngine --> HabitsViews["HabitsHub & Dashboard Card"]
```

### 2.1 Storage & Synchronization Layers

1. **Layer 0 — In-Memory State**: Managed by `@MainActor public final class HabitsService: ObservableObject` in `DailyCore`. Publishes reactive properties (`waterTotalToday`, `waterProgressPercent`, `smokesTotalToday`, `smokesFinancials`, `sevenDayHistory`, `consistencyHeatmap`).
2. **Layer 1 — App Group Shared Cache (`group.com.intellidream.daily`)**: Provides instant local hydration across app launches, shared between iOS main app, future WidgetKit extensions, and watchOS companion.
3. **Layer 2 — Durable Offline Queue**: Persists unsynced log operations as JSON in `habits_offline_queue.json`. Automatically flushes when online, ensuring no logs are lost in poor connectivity.
4. **Layer 3 — Cloud Persistence (Supabase PostgREST)**:
   - `habits_logs`: `id`, `user_id`, `habit_type` (`"water"` | `"smokes"`), `amount`, `unit`, `logged_at`, `notes`, `metadata` (JSONB storing preset, drink type, nicotine mg, cigarette type).
   - `habits_goals`: `user_id`, `habit_type`, `daily_goal`, `baseline_daily_count`, `target_reduction_pct`, `price_per_pack`, `items_per_pack`, `currency`.

---

## 3. Bubbles (Hydration) Module

### 3.1 Multi-Liquid Fluid Wave Simulation (`WaterProgressWaveView`)
The Bubbles hero card renders a circular Liquid Glass gauge with an interactive fluid simulation:
- **Multi-Liquid Stratification**: Partitions the consumed liquid column into physical fluid layers based on exact consumption volume and beverage type:
  - **Water Layer (Bottom)**: Standard drinking water, bottles, and glasses rendered in vivid cyan/deep ocean blue (`#00E5FF` to `#0077B6`).
  - **Tea Layer (Middle)**: Herbal tea and infusions rendered in matcha/herbal green (`#84CC16` to `#3F6212`).
  - **Coffee Layer (Top)**: Espresso and coffee rendered in warm roast amber with crema highlights (`#F59E0B` to `#92400E`).
- **Harmonic Sine Waves**: Every fluid interface (both internal beverage boundaries and top surface) undulates independently with sine wave harmonics and 3D parallax back-waves.
- **Proportional Segmented Outer Rim**: The circular border track is divided into distinct color-coded segments matching each beverage's proportion of the total intake.
- **In-Circle Breakdown Ticker**: A frosted glass capsule (`HabitCircleBreakdownTicker`) nestled under the status badge displays the exact totals per liquid (e.g. `💧 1500 ml • ☕️ Coffee 200 ml`).
- **Goal Completion FX**: Upon reaching 100% of the target, an ambient emerald aura and gold star badge illuminate with tactile haptic feedback.

### 3.2 Quick Presets & Custom Intake
- **Standard Vessels**: 150ml (Small Cup), 250ml (Glass), 300ml (Mug), 500ml (Bottle).
- **Beverage Variations**: 100ml Espresso/Coffee, 250ml Herbal Tea.
- **Custom Logger**: Interactive modal sheet allowing free-form milliliter entry and custom drink categorization.

### 3.3 Circadian Diurnal Schedule
Based on circadian renal dynamics and cellular hydration research, hydration is broken into 5 diurnal slots:
1. **Morning Wake-Up (07:00 – 09:00)**: 500ml recommended to kickstart metabolism and replace nocturnal fluid loss.
2. **Mid-Morning Focus (10:00 – 12:00)**: 500ml for sustained cognitive performance and blood volume maintenance.
3. **Afternoon Energy (13:00 – 15:00)**: 500ml to prevent postprandial fatigue and dehydration headache.
4. **Evening Hydration (16:00 – 18:00)**: 400ml to support evening physical activity recovery.
5. **Pre-Bed Wind-Down (19:00 – 21:00)**: 200ml gentle intake to avoid nocturia and disrupted sleep cycles.

### 3.4 Drink Hydration Index (DHI / BHI)
Incorporates clinical Drink Hydration Index values relative to still water ($1.00$):
- **Still Water**: $1.00$ (Optimal baseline)
- **Electrolyte Solution / Oral Rehydration**: $1.50$ (Superior cellular retention)
- **Milk**: $1.50$ (High electrolyte, protein and fat content delays gastric emptying)
- **Herbal Tea**: $0.98$ (Near-identical to water)
- **Black Coffee**: $0.85$ (Mild diuretic effect at higher doses)
- **Caffeinated Energy Drinks / Alcohol**: $< 0.70$ (Requires supplemental hydration)

### 3.5 Armstrong 4-Tier Urine Hydration Chart
Clinical self-assessment reference:
- **Pale / Light Yellow**: Optimal hydration ($\le 1.010$ specific gravity).
- **Straw Yellow**: Well hydrated.
- **Amber / Honey**: Mild dehydration (trigger +250ml intake).
- **Dark Brown / Amber**: Severe dehydration (immediate fluid replenishment required).

---

## 4. Smokes (Tobacco Cessation & Reduction) Module

### 4.1 Lungs Silhouette & Biological Color Degradation (`SmokesLungsGaugeView`)
Visualizes tobacco consumption relative to the user's daily baseline with anatomical feedback:
- **Vector Anatomical Silhouette**: Features detailed lobes, trachea, and internal bronchial airway tree branches (`VectorLungsBronchiShape`).
- **Biological Color Degradation (Healthy Pink to Diseased Gray)**:
  - **Radiant Healthy Pink (`#FF6B8B`)**: Displayed at 0 cigarettes (smoke-free today), reflecting healthy, oxygenated pulmonary tissue.
  - **Dusky Rose (`#D77D91`)**: Subtly desaturates as the user logs initial cigarettes ($1\% - 35\%$ of baseline).
  - **Sickly Ashen Gray (`#78716C`)**: Appears as intake reaches moderate levels ($35\% - 75\%$ of baseline).
  - **Cold Unwholesome Lead Gray (`#4B5563`)**: Fully envelopes lung tissue as intake approaches the baseline threshold ($75\% - 100\%$).
  - **Diseased Soot Charcoal (`#27272A`)**: Darkens with a toxic smoky outline when consumption exceeds the baseline ceiling ($> 100\%$).
- **Segmented Gauge Track Arc**: Proportional multi-colored active gauge arc along the circular rim displaying the relative ratio of cigarette types (Cigarettes, Heated Tobacco, Rolled, Cigarillos).
- **In-Circle Breakdown Ticker**: A frosted glass capsule (`HabitCircleBreakdownTicker`) displaying exact counts per tobacco type (e.g. `11 Cigarillo • 9 Heat`).
- **Live "Craving-Free" Counter**: Computes elapsed duration since the last logged smoke (e.g., `"19m craving-free"`), promoting micro-streaks.

### 4.2 Logging Presets
- **Cigarette** (+1 Standard combustion cigarette)
- **Heated Tobacco** (+1 Heated tobacco stick / TEREA / HEETS)
- **Rolled Tobacco** (+1 Hand-rolled cigarette)
- **Cigarillo / Cigar** (+1 Small cigar)

### 4.3 4D Craving Emergency Protocol
When a craving strikes, tapping the **"4D Craving Emergency"** banner opens an interactive psychological de-escalation protocol:
1. **Delay (5 Minutes)**: Live interactive countdown timer. Most acute dopamine surges subside within 3 to 5 minutes.
2. **Deep Breathe**: 4-7-8 breathing pattern (4s inhale, 7s hold, 8s slow exhale) to activate parasympathetic vagal tone.
3. **Drink Water**: Sipping cold water provides oral substitution and sensory grounding.
4. **Distract**: Shift visual and physical focus (walk, puzzle, call a friend) to reset executive attention.

### 4.4 Clinical Recovery Timeline
Presents scientific evidence-based milestones since quitting/reduction:
- **20 Minutes**: Blood pressure and pulse drop back to normal baseline.
- **8 Hours**: Blood carbon monoxide levels halve, oxygen levels return to normal.
- **24 Hours**: Carbon monoxide eliminated; lungs begin clearing mucus.
- **48 Hours**: Nicotine eliminated from body; taste and smell nerve endings regenerate.
- **72 Hours**: Bronchial tubes relax, breathing becomes noticeably easier.
- **2 to 12 Weeks**: Circulation throughout extremities and overall lung function improve up to 30%.

### 4.5 Financial & Longevity Metrics Engine
Computes real-time economic and physiological recovery:
- **Money Saved**: $(\text{Baseline} - \text{Logged}) \times \frac{\text{Pack Price}}{\text{Items per Pack}}$.
- **Cigarettes Avoided**: Cumulative avoided units over tracking periods.
- **Life Regained**: Based on epidemiological estimates ($11\text{ minutes of life preserved per avoided cigarette}$).

---

## 5. Analytics & Consistency Heatmap

### 5.1 7-Day Performance Bar Chart
- Compares daily intake or cigarette counts over the last 7 consecutive calendar days.
- Renders an overlay dashed line representing the target goal or baseline limit.
- Dynamically colors bars matching daily achievement (Cyan for water goal met; Emerald for smoking under baseline).

### 5.2 120-Day Consistency Heatmap
- GitHub-style contributions grid organized into 17 weekly columns $\times$ 7 day rows ($119 - 120$ days).
- 5 discrete visual intensity levels:
  - `Level 0`: Inactive / No data logged.
  - `Level 1`: $1 - 49\%$ of goal / minimal activity.
  - `Level 2`: $50 - 79\%$ of goal.
  - `Level 3`: $80 - 99\%$ of goal.
  - `Level 4`: $100\%+$ of goal (Peak achievement / smoke-free).

---

## 6. Dashboard Integration & Navigation

1. **Dashboard Live Card (`HabitsDashboardCard`)**:
   - Title: `"Habits & Cravings"` with clean subheaders `"BUBBLES"` and `"SMOKES"`.
   - Displays real-time hydration volume vs. goal and daily smoke count vs. baseline limit.
   - Provides 5 compact one-tap quick action chips: `[💧 300]`, `[💧 150]`, `[☕ 100]`, `[🚬 Cig]`, `[⚡ Heat]` directly from the primary dashboard screen without navigating away.
   - Smooth navigation tap transitioning directly to the Habits hub.
2. **Floating Glass Capsule (`FloatingGlassCapsule`)**:
   - Added sixth tab item: `.habits = "Habits"` with system icon `"drop.fill"`.
   - Compacted spacing and font metrics to fit 6 tabs comfortably on all modern iPhones (from iPhone SE up to iPhone 17 Pro Max).

---

## 7. Refinements, Bug Fixes & Architectural Enhancements (v1.1)

### 7.1 Multiplier Intake & Deletion Parity
- **Multipliers**: Supports quick logging multipliers `1x`, `2x`, `3x`, `5x` directly above the Quick Action grid.
- **Dynamic Values**: Preset buttons dynamically update their labels (e.g. `+200 ml` or `+2 Logs`) reflecting the active multiplier.
- **Log Formatting**: Entries display formatted titles such as `2× Coffee (+200 ml)` or `3× Cigarette (+3)`.
- **Full Deletion**: Deleting a multiplied entry subtracts the full logged volume or count from the day's total and updates the local 120-day historical aggregates.

### 7.2 Specific Beverage & Tobacco Icons
- In log timelines (`HabitLogRow`) and quick actions, items now render their specific icons and colors rather than generic drops or flames:
  - Coffee: `cup.and.saucer.fill` (#F59E0B)
  - Tea: `mug.fill` (#10B981)
  - Bottle: `waterbottle.fill` (#00F0FF)
  - Heated Tobacco: `bolt.fill` (#3B82F6)
  - Rolled: `leaf.fill` (#F97316)
  - Cigarette: `flame.fill` (#EF4444)
  - Cigarillo: `flame` (#A855F7)

### 7.3 Supabase `user_preferences` Sync & Settings Section
- **Database Schema**: Syncs with Supabase `user_preferences` table (`smokes_baseline`, `smokes_pack_size`, `smokes_pack_cost`, `smokes_currency`, `smokes_quit_date`, `water_goal`).
- **Settings UI**: Added dedicated "TOBACCO & SMOKES REDUCTION" section in `FeaturesSettingsSection` allowing full configuration of daily baseline, pack size, pack cost, and currency, with real-time sync across devices.
- **Hydration Target Sync**: Adjusting hydration target in Settings immediately updates `HabitsService` and synchronizes to `habits_goals` and `user_preferences`.

### 7.4 Historical Date Context Attribution
- Fixed date context attribution: When browsing a past date in the calendar, logged items are attributed to that specific date (preserving the current time of day) rather than defaulting to today's date.

### 7.5 Separate Precalculated 7-Day & 120-Day Histories
- Maintained separate precalculated collections for Water and Smokes (`waterSevenDayHistory`, `smokesSevenDayHistory`, `waterConsistencyHeatmap`, `smokesConsistencyHeatmap`).
- Cached in App Group `userDefaults` (`group.com.intellidream.daily`) for 0ms instant display upon app launch.
- Batch queries 120 days of historical logs from Supabase in a single network request to accurately hydrate the GitHub-style consistency heatmaps.

### 7.6 Native iOS Pull-to-Refresh & Desktop Cleanup
- Added native `.refreshable` to `DashboardView` (refreshing Weather, Health, Habits, and News in parallel) and `HabitsMainView`.
- Removed legacy desktop-style static refresh buttons from `WeatherDetailView` and `HealthMainView` headers.

### 7.7 Collapsible Logs, Dynamic Title & Resilient Watch-Parity Historical Ingestion
- **Standardized Cigarette Icon**: Aligned Cigarette icon to `flame.fill` across dashboard chips, log timelines, and `SmokePreset.cigarette`.
- **Collapsible Logs Timeline**: Relocated daily logs timeline immediately beneath the Quick Logging Grid. Defaults to collapsed with entry count readout and smooth spring disclosure animation.
- **Dynamic Header Title**: Replaced static header with contextual title: `"TODAY'S LOGS"`, `"YESTERDAY'S LOGS"`, or `"[DATE] LOGS"` (e.g. `10 SEP LOGS`).
- **Resilient Multiplatform Ingestion**: Introduced `FlexibleDouble`, `AnyCodableScalar`, `HabitLogMetadataHelper`, and `HabitHistoricalLogItem` to prevent malformed rows from discarding 120-day historical batches.
- **App Group Week Cache Interop**: Bi-directionally synchronizes `bubbles_week_cache` and `smokes_week_cache` with WatchOS so the 7-day trend and watch complications stay perfectly in sync.

---

### 7.8 Server-Side RPC Consistency & Dual-Table Historical Architecture
- **Root Cause Resolution for Incomplete Data & Missing Days**:
  - Investigated the Supabase database and WinUI reference implementation (`Services/HabitsService.cs`, `supabase/migrations/habits_rpc_functions.sql`, `Docs/DataStrategy.md`).
  - Older historical habit data in DayOne is stored across two tables: consolidated daily summaries in `habits_daily_summaries` (`id`, `user_id`, `habit_type`, `date`, `total_value`, `log_count`) and recent granular logs in `habits_logs`.
  - Previously, iOS was only querying `habits_logs`, resulting in permanent holes and missing historical days in 7-Day Performance and the Consistency Heatmap unless a user navigated to a specific day.
- **`get_habits_consistency` RPC Integration**:
  - Integrated Supabase RPC function `get_habits_consistency(p_habit_type, p_start_date, p_end_date)` in `DailyCore`.
  - Automatically unions `raw` (`habits_logs`) and `summaries` (`habits_daily_summaries`) server-side with raw logs overriding summary aggregates for the same day.
- **Bulletproof Dual-Table Direct Fallback**:
  - If RPC fails, network is constrained, or offline, `HabitsService` automatically queries both `habits_daily_summaries` and `habits_logs` concurrently, merging them client-side with raw log precedence.
- **112-Day / 16 Full Weeks Alignment**:
  - Aligned heatmap range to 112 days (exactly 16 columns of 7 squares each), eliminating incomplete weeks and shifting weekday rows.
  - 7-Day Performance chart consistently anchors to the 7 days ending Today (`today - 6` through `today`).
- **Chromatic Scale Correction for Smokes**:
  - Fixed smoke heatmap intensity levels to properly reflect consumption:
    - Level 0 (0 cigs / smoke-free): Dark neutral
    - Level 1 (< 50% baseline): Emerald Green (great discipline)
    - Level 2 (50% - 80% baseline): Amber Yellow (moderate)
    - Level 3 (80% - 100% baseline): Warm Orange (near baseline limit)
    - Level 4 (> 100% baseline): Crimson Red (exceeded limit)
- **`get_smokes_financials` RPC Integration**:
  - Accurately computes lifetime cigarettes avoided and money saved across the entire quit journey (`p_since_date`) by combining raw logs and daily summaries.

---

## 8. Verification & Automated Test Coverage

The feature is verified with unit tests in `DailyCoreTests/HabitsServiceTests.swift`:
- `Smoke Presets Validation`: Verified baseline counts, types, and nicotine metrics.
- `Water Presets Validation`: Verified standard volume values and beverage types.
- `Offline Queue JSON Round-Trip Serialization`: Verified disk serialization, FIFO extraction, and schema stability.
- `Habit Log Record Metadata Parsing`: Verified JSONB deserialization for custom volumes and timestamps.
- `Smokes Financials & Avoided Cigarettes Calculations`: Verified pack price, currency formatting, and life regained formulas.
- `Habits Guidance Protocol Validation`: Verified circadian slots, DHI indices, Armstrong color levels, and 4D step structures.
- `Multiplier Logging and Display Formatting`: Verified multiplier calculations and formatted string display.
- `Specific Icons & Colors for Beverage and Tobacco Types`: Verified correct icon resolution for coffee, tea, bottles, heated tobacco, and cigarettes (`flame.fill`).
- `User Preferences Record JSON Decoding`: Verified round-trip parsing of Supabase `user_preferences` schema.
- `Habits Consistency Row Decoding & Date Normalization`: Verified JSON decoding of `get_habits_consistency` RPC responses, FlexibleDouble round-trip serialization, and date normalization.
- `Habit Date Parser Date-Only String Parsing`: Verified that date-only strings (`yyyy-MM-dd`) are properly parsed to valid `Date` objects.
- **Full Suite Status**: All tests in `DailyCore` pass 100% green. Build visually verified on `SimulaPhone` with screenshots (zero holes, full 7-day and 16-week data) and deployed to physical iPhone 16 Pro ("Schmitz").


