# Feature: Health & Vitals (Sensor Sync & Trends)

The Health feature aggregates and visualizes biometric data (vitals) using a "Mobile-as-Bridge" cloud-truth architecture. It integrates with native phone OS health stores (Apple HealthKit and Google Health Connect), synchronizes data to Supabase, and exposes details across mobile and desktop apps.

---

## 1. Functional Specification

### 1.1 Mobile-as-Bridge Vitals Synchronization
Health tracking operates on a bridge pattern:
- **Mobile Sensor Ingestion**: The mobile apps run background tasks to query native sensor stores (iOS HealthKit or Android Health Connect). They synchronize these metrics to the cloud database (`vitals` table) via `SyncNativeHealthDataAsync()`.
- **Universal Cloud Truth**: All platforms (including Mac, Windows, and Web) read their vitals directly from the Supabase database. There is no local health store on desktops; instead, they display cloud truth.

### 1.2 Metric Types & Categories
Aggregates and organizes 35+ metrics into structured categories:
- **Activity**: Steps, Active Energy, Basal Energy, Distance, Floors Climbed, Walking Speed, Running Speed, Cycling Power, Cycling Cadence, Workout Duration.
- **Heart & Vitals**: Heart Rate, Resting Heart Rate, Heart Rate Variability (SDNN/RMSSD), Respiratory Rate, Blood Pressure (Systolic & Diastolic), Blood Glucose, Oxygen Saturation (SpO2), Body Temperature, Basal Body Temperature.
- **Body Composition**: Weight, Body Fat Percentage, Lean Body Mass, Height, Bone Mass, BMI.
- **Nutrition (Macros & Micros)**: Carbohydrates, Fat, Protein, Caffeine, Sugar, Water (Hydration), and micronutrients (Magnesium, Zinc, Calcium, Iron, Vitamin C, Vitamin A).
- **Sleep & Mindfulness**: Sleep Duration, Sleep Stages (Deep, Light/Core, REM, Awake), and Mindful Session duration.

### 1.3 Source Attribution & Diagnostics
- **Source Origin Visuals**: The UI displays small colored dots next to each biometric metric indicating which platform synced the data:
  - **Blue** (`#2979FF`): iOS / HealthKit
  - **Green** (`#00E676`): Android / Health Connect
  - **Pink** (`#E91E63`): Manual entry
  - **Grey**: Mixed/Unknown
- **Dominant Source Heuristics**: The "Today" header evaluates the list of active vitals using a dominant majority algorithm (if $\ge 70\%$ of the metrics come from one platform, the header dot matches that platform; otherwise, it displays grey).
- **Sync Status**: Displays relative timestamps indicating when the biometric sync occurred (e.g. "Synced 5m ago"), falling back to row update times if sync logs are unavailable.

### 1.4 Historical Trends (Past 7 Days)
- **6-Metric Trends Catalog**: Displays trends for Steps, Heart Rate, Sleep, Active Energy (Calories), Weight, and Heart Rate Variability (HRV).
- **Incomplete Day Filtering**: To prevent today's incomplete/in-progress metrics (e.g. partial step counts) from skewing the graph downward, the trend calculations explicitly query and display data for the **past 7 completed days**, skipping the current day.
- **Vitals Stats Grid**: Under each line graph, a compact stats panel displays key historical statistics:
  - **Steps / Calories**: AVG, HIGH, LOW, and TOTAL.
  - **Heart Rate / Sleep / Weight / HRV**: AVG, HIGH, LOW, and TODAY's latest value.
- **Daily Capsule Bar Charts**: Under the stats panel, a custom daily breakdown shows a horizontal list of 7 vertical capsule bars representing daily totals/values:
  - Cumulative metrics (Steps, Calories, Sleep) are scaled linearly against the maximum value in the range.
  - Spot/fluctuating metrics (Heart Rate, Weight, HRV) are normalized using a range-based formula `((val - min) / (max - min)) * 50.0` clamped between 15% and 100% height to emphasize relative daily fluctuations rather than absolute zeros.

### 1.5 Granular Health Telemetry Data (Smartwatches & Continuous Sensors)
- **Multi-Device Telemetry Ingestion**: Captures high-frequency time-series biometrics directly from smartwatches and sensors:
  - **Apple Watch**: Synchronized via `HealthTelemetryManager.swift` in `DailyWatchApp`, pushing discrete metrics to Supabase `health_telemetry`.
  - **Zepp OS (Amazfit)**: Ingested via native Zepp OS app companion scripts.
  - **Direct/Manual Telemetry**: Extensible to additional wearable platforms and automated test suites.
