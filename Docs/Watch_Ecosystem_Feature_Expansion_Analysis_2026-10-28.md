# Daily Orbit — Exhaustive Ecosystem & Smartwatch Expansion Analysis (`watchOS` & `WearOS`)

**Date:** October 28, 2026  
**Reference Golden Standards:** `DailyCore/`, `iOS/Daily/`, `MacOS/Daily/` (including `MenuBarCompanionView` & `DailyWidgets`)  
**Target Watch Platforms:**
- **watchOS:** Apple Watch Ultra 2 (`WatchOS/DailyWatch`)
- **WearOS:** Google Pixel Watch 5 & OnePlus Watch 3 (`WearOS/app`)

---

## 1. Executive Summary & Design Philosophy

Following the local-first performance modernization on both **WearOS** (commit `cf42d4d`) and **watchOS** (commit `c33eabc`), both smartwatch apps now operate with **0ms optimistic UI mutations**, **<1ms local disk hydration**, **bidirectional offline outboxes**, and **60fps native crown/rotary scrolling**.

However, auditing the full native Daily ecosystem (`DailyCore`) reveals a massive capability gap: **smartwatches currently expose less than 15% of Daily's micro-interaction surface** (only 3 water presets, 2 smoke presets, 7-day habit bars, and pairing status). Meanwhile, Daily's core domain models — particularly **TagDoS**, **Smart Ledger**, **Stress & Haptic Breathing**, **Sleep Studio**, **Smart Briefing**, and **Habits Guidance** — were architected around ultra-compact DSLs, shorthand tokens, and atomic deltas that are naturally suited for **under-3-second wrist interactions**.

### The Golden Rule for Daily on the Wrist
> **A smartwatch is not a shrunken iPhone or Mac — it is a 0ms wrist command deck.**  
> Every feature brought to `watchOS` and `WearOS` must pass two strict filters:
> 1. **Real Autonomous Utility:** Does it genuinely save pulling out the phone/laptop (while driving, shopping, walking, in meetings, at checkout, or managing cravings/stress)?
> 2. **Zero Performance Regression:** Can its local state fit in `<10 KB` of cached JSON, render at locked `60fps` without nested scroll jank, and mutate optimistically via the local Outbox without blocking the UI on radio wakeups?

---

## 2. Ecosystem Audit: `DailyCore` vs. Current Smartwatch Capabilities

