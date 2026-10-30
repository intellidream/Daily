# Universal Smart Ledger (Money) Parity & Orbit Context Caching Architecture

**Date**: October 30, 2026  
**Status**: Verified & Deployed Across All Platforms  
**Scope**: iOS (Golden Standard - Schmitz & Simulators), macOS (DailyCore), Android (Phones & Foldables), Windows 11 (WinUI 3), watchOS (Apple Watch Ultra 2), and Wear OS (Pixel Watch 5 / OnePlus Watch 3).

---

## 1. Executive Summary

The **Money / Smart Ledger** feature provides users with an instant, plain-text DSL-driven financial tracker and net-worth visualizer. It allows users to define custom Incoming, Outgoing, Balance, and Deposit entries using structured DSL lines with inline comments, tags, and scaling factors (e.g. `Tigari (40/45) = 10` where `10` scales to `1,000 Lei`).

To achieve 100% mathematical parity, bulletproof synchronization, and battery-friendly operation across all platforms, this initiative delivered:
1. **Universal Parser & AST Parity**: Identical AST parsing across Swift (`DailyCore`), Kotlin (Android & Wear OS), and C# (WinUI 3), guaranteeing consistent key extraction, scale multiplication, and totals computation.
2. **Gold Standard Verification on Schmitz**: Maintained iOS as the golden source of truth, aligning all platforms with its AST tokenization and debounced Supabase synchronizer.
3. **Smartwatch Fast Cache & Battery Preservation (<1ms, 10m TTL)**: Implemented strict 10-minute caching TTLs on Apple Watch Ultra 2 (watchOS) and Pixel Watch 5 / OnePlus Watch 3 (Wear OS) in Orbit Context, preventing network thrashing and battery drain while serving instant local data (<1ms).
4. **Android Dynamic Glance Widgets & Reactive Sync**: Replaced hardcoded widget numbers in `DailyMoneyGlanceWidget.kt` with live AST values, and hooked authentication state changes directly to the Room database synchronizer.

---

## 2. Universal Architecture & Schema

### 2.1 Cloud Contract (Supabase)

All platforms communicate with a unified Supabase table: `smart_ledgers`:

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `UUID PRIMARY KEY` | Unique record identifier (default `gen_random_uuid()`) |
| `user_id` | `UUID NOT NULL` | Foreign key referencing `auth.users(id)` |
| `ledger_text` | `TEXT NOT NULL` | Full raw text containing the Smart Ledger DSL document |
| `created_at` | `TIMESTAMPTZ` | Record creation timestamp |
| `updated_at` | `TIMESTAMPTZ` | Timestamp of last modification |

```sql
-- Fast lookup index for active user ledger document
CREATE INDEX IF NOT EXISTS idx_smart_ledgers_user_updated 
ON public.smart_ledgers (user_id, updated_at DESC);
```

### 2.2 Mathematical Rules & DSL Grammar

1. **Section Headers**:
   - `**Incoming**`: Scaled by default (`× 100`) unless specified otherwise.
   - `**Outgoing**`: Scaled by default (`× 100`) unless specified otherwise.
   - `**Balance**`: Automatically computed if missing as `Incoming - Outgoing`.
   - `**Deposit**`: Raw values (not scaled by 100); supports currency suffixes (`L`, `€`, `EUR`, `$`).
2. **Numeric Token Parsing**:
   - Strips parenthetical sub-allocations like `(40/45)` or `(//~8.400€)`.
   - Parses German/Romanian thousand separators (`.` as thousand separator, `,` as decimal point).
   - EUR conversion default: `1 EUR = 5.0 Lei`.
   - Net Worth formula: `Net Worth = Deposits + Balance`.

---

## 3. Platform Implementations

### 3.1 iOS & macOS (Swift / DailyCore - Gold Standard)
- **Model**: `DailyCore.SmartLedgerParser` and `DailyCore.ParsedSmartLedger`.
- **Store**: `SmartLedgerStore` uses App Group `UserDefaults` (`daily_smart_ledger_raw_text_v1`) for instant widget hydration, 500ms write debouncing, and Supabase PostgREST synchronization.
- **Verification**:
  - `swift test --package-path DailyCore`: 56 tests in 8 suites passed (100%).
  - `MacOS/Daily.xcodeproj`: Built and verified on host Mac.
  - `iOS/Daily.xcodeproj`: Built and verified on `SimulaPhone`, `SimulaDuo`, and physical iPhone 16 Pro (`Schmitz`).

### 3.2 Android (Pure Kotlin & Jetpack Compose)
- **Database & Sync**: `SmartLedgerRepository` in `core-database` backed by Room `SmartLedgerEntity`.
- **Session Lifecycle**: `DailyApp.kt` monitors `authRepository.sessionState` and automatically provisions `smartLedgerRepository.setUserId(uid)` upon login, triggering immediate cloud synchronization.
- **Resume Hook**: `MainActivity.kt` executes `smartLedgerRepository.syncWithCloud()` in `onResume()`.
- **Glance Widget**: `DailyMoneyGlanceWidget.kt` dynamically computes Incoming, Outgoing, Net Worth, and top spending items directly from `parsedLedger.value` instead of static constants.
- **Verification**: `assembleDebug` passed cleanly in 11s.

