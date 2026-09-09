# WearOS & HarmonyOS Ecosystem Parity: DayOne Orbit

## Overview
This feature implements **1:1 complete parity** for both the **WearOS** (`com.intellidream.daily.wearos`) and **HarmonyOS** (`com.intellidream.daily`) companion apps, bringing them to the exact gold-standard established on **watchOS** and **ZeppOS**.

---

## 1. Parity Matrix: Across All 4 Companion Platforms

| Feature / Dimension | Apple watchOS | Amazfit ZeppOS | Google WearOS | Huawei HarmonyOS |
| :--- | :--- | :--- | :--- | :--- |
| **App Name** | `DayOne Orbit` | `DayOne Orbit` | `DayOne Orbit` | `DayOne Orbit` |
| **App Icon** | 3D Orbit Glowing Logo | 3D Orbit Glowing Logo | 3D Orbit Glowing Logo | 3D Orbit Glowing Logo |
| **Main Layout** | 5-Tab Pager | 5-Page Swiper | 5-Page `HorizontalPager` | 5-Page `Swiper` |
| **Page 0: Bubbles** | Ring + 3 Btns + Breakdown + In-Flow Logs | Ring + 3 Btns + Breakdown | Ring + 3 Btns + Breakdown + In-Flow Logs | Ring + 3 Btns + Breakdown + In-Flow Logs |
| **Page 1: 💧 7 Days**| Mon–Sun Stacked Chart | Mon–Sun Stacked Chart | Mon–Sun Stacked Chart | Mon–Sun Stacked Chart |
| **Page 2: Smokes** | Ring + 2 Btns + Breakdown + In-Flow Logs | Ring + 2 Btns + Breakdown | Ring + 2 Btns + Breakdown + In-Flow Logs | Ring + 2 Btns + Breakdown + In-Flow Logs |
| **Page 3: 🔥 7 Days**| Mon–Sun Stacked Chart | Mon–Sun Stacked Chart | Mon–Sun Stacked Chart | Mon–Sun Stacked Chart |
| **Page 4: About** | Logo + Status + Health + Unpair | Logo + Health + Unpair | Logo + Status + Health + Unpair | Logo + Status + Health + Unpair |
| **Chevrons Header**| `‹ Today ›` (sleek chevrons)| `◀ Today ▶` (sleek controls)| `‹ Today ›` (sleek chevrons)| `‹ Today ›` (sleek chevrons)|
| **Week Navigation**| `‹ This Week ›` (Mon–Sun) | `◀ This Week ▶` (Mon–Sun) | `‹ This Week ›` (Mon–Sun) | `‹ This Week ›` (Mon–Sun) |
| **Action Buttons** | `💧 300`, `💧 150`, `☕ 100`<br>`🔥 Cig`, `⚡ Heat` | `💧 300`, `💧 150`, `☕ 100`<br>`🔥 Cig`, `⚡ Heat` | `💧 300`, `💧 150`, `☕ 100`<br>`🔥 Cig`, `⚡ Heat` | `💧 300`, `💧 150`, `☕ 100`<br>`🔥 Cig`, `⚡ Heat` |
| **Breakdown Line** | `💧 ... • ☕ ...`<br>`🔥 ... • ⚡ ...` | `💧 ... • ☕ ... ›`<br>`🔥 ... • ⚡ ... ›` | `💧 ... • ☕ ...`<br>`🔥 ... • ⚡ ...` | `💧 ... • ☕ ...`<br>`🔥 ... • ⚡ ...` |
| **Logs Placement** | Embedded in-flow under rings | Dedicated sub-page (memory-safe) | Embedded in-flow under rings | Embedded in-flow under rings |
| **Log Tap Action** | Tap to Delete (with dialog) | Tap to Delete (with dialog) | Tap to Delete (with dialog) | Tap to Delete (with dialog) |
| **Health Sync Text**| `Health: synced at [Time]` | `Health: synced at [Time]` | `Health: synced at [Time]` | `Health: synced at [Time]` |
| **Rotary / Crown** | Digital Crown vertical scroll | N/A | Rotary input (`onRotaryScrollEvent`) | Crown Scroll / Swipe |
| **OS Widgets** | WidgetKit Complications | N/A | Tiles & Complications with Tap Intent | Service Cards (`🔥`) |

---

## 2. 5-Page Horizontal Navigation Architecture

All companion apps now share an identical 5-page horizontal swiper/pager experience:
1. **Page 0 (`💧 Bubbles`)**:
   - Title: `💧 Bubbles`
   - Temporal header: `◀ Today ▶` / `◀ Yesterday ▶` / `◀ EEE, d MMM ▶` (with forward button hidden on today).
   - Dual-arc progress ring: Cyan Water arc + Orange Coffee arc. Center displays `Total / Goal`.
   - Action buttons: `💧 300`, `💧 150`, `☕ 100`.
   - Breakdown text: `💧 X ml  •  ☕ Y ml  ›`.
   - Tapping the center ring or breakdown opens the dedicated **Habit Logs Screen**.
