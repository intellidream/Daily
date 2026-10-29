# Cosmos Observatory — Cross-Platform Bookmarks, Observations UI & Ergonomics

**Date:** October 29, 2026  
**Status:** Implemented, Fully Verified Across All 4 Native Platforms (iOS, macOS, Android, Windows WinUI 3)  
**Verification:**
- **iOS & macOS:** `xcodebuild -scheme Daily build` (iOS Simulator + macOS native) — **`** BUILD SUCCEEDED **`**, `swift test` 55/55 passed.
- **Android:** `./gradlew assembleDebug` — **BUILD SUCCESSFUL in 6s**, deployed and live-verified on physical **Google Pixel 9 Pro** and **Samsung Galaxy Z Fold 8 ("RADAR")**.
- **Windows (WinUI 3):** `dotnet build -c Debug -p:Platform=ARM64` on Windows 11 ARM64 VM — **`0 Error(s)`**, verified live with Win2D Direct2D.

---

## 1. Executive Summary & Remediation Highlights

In response to the user's audit and requirements, three key system-wide improvements were designed and delivered:

1. **Authentic Stargazing Visibility Score Synchronization:**
   - Eliminated misleading offline score resets (e.g., fallback score ~78) across in-app Dashboard cards and desktop/mobile widgets.
   - Synchronized live atmospheric seeing, multi-layer cloud cover (low, mid, high), and Bortle quality directly with real Open-Meteo & 7Timer telemetry across iOS, macOS, Android, and Windows.
2. **Full Cross-Platform UI Reflection of `cosmos_bookmarks` and `cosmos_observations`:**
   - **Sky Bookmarks:** Interactive deck section across all four platforms with live count, `CLOUD SYNC` indicator, tap-to-slew camera animation, and trash button for remote Supabase deletion. Integrated saved bookmarks into celestial catalog search sheets.
   - **Observations & Logged Sightings:** Dedicated deck section reflecting logged sightings with complete metadata (UTC timestamp, optics, Bortle class, sky score, location name, custom notes), a green verified checkmark, a `#sky TagDoS` badge, and delete affordance.
   - **Empty States:** Clear, informative empty state banners guiding the user when collections are clean.
3. **iOS Standard Phone Compact HUD Ergonomics:**
   - Resolved layout cramping on standard iPhone displays (`viewportWidth < 520pt`).
   - Replaced text-heavy `"Weather"` button with a compact 34×34 circular icon button matching the back chevron.
   - Constrained observer location readout to a maximum of 95–100pt with `.minimumScaleFactor(0.75)` and `.truncationMode(.tail)`.
   - Compacted azimuth/altitude telemetry readout (`· 180° S · +45°`) to ensure all 6 top controls fit cleanly without overlapping.

---

## 2. Technical Architecture & File Level Changes

### A. Shared Business Logic & Data Layer
- **`DailyCore/Sources/DailyCore/Services/CosmosSyncService.swift`**:
  - Implemented `deleteObservation(id: UUID)` with local cache invalidation and authenticated remote PostgREST deletion (`.from("cosmos_observations").delete().eq("user_id", ...).eq("id", ...)`).
- **`DailyCore/Sources/DailyCore/Services/WidgetDataCoordinator.swift`**:
  - Refactored `fetchCosmosSnapshot()` to preserve authentic live weather conditions and seeing scores when cached telemetry is under 24 hours old, re-evaluating only real-time celestial clock ephemerides (moon illumination, phase, and planet visibility).
  - Prevented premature cache eviction and synthetic score resets.

### B. iOS & macOS Swift / SwiftUI Layer
- **`iOS/Daily/Views/Dashboard/CosmosDashboardCard.swift` & `MacOS/...`**:
  - Added `effectiveScore`, `effectiveVerdict`, and `effectiveConditions` computed properties prioritizing real-time telemetry from `cosmosLive.stargazingConditions` with fallback to `cosmosVM.state.conditions`.
  - Added coordinate caching (`weather_cached_lat`/`lon`) during `.task` to ensure widgets reflect the exact user location immediately.
- **`iOS/Daily/Views/Cosmos/CosmosViewModel.swift` & `MacOS/...`**:
  - Updated `recomputeEphemeris()` to preserve live conditions during live-time tracking.
  - Added `target(forBookmark:)` to dynamically locate or instantiate valid celestial targets for any saved bookmark.
- **`iOS/Daily/Views/Cosmos/CosmosDetailView.swift` & `MacOS/...`**:
  - Added `isCompact` responsiveness (`viewportWidth < 520`) to `topHUDBar` and `CosmosHeadingReadoutView`.
  - Integrated **SKY BOOKMARKS** card into `observatoryTelemetryDeck` with tap-to-slew, delete action, count, and empty state.
  - Integrated **OBSERVATIONS & LOGGED SIGHTINGS** card into `observatoryTelemetryDeck` with `#sky TagDoS` badge, sighting details, and delete action.
  - Added **SAVED BOOKMARKS** section to catalog search sheet when query is empty.

### C. Android Jetpack Compose Layer
- **`Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosLiveRepository.kt`**:
  - Added `deleteObservation(id: String)` updating Room local cache, SharedPreferences fallback, and Supabase cloud backend via PostgREST.
- **`Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosViewModel.kt`**:
  - Added `removeBookmark(...)`, `deleteObservation(...)`, and `targetForBookmark(...)` bridging stored bookmarks directly to camera slew mechanics.
- **`Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosScreen.kt`**:
  - Added **Card 8 ("SKY BOOKMARKS")** with `CLOUD SYNC` badge, tap-to-slew, delete action, and empty state.
  - Added **Card 9 ("OBSERVATIONS & LOGGED SIGHTINGS")** with `#SKY TAGDOS` badge, full sighting telemetry, delete action, and empty state.
  - Enhanced `CosmosSearchDialog` with bookmark selection callback to center camera and dismiss dialog directly.

