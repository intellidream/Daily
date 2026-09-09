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