2. **Page 1 (`💧 7 Days`)**:
   - Title: `💧 7 Days`
   - Temporal header: `◀ This Week ▶` / `◀ Last Week ▶` / `◀ d MMM - d MMM ▶` (with forward button hidden on this week).
   - 7-Column Monday–Sunday stacked histogram: Water (Cyan) + Coffee (Orange).
   - Dashed horizontal Goal line at daily target.
   - Metric summary row: `💧 Avg: X ml/d  •  Goal: Y ml`.
3. **Page 2 (`🔥 Smokes`)**:
   - Title: `🔥 Smokes`
   - Temporal header: `◀ Today ▶` / `◀ Yesterday ▶` / `◀ EEE, d MMM ▶` (with forward button hidden on today).
   - Progress ring: Green (`< 75%`), Orange (`75-99%`), Red (`≥ 100%`). Center displays `Total / Baseline`.
   - Action buttons: `🔥 Cig`, `⚡ Heat`.
   - Breakdown text: `🔥 X cig  •  ⚡ Y heat  ›`.
   - Tapping the center ring or breakdown opens the dedicated **Habit Logs Screen**.
4. **Page 3 (`🔥 7 Days`)**:
   - Title: `🔥 7 Days`
   - Temporal header: `◀ This Week ▶` / `◀ Last Week ▶` / `◀ d MMM - d MMM ▶` (with forward button hidden on this week).
   - 7-Column Monday–Sunday stacked histogram: Cigarette (Red) + Heated Tobacco (Blue).
   - Dashed horizontal Baseline line.
   - Metric summary row: `🔥 Avg: X/d  •  Base: Y`.
5. **Page 4 (`⚙️ About`)**:
   - Official 3D Orbit logo.
   - App branding: `DayOne Orbit`, `v1.0`.
   - Connection status: `Connected` (green).
   - Health telemetry status: `synced` / `not synced`.
   - `Unpair Watch` destructive button with confirmation dialog.

---

### 3. In-Flow Habit Logs List & Soft-Delete (watchOS, WearOS & HarmonyOS)

To provide instant access to daily activity without unnecessary screen transitions:
- **In-Flow Logs**: On watchOS, WearOS, and HarmonyOS, the day's logged habit entries are placed directly underneath the progress ring and breakdown summary within the vertical scroll container (`ScalingLazyColumn` on WearOS, `Scroll()` on HarmonyOS, `ScrollView` on watchOS).
- **Entries**: Cards display habit emoji (`💧`, `☕`, `🔥`, `⚡`), exact amount & type (`300 ml Large`, `100 ml Coffee`, `1 Cig`, `1 Heat`), and localized time `HH:mm`.
- **Natural Tap to Delete**: Tapping on any individual log entry triggers an OS-native confirmation dialog (`Delete Log?`), replacing previous awkward long-press or separate sub-pages.
- **ZeppOS Independence**: ZeppOS continues to utilize dedicated lightweight sub-pages due to micro-controller memory limits and non-scrollable nested view architectures.
- **Multi-Device Soft-Delete**: Deletion sends a `PATCH` request setting `{ is_deleted: true }` in the Supabase `habits_logs` table, keeping all connected devices in sync without data loss.

---

## 4. Historical Habit Logging

When the user navigates to a past date (`dayOffset < 0`) and taps an action button (`💧 300`, `☕ 100`, `🔥 Cig`, `⚡ Heat`):
1. The app computes the exact timestamp on that past day (`logged_at`).
2. The log is inserted into Supabase with that historical timestamp.
3. The day's totals, progress arcs, and the corresponding 7-day histogram bar update optimistically.

---

## 5. OS Integration, Complications & Tiles

- **WearOS**:
  - `strings.xml`: Application name set to `DayOne Orbit`.
  - Complication Tap Actions: `WaterComplicationService` launches `MainActivity` directly to Page 0 (`💧 Bubbles`); `SmokesComplicationService` launches `MainActivity` directly to Page 2 (`🔥 Smokes`).
  - Tile Tap Action: `DailyTileService` (`GlanceTileService`) launches `MainActivity` upon click.
  - Emoji unification: Complications and Tiles updated from `🚬` to `🔥`.
  - Icons: High-resolution 3D Orbit logo generated across all mipmap densities (`mdpi` through `xxxhdpi`) and `res/drawable/orbit_logo.png`.
