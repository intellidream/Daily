# Health Feature Details

> Reference document for the Health/Vitals feature architecture, data flow, and implementation details.

## Architecture Overview

The Health feature uses a **"Mobile-as-Bridge"** pattern:

1. **iOS** (HealthKit) and **Android** (Health Connect) fetch health data locally on phones
2. Mobile devices **sync** data to **Supabase** (`vitals` table) via `SyncNativeHealthDataAsync()`
3. **All platforms** (iOS, Android, Mac, Windows) **read from Supabase** for UI display ("Cloud Truth")
4. A `MockNativeHealthStore` provides fallback for platforms without native health stores (Desktop)

```
┌─────────┐     ┌───────────────┐     ┌──────────┐     ┌─────────────┐
│ HealthKit│────▶│SupabaseHealth │────▶│ Supabase │◀────│HealthConnect│
│  (iOS)   │     │   Service     │     │ (Cloud)  │     │  (Android)  │
└─────────┘     └───────────────┘     └──────────┘     └─────────────┘
                       │                     │
                       ▼                     ▼
                 HealthWidget.razor    HealthDetail.razor
```

## Data Model

### VitalMetric (`Models/Health/VitalMetric.cs`)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | References `auth.users` |
| `type` | text | `VitalType` enum as string (e.g., "Steps", "HeartRate") |
| `value` | double | Metric value |
| `unit` | text | Unit string (e.g., "count", "bpm", "min") |
| `date` | date | Day the metric belongs to (midnight) |
| `source_device` | text | "iOS", "Health Connect", or "Manual" |
| `created_at` | timestamptz | Row creation time (UTC) |
| `updated_at` | timestamptz | Last update time (UTC) |
| `synced_at` | timestamptz | Local device time when synced to Supabase |

**Unique constraint**: `(user_id, date, type)` — one metric per type per day per user.

### VitalType Enum

Organized into categories:

- **Activity**: Steps, ActiveEnergy, BasalEnergyBurned, Distance, FloorsClimbed, WalkingSpeed, RunningSpeed, CyclingPower, CyclingCadence, WorkoutDuration
- **Heart & Vitals**: HeartRate, RestingHeartRate, HeartRateVariabilitySDNN, HeartRateVariabilityRMSSD, RespiratoryRate, BloodPressureSystolic, BloodPressureDiastolic, BloodGlucose, OxygenSaturation, BodyTemperature, BasalBodyTemperature
- **Body**: Weight, BodyFatPercentage, LeanBodyMass, Height, BodyMassIndex, BoneMass
- **Nutrition**: Carbs, Fat, Protein, Caffeine, Sugar, VitaminC, VitaminA, Iron, Magnesium, Zinc, Calcium, Hydration
- **Sleep**: SleepDuration, SleepAwake, SleepDeep, SleepLight, SleepREM
- **Cycle**: MenstruationFlow, OvulationTest, SexualActivity
- **Mindfulness**: MindfulSession

## Platform Coverage

### iOS HealthKit (`Platforms/iOS/HealthKitService.cs`)

Fetches **30+ metric types** using `HKStatisticsQuery` and `HKSampleQuery`:

| Category | Metrics | Aggregation |
|----------|---------|-------------|
| Activity | Steps, ActiveEnergy, BasalEnergy, Distance, FloorsClimbed, WalkingSpeed, CyclingPower | SUM/AVG |
| Heart | HeartRate, RestingHeartRate, HRV (SDNN), RespiratoryRate | AVG |
| Clinical | BloodPressure (Correlation), BloodGlucose, SpO2, BodyTemp | AVG |
| Body | Weight, BodyFat, LeanBodyMass, Height | AVG/Latest |
| Sleep | SleepDuration + stages (Deep, Light/Core, REM, Awake) | SUM |
| Nutrition | Carbs, Fat, Protein, Caffeine, Sugar, VitC, Iron, Magnesium, Zinc, Calcium, Water | SUM |
| Other | MenstruationFlow, MindfulSession | Count/SUM |

**Permission**: `RequestPermissionsAsync()` requests read access for all fetched types (35+ `HKObjectType` entries).

### Android Health Connect (`Platforms/Android/HealthConnectService.cs`)

Fetches **30+ metric types** using the reflection-based `ReadRecordsInternal<T>()` pattern:

| Category | Metrics | Notes |
|----------|---------|-------|
| Activity | Steps, Calories, Distance, FloorsClimbed, Speed, Power, BasalMetabolicRate | Reflection bridge |
| Heart | HeartRate, RestingHeartRate, HRV (RMSSD), RespiratoryRate | Sample-based |
| Clinical | BloodPressure, BloodGlucose, SpO2, BodyTemp, BasalBodyTemp | |
| Body | Weight, BodyFat, LeanBodyMass, Height, BoneMass | Latest value |
| Sleep | SleepDuration (from `SleepSessionRecord`) | Boundary-aware |
| Nutrition | All macros + micros from `NutritionRecord` | Aggregated |
| Other | Cycle tracking, Mindfulness sessions | |

## Sync Logic

### Merge Strategy (`SupabaseHealthService.SyncNativeHealthDataAsync`)

