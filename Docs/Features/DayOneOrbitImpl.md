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

### Tiered Delta Syncing
To prevent battery drain while building a massive historical telemetry dataset, the wearable node uses a **Tiered Delta Sync** strategy:
1. **Delta Syncing (`HKQueryAnchor`)**: The device stores anchor tokens locally. HealthKit queries only return data generated *since the last successful sync*, keeping the HTTP payload size near zero and preventing redundant row inserts.
2. **Tier 1 (Fast Sync)**: Low-volume, high-priority metrics (Heart Rate, Steps, Active Energy, and Habit Logs) are synced every 15–30 minutes to keep the WinUI Dashboard feeling "real-time".
3. **Tier 2 (Deep Sync)**: High-volume or deep analytics data (Sleep Analysis, HRV, Respiratory Rate) are batched and executed only once every 4 hours (or when on Wi-Fi/Charging) to conserve battery and network usage.