- **HarmonyOS**:
  - `AppScope/resources/base/element/string.json`: `app_name` set to `DayOne Orbit`.
  - `entry/src/main/resources/base/element/string.json`: `EntryAbility_label` set to `DayOne Orbit`.
  - Icons: `startIcon.png` and `foreground.png` updated with official 3D Orbit logo.
  - Card & complication labels unified with DayOne Orbit branding.

---

## 6. Pairing Handshake Architecture (`watch_pairing_codes`)

Both WearOS and HarmonyOS utilize the exact same handshake channel established by watchOS and ZeppOS:
1. **Watch Generates 6-Digit PIN**: Inserts `{ pin_code: "<6-digit-pin>" }` into `public.watch_pairing_codes` with `'Prefer': 'return=representation'`.
2. **Watch Displays Instruction**: `"Enter this PIN in DayOne to link."` with large monospace green digits.
3. **User Claims PIN in DayOne (Desktop / Mobile)**: The user enters the PIN into the DayOne app (`FeaturesPage` / `Settings`). The app claims the code by updating `claimed = true`, generating a long-lived JWT token, and writing `access_token`.
4. **Watch Polls & Retrieves Session**: Watch polls `watch_pairing_codes?pin_code=eq.<pin>&select=*` every 2.5s. When `claimed == true` and `access_token` is present, it imports the token, deletes the pairing code row, registers the watch in `paired_watches`, and enters the 5-page dashboard.

### 6.1 WearOS Pairing Infinite Loop Prevention & Idempotency
- **Immediate Polling Invalidation**: As soon as `access_token` is retrieved from `watch_pairing_codes`, `stopPolling()` is executed immediately, setting volatile `isPolling = false`, `isPairingCompleted = true`, and cancelling `pollJob`. This prevents subsequent coroutine iterations from running even if backend network calls take multiple seconds.
- **Structured Concurrency Protection**: `CancellationException` is explicitly re-thrown in all suspend catches rather than swallowed by generic `catch (e: Exception)`.
- **Direct DataStore State Persistence**: Tokens (`access_token`, `refresh_token`, `user_id`) are written directly to DataStore and memory StateFlows (`_isAuthenticated = true`, `_currentUserId = uid`) inside the handler, guaranteeing immediate UI transition without relying on asynchronous session status events.
- **10-Year Watch JWT Support**: DayOne Orbit watch tokens are long-lived (10 years) and issued with an empty refresh token (`refresh_token = ""`). Authentication and recovery checks across `checkExistingSession()`, `recoverFromDataStore()`, and `startSessionListener()` check for valid `access_token` and `user_id`, treating empty refresh tokens as normal rather than forcing a pairing reset.
- **`registerPairing` Idempotency Guard**: Prior to executing `POST /rest/v1/paired_watches`, `WatchSessionManager` verifies whether a `paired_watch_id` already exists in DataStore. If already registered, subsequent duplicate insertions are prevented.

### 6.2 WearOS Duplicate PIN Generation & Post-Pairing PostgREST Auth Fix
- **Root Cause 1 (Duplicate PINs)**: In `DailyWearApp`, when not yet authenticated, `PairingScreen` was composed. `PairingScreen` triggered a redundant `LaunchedEffect(Unit) { sessionManager.checkExistingSession() }` simultaneously with `WatchSessionManager.getInstance(context)`. Both coroutines ran concurrently without a re-entrancy mutex, found an empty DataStore, generated two separate 6-digit PIN codes, and inserted both into `watch_pairing_codes`. The UI displayed PIN 1 while the backend polling job was overridden with PIN 2.
  - *Fix*: Removed redundant `LaunchedEffect` in `PairingScreen`, introduced `@Volatile private var isCheckingSession = false` mutex in `WatchSessionManager.checkExistingSession()`, and guarded against re-generating PINs if a code is already active (`!_isPairing.value || _pairingCode.value.isEmpty()`).
- **Root Cause 2 (No Data After Pairing)**:
  1. PostgREST requests authenticate via Supabase Auth's `currentAccessTokenOrNull() ?: supabaseAnonKey`. `importAuthToken(token, "")` creates a `UserSession` with `expiresIn = 0L`, causing the library to treat the token as immediately expired and fall back to the anonymous key, returning empty arrays (`[]`) under Supabase RLS.
  2. Setting `_isAuthenticated.value = true` before importing the token triggered immediate composition of `BubblesScreen` and `SmokesScreen`, which fired PostgREST queries before the auth plugin had the bearer token in memory.
  3. In `BubblesScreen` and `SmokesScreen`, exception catch blocks previously called `refreshCurrentSession()`. For 10-year Orbit tokens with no refresh token, Supabase Auth returned 400 Bad Request, triggering `clearSession()` and wiping the authenticated session permanently.
  - *Fix*: Added `importOrbitSession(accessToken, refreshToken)` configuring `UserSession` with `expiresIn = 315360000L` (10 years in seconds) and `autoRefresh = false`. Called `importOrbitSession` **before** setting `_isAuthenticated.value = true`, and eliminated the destructive `refreshCurrentSession()` calls from screen error catch blocks.