- **Resilient Multi-Format Normalization (`HealthTelemetry.cs`)**:
  - Raw records in Supabase use snake_case, lowercase, or PascalCase formats (`"heart_rate"`, `"steps"`, `"sleep"`, `"sleep_stage_deep"`, `"sleep_stage_rem"`, `"sleep_stage_awake"`).
  - The `HealthTelemetry` domain model exposes robust computed properties:
    - `NormalizedType`: Trims whitespace, underscores, and lowers case.
    - `IsHeartRate`: Identifies heart rate records (`"heartrate"`, `"hr"`).
    - `IsSteps`: Identifies step records (`"steps"`, `"stepcount"`).
    - `IsSleep`: Identifies sleep segments (`"sleep..."`).
    - `SleepCategory`: Accurately classifies sleep stages into `"Deep"`, `"REM"`, `"Awake"`, and `"Core"` (light).
    - `DurationSeconds`: Derives accurate segment durations from either `(EndTime - StartTime)` or `Value` with flexible units (`hours`, `minutes`, `seconds`).
    - `LocalStartTime` & `LocalEndTime`: Normalizes UTC database timestamps into the local timezone for accurate "Today" boundaries and chart time axes.
    - `NumericValue`: Provides null-safe double representation for chart bindings.
- **Health Telemetry Widget (`HealthTelemetryWidget`)**:
  - High-level telemetry card providing today's total steps, total sleep duration, and real-time heart rate sparkline.
  - Interactive header action allows users to open the full detail window.
  - Subscribes to `IRefreshService.HealthRefreshRequested` to reactively update on new data inserts.
- **Detailed Telemetry View (`HealthTelemetryDetailPage` / `HealthTelemetryDetail.razor`)**:
  - **Clinical 4-Level Sleep Hypnogram**: Multi-tier hypnogram graphing Awake, REM, Light/Core, and Deep stages with an hourly X-axis and duration tooltips.
  - **Sleep Architecture Metrics**: Real-time display of Sleep Score (0-100), Sleep Efficiency %, Time Asleep vs. In Bed, Bedtime/Wake times, and Awake Count.
  - **Heart Rate Zones Breakdown**: Rest, Fat Burn, Cardio, and Peak zone distribution with continuous intraday telemetry.
  - **Hourly Step Cadence**: Hourly step cadence bar distribution and active hours count.
  - **Raw Telemetry Log**: Interactive data table displaying timestamped telemetry entries with device attribution.

### 1.6 Date Isolation, Sleep Clustering & Day Navigation
- **Multi-Day Data Separation**: Prior versions of the application suffered from cross-day metric bleeding where sleep from prior days or sensor telemetry over 30+ hours were displayed on the same timeline. The system now enforces strict temporal boundaries:
  - **Cumulative Metrics (Steps, Calories, Distance, Floors, Hydration)**: Strictly filtered to `[targetDate, targetDate + 1 day)`.
  - **Persistent Snapshot Metrics (Weight, Height, Body Fat, Blood Pressure, Glucose)**: Displayed as snapshot values; if not measured on `SelectedDate`, they carry an `IsHistorical = true` badge indicating the measurement date.
  - **Nocturnal Sleep Clustering (`SleepSession.cs`)**:
    - Sleep belongs to the morning of the day the user wakes up. Telemetry is queried for `[targetDate.AddDays(-1).AddHours(18), targetDate.AddHours(16)]`.
    - Stage records separated by $\ge 90$ minutes of continuous absence are automatically clustered into distinct sessions (`SleepSession`).
    - The primary nocturnal session is identified (longest duration or nighttime overlap) and separate daytime naps (`IsNap = true`) are isolated.
    - Full-screen views offer session switcher chips allowing the user to inspect each session independently without multi-day timeline stretching.
  - **Universal Day Navigator**: Detail pages (`HealthDetail.razor`, `HealthTelemetryDetail.razor`, `HealthDetailPage.xaml`, `HealthTelemetryDetailPage.xaml`) feature an interactive top navigation bar (`[ ◀ ] [ Date Label ] [ ▶ ]` + `Jump to Today`) powered by `IHealthService.SelectedDate` and `OnSelectedDateChanged`.

### 1.7 High-Density Widget Redesign
Both MAUI Blazor Hybrid and WinUI controls (`HealthWidget`, `HealthWidgetControl`, `HealthTelemetryWidget`, `HealthTelemetryWidgetControl`) feature a clinical, high-density layout:
- **Health Widget**:
  - **Activity Cluster**: Linear progress bar against 10k goal, goal percentage, large steps counter, and compact pills for Kcal, Distance, and Floors.
  - **Sleep Architecture Card**: Sleep score badge, total sleep duration, bedtime/wake time schedule, efficiency percentage, awake count, and a segmented mini-hypnogram stage strip (Deep `#3949AB`, REM `#26C6DA`, Core `#42A5F5`, Awake `#FF7043`) with micro duration badges.
  - **Cardiovascular & Vitals Cluster**: Live heart rate with pulsing indicator, resting HR, HRV, SpO2, respiration rate, wearable stress score, PAI, and blood pressure.
  - **Hydration & Body Snapshot**: Hydration progress bar against 2,500 ml target, weight, and BMI.
