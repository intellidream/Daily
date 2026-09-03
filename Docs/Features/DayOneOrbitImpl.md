# DayOne Orbit Architecture & Implementation

## Core Philosophy
The objective is to establish a standalone smartwatch ecosystem where smart devices communicate directly with the Supabase PostgreSQL backend, acting as independent nodes in the DayOne architecture rather than relying exclusively on a mobile iOS/Android companion app proxy. The WinUI 3 desktop application acts as the real-time consumer.

## 1. Database Layer (Supabase)

### New Tables
- **`health_telemetry`**: Stores raw, highly granular time-series data pushed directly by the standalone smartwatch (e.g. 5-minute interval heart rates).
- **`health_vitals`**: Stores daily aggregated snapshots (e.g. total steps for the day, latest resting heart rate). This runs parallel to the legacy `vitals` table until full migration.
- **`watch_pairing_codes`**: Manages secure OTP (One Time Password) pairing logic to bind a new smartwatch to an authenticated user's account without requiring complex OAuth flows on the watch's small screen. During creation, the desktop application injects its current `access_token` and `refresh_token` into the record so the watch can inherit the authentication session immediately upon claiming the PIN.

### Triggers & Aggregation
A PostgreSQL Trigger (`trigger_aggregate_health_telemetry`) is attached to `health_telemetry` `AFTER INSERT`. It fires a function (`aggregate_health_telemetry_to_vitals`) that determines if a metric is cumulative (e.g., Steps) or absolute (e.g., Heart Rate). It then updates the `health_vitals` table via an `ON CONFLICT (user_id, date, type) DO UPDATE` UPSERT operation. 

### Security: The Claim PIN RPC
Because `watch_pairing_codes` enforces Row Level Security (RLS) to prevent unauthorized extraction of access tokens, the unauthenticated smartwatch cannot execute a `PATCH` request directly against the table. Instead, we use a Postgres RPC (`claim_orbit_pin`) configured with `SECURITY DEFINER`. This function safely verifies the PIN, marks it claimed, and returns the authentication tokens without giving the `anon` role global `SELECT` privileges.

## 2. Desktop Application (WinUI)

### UI & Configuration
The **DayOne Orbit** section inside `FeaturesPage.xaml` exposes:
1. **Link Smartwatch**: Initiates the pairing flow. It inserts a new record into `watch_pairing_codes` with a randomly generated 6-digit PIN and a 10-minute expiration. 
2. **Watch Sync Frequency**: A user preference saved to `AppSettings`. The smartwatch evaluates this to adjust its `WKApplicationRefreshBackgroundTask` wake-up cadence.

### Realtime Subscription
To optimize WebSocket traffic and maintain free-tier compatibility, the WinUI application uses `SupabaseHealthService.cs` to subscribe **only** to the aggregated `health_vitals` table. 
- Raw data hits `health_telemetry`
- Supabase trigger updates `health_vitals`
- Realtime Postgres Change event fires to WinUI
- WinUI pulls the lightweight payload, saves it to the local SQLite `LocalVitalMetric` table, and triggers an immediate Dashboard UI refresh.

## 3. Wearable Strategy

### Architecture (watchOS & Wear OS)
The standalone architecture is unified across platforms, pushing identical telemetry payloads directly to the Supabase REST endpoint:
- **watchOS**: Utilizes `WKApplicationRefreshBackgroundTask` to sample `HKHealthStore` and push via the Supabase Swift SDK.
- **Wear OS**: Utilizes Android `WorkManager` with `Health Connect` to push to the same REST endpoints. 
- **Pairing**: The watch user inputs the 6-digit PIN, triggering a `POST` to the `/rpc/claim_orbit_pin` endpoint. If valid, it claims the code and returns the `access_token` and `refresh_token` for full direct-to-cloud capabilities.

### Wearable UX & Lifecycle
- **Custom PIN Entry**: Because watchOS `TextField` inputs default to a clunky scribble/dictation menu, the pairing screen implements a custom 6-digit numeric keypad (`OrbitPinEntryView`) wrapped in a `NavigationStack` for a native, fast pairing experience.
- **Remote Unpairing via `paired_watches`**: Once paired, `watch_pairing_codes` is no longer used. Instead, the watch registers itself in the `paired_watches` persistent ledger. On every app foreground (`onAppBecameActive`), the watch queries this ledger. If the desktop app deletes the watch or sets `is_active = false`, the watch detects it, wipes local tokens, and forces the user back to the PIN screen seamlessly (preventing UI flickering by holding a loading state during the check).