| Ecosystem Pillar (`DailyCore`) | Supabase Backing Tables / APIs | Current iOS / macOS Capabilities | Current `watchOS` / `WearOS` State | Wrist Fit & Control Potential |
| :--- | :--- | :--- | :--- | :--- |
| **Habits (`Bubbles` & `Smokes`)** | `habits_logs`, `habits_goals`, `habits_daily_summaries`, `user_preferences` | 6 drink presets + hydration factors, 4 smoke presets, multipliers (`1×–5×`), Craving Timer (`timeSinceLastSmoke`), Financial saved/spent (`RON`), editable goals | Only 3 water chips (`300`, `150`, `100☕`) & 2 smoke chips (`Cig`, `Heat`), Today logs + delete, 7D bars | **⭐⭐⭐⭐⭐ Critical** — Missing Craving Timer, Crown custom ml/multipliers, Tea/Bottle/Rolled, goal editing, financial badge |
| **TagDoS (Mental Execution Engine)** | `tagdos_streams`, `tagdos_quick_notes`, `tagdos_attachments` | 5 prioritized Streams, shorthand clusters & pills (`!`, `$`), `drivingPill` per stream, Quick Notes, `MenuBarCompanionView` quick entry | **0% Absent** | **⭐⭐⭐⭐⭐ Game-Changer** — Check off/recycle pills while shopping/commuting; voice-dictate new `TagDo` pill or `Quick Note` |
| **Health, Sleep & Stress Studio** | `health_telemetry`, `health_daily_summary`, `vitals` | Sleep Score + Verdict (`SleepGuidance`), Stress Score (`0–100`) + `MonkeyMood`, 4 scientific `BreathingProtocol`s, RHR/HRV/SpO2/Steps | `watchOS` pushes HealthKit in background (`HealthTelemetryManager`), **0% UI**; `WearOS` has **0% Health sync & 0% UI** | **⭐⭐⭐⭐⭐ Native Superpower** — Eyes-free **Haptic Guided Breathing**, Morning Sleep Verdict + Stress/HRV glance, WearOS Health Services sync |
| **Finances & Smart Ledger** | Local DSL (`SmartLedgerStore`) + Yahoo Finance v8 JSON (`FinanceService`) | `ParsedSmartLedger` (`Card`, `Cash`, `Outgoing`, `Deposit`, `Net Worth`), `SmartLedgerQuickAdjustSheet` (`±100/200/500 Lei`), Stocks Watchlist, 6 Macro Pillars | **0% Absent** | **⭐⭐⭐⭐ High** — Quick-adjust `Card`/`Cash`/categories at checkout via Crown + glance at Balance, Stocks & 6 Macro Pillars *(requires lightweight Supabase sync for DSL)* |
| **Smart Briefing** | `daily_smart_summaries` | Diurnal AI/deterministic narrative (`Morning`, `Intraday`, `Evening`, `Nightly`) + key metrics | **0% Absent** | **⭐⭐⭐⭐ High** — 10-second executive wrist briefing upon waking up or between meetings |
| **Weather & Cosmos** | OpenWeatherMap REST + deterministic local `AstronomyService` | Current/Forecast weather, Rain probability (`pop`), Wind, Sunrise/Sunset, Golden Hour, Moon Phase | **0% Absent** | **⭐⭐⭐ Medium-High** — Tactical rain/temp/UV + sunset/moon glance before stepping outside |
| **News / RSS Reader** | `rss_subscriptions`, `rss_saved_articles` | Full RSS aggregation, Readability full-text extraction, Saved Articles | **0% Absent** | **⭐ Low (Anti-Goal for full reading)** — Full articles hurt watch UX/RAM; at most a 3-headline glance with *"Save to Reading List"* |
| **System Surface (Faces, Tiles, Intents)** | `AppIntents` / `WidgetKit` (`watchOS`), `GlanceTile` / Complications (`WearOS`) | Interactive iOS 17+ `DailyWidgets` (`LogWaterIntent`, `LogSmokeIntent`, `AdjustLedgerIntent`) | `watchOS`: Non-interactive widget making raw HTTP calls; no Ultra Action Button. `WearOS`: Static 2-line stub tile reading stale prefs | **⭐⭐⭐⭐⭐ Zero-App-Open Speed** — 1-tap logging directly from Watch Face, Smart Stack, Ultra Action Button, and Interactive WearOS Tile |

---

## 3. Detailed Feature Proposals by Domain

### A. Habits 2.0 — Complete Wrist Autonomy (`Bubbles` & `Smokes`)
Referenced models: [`HabitModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/HabitModels.swift), [`HabitsGuidance.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HabitsGuidance.swift).

1. **Live Craving & Pacing Timer (`timeSinceLastSmoke`) on Smokes:**
   - Display a compact badge directly inside or beneath the Smokes hero gauge: **`⏱ 2h 18m de la ultima`** (computed in `O(1)` from `todaySmokesLogs.first?.loggedAt`, zero network calls).
   - Color-coded pacing feedback: subtle amber if `< 45m`, emerald green when stretching intervals `> 2h`.
2. **"Beat Craving" 48-Second Haptic Shortcut:**
   - Optional micro-action on Smokes that launches the **Physiological Sigh** haptic breathing session (`48s`) to ride out a nicotine urge instead of logging a smoke.