- **Cumulative metrics** (Steps, Calories, etc.): **Max Wins** — keeps the higher value between local and remote
- **Spot metrics** (Weight, HR, etc.): **Last Write Wins** — the syncing device is authoritative
- Syncs **Today + Yesterday** data for backfill
- Upsert uses `ON CONFLICT (user_id, date, type)` strategy

### SyncedAt Timestamp

Each metric gets `SyncedAt = DateTime.Now` (local device time) before upserting. This is displayed in HealthDetail as a relative timestamp (e.g., "Synced 5m ago").

## Source Attribution

### Visual Origin Dots

Small colored dots appear next to each metric indicating its source:
- **Blue** (`#2979FF`): iOS / HealthKit
- **Green** (`#00E676`): Android / Health Connect
- **Pink** (`#E91E63`): Manual entry
- **Grey**: Unknown/Mixed

### Dominant Source Indicator

The "Today" header dot uses a **dominant majority** algorithm:
- **Blue**: ≥70% of sourced metrics come from iOS
- **Green**: ≥70% come from Android/Health Connect
- **Grey**: Mixed (no platform reaches 70%)
- Tooltip shows breakdown: "iOS: X, Android: Y"

This appears in both `HealthWidget.razor` (header) and `HealthDetail.razor` (Activity header).

## Health History / Trends

The HealthDetail page includes a **"7-Day Trends"** section (collapsible `MudExpansionPanel`) showing line charts for:
- **Steps** (orange line)
- **Sleep** in hours (purple line)
- **Heart Rate** in bpm (red line)

Data is fetched via `IHealthService.GetHistoryAsync(VitalType type, int days)` which queries the `vitals` table for daily values over the specified range.

Charts only render if there is at least one non-zero data point in the 7-day window. If no data exists, a placeholder message is shown.

## UI Components

### HealthWidget.razor (Main Dashboard)
- "Clean Snapshot" pattern with radial progress circles (Steps, Calories, Sleep)
- Secondary stats: Heart Rate, Weight, Blood Pressure
- Nutrition pills: Carbs, Protein, Fat
- Header shows "Today" + dominant source dot

### HealthDetail.razor (Detail Page)
- "Hero Left / Grid Right" layout
- Activity hero: Steps, Calories ring, Sleep
- Vitals grid: HR, Weight, HRV, BP, Body Composition, Sleep & Mind, Nutrition, Cycle
- 7-Day Trends section with line charts
- SyncedAt timestamp display
- Diagnostics & Sync panel with manual sync button and log viewer

## Supabase Schema

```sql
-- Core table
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

-- RLS enabled: Users can only see/modify their own vitals
```

## Key Files

| File | Purpose |
|------|---------|
| `Models/Health/VitalMetric.cs` | Data model with VitalType enum |
| `Services/Health/IHealthService.cs` | Service interface |
| `Services/Health/INativeHealthStore.cs` | Platform abstraction interface |
| `Services/Health/SupabaseHealthService.cs` | Cloud sync & data access |
| `Services/Health/MockNativeHealthStore.cs` | Desktop fallback |
| `Platforms/iOS/HealthKitService.cs` | iOS HealthKit integration |
| `Platforms/Android/HealthConnectService.cs` | Android Health Connect integration |
| `Components/Widgets/HealthWidget.razor` | Dashboard widget |
| `Components/Pages/HealthDetail.razor` | Detail page |
| `Docs/SQL/health_improvements_migration.sql` | DB migration for synced_at |

## Recent Updates

### Source dots on ALL values
— Rewrote HealthDetail.razor to use GetMetric() returning full VitalMetric objects, so every metric now has a blue/green/grey source dot. Per-metric sync time captions ("5m ago") also show under the main hero metrics (Steps, Calories, Sleep, HR, Weight, HRV, BP).

### All fetched data now displayed — Added:

Sleep Stages row: Deep, Light, REM, Awake (conditionally shown when data exists)
Expanded Vitals row: Resting Heart Rate, Respiratory Rate, SpO2, Blood Glucose
Full Micros: Magnesium, Zinc, Calcium added alongside existing Sugar/Iron/VitC/Caffeine

### 7-Day Trends fallback — Two fixes:

CalculateSyncedAgo + GetSyncCaption now fall back to UpdatedAt when SyncedAt is null (for your older data)
GetHistoryAsync now uses DateTime.UtcNow.Date instead of DateTime.Today to correctly match Supabase-stored UTC dates, which should surface your existing historical data

### 7-Day Trends fallback — One fix:

Is it stilll useful to keep in 7-Day Trend data for today, it seems it's never populated in the current day and just gets the graph to go down in an unrealistic manner, what do you think?

Great observation — you're absolutely right. Today's data is always partial (the day isn't over), so it drags the trend line down artificially. Plus, today's values are already displayed prominently in the hero section above. The trend should show the previous 6 completed days only.

Let me fix that:

Simple fix — change the loop to start from 7 days ago through yesterday (skip today), and update the heading to say "Past 7 Days":

Done — simple two-line change. The trend now shows yesterday through 7 days ago (7 completed days), skipping today entirely. The section is also renamed to "Past 7 Days" to make this clearer.

Today's live values are already shown prominently in the hero section at the top, so there's no data loss — just a more accurate trend line that won't dip artificially from incomplete daily totals.