### Tiered Delta Syncing
To prevent battery drain while building a massive historical telemetry dataset, the wearable node uses a **Tiered Delta Sync** strategy:
1. **Delta Syncing (`HKQueryAnchor`)**: The device stores anchor tokens locally. HealthKit queries only return data generated *since the last successful sync*, keeping the HTTP payload size near zero and preventing redundant row inserts.
2. **Tier 1 (Fast Sync)**: Low-volume, high-priority metrics (Heart Rate, Steps, Active Energy, and Habit Logs) are synced every 15–30 minutes to keep the WinUI Dashboard feeling "real-time".
3. **Tier 2 (Deep Sync)**: High-volume or deep analytics data (Sleep Analysis, HRV, Respiratory Rate) are batched and executed only once every 4 hours (or when on Wi-Fi/Charging) to conserve battery and network usage.

### Watch Pairing & Authentication (Zepp OS 3.0 & WinUI)
*Added: Sep 2026*

The process of directly pairing a Zepp OS smartwatch to the Supabase backend was implemented using a 6-digit PIN bridging process:
1. **App-Side Communication**: The Zepp OS 3.0 implementation requires wrapping the `app-side` logic in `BaseSideService` and the `app.js` in `BaseApp` for the `messageBuilder` bridge to correctly pass data from the watch UI to the companion app environment.
2. **Fetch API Constraint**: Zepp OS uses a custom `fetch` implementation taking a single parameter object (`fetch({ url, method, body, headers })`) instead of the standard Web API signature.
3. **PostgreSQL RLS for Pairing**: When claiming a PIN from the WinUI Desktop App (updating `user_id` and `access_token`), an `UPDATE` policy is enforced on `watch_pairing_codes`. A critical requirement is to explicitly specify the `WITH CHECK (true)` clause. Omitting it causes the database to implicitly evaluate the `USING (NOT claimed)` clause against the mutated row (`claimed = true`), triggering a silent rejection (returned as an empty array) which manifests as a `PostgrestException` in the C# `Supabase.Client`.

### Zepp OS 3.0 Implementation Details
*Added: Sep 2026*

The Zepp OS application features robust habit trackers and health telemetry synchronization directly on the watch, bypassing the need for a phone UI:
- **Persistent Sessions**: `@zos/storage` handles storing the user's Supabase JWT tokens locally on the watch, allowing the user to seamlessly skip pairing screens after the first login.
- **Direct-to-Cloud Bridge**: New endpoints in the ZML proxy (`app-side`) were created (`GET_HABITS_TODAY`, `LOG_HABIT`, `SYNC_TELEMETRY`). They intercept watch parameters and fire `fetch` commands directly to Supabase using the user's saved `Authorization: Bearer` token.
- **Optimistic UI**: When users log water, coffee, or smokes on the watch, the UI updates instantly using optimistic rendering, ensuring zero perceived latency before network confirmation.
- **Multi-Device Support**: The concept of enforcing a "single-device-per-platform" constraint was completely removed from both MAUI and WinUI. Users can now pair multiple devices of the same operating system (e.g., two Zepp OS watches or two Apple Watches). Devices are strictly managed via the desktop app's `Unpair` action rather than automatic database overwrites.
- **Zepp OS 3.0 Sensor Quirks**: The Health extraction implementation uses specific Zepp OS 3.0 APIs: `Step` now returns a primitive number rather than an object (requiring the standalone `Calorie` class for energy extraction).
- **Advanced Telemetry (Stress, PAI, Naps)**: Direct OS-level integration with the `Stress` and `Pai` sensors pushes current stress levels and daily PAI scores. The `SomnusCare` engine's `sleep.getNap()` is utilized to extract and push daytime naps (`sleep_nap`) directly into the `health_telemetry` table.
- **Detailed Sleep Timeline**: Instead of relying on the aggregated properties of `getInfo()`, the integration iterates over the highly granular `sleep.getStage()` array. Because Zepp OS returns sleep stages as minutes elapsed since midnight (including negative integers for the previous day), the algorithm establishes a strict `midnightAnchor` (`00:00:00` of the current day) to dynamically calculate precise ISO8601 `start_time` and `end_time` timestamps. This allows the Supabase database to hold the exact chronological timeline of `sleep_stage_light`, `sleep_stage_deep`, `sleep_stage_rem`, and `sleep_stage_awake` blocks, making it possible to reconstruct the native 1:1 Zepp Sleep Graph entirely within the Windows client.
- **Battery-Optimized Telemetry (Snapshot Sync)**: Instead of utilizing a heavy background `app-service` that drains battery on Zepp OS, telemetry syncing runs explicitly as a "Snapshot" whenever the user opens the DayOne Orbit app on their watch. To aid debugging in production, a dedicated scrolling text widget (`debugText`) is injected above the settings layout to display timestamped network confirmations or precise REST API failure codes.