### 6.3 WearOS Post-Pairing Black Screen & Safe FocusRequester
- **Root Cause 1 (Dead Black Box in UI Tree)**: In `DailyWearApp.kt`, an `else if (isPairing) PairingScreen(...) else { Box(background) }` construct created an empty, black, unrecoverable container whenever `isAuthenticated == false` and `isPairing == false`. When pairing completed and `_isPairing.value = false` was emitted, the UI fell into the dead black box.
  - *Fix*: Replaced `else if (isPairing)` with `else { PairingScreen(sessionManager) }`. `PairingScreen` already natively displays connecting progress, PIN display, and retry states.
- **Root Cause 2 (FocusRequester Exception in Pager Pages)**: `HorizontalPager` composes adjacent pages simultaneously. Calling `focusRequester.requestFocus()` in `LaunchedEffect(Unit)` without try-catch threw an `IllegalStateException: FocusRequester is not initialized` if layout wasn't yet attached, cancelling the Composition coroutine scope and killing the UI tree.
  - *Fix*: Wrapped all `focusRequester.requestFocus()` calls in `try { focusRequester.requestFocus() } catch (_: Exception) {}` across all 5 screens.
- **Root Cause 3 (Atomic Pairing State Transitions & UID Fallback)**: In `checkPairingStatus()`, `extractUserId(token)` now falls back to `pairing.user_id` from the database record (`val uid = extractUserId(token) ?: pairing.user_id`). DataStore persistence and session import complete before updating `_currentUserId`, `_isAuthenticated`, `_isPairing`, and `_pairingCode` atomically in a single state pass.

---

## 7. WearOS Rotary Input & Layout Centering

- **Rotary Crown Support**: All scrollable screens (`BubblesScreen`, `Bubbles7DaysScreen`, `SmokesScreen`, `Smokes7DaysScreen`, `AboutScreen`) capture physical bezel/crown rotations via `focusRequester`, `focusable()`, and `onRotaryScrollEvent { listState.scrollBy(pixels) }`, with safe try-catch focus request guards.
- **Vertical Viewport Centering**: Removed default `autoCentering` (`autoCentering = null`) from `ScalingLazyColumn` and applied content padding `PaddingValues(top = 22.dp, bottom = 28.dp, start = 8.dp, end = 8.dp)`. This prevents round displays from clipping the bottom content or pushing the progress ring down on initial launch.
- **Robust ISO Timestamp Parsing**: Replaced fragile `SimpleDateFormat` parsing with `OffsetDateTime.parse` and `Instant.parse`, guaranteeing that past-week histogram queries and local time conversions never drop logs containing microseconds or timezone offsets.

---

## 8. Universal Health Sync Timestamp Format

All 4 platforms now adhere to the unified sync status string:
```text
Health: synced at [DateTime]
```
- For same-day synchronization: `Health: synced at HH:mm` (e.g., `Health: synced at 14:32`).
- For previous-day synchronization: `Health: synced at HH:mm, d MMM` (e.g., `Health: synced at 14:32, 9 Sep`).
- If never synced: `Health: not synced` (styled in warning/error red).
- Unified on ZeppOS (`debugText`), WearOS (`AboutScreen`), HarmonyOS (`AboutView`), and watchOS (`AboutView`).

---

## 7. WearOS Pairing Flow & Storage Resilience Fix

### Problem
When pairing the WearOS watch application with DayOne Desktop/Mobile, the pairing PIN was successfully claimed and updated in Supabase (`watch_pairing_codes` had `claimed = true` and `access_token = ...`), but the WearOS app remained indefinitely stuck on the pairing screen displaying `Waiting for authorization...` without transitioning into the dashboard.

### Root Cause
1. **Jetpack DataStore Mutex/Futex Deadlock**: `WatchSessionManager` used Jetpack `DataStore` with `context.dataStore.edit { ... }`. Concurrently, `DailyTileService` was executing `runBlocking { dataStore.data.first() }`, and complication services were also reading from `DataStore`. When `checkPairingStatus()` found the claimed PIN, it invoked `dataStore.edit`, which hung in `futex_wait_queue` due to internal lock contention and thread starvation between coroutine scopes.
2. **Synchronous Dependency on Storage Before State Transition**: UI state emission (`_isAuthenticated.value = true`, `_isPairing.value = false`) was placed after `dataStore.edit` and `importOrbitSession`, causing any delay or hang in storage to freeze the UI in the pairing state.