- **Health Telemetry Widget**:
  - **Dual Pill**: Steps today vs goal & Sleep last night.
  - **Mini Hypnogram Strip**: Visual breakdown of nocturnal sleep stages.
  - **Intraday Heart Rate Curve & Stats**: BPM sparkline with min-max range, average HR, stress score, PAI, and sample count.

---

## 2. Technical Architecture & Data Model

### 2.1 Services & Device Bridges
- `IHealthService` / `SupabaseHealthService`: Manages loading today's vitals, fetching historical trend logs, tracking view states (`CurrentViewType`), notifying subscribers via `OnViewTypeChanged`, and writing manual logs.
- `INativeHealthStore`: Platform interface wrapping native OS health APIs.
- `MockNativeHealthStore` / `MockHealthService`: Desktop implementation for offline prototyping and UI development.
- **iOS HealthKit (`HealthKitService.cs`)**: Coordinates read queries for 35+ `HKObjectType` types.
- **Android Health Connect (`HealthConnectService.cs`)**: Reflection-based bridge fetching records from Android's Health Connect SDK.

### 2.2 Sync Merge Strategy
- **Cumulative Metrics** (e.g., Steps, Calories, Water): **Max Wins** — preserves the higher value between the local device total and the remote database total to prevent double-counting.
- **Spot Metrics** (e.g., Heart Rate, Weight, Blood Pressure): **Last Write Wins** — updates the value using the most recent timestamp.
- **Backfill**: Sync routines scan and upload data for both `Today` and `Yesterday` to account for offline logging.
- **Cache Resilience, Realtime Re-authentication & Manual Refreshes**: Queries check for local cache staleness every 15 minutes before running remote updates. On wake/network reconnection, the service locks duplicate execution using semaphores. Expired JWT leases trigger `EnsureFreshSessionAsync()` to proactively restore authorization. The service listens to the `TokenRefreshed` auth state, updating the Realtime client authentication (`SetAuth(token)`) and force-recreating the Postgres changes channel (`_vitalsChannel` & `_telemetryChannel`) to prevent silent connection dropouts. Manual dashboard refreshes bypass the 15-minute staleness check to force-await `PullDeltasAsync()` and reload the UI immediately. Window wake/restoration (`ShowAndActivate()`) triggers a background session verify, catch-up pull, and widget refresh.

### 2.3 Database Schema

#### Supabase `vitals` Table (Daily Aggregated Vitals)
```sql
CREATE TABLE public.vitals (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  type TEXT NOT NULL,
  value DOUBLE PRECISION NOT NULL,
  unit TEXT,
  date DATE NOT NULL,
  source_device TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ,
  CONSTRAINT vitals_user_date_type_key UNIQUE (user_id, date, type)
);
-- RLS (Row Level Security) ensures users can only read/write their own vitals.
```

#### Supabase `health_telemetry` Table (High-Frequency Wearable Telemetry)
```sql
CREATE TABLE public.health_telemetry (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  type TEXT NOT NULL,
  value DOUBLE PRECISION,
  unit TEXT,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ,
  source_device TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_health_telemetry_user_time ON public.health_telemetry (user_id, start_time DESC);
```

### 2.4 Realtime Wearable Reactivity
- In addition to daily vitals, `SupabaseHealthService` sets up a dedicated Postgres change listener on the `health_telemetry` table (`realtime_telemetry` channel, filtered by `user_id=eq.{userId}`).
- When a smartwatch syncs a new heart rate sample, step count, or sleep stage record:
  1. The Realtime event fires on `_telemetryChannel`.
  2. `OnTelemetryReceived` invokes `_refreshService.TriggerHealthRefreshAsync()`.
  3. All active telemetry controls (`HealthTelemetryWidgetControl`, `HealthTelemetryDetailPage`, `HealthTelemetryWidget`, `HealthTelemetryDetail`) receive the refresh request on their respective UI dispatchers and update their models and charts instantly.

---

---

## 3. UI/UX & Layout Architecture

### 3.1 Dual-View Health Architecture
The health experience is cleanly partitioned into two specialized, complementary views across both MAUI Blazor Hybrid and WinUI:

1. **Classic Vitals Dashboard (`vitals` / `HealthDetail.razor` & `HealthDetailPage.xaml`)**:
   - **Activity Hero**: Large steps counter, circular active energy (Kcal) ring, total sleep duration, distance km, floors climbed, and walking speed.
   - **Vitals Grid**: Real-time tiles for Heart Rate (bpm), Weight (kg), Secondary vitals (RHR, Resp, SpO2, Blood Glucose), Body Composition (Body Fat %, BMI, Lean Mass), Sleep breakdown (Deep, Light, REM, Awake), Mindfulness, Temperature, and Hydration.
   - **7-Day Historical Trend Charts**: 6-metric trends catalog (Steps, Heart Rate, Sleep, Active Energy, Weight, HRV) complete with stats grid (Avg, High, Low, Total/Today) and 7 daily capsule bars.
   - **Diagnostics & Sync Logs**: Native sync logs, source attribution, and device platform origin badges.

