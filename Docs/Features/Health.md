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
- Renders historical trends inside a collapsible panel.
- To prevent today's incomplete/in-progress metrics (e.g. partial step counts) from skewing the graph downward, the trend line calculations explicitly query and display data for the **past 7 completed days**, skipping the current day entirely.

---

## 2. Technical Architecture & Data Model

### 2.1 Services & Device Bridges
- `IHealthService` / `SupabaseHealthService`: Manages loading today's vitals, fetching historical trend logs, and writing manual logs.
- `INativeHealthStore`: Platform interface wrapping native OS health APIs.
- `MockNativeHealthStore`: Desktop implementation that generates randomized placeholder metrics to enable offline desktop prototyping.
- **iOS HealthKit (`HealthKitService.cs`)**: Coordinates read queries for 35+ `HKObjectType` types.
- **Android Health Connect (`HealthConnectService.cs`)**: Reflection-based bridge fetching records from Android's Health Connect SDK.

### 2.2 Sync Merge Strategy
- **Cumulative Metrics** (e.g., Steps, Calories, Water): **Max Wins** — preserves the higher value between the local device total and the remote database total to prevent double-counting.
- **Spot Metrics** (e.g., Heart Rate, Weight, Blood Pressure): **Last Write Wins** — updates the value using the most recent timestamp.
- **Backfill**: Sync routines scan and upload data for both `Today` and `Yesterday` to account for offline logging.

### 2.3 Database Schema (Supabase `vitals` table)
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

---

## 3. UI/UX & Layout

### 3.1 Vitals Gauges & Interactive Breath Guides
- **Vitals Hero Ring**: Displays circular progress rings for Steps, Calories, and Sleep.
- **Breathing Guides (Lungs Control)**: In WinUI, the health section features an interactive breathing exercises panel (`LungsControl.cs`). It uses WinUI composition animations to dynamically expand and contract circles, guiding users through inhale/hold/exhale breathing exercises.

### 3.2 Trend Charts
- Employs light sparkline trend charts for Steps (orange), Sleep (purple), and Heart Rate (red). If no data points exist in the 7-day completed window, it displays a placeholder.

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **UI Technology** | Native XAML Controls (`HealthWidgetControl.xaml` & `HealthDetailPage.xaml`) | Blazor Hybrid Razor components (`HealthWidget.razor` & `HealthDetail.razor`) |
| **Vitals Store** | Fallback to `MockHealthService.cs` (or queries Supabase database for synced data) | Hooks into iOS `HealthKitService` and Android `HealthConnectService` native libraries |
| **Breathing Control** | Native XAML custom shape rendering (`LungsControl.cs`) | Simplified static card grids (does not include the breathing animation) |
| **Manual Logs** | Desktop manual logging modals using standard WinUI XAML dialogs | MudBlazor forms and dialog overlays |
| **Charts** | Custom XAML path-drawn lines | MudBlazor chart controls (`MudChart` line/bar visualizers) |