### Solution
1. **Migration to SharedPreferences**: Replaced Jetpack `DataStore` with Android's native, synchronous, and thread-safe `SharedPreferences` (`"daily_prefs"`), which exactly mirrors `UserDefaults.standard` on Apple Watch (watchOS) and `dataPreferences` on Huawei HarmonyOS.
   - Eliminated `runBlocking` from `DailyTileService`.
   - Replaced asynchronous reads and writes in `WatchSessionManager`, `WaterComplicationService`, `SmokesComplicationService`, and `AboutScreen` with instantaneous `SharedPreferences` operations.
2. **Immediate UI State Transition**: In `checkPairingStatus()`, once the token and user ID are verified, `_isAuthenticated.value = true` and `_isPairing.value = false` are updated immediately, allowing the UI to transition seamlessly to the 5-page dashboard without waiting on non-blocking background tasks (`importOrbitSession`, remote record cleanup, or device registration).
3. **SupervisorJob Coroutine Protection**: Ensured `WatchSessionManager` uses `SupervisorJob() + Dispatchers.IO` so that failures in auxiliary network coroutines never cancel the session management scope.

---

## 9. WearOS Refinements: Last Week Histograms, Rotary Scroll & About Polish

### 1. Last Week Histogram Deserialization Fix
- **Problem**: When navigating to "Last Week" on both Bubbles and Smokes 7-day screens, the charts rendered 0 bars and 0 averages, despite logs existing in Supabase.
- **Root Cause**: Earlier logs in Supabase contained raw JSON objects inside the `metadata` column (e.g., `{"drink": "Small Water"}` or `{"type": "Cigarette"}`), unlike newer stringified JSON values (`"{\"drink\":\"...\"}"`). In Kotlinx Serialization, deserializing a JSON object into a `String?` field threw a `JsonDecodingException` which was caught silently, discarding all week logs. Furthermore, legacy timestamps with space separators or fractional microsecond precisions failed standard ISO8601 parsing.
- **Solution**:
  - Implemented `FlexibleMetadataSerializer` and `FlexibleDoubleSerializer` on `HabitLog`, dynamically converting `JsonNull`, `JsonPrimitive`, `JsonObject`, and `JsonArray` into safe strings, and accommodating mixed integer/double types.
  - Created `HabitDateParser.parseToLocalDate` with multi-tier parsing (OffsetDateTime, Instant, and SimpleDateFormat patterns for PostgreSQL timestamps).
  - Enlarged `TemporalNavHeader` chevron touch targets to 36x28dp with bold 17sp gliphs for effortless tapping on round screens.

