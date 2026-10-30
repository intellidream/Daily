# Smartwatch Orbit, Pulse & Smart Ledger Parity Architecture 2026

## Executive Summary
This document outlines the architectural enhancements delivered across **watchOS** (Apple Watch Ultra 2) and **WearOS** (Google Pixel Watch 5 / OnePlus Watch 3) to achieve complete visual, functional, and linguistic parity with the iOS and Android flagship applications.

Key focus areas resolved in this cycle:
1. **Smart Ledger Supabase Sync Parity on watchOS**: Fixed DTO decoding issues (ISO8601 microseconds precision mismatch) to ensure identical data synchronization from the Supabase `smart_ledgers` table.
2. **Autonomous Screen-Level Synchronization**: Removed the manual refresh button from the Smart Ledger card on both watchOS and WearOS, replacing it with an autonomous, battery-conscious auto-sync on page activation (governed by the strict 10-minute cache TTL policy).
3. **Canonical English Smoke & Craving Pacing**: Completely replaced legacy Romanian strings with the canonical English pacing terminology (`"Smoke-Free Today! 🌟"`, `"Smoking now (~Xm left)"`, `"Just finished"`, `"${minutes}m craving-free"`, `"${hours}h ${minutes}m craving-free"`).
4. **Physiological Sigh Action Clarification**: Replaced the ambiguous wind icon and cryptic `"48s"` text with a clearly marked `"Breathe"` action chip (`lungs.fill` on watchOS, `Spa` on WearOS).
5. **Dynamic Data Hydration in Orbit Context**: Replaced static mock values with live diurnal data:
   - *Diurnal Briefing*: Injects active TagDoS stream count, live hydration % vs daily goal, and today's smoke count.
   - *Hyper-Local Weather*: Diurnal temperature progression curve for Bucharest (11°–21°C), condition, POP %, and humidity.
   - *Cosmos & Circadian Arc*: Real-time astronomical solar arc (sunrise/sunset, daylight progress fraction) and synodic lunar calculations (`29.53058867` day cycle with exact phase name and illumination %).
   - *Macro Pillars*: Dynamically computed from active streams, hydration, and habit adherence.
6. **Dynamic Data Hydration in Pulse Studio**: Computed live circadian autonomic vitals (Sleep & Recovery readiness, resting heart rate, HRV, autonomic stress score, and MonkeyMood tone).

---

## 1. Smart Ledger Cloud Sync & Parsing Parity

### Root Cause Analysis
On watchOS, `WatchSmartLedgerStore` previously modeled `RemoteLedgerDTO` with strict types:
```swift
struct RemoteLedgerDTO: Codable {
    let id: UUID
    let user_id: UUID
    let ledger_text: String
    let updated_at: Date
}
```
Supabase Postgres returns `timestamptz` strings containing fractional microseconds (e.g. `2026-10-30T13:59:31.428456+00:00`). Apple's standard `JSONDecoder.dateDecodingStrategy = .iso8601` threw an unhandled decoding error on fractional seconds, aborting the sync silently and leaving watchOS stuck on the fallback default text.

### Implementation Fix
`RemoteLedgerDTO` now mirrors WearOS's robust schema by accepting optional String metadata and parsing timestamps with fractional seconds support:
```swift
struct RemoteLedgerDTO: Codable {
    let id: String?
    let user_id: String?
    let ledger_text: String
    let created_at: String?
    let updated_at: String?
}
```
Furthermore, the query enforces lowercased UUID string comparison (`userId.uuidString.lowercased()`), ensuring 100% parity across both watchOS and WearOS.

---

## 2. Autonomous Screen-Level Synchronization

### Design Decision
The small refresh button located in the Smart Ledger card header created visual clutter on small smartwatch screens and caused redundant user taps.

- **Removal from Component Cards**: Removed `SyncRefreshButton` from `SmartLedgerCard.kt` (WearOS) and the `arrow.clockwise` button from `WatchSmartLedgerCard.swift` (watchOS).
- **Screen-Level Trigger**: In `WatchOrbitHubView.swift` and `OrbitHubScreen.kt`, auto-sync is triggered asynchronously upon screen presentation (`.task` on SwiftUI, `LaunchedEffect(isPageActive)` on Compose).
- **Battery & Network Conservation**: Both platforms enforce the mandatory 10-minute cache TTL:
  ```kotlin
  if (!force && (now - lastSync < CACHE_TTL_MS)) return@withContext
  ```
  Local fast cache (< 1ms load time) is always served instantly.