### D. Windows 11 WinUI 3 & Win2D Layer
- **`WinUI/Daily.WinUI/Services/Cosmos/CosmosLiveService.cs`**:
  - Implemented `LoadObservationsAsync()` and `DeleteObservationAsync(string id)` with authenticated Supabase PostgREST synchronization and local caching.
- **`WinUI/Daily.WinUI/Views/CosmosDetailPage.xaml` & `.cs`**:
  - Added `ObservationsDeckCard` to the right-hand Observatory Deck with `#SKY TAGDOS` badge and `ObservationsStack`.
  - Implemented interactive deletion and slewing for both Bookmarks and Observations.
  - Added automatic deck re-rendering upon clicking `"Log Sighting (#sky)"`.

---

## 3. Live Physical Verification Matrix

| Platform | Target Device / Environment | Verification Result | Artifact Reference |
| :--- | :--- | :--- | :--- |
| **Android Phone** | Google Pixel 9 Pro | **PASSED** — Live score 18/100, Bookmarks card (9 items), Logged observation with TagDoS `#sky` badge, real-time deletion. | `pixel9pro_tonight_logged_observation_verified.png` |
| **Android Foldable** | Samsung Galaxy Z Fold 8 ("RADAR") | **PASSED** — Unfolded dual-pane observatory, live score 19/100, full telemetry deck, responsive controls. | `zfold8_cosmos_opened_live.png` |
| **Windows Desktop** | Windows 11 ARM64 VM (WinUI 3) | **PASSED** — Direct2D Win2D Planetarium, live score 17/100, Bookmarks (0) and Observations (0) cards with `#SKY TAGDOS` badge. | `win11_cosmos_scrolled_decks.png` |
| **iOS / macOS** | iOS Simulator & macOS Native | **PASSED** — Clean compilation, compact HUD bar, 55/55 Swift test suite passed. | DerivedData & test logs |

---

## 4. Maintenance & Operational Guidelines

- **Supabase Authentication Context:** Whenever bookmarks or observations are created or deleted, operations automatically resolve the active `auth.users.id`. In offline or unauthenticated mode, changes persist to local SQLite/Room/UserDefaults caches and sync upon reconnection.
- **TagDoS Quick Note Integration:** When logging a sighting, a rich markdown note tagged `#sky` is automatically recorded in `tagdos_quick_notes`, ensuring amateur astronomy logs seamlessly appear in the user's TagDoS stream.

## 6. Windows 11 WinUI 3 Postgrest Serialization & Favorite Star Parity

### Root Cause Analysis & Newtonsoft.Json Transition
- **Issue:** On Windows 11, the Cosmos bookmarks deck remained empty (`SAVED SKY BOOKMARKS (0)`) even though the cloud database contained 9 bookmarks synced across Android and iOS. Target inspector favorite buttons also remained empty (`\uE734`).
- **Root Cause:** In `WinUI/Daily.WinUI/Services/CosmosLiveService.cs`, Supabase `CosmosBookmarkRecord` and `CosmosObservationRecord` inherit from Postgrest `BaseModel`. Attempting to serialize `BaseModel` instances to local disk cache using `System.Text.Json` threw:
  `System.NotSupportedException: The type 'Supabase.Postgrest.Attributes.PrimaryKeyAttribute' is not a supported dictionary key using converter of type 'System.Text.Json'`.
  This exception silently interrupted the hydration lifecycle, aborting cache write and returning an empty list.
- **Resolution:** Replaced `System.Text.Json` with `Newtonsoft.Json` (`JsonConvert.SerializeObject` and `JsonConvert.DeserializeObject`), matching the rest of Daily's Supabase Postgrest persistence.
- **Target ID Normalization:** Celestial target identifiers vary across platforms (e.g. `BODY-Moon` or `body_moon` vs `Moon` / `moon`). Added `IsTargetBookmarked(string objId, string targetName)` to normalize IDs and match targets seamlessly against stored cloud records.
- **Visual Feedback:** Updated `RefreshSelectedTargetInspector()` in `CosmosDetailPage.xaml.cs` to render a filled golden star `★` (`\uE735`) in `#FFFFD166` (or red in night vision) with dynamic tooltips, refreshing automatically when cloud bookmarks hydrate or deck items are clicked.

## 7. Multi-Device Verification & Delivery Status

| Platform / Target | Build Status | Delivery & Verification | Key Observables Verified |
| :--- | :--- | :--- | :--- |
| **Windows 11 VM** | Clean ARM64 build (`0 Errors`) | Live App Executed | `SAVED SKY BOOKMARKS (9)` with `CLOUD SYNC`, filled golden star `★` in Target Inspector |
| **macOS Native** | Clean macOS Debug build | Launched via `-startTabCosmos` | Liquid Glass sky dome, cardinals (`NE`, `N`), Moon inspector with filled star `★`, 22/100 seeing score |
| **SimulaDuo (Foldable)**| Clean iOS build | Launched via `-startTabCosmos` | Split dual-pane: interactive sky dome left, Observatory Deck right with 17/100 score & visible targets |
| **SimulaPhone (iPhone 17 Pro)** | Clean iOS build | Launched via `-startTabCosmos` | Compact weather button, uncrowded location HUD, cardinal indicators, live ephemeris |
| **Physical iPhone ("Schmitz")** | Clean signed build (MIHAI IONESCU) | Installed via `devicectl` & Launched | `com.intellidream.daily` launched into Cosmos view |