### 2. Rotary Crown Multi-Page Focus Fix
- **Problem**: Physical rotary crown scrolling worked exclusively on the initial page (Bubbles) but did not work when swiping to Smokes (to scroll down to today's logs) or other pages.
- **Root Cause**: `HorizontalPager` pre-composes adjacent pages. When using `LaunchedEffect(Unit)`, only the initial page requested and maintained rotary focus. As the user navigated horizontally to other pages, the active page never called `focusRequester.requestFocus()`, leaving rotary events captured by page 0 or dropped.
- **Solution**:
  - Passed `isPageActive = (pagerState.currentPage == page)` from `DailyWearApp`'s `HorizontalPager` into each screen (`BubblesScreen`, `Bubbles7DaysScreen`, `SmokesScreen`, `Smokes7DaysScreen`, `AboutScreen`).
  - Added `LaunchedEffect(isPageActive)` in all screens: whenever a screen becomes active, it immediately requests focus via `focusRequester.requestFocus()`, ensuring the rotary crown smoothly scrolls each page's list.

### 3. About Screen Layout & Button Polish
- **Problem**: The app version `v1.0` was drawn overlapping the title text `DayOne Orbit`, and the "Unpair Watch" button was disproportionately wide across the bottom of the circular display.
- **Solution**:
  - Encapsulated `DayOne Orbit` and `v1.0` inside a centered `Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth())` with a 2dp spacer, ensuring `v1.0` is always centered neatly beneath the title.
  - Refined the "Unpair Watch" button into a sleek, compact pill button with `width(128.dp)`, `height(32.dp)`, and `shape = RoundedCornerShape(16.dp)`, eliminating edge-to-edge stretching on circular watch faces.

---

## 10. WearOS Rotary Coordination & Previous Days Non-Cumulative Isolation Fix

### 1. Rotary Crown Multi-Page Focus Architecture (`HierarchicalFocusCoordinator`)
- **Problem**: Physical crown rotary scrolling only worked on Page 0 (Bubbles). Swiping to Smokes (Page 2) or Charts (Pages 1 & 3) failed to scroll with the physical crown on hardware devices (OnePlus Watch 2 / `OPWWE251`), despite touch drag working.
- **Root Cause**:
  1. `androidx.wear.compose.foundation`'s `ScalingLazyColumn` natively uses `rememberActiveFocusRequester()` for its default rotary behavior (`RotaryScrollableDefaults.behavior(listState)`), which requires a parent `HierarchicalFocusCoordinator` to know which leaf composable is active in a pager hierarchy.
  2. In `DailyWearApp`, `HorizontalPager` did not declare `HierarchicalFocusCoordinator`. Page 0 retained focus permanently from initial composition, while Page 2 failed to gain focus mid-swipe. Rotary events on Page 2 were dispatched to Page 0 in the background.
  3. Screens attached conflicting, unregistered manual `FocusRequester` instances and `.onRotaryScrollEvent { ... }` handlers that intercepted rotary input and short-circuited Compose's native rotary fling and haptic behaviors.
- **Solution**:
  - Wrapped each page in `HorizontalPager` with `HierarchicalFocusCoordinator(requiresFocus = { pagerState.currentPage == page && !pagerState.isScrollInProgress })`. When a swipe animation settles on a page, focus is cleanly transferred to that page's list while clearing focus from previous pages.
  - Removed manual `.onRotaryScrollEvent` listeners and manual focus requesters from `BubblesScreen`, `SmokesScreen`, `Bubbles7DaysScreen`, `Smokes7DaysScreen`, and `AboutScreen`, delegating rotary input directly to Wear Compose's built-in `rotaryScrollable` handler with velocity tracking and rotary haptics.

### 2. Previous Days Cumulative Logs Accumulation Fix
- **Problem**: When navigating to previous days (`dayOffset < 0`) via the temporal chevrons on `BubblesScreen` or `SmokesScreen`, entries appeared cumulative — yesterday displayed yesterday + today; two days ago displayed day -2 + yesterday + today.
- **Root Cause**:
  1. `postgrest-kt` 3.0.0 builds query parameters using `params.mapToFirstValue()`, taking only the first item in `List<String>` for a given key. When calling `gte("logged_at", startStr)` followed by `lt("logged_at", endStr)`, both mapped to key `"logged_at"`, causing `mapToFirstValue()` to silently discard `lt(...)`. The network request sent to PostgREST was strictly `logged_at=gte.startStr`, pulling all logs from that past date up to the present.
  2. `BubblesScreen` and `SmokesScreen` lacked an in-memory local date safeguard, directly calculating totals and populating `dayLogs` with all returned records.
- **Solution**:
  - Wrapped timestamp constraints in PostgREST `and { gte("logged_at", startStr); lt("logged_at", endStr) }`, generating PostgREST URL parameter `and=(logged_at.gte.startStr,logged_at.lt.endStr)` where both upper and lower bounds are preserved and evaluated on Supabase.
  - Formatted timestamps using ISO-8601 UTC strings via `Instant.ofEpochMilli(time).toString()`.
  - Added strict in-memory local date filtering via `HabitDateParser.parseToLocalDate(log.logged_at)?.toString() == targetDateStr`, guaranteeing 100% mathematical day isolation even in edge cases of network or timezone boundary mismatches.

---

## 11. WearOS Smokes Multi-Record Quantities & Pairing Duplicate Elimination

### 1. Smokes Multi-Record Value Interpretation & UI Multipliers
- **Problem**: When a user logged multiple cigarettes or heated units in a single record (e.g. `value = 13.0` logged via DayOne desktop or mobile), WearOS `SmokesScreen` calculated it as only 1 unit (`tCig += 1` / `tHeat += 1`). The progress ring displayed `28 / 40` instead of `40 / 40`, and the log history list rendered only `Heated Tobacco` without any quantity count.
- **Root Cause**:
  - In `SmokesScreen.kt`, the summation loop hardcoded `if (isHeat) tHeat += 1 else tCig += 1` instead of extracting `val count = maxOf(1, log.value.toInt())`.
  - The `deleteLog` callback also subtracted only 1 unit (`maxOf(0, todayHeat - 1)`).
  - The LazyColumn items rendered only `displayType` without checking if `log.value > 1`.
- **Solution**:
  - In `SmokesScreen.kt`, updated `fetchLogs()` to accumulate `val count = maxOf(1, log.value.toInt())` for both `tHeat` and `tCig`.
  - In `deleteLog`, updated decrements to subtract `count` rather than 1.
  - In `SmokesScreen.kt` list items, added quantity multiplier formatting: if `count > 1`, item displays `"${count}× $baseType"` (e.g. `13× Heated Tobacco`), else `$baseType`.
  - In `SmokesScreen.kt` delete confirmation alert, updated dialog text to show `"${count}× $typeName"`.
  - In `Smokes7DaysScreen.kt`, updated bucket accumulation to ensure `val count = if (log.value > 0) log.value else 1.0` is added to `bucket.cig` or `bucket.heat`.

### 2. Elimination of Duplicate `paired_watches` Entries & Remote Unpair Parity
- **Problem**: During WearOS pairing, two rows were being inserted into `public.paired_watches`:
  1. One row created by DayOne Desktop/MAUI (`FeaturesPage.xaml.cs` / `Settings.razor`) with `device_name: "Wear OS"`, `last_token_push: null`, `is_active: true`.
  2. A second row created 2 seconds later by `WatchSessionManager.kt` via `POST /rest/v1/paired_watches` with `device_name: Build.MODEL` (`"OPWWE251"` or `"sdk_gwear_arm64"`).
  Because the watch generated its own row and stored that ID in `SharedPreferences`, the desktop-created row remained an untracked orphan duplicate in the database.
- **Root Cause**:
  - DayOne Desktop creates a `PairedWatch` placeholder row immediately upon claiming the PIN so the desktop UI can show the paired watch immediately without waiting for watch polling.
  - `WatchSessionManager.kt` executed a blind `POST` without checking if an active pairing placeholder was already created for that `user_id` and `platform = "wearos"`.
- **Solution**:
  - In `WatchSessionManager.kt` (`registerPairing`):
    1. **Safe Adoption Pattern**: Before inserting, queries `/rest/v1/paired_watches?user_id=eq.$userId&platform=eq.wearos&or=(device_name.eq.Wear%20OS,device_name.eq.Watch)&is_active=eq.true&order=paired_at.desc&limit=1`. It strictly targets generic desktop-created placeholders (`"Wear OS"` or `"Watch"`).
    2. **Hardware Metadata Upgrade**: Sends a `PATCH` to `/rest/v1/paired_watches?id=eq.$adoptedId` with `{ "device_name": "$deviceName", "last_token_push": "$now" }`, upgrading the generic placeholder label to the actual hardware model (`"OPWWE251"` / `"sdk_gwear_arm64"`) and recording the pairing timestamp.
    3. **Preservation of Other Active Watches (Simultaneous Multi-Device Support)**: Removed destructive deactivations of other watches. Since existing active watches already have their `device_name` changed to their model name, they are never matched or modified during new pairings. Multiple WearOS devices (e.g., OnePlus Watch 2 and the emulator) can coexist simultaneously.
    4. **Fallback Creation**: If no desktop placeholder was created, cleanly inserts a new record with `device_name = Build.MODEL`, `is_active = true`, and `last_token_push = now()`.
  - In `WatchSessionManager.kt` (`checkForRepairTokens`):
    - Remote unpair parity: only triggers logout if the device's record explicitly exists with `is_active == false` (`record != null && record.is_active == false`), matching watchOS behavior and avoiding unintended logouts.
    - Allowed repair token recovery when `pending_access_token` is present even if `pending_refresh_token` is empty string (matching DayOne Desktop's long-lived token architecture).
  - In `FeaturesPage.xaml.cs` (WinUI) and `Settings.razor` (Blazor):
    - Initialized `LastTokenPush = DateTime.UtcNow` upon creating `PairedWatch` rows.

---

## HarmonyOS: Rezolvare Conflict Semnătură & Aliniere `bundleName`

### 1. Descrierea Erorii la Semnare
- **Eroare**: `hvigor ERROR: 00303074 Configuration Error: The bundleName in app.json does not match the bundleName in the generated SigningConfigs. At file: HarmonyOS/DailyWear/build-profile.json5`.
- **Cauză**: În commit-ul recent, `bundleName` din `HarmonyOS/DailyWear/AppScope/app.json5` fusese modificat în `"com.intellidream.daily.orbit"`. Certificatul de dezvoltator și profilul de provisioning generat (`.p7b`) din `~/.ohos/config/` erau emise și semnate de Huawei Developer Relations CA pentru `bundle-name: "com.intellidream.daily"`. La etapa `SignHap`, `hvigor` valida corespondența strictă între `app.json5` și profilul de semnare.

### 2. Soluție & Rezolvare
1. **Corectare `bundleName`**: În `AppScope/app.json5`, s-a revenit la `"bundleName": "com.intellidream.daily"`. Numele vizual al aplicației pe ceas rămâne `"DayOne Orbit"` prin `label: "$string:app_name"`.
2. **Compilare & Semnare Validată**: Rulat `hvigorw assembleHap`, finalizat cu succes:
   `Finished :entry:default@SignHap... after 2 s 404 ms` -> `BUILD SUCCESSFUL in 42 s`.
3. **Instalare Emulator**: La reinstalarea pe simulatorul Huawei (`127.0.0.1:5555`), a apărut `code:9568332 error: install sign info inconsistent` din cauza versiunii vechi nesemnate deja instalate. S-a efectuat `hdc app uninstall com.intellidream.daily` urmat de instalarea curată a pachetului semnat `entry-default-signed.hap`.
4. **Verificare Live**: Aplicația a pornit cu succes pe simulator, a generat PIN-ul de pairing, s-a împerecheat și a încărcat dashboard-ul de date în timp real.

---

## HarmonyOS: Optimizare Layout Ecran Rotund & Dialoguri Accesibile

### 1. Probleme Identificate pe Ceasul Circular (466x466)
1. **Titluri & Butoane Navigare Tăiate**: Titlurile ecranelor de logging (`💧 Bubbles`, `🔥 Smokes`) și cel din grafice (`7 Days`) erau împinse prea sus, lipite de curbura superioară a cadranului.
2. **Săgeți Navigare Temporală Ascunse (`‹` / `›`)**: `TemporalNavHeader` avea lățimea setată la `94%` (438px). Pe un ecran rotund de 466px, lățimea vizibilă a corzii la înălțimea y=50 este de doar ~288px, astfel încât butoanele `‹` și `›` erau împinse complet în afara marginii vizibile a ecranului.
3. **Elemente Ieșite din Ecran în Grafice (Charts 7 Days)**: Rândul de sumar `💧 Avg: ...  Goal: ...` și `🔥 Avg: ...  Base: ...` avea lățimea de `90%` cu `SpaceBetween`, poziționând etichetele în colțurile tăiate de curba ecranului. Histograma la `90%` era de asemenea la limită.
4. **Buton Unpair Prea Mare**: În ecranul `AboutView`, butonul `Unpair Watch` ocupa `85%` din lățime cu o înălțime de 36px, având un aspect mult prea lat și disproporționat.
5. **Trunchiere Text Butoane Dialog ("C..." și "D...")**: La ștergerea unui log sau la unpair, `AlertDialog` afișa butoanele orizontal (side-by-side). Pe ecranul mic al ceasului, lățimea fiecărui buton era sub 80px, forțând ArkUI să trunchieze textele `Cancel` și `Delete` în `C...` și `D...`.

### 2. Soluții Implementate
1. **Header & Padding Sigur pentru Display Circular**:
   - În `BubblesView.ets`, `SmokesView.ets`, `Bubbles7DaysView.ets`, `Smokes7DaysView.ets` și `AboutView.ets`, containerul `Column` din `Scroll()` a primit `.padding({ top: 22, bottom: 36 })`, iar marginea de sus a titlurilor a fost redusă la `0`. Titlul și iconițele stau acum natural și aerisit sub rama curbată de sus.
2. **Ajustare Lățime `TemporalNavHeader`**:
   - Redusă lățimea containerului de la `94%` la `78%`.
   - Mărit butonul `‹` și `›` la `width(30)`, `height(26)`, `borderRadius(8)` și font `17px`.
   - Ambele butoane de navigare temporală sunt acum 100% vizibile, confortabile la atingere și au un spațiu de siguranță de ~35px față de rama rotundă.
3. **Optimizare Grafice 7 Zile**:
   - Histogramele reduse la `.width('82%')`.
   - Rândul de sumar `Avg / Goal` a fost centrat la `.width('82%')` cu separator `•` (`💧 Avg: 1900 ml/d  •  Goal: 2000 ml`), eliminând complet ieșirea textelor în afara ecranului.
4. **Redimensionare Buton `Unpair Watch`**:
   - Transformat într-un pill button compact, centrat: `width(128)`, `height(30)`, `borderRadius(15)` cu text de `11px`, identic cu rezolvarea de pe WearOS.
5. **Dialoguri Verticale pentru Butoane Complete (`Cancel` & `Delete`)**:
   - În toate ecranele (`BubblesView`, `SmokesView`, `LogsView`, `AboutView`), s-a configurat `showAlertDialog` folosind:
     ```ets
     buttonDirection: DialogButtonDirection.VERTICAL,
     buttons: [
       { value: 'Delete', fontColor: '#FF3B30', action: async () => { ... } },
       { value: 'Cancel', fontColor: '#888888', action: () => {} }
     ]
     ```
   - Cu dispunerea verticală, butoanele ocupă întreaga lățime a dialogului, afișând complet și lizibil cuvintele `Delete` / `Unpair` și `Cancel`.