2. **Wearable Sensors & Telemetry View (`HealthTelemetry` / `HealthTelemetryDetail.razor` & `HealthTelemetryDetailPage.xaml`)**:
   - **Universal Day Navigator**: `[ ◀ ] [ Today, Sun Sep 6 ] [ ▶ ]` + `Jump to Today` button for inspecting any individual day without cross-day metric bleeding.
   - **Clinical 4-Level Hypnogram**: Continuous hypnogram bounded strictly to the nocturnal sleep session (Bedtime to Wake time) displaying Awake (`#FF7043`), REM (`#26C6DA`), Light/Core (`#42A5F5`), and Deep (`#3949AB`) with hourly timeline ticks and stage percentage bars.
   - **Sleep Architecture Metrics**: Sleep Score (0-100), Sleep Efficiency %, Time Asleep (strictly Deep + Light + REM; Awake excluded), Time In Bed, Bed/Wake times, Awake Count, and Restorative Sleep (Deep + REM %).
   - **Daytime Naps**: Explicitly segregated into distinct nap session cards so they never distort nocturnal sleep metrics.
   - **Continuous Intraday Heart Rate**: Full intraday BPM curve with Min, Max, Avg, and RHR.
   - **Heart Rate Intensity Zones**: Rest, Fat Burn, Cardio, and Peak zone distribution bars and minutes.
   - **Biometric Stress & PAI**: Stress score (0-100) with color indicators and Personal Activity Intelligence (PAI) score.
   - **Hourly Step Cadence**: Hourly step cadence bar distribution and active hours counter.
   - **Raw Telemetry Log**: Interactive data table displaying timestamped telemetry records with source device attribution.

### 3.2 Companion Widgets
1. **Vitals Widget (`HealthWidget.razor` & `HealthWidgetControl.xaml`)**:
   - Compact summary of daily activity (Steps, Kcal, HR), nocturnal sleep summary with 4-stage bar, and cardiovascular essentials (HRV, RHR, Resp, SpO2). Tapping navigates to Vitals (`vitals`).
2. **Health Telemetry Widget (`HealthTelemetryWidget.razor` & `HealthTelemetryWidgetControl.xaml`)**:
   - Steps today vs goal, nocturnal sleep duration & score, segmented mini-hypnogram stage strip, intraday heart rate sparkline, stress index, and PAI. Tapping navigates to Health Telemetry (`HealthTelemetry`).

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **Aggregated Vitals UI** | Native XAML Controls (`HealthWidgetControl.xaml` & `HealthDetailPage.xaml`) | Blazor Hybrid Razor components (`HealthWidget.razor` & `HealthDetail.razor`) |
| **Telemetry Widget** | Native XAML (`HealthTelemetryWidgetControl.xaml` / `.xaml.cs`) with Canvas mini-hypnogram strip | Blazor component (`HealthTelemetryWidget.razor`) with SVG mini-hypnogram strip |
| **Telemetry Detail View** | Native XAML Page (`HealthTelemetryDetailPage.xaml` / `.xaml.cs`) with Canvas 4-level hypnogram | Dedicated Razor Page (`HealthTelemetryDetail.razor` hosted via `DetailPane.razor`) |
| **Sleep Hypnogram Drawing** | Custom code-behind drawing on WinUI Canvas (`DrawSleepHypnogram`), rendering hourly vertical grid lines, stage rectangles, and text ticks | Responsive SVG with 4 stage bands, hourly vertical grid markers, dynamic time ticks, and hover tooltips |
| **Realtime Dispatching** | `DispatcherQueue.TryEnqueue` invoking `LoadDataAsync()` | `InvokeAsync(StateHasChanged)` with `IDisposable` event unsubscription |
| **Vitals Store** | `MockHealthService.cs` or queries Supabase database for synced data | Hooks into iOS `HealthKitService` and Android `HealthConnectService` native libraries |
| **XAML Compatibility** | Strict WinUI 3 XAML without unsupported properties like `Cursor` on `Border` elements | MudBlazor CSS styling |
| **Manual Logs** | Desktop manual logging modals using standard WinUI XAML dialogs | MudBlazor forms and dialog overlays |
| **Charts & Visualizers** | Canvas hypnograms, custom Gantt/bar visualizers, and XAML progress rings | MudBlazor chart visualizers (`MudChart` line/bar), SVG hypnograms, and CSS progress bars |

