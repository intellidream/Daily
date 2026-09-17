# Android Phase 3: Habits Tracker (Bubbles Hydration & Smokes Cessation)

## 1. Overview
Phase 3 introduces native Android parity for the **Habits Tracker**, replicating 100% of the iOS `HabitsService`, `WaterProgressWaveView`, `SmokesLungsGaugeView`, and `HabitQuickActionGrid` functionality. It features an offline-first Room database cache with dirty tracking (`synced_at = null`), dual harmonic sinusoidal wave rendering for stratified beverage hydration, anatomical vector lung rendering with dynamic biological tissue coloration, a full-fidelity clinical guidance sheet with 4D emergency craving timer, and modular dashboard widgets spanning all 4 grid sizes (`1x1 Small`, `2x1 Wide`, `1x2 Tall`, `2x2 Large`).

---

## 2. Architecture & Data Contracts

### 2.1 Domain Models (`core-model/com.intellidream.daily.model.HabitModels.kt`)
- **`HabitType`**: `BUBBLES` (hydration), `SMOKES` (harm reduction/cessation).
- **`WaterPreset`**: `SMALL_WATER` (150 ml), `LARGE_WATER` (300 ml), `BOTTLE` (500 ml), `COFFEE` (100 ml), `TEA` (250 ml), `CUSTOM`.
- **`SmokePreset`**: `CIGARETTE` (1 cig), `HEATED` (1 stick), `ROLLED` (1 unit), `CIGARILLO` (1 unit).
- **`HabitLogRecord`**: Immutable record with timestamp, habit type, preset, volume/count, note, and UUID.
- **`SmokesSettings` & `SmokesFinancialMetrics`**:
  - Baseline daily count tracking, pack price in RON, currency, cigarettes per pack.
  - Financial savings computation: `(baselineCount - actualCount) * (packPrice / packSize)`.
  - Clinical metrics: cigarettes avoided and hours of life regained (11 min/cig).
- **`HabitDrinkBreakdown`**: Stratified drink percentages and volumes for stratified liquid rendering.
- **`HabitTrendDay` & `HabitConsistencyCell`**: Reactive data models powering the 7-day performance bar chart and 112-day (16-week) consistency heatmap.
- **`HabitsGuidance`**: Circadian schedule (07:00 kickstart to 20:00 night taper), Drink Hydration Index (DHI) scales, 4D craving protocol, and physiological recovery milestones (20 mins to 15 years).

### 2.2 Offline-First Persistence (`core-database`)
- **`HabitLogEntity`**:
  - Primary key: `id: String` (UUID v4).
  - Dirty tracking: `synced_at: Long?` (null on local write, populated on remote sync ACK).
  - Query indexes: index on `(habit_type, timestamp)`.
- **`HabitLogDao`**: Reactive Kotlin Coroutine `Flow` queries for zero-latency reactive updates.
- **`DailyDatabase`**: SQLite Room Database `DailyAndroid.db` (version 1) powered by `androidx.room 2.7.0-alpha13`.
- **`HabitsRepository`**:
  - In-memory hot state combined with Room persistence for instant, stutter-free 120Hz frame rates.
  - Dynamic derivation of `waterTotalToday`, `smokesTotalToday`, `drinkBreakdownToday`, `weeklyTrend`, `consistencyHeatmap`, and `financialMetrics`.
  - Quick action methods: `logWater()`, `logSmoke()`, `deleteLog()`, `updateWaterGoal()`, `updateSmokesSettings()`.

### 2.3 Remote Sync (`core-network`)
- **`HabitRemoteService`**: Supabase PostgREST sync client targeting `habits_logs` table.

---

## 3. Visual & UI Components (`app/presentation/habits`)

### 3.1 Water Progress Wave View (`WaterProgressWaveView.kt`)
- Dual infinite harmonic sine-wave generator using `rememberInfiniteTransition` with distinct wave periods (3.0s and 4.5s) to simulate realistic fluid dynamics.
- Multi-layer stratified liquid rendering:
  - Cyan water base layer (`ThemeColors.accentCyan` to `#0077B6`).
  - Amber coffee layer (`#F59E0B` to `#B45309`).
  - Lime herbal tea layer (`#10B981` to `#047857`).
- Percentage badge, dynamic completion state, and milestone badge at 100% goal.