3. **Crown / Rotary Custom Entry & Full Presets Sheet (`+` Pill):**
   - Keep the main screen uncluttered with the primary 1-tap presets, and add a compact **`+ Custom`** pill opening a 0ms sheet:
     - **Bubbles:** Rotate Digital Crown / Rotary Bezel in `25ml` steps (`50ml – 1000ml`) + select any [`WaterPreset`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/HabitModels.swift#L627-L709) (`Glass 250ml`, `Bottle 500ml`, `Tea 250ml`, `Coffee 100ml`) + multiplier (`1×–4×`).
     - **Smokes:** Select [`SmokePreset`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/HabitModels.swift#L713-L754) (`Cigarette`, `Heated`, `Rolled`, `Cigarillo`) or log a retroactive smoke (`-15m`, `-30m`, `-1h`) if you forgot to log when outside.
4. **On-Wrist Goal & Financial Pulse:**
   - Tap the target subtitle (`of 2000 ml` / `max 20`) to adjust `water_goal` or `smokes_baseline` with the Crown (syncing to `user_preferences` & `habits_goals`).
   - Display daily tobacco spend / savings (`SmokesFinancialMetrics`: e.g. `7.95 RON azi` vs `Economisit +18.55 RON`) on the 7-Day Smokes summary screen.

---

### B. TagDoS Wrist Command — Checklists, Driving Pills & Voice Capture
Referenced models & stores: [`TagdoModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/TagdoModels.swift), [`TagdosStore.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/TagdosStore.swift), [`MenuBarCompanionView.swift`](file:///Users/mihai/Source/Daily/MacOS/Daily/Views/MenuBar/MenuBarCompanionView.swift).

TagDoS is arguably the **highest-ROI new module** for smartwatches in the entire ecosystem because its data model (`tagdos_streams` + `tagdos_quick_notes`) is already 100% synced via Supabase and uses ultra-concise tokens (`MG`, `FSH/LDL`, `BUY/GROC`, `!MP$`).

1. **"Driving Pills" Radar (5-Stream Executive View):**
   - Displays the 5 prioritized streams (`S1 Daily Ops` → `S5 Home & Life`) with each stream's **`drivingPill`** (first uncompleted pill) highlighted in its semantic color (`urgent` crimson, `financial` emerald, `standard` cyan) + active count badge.
2. **One-Tap Checklist & Queue Control (Shopping / Errands Mode):**
   - Tap any stream to view its clusters and active `TagDoPill`s:
     - **Single Tap:** `togglePillCompletion` (`✓` strike-through + crisp haptic click).
     - **Swipe / Secondary Tap:** `recyclePillToBack` (`↻` moves recurring task like `PL98` or `GROC` to the back of the stream queue!) or `movePillToFront` (`↑`).
3. **Voice / Scribble Dual Quick Capture (`[TagDo | Note]`):**
   - Modeled directly on macOS [`MenuBarCompanionView`](file:///Users/mihai/Source/Daily/MacOS/Daily/Views/MenuBar/MenuBarCompanionView.swift#L322-L420):
     - Tap `🎙️` → native watchOS Dictation/Scribble or WearOS Voice Input (`RecognizerIntent`) → choose **`+ Stream 1 Pill`** or **`+ Quick Note`**.
     - Persists locally in `<1ms` and syncs via Outbox to `tagdos_streams` / `tagdos_quick_notes`.
4. **Pinned Quick Notes Peek:**
   - Read pinned [`TagDoQuickNote`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/TagdoModels.swift#L225-L263) items (e.g., apartment codes, shopping specifics, parking spot, plate/ticket reminders) right on the wrist.

---

### C. Health, Sleep Verdict & Eyes-Free Haptic Breathing Studio
Referenced models & services: [`StressModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/StressModels.swift), [`HealthDailySummaryModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/HealthDailySummaryModels.swift), [`HealthTelemetryManager.swift`](file:///Users/mihai/Source/Daily/WatchOS/DailyWatch/DailyWatch Watch App/HealthTelemetryManager.swift).

1. **Eyes-Free Haptic Guided Breathing (Signature Watch Feature):**
   - Bring Daily's 4 scientific [`BreathingProtocol`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/StressModels.swift#L72-L166) presets to the wrist:
     - **Physiological Sigh** (`2s + 1.5s` double inhale, `6s` exhale — 5 cycles, **48 sec** rapid vagal reset)
     - **Box Breathing** (`4-4-4-4` — tactical focus)
     - **Resonance Flow** (`5.5s / 5.5s` — HRV coherence)
     - **Relaxing 4-7-8** (pre-sleep wind-down)
   - Uses `WKInterfaceDevice.current().play(...)` on watchOS and `VibrationEffect.createWaveform(...)` on WearOS so the user can **close their eyes** and follow inhale/hold/exhale transitions purely through tactile wrist haptics, showing HR delta (`78 → 66 bpm`) at completion!
2. **Readiness, Sleep & Stress Glance:**
   - Consumes `health_daily_summary` (plus live local HealthKit / Health Services HR & Steps):
     - **Morning / Recovery Card:** Sleep Score (`0–100`), Total Asleep (`7h 24m`), Deep/REM %, and `SleepRecoveryVerdict` badge.
     - **Autonomic Stress Card:** Stress Score (`0–100`), `MonkeyMood` (`Zen`, `Curious`, `Busy`, `Overheated`), HRV (`ms`), Resting HR (`bpm`), and live Steps / Active `kcal`.
3. **WearOS Biometric Producer Parity (`WearHealthTelemetryManager`):**
   - Currently `watchOS` uploads anchored HealthKit samples to `health_telemetry`, while `WearOS` only consumes Habits. Adding lightweight background `HealthServicesClient` / `HealthConnect` delta sync on Pixel Watch 5 & OnePlus Watch 3 makes both watches full biometric peers in **Daily Orbit**.

---

### D. Smart Ledger Quick-Adjust & Market Pulse
Referenced models & services: [`SmartLedgerModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/SmartLedgerModels.swift), [`SmartLedgerStore.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/SmartLedgerStore.swift), [`SmartLedgerQuickAdjustSheet.swift`](file:///Users/mihai/Source/Daily/iOS/Daily/Views/Finances/SmartLedgerQuickAdjustSheet.swift), [`FinanceService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/FinanceService.swift).

> **Architectural Prerequisite Uncovered During Audit:**  
> Currently, [`SmartLedgerStore`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/SmartLedgerStore.swift#L20) persists `daily_smart_ledger_raw_text_v1` locally in `AppGroup` / `UserDefaults` without a Supabase table. Because Daily watches operate autonomously via 10-year Supabase JWTs (including over Wi-Fi/LTE without phone tethering), enabling Smart Ledger on watches requires a lightweight 1-row Supabase sync (e.g. `user_smart_ledger` table with `user_id`, `raw_text`, `updated_at` — `<2 KB` payload). Bonus: this simultaneously unlocks live Smart Ledger sync across **iOS, macOS, Android, and WinUI**!

1. **Smart Ledger Balance & Crown Quick-Adjust:**
   - Top card showing **Available Balance**, **Card** vs **Cash**, and **Outgoing Total** (with optional tap-to-reveal **Net Worth** for privacy in public).
   - Tap `Card`, `Cash`, or top Outgoing categories (`Cora/Mega`, `Tigari`, `Car/Benzina`, `Iesiri`) → adjust with `-500 / -100 / +100 / +500 Lei` chips or **Digital Crown / Rotary** (`1 DSL unit = 100 Lei`), recalculating totals deterministically on-device in `<0.5ms`.
2. **6 Macro Pillars & Watchlist Ticker:**
   - Compact glanceable list of Daily's **6 Core Macro Pillars** (`🛢️ Oil`, `🟡 Gold`, `💵 DXY`, `💻 NDX`, `₿ BTC`, `📊 VIX`) + user Watchlist (`AAPL`, `NVDA`, `MSFT`, `TSLA`, `EUR/USD`), cached locally with a 15-minute TTL.

---

### E. Daily Context — Diurnal Smart Briefing, Weather & Cosmos
Referenced models & services: [`SmartBriefingModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/SmartBriefingModels.swift), [`WeatherModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/WeatherModels.swift), [`AstronomyService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/AstronomyService.swift).

1. **Diurnal Smart Briefing Card:**
   - Pulls the latest slot (`morning`, `intraday`, `evening`, `nightly`) from `daily_smart_summaries` — 2–3 crisp sentences synthesizing sleep, habits pace, weather, and top focus.
2. **Hyper-Local Weather + Solar/Lunar Arc:**
   - Current temperature, feels-like, wind, next-6h rain probability (`pop`) mini-bars, plus zero-network local `AstronomyService` computation for **Sunrise / Sunset / Golden Hour** and **Moon Phase**.

---

### F. System-Level Zero-App-Open Controls (Watch Faces, Action Button & Tiles)
Referenced files: [`DailyWatchWidgetExtension.swift`](file:///Users/mihai/Source/Daily/WatchOS/DailyWatch/DailyWatchWidgetExtension/DailyWatchWidgetExtension.swift), [`WidgetIntents.swift`](file:///Users/mihai/Source/Daily/iOS/DailyWidgets/WidgetIntents.swift), [`DailyTileService.kt`](file:///Users/mihai/Source/Daily/WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/tile/DailyTileService.kt), [`WaterComplicationService.kt`](file:///Users/mihai/Source/Daily/WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/complication/WaterComplicationService.kt).

1. **`watchOS` Interactive Smart Stack & Complications (`AppIntents`):**
   - Refactor `DailyWatchWidgetExtension` to read **instantly from `WatchHabitStore`'s AppGroup cache** (eliminating raw HTTP blocking inside `getTimeline`!).
   - Add **interactive `Button(intent:)`** actions in `.accessoryRectangular` Smart Stack widgets (`+300ml`, `+100☕`, `+Cig`, `+Heat`, `✓ Driving TagDo`) + dedicated single-metric complications (Hydration Gauge, Craving Timer, Stress/Sleep Score, Next TagDo).
   - **Apple Watch Ultra 2 Physical Action Button & Double Tap:** Register `AppShortcutsProvider` intents so the physical orange Action Button can trigger *Log Water*, *Voice TagDo*, or *48s Craving Breath* instantly!
2. **`WearOS` Interactive ProtoLayout/Glance Tile & Rich Complications:**
   - Replace the static 2-line `DailyTileService.kt` stub (which currently reads legacy empty `SharedPreferences` keys!) with a **true Interactive Habits + TagDoS Tile** wired to `WatchHabitRepository` + `OfflineSyncManager`: tap `+300`, `+150`, `+☕`, `+Cig`, or `+Heat` directly on the Tile swipe-carousel without opening `MainActivity`!
   - Upgrade `WaterComplicationService` & `SmokesComplicationService` to support `RANGED_VALUE` circular progress arcs, `SHORT_TEXT`, and `LONG_TEXT` (including Craving Timer & Next TagDo), pushed immediately via `ComplicationDataSourceUpdateRequester` on every local mutation.

---

## 4. Navigation & Performance Architecture: Scaling Without Losing 0ms Speed

### Why We Must NOT Use a 12-Page Flat Horizontal Pager
Adding 7+ screens to a flat `TabView(.page)` (`watchOS`) or `HorizontalPager` (`WearOS`) causes two severe regressions:
1. **Ergonomic Swipe Fatigue:** Swiping horizontally 8 times to reach TagDoS or Breathing violates the `<3 second` wrist rule.
2. **Composition & Memory Pressure:** Keeping 10 complex pages warm in a horizontal pager risks frame drops on wrist raise.

### Recommended Architecture: **Compact Core Pager (4–5 Pages) + Vertical Drill-Down**
1. **Consolidate 7-Day Views Vertically (or via Gauge Tap):**
   - Instead of dedicating 2 separate horizontal root pages to `Bubbles 7D` and `Smokes 7D`, tapping the Hero Gauge (or scrolling past Today's quick-add chips) reveals the 7-Day stacked chart + Today's Logs. That **immediately frees 2 horizontal root slots** while making Habits faster to navigate!
2. **Clean 5-Slot Root Horizontal Architecture (Customizable Order):**
   - **Page 1 — `Bubbles`:** Hero Gauge + Presets + `+ Custom/Crown` → *(tap gauge or scroll for 7D & Logs)*.
   - **Page 2 — `Smokes`:** Hero Gauge + **Craving Timer** + Presets + *48s Sigh* → *(tap gauge or scroll for 7D, Financials & Logs)*.
   - **Page 3 — `TagDoS`:** **Voice Capture `[TagDo | Note]`** + 5 Stream Driving Pills → *(tap stream to check off / recycle pills)*.
   - **Page 4 — `Pulse (Health & Calm)`:** **Sleep Score/Verdict + Stress/HRV** + **Haptic Guided Breathing** launcher.
   - **Page 5 — `Orbit Hub (Ledger, Market, Briefing & Status)`:** Bento cards for **Smart Ledger Quick-Adjust**, **Macro/Stocks**, **Briefing/Weather**, and **Sync/Pairing Status**.
   *(Alternatively, Page 1 can be a compact 2×3 Bento Command Hub with 1-tap jump to any module, or users can toggle visible pages!)*

### Zero-Regression Technical Guardrails
1. **Isolated Domain Stores (`<1ms` Cold Start):** Separate `WatchHabitStore`, `WatchTagdosStore`, `WatchHealthStore`, and `WatchLedgerStore`. Only lightweight summary scalars hydrate synchronously at frame 0; secondary lists decode lazily when the page is visited.
2. **Polymorphic Offline Outbox v3:** Extend `OfflineSyncManager` (`actor` on watchOS, `Mutex` singleton on WearOS) with typed operations (`habitInsert`, `habitDelete`, `tagdoStreamUpsert`, `tagdoNoteUpsert`, `ledgerUpsert`, `goalUpdate`) — guaranteeing 0ms local UI updates and resilient offline replay.
3. **Strict Network Coalescing & TTLs:**
   - Habits & TagDoS: foreground sync debounced (`≥30s`) + immediate background flush on local write.
   - Health Summary & Briefing: pull on morning wake / `15m` TTL.
   - Weather & Market Quotes: pull only when visited if cache age `> 15m`.
4. **Zero Heavy Rendering:** Pure `Canvas` / lightweight SwiftUI shapes, static formatters, immutable pre-computed view models, and zero `WebView` / bitmap decoding on watch threads.

---

## 5. Proposed Implementation Roadmap (Phased Delivery)

| Phase | Focus Area | Key Deliverables (`watchOS` + `WearOS` Parity) | Complexity | Wrist Impact |
| :--- | :--- | :--- | :---: | :---: |
| **Phase 1** | **System Surfaces & Habits 2.0** | Interactive Complications/Tiles (wired to v2 cache!), Ultra Action Button, Smokes **Craving Timer**, Crown Custom ml/Presets/Multipliers, On-Wrist Goal Edit, Vertical 7D consolidation | Low–Med | 🔥 Immediate daily speed boost (even without opening the app) |
| **Phase 2** | **TagDoS Wrist Command** | 5-Stream Driving Pills, Checklist tap-to-complete & recycle-to-back, **Voice/Scribble Quick Capture** (`TagDo` pill or `Quick Note`), Pinned Notes view + Outbox sync | Medium | 🔥 Massive autonomy while shopping, driving & commuting |
| **Phase 3** | **Pulse: Health, Sleep & Haptic Breathing** | **Eyes-Free Haptic Guided Breathing** (*Physiological Sigh 48s*, *Box*, *Resonance*, *4-7-8*), Sleep Score/Verdict + Stress/Monkey/HRV glance, WearOS Health Services sync | Medium | 🔥 Transforms watches into active autonomic recovery tools |
| **Phase 4** | **Smart Ledger Quick-Adjust & Context** | Lightweight Supabase sync for `SmartLedgerStore` (benefiting all 6 platforms!), Watch Balance + Crown Quick-Adjust (`±100 Lei`), 6 Macro Pillars + Briefing/Weather Bento | Med–High | 🔥 Complete financial & diurnal awareness from the wrist |