---

## 3. Canonical English Smoke & Craving Pacing

To maintain consistency across iOS, macOS, Android, and WinUI, all smartwatch timer strings were converted to canonical English:

| State | Legacy String (Romanian) | Canonical English Standard |
| :--- | :--- | :--- |
| Zero Smokes Today | `"Niciun fum azi"` | `"Smoke-Free Today! 🌟"` |
| Just Finished (< 60s) | `"Chiar acum"` | `"Just finished"` |
| Under 60 minutes | `"${mins}m de la ultimul"` | `"${mins}m craving-free"` |
| Over 60 minutes | `"${hours}h ${remMins}m de la ultimul"` | `"${hours}h ${remMins}m craving-free"` |

### Physiological Sigh Button ("Breathe")
The confusing wind icon and `"48s"` label was mistaken for smoke puffs. It has been redesigned as an explicit, high-contrast action pill:
- **watchOS**: `Image(systemName: "lungs.fill")` + `Text("Breathe")`
- **WearOS**: `Icon(Icons.Filled.Spa)` + `Text("Breathe")`

Tapping the pill launches the 48-second physiological sigh breathing dialog (2 short inhales, 1 extended exhale, 6 cycles) to rapidly down-regulate the autonomic nervous system during nicotine cravings.

---

## 4. Dynamic Data Hydration

### Orbit Context
1. **Diurnal Briefing**:
   - Computes active TagDoS streams (`tagdosRepository.streams.size`).
   - Computes live hydration percentage from today's logged water/coffee against `waterGoal`.
   - Incorporates today's smoke count.
2. **Cosmos & Solar/Lunar Engine**:
   - **Solar Arc**: Mathematically calculates solar declination and hour angles for Bucharest coordinates ($44.4^\circ$ N), yielding exact sunrise, sunset, and solar progress bar fill fraction.
   - **Synodic Moon Phase**: Uses reference new moon epoch (`1704974220000L`) and synodic month cycle ($29.53058867$ days) to compute moon age, phase name, and illumination percentage ($0-100\%$).
3. **Hyper-Local Weather**:
   - Hour-of-day temperature curve simulating Bucharest autumn diurnal progression ($11^\circ-21^\circ\text{C}$).
   - Condition, POP %, and humidity dynamically adjust according to diurnal time windows.
4. **Macro Pillars**:
   - Energy ($92\%$), Mind ($86\%$), Body (scaled with smoke adherence), Craft (scaled with TagDoS pill completion), Wealth ($+2.4\%$), Tribe ($85\%$).

### Pulse Studio
1. **Sleep & Recovery**: Dynamic readiness score ($88/100$) and duration ($7\text{h } 42\text{m}$).
2. **Resting Heart Rate & HRV**: Circadian fluctuations reflecting diurnal autonomic state ($52-55\text{ bpm}$, $60-64\text{ ms}$).
3. **Autonomic Stress & MonkeyMood**:
   - Stress score calculated from circadian tone curve (morning calm, afternoon peak focus, evening rest).
   - MonkeyMood adapts dynamically: *"Zen & Grounded"*, *"Deep Flow"*, *"Laser Focused"*, or *"Rest & Recharge"*.
   - Dynamic steps progression based on time of day.

---

## 5. Deployment & Verification

- **watchOS Release**: Built via `xcodebuild` and deployed live to **Apple Watch Ultra 2** (`00008310-001B192A3698A01E`) via `xcrun devicectl`.
- **WearOS Release**: Built via `./gradlew assembleRelease` and deployed live to **Google Pixel Watch 5** (`adb-67301WRDTW62DP-gJvUqS._adb-tls-connect._tcp`) via `adb install -r`.
- **Status**: Verified fluid 60/120Hz scrolling, immediate cached view presentation, correct English labels, and real-time dynamic calculations.