### 3.2 Smokes Lungs Anatomical Silhouette Gauge (`SmokesLungsGaugeView.kt`)
- Vector anatomical bronchial tree, trachea, and left/right lung lobes drawn dynamically on Jetpack Compose `Canvas`.
- Dynamic biological tissue coloration:
  - `0 smokes`: Radiant healthy lung pink (`#FF6B8B`).
  - `Mild (<=35%)`: Healthy light salmon (`#D97D8E`).
  - `Moderate (<=75%)`: Dull bronze/brown (`#B8860B`).
  - `Severe (>75%)`: Charcoal/dark tar (`#333333`).
- 270° allowance circular gauge arc with dynamic status color (emerald, cyan, amber, red).
- Elapsed smoke-free timer pill ("Just now", "Xm ago", "Xh Xm ago").

### 3.3 Quick Intake & Craving Actions (`HabitQuickActionGrid.kt`)
- 5 water presets with icons (`Coffee`, `Water`, `Bottle`, `Tea`, `Custom dialog`).
- 4 harm-reduction smoke presets (`Cigarette`, `Heated`, `Rolled`, `Cigarillo`).
- Emergency 4D Craving Protocol hero banner with direct trigger action.

### 3.4 Clinical Guidance Bottom Sheet (`HabitGuidanceSheet.kt`)
- Tab switcher: `Bubbles Hydration` vs `Smokes & Cravings`.
- Live 5-minute interactive 4D emergency craving countdown timer (5:00 to 0:00) with glowing pulse ring, Start, Pause, and Reset controls.
- Complete 4D craving step cards: Delay, Deep Breathe (box breathing), Drink Water, Distract.
- Physiological recovery roadmap (20m heart rate drops, 8h CO levels normal, 48h nerve endings regrow, 72h breathing improves, 1y heart attack risk cut in half).
- Circadian diurnal hydration schedule and Drink Hydration Index (DHI) reference guides.

### 3.5 Full Hub View (`HabitsMainView.kt`)
- Date navigator capsule with Day-stepping arrows.
- Segmented tab pill (`Bubbles` vs `Smokes`).
- Hero visualizer (`WaterProgressWaveView` or `SmokesLungsGaugeView`).
- Collapsible interactive daily log timeline with delete swipe/icon.
- Financial savings and clinical recovery gains card.
- 7-Day performance bar chart.
- 112-Day (16-week) consistency heatmap with responsive cells.

### 3.6 Modular Dashboard Card (`HabitsDashboardCard.kt`)
Supports all 4 modular layout sizes from the dashboard grid:
1. **`1x1 Small`**: Compact 155dp glance with dual mini progress rings, water and smoke totals, and quick `+150` water action.
2. **`2x1 Wide`**: Standard 160dp card with dual 38dp progress rings, full labels, and 5 quick intake chips (`100`, `150`, `300`, `Cig`, `Heat`).
3. **`1x2 Tall`**: Vertical 324dp habits tower with stacked Bubbles and Smokes sections, dual rings, and paired action chips.
4. **`2x2 Large`**: Extended 324dp full-feature hub card with 44dp progress rings, goal subtitles, and 6 intake action chips.

---

## 4. Verification & Testing

1. **Gradle Compilation**:
   - Upgraded Room to `2.7.0-alpha13` in `gradle/libs.versions.toml` to support AGP 9.4 and Kotlin metadata 2.2.0.
   - Clean build: `./gradlew assembleDebug` passed cleanly.
2. **Emulator Verification (`emulator-5558`)**:
   - Installed and verified live on Mac Android emulator `Medium_Phone_API_36.1`.
   - Tested quick action intake: logged 150ml water, 500ml bottle, 100ml coffee, and 1 cigarette.
   - Verified real-time animated dual progress rings.
   - Verified stratified liquid wave simulation (amber coffee atop cyan water).
   - Verified anatomical lungs silhouette with dynamic healthy pink tissue color.
   - Verified 4D craving emergency countdown timer (5:00 live ticker).
   - Tested modular sizing: switched dashboard to `2x2 Large` and verified 6-chip grid and dual 44dp rings.
3. **Physical Hardware Deployment**:
   - Built and deployed APK to physical **Google Pixel 9 Pro** via ADB:
     `adb -s adb-48231FDAP0011V-Ma9KPE._adb-tls-connect._tcp. install -r app-debug.apk` -> **Success** (exit code 0).