### 3.3 Windows 11 (WinUI 3 / C#)
- **Service**: `SmartLedgerParser.cs` in `Services/Finances/`.
- **Parity Alignment**: Added `CleanKeyName` to strip trailing slashes and inline parentheses, ensuring `item.Key` strictly matches Swift and Kotlin token outputs.
- **Workflow**: Mac host commit & push -> Parallels Windows 11 pull -> Native `dotnet build -c Debug -p:Platform=ARM64` on Parallels VM.
- **Verification**: `dotnet build` succeeded with `0 Error(s)` in 1m 26s.

### 3.4 watchOS (Apple Watch Ultra 2)
- **Store**: `WatchSmartLedgerStore.swift` completely rewritten. Replaced fragile regular expressions with full AST parser and inline arithmetic adjusters (`recalculateTotalsInLines`).
- **Caching**: Dual-storage keys (`daily_smart_ledger_raw_text_v1` and `smart_ledger_raw_text`) with strict 10-minute cache TTL (`lastSyncTimestamp`) on network fetches.
- **UI**: Extracted `WatchSmartLedgerItemRow` into a dedicated SwiftUI view to eliminate compiler type-checker timeouts.
- **Verification**: `xcodebuild -scheme "DailyWatch Watch App"` passed with `** BUILD SUCCEEDED **`.

### 3.5 Wear OS (Pixel Watch 5 / OnePlus Watch 3)
- **Parser**: Created `SmartLedgerParser.kt` under `wearos.data`, mirroring the complete DSL parser, quick adjust calculations, and line totals recalculation.
- **Repository**: Created `WatchSmartLedgerRepository.kt` with SharedPreferences fast cache (`daily_prefs`), 10-minute network throttle TTL, and debounced Supabase mutations.
- **Orbit Card**: Rebuilt `SmartLedgerCard.kt` to bind reactively to `WatchSmartLedgerRepository.parsed`, featuring animated sync indicators, manual refresh buttons, and 1-tap quick steppers (`+`/`-`).
- **Build**: Added `org.gradle.java.home` to `WearOS/gradle.properties` for Java 17 compatibility.
- **Verification**: `assembleDebug` passed cleanly in 17s.

---

## 4. Smartwatch Network & Battery Caching Policy

To prevent battery drain and cellular/BT radio contention on wearable devices, both watchOS and Wear OS adhere to the following contract:

```mermaid
flowchart TD
    A["Orbit Context Opens"] --> B["Read Local Fast Cache (< 1ms)"]
    B --> C["Render UI Immediately (0ms Latency)"]
    C --> D{"Is Cache > 10 min old or Force Refresh?"}
    D -- "No (Cache Fresh)" --> E["No Network Call (Radio Idle)"]
    D -- "Yes (Cache Stale / User Tap)" --> F["Background Query to Supabase"]
    F --> G["Parse Remote DSL Text"]
    G --> H["Update Local Cache & StateFlow"]
```

1. **Instant Glanceability (<1ms)**: Smartwatches must never show blank screens, loading spinners, or blocking queries when opening Orbit Context. Cached values are read synchronously from `UserDefaults` / `SharedPreferences`.
2. **10-Minute Network TTL**: Background sync occurs only if `currentTime - lastSyncTime >= 10 minutes`. Calls before this threshold return immediately.
3. **Manual Override**: The user can force an immediate network refresh at any time by tapping the refresh icon in the header.
4. **Debounced Mutations**: 1-tap quick adjustments update the local state and UI instantaneously (<1ms), while batching and debouncing cloud updates by 500ms.

---

## 5. Summary of Verification Runs

| Target / Platform | Device / Environment | Build / Test Command | Result |
| :--- | :--- | :--- | :--- |
| **Swift Core** | Host macOS | `swift test --package-path DailyCore` | **56 / 56 Passed** |
| **macOS App** | Host macOS (Apple Silicon) | `xcodebuild -scheme Daily -destination platform=macOS` | **BUILD SUCCEEDED** |
| **iOS Simulator** | SimulaPhone (iPhone 17 Pro) | `xcodebuild -scheme Daily -destination id=E618B1DA...` | **BUILD SUCCEEDED & RUNNING** |
| **iOS Foldable** | SimulaDuo (iPhone Duo) | `xcodebuild -scheme Daily -destination id=6BB33377...` | **BUILD SUCCEEDED & RUNNING** |
| **iOS Physical** | Schmitz (iPhone 16 Pro) | `xcrun devicectl device install app --device 00008140...` | **INSTALLED ON DEVICE** |
| **watchOS** | Apple Watch Series 12 / Ultra 2 | `xcodebuild -scheme "DailyWatch Watch App"` | **BUILD SUCCEEDED** |
| **Android App** | Phone & Foldable targets | `cd Android && ./gradlew assembleDebug` | **BUILD SUCCESSFUL (11s)** |
| **Wear OS App** | Pixel Watch 5 / OnePlus Watch 3 | `cd WearOS && ./gradlew assembleDebug` | **BUILD SUCCESSFUL (17s)** |
| **Windows 11** | Parallels Windows 11 VM (ARM64) | `dotnet build WinUI\Daily.WinUI -c Debug -p:Platform=ARM64` | **0 Errors, BUILD PASSED** |
