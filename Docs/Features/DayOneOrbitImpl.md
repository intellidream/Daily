# DayOne Orbit Architecture & Implementation

## Core Philosophy
The objective is to establish a standalone smartwatch ecosystem where smart devices communicate directly with the Supabase PostgreSQL backend, acting as independent nodes in the DayOne architecture rather than relying exclusively on a mobile iOS/Android companion app proxy. The WinUI 3 desktop application acts as the real-time consumer.

## 1. Database Layer (Supabase)

### New Tables
- **`health_telemetry`**: Stores raw, highly granular time-series data pushed directly by the standalone smartwatch (e.g. 5-minute interval heart rates).
- **`health_vitals`**: Stores daily aggregated snapshots (e.g. total steps for the day, latest resting heart rate). This runs parallel to the legacy `vitals` table until full migration.
- **`watch_pairing_codes`**: Manages secure OTP (One Time Password) pairing logic to bind a new smartwatch to an authenticated user's account without requiring complex OAuth flows on the watch's small screen.

### Triggers & Aggregation
A PostgreSQL Trigger (`trigger_aggregate_health_telemetry`) is attached to `health_telemetry` `AFTER INSERT`. It fires a function (`aggregate_health_telemetry_to_vitals`) that determines if a metric is cumulative (e.g., Steps) or absolute (e.g., Heart Rate). It then updates the `health_vitals` table via an `ON CONFLICT (user_id, date, type) DO UPDATE` UPSERT operation. 

## 2. Desktop Application (WinUI)

### UI & Configuration
The **DayOne Orbit** section inside `FeaturesPage.xaml` exposes:
1. **Link Smartwatch**: Initiates the pairing flow. It inserts a new record into `watch_pairing_codes` with a randomly generated 6-digit PIN and a 10-minute expiration. 
2. **Watch Sync Frequency**: A user preference saved to `AppSettings` and synchronized to the cloud. The smartwatch reads this property via API to adjust its background refresh cadence.

### Realtime Subscription
To optimize WebSocket traffic and maintain free-tier compatibility, the WinUI application uses `SupabaseHealthService.cs` to subscribe **only** to the aggregated `health_vitals` table. 
- Raw data hits `health_telemetry`
- Supabase trigger updates `health_vitals`
- Realtime Postgres Change event fires to WinUI
- WinUI pulls the lightweight payload, saves it to the local SQLite `LocalVitalMetric` table, and triggers an immediate Dashboard UI refresh.

## 3. Wearable Strategy
The architecture natively supports both watchOS and Wear OS:
- **watchOS**: Utilizes `WKApplicationRefreshBackgroundTask` to sample `HKHealthStore` and push JSON payloads directly via `NSURLSession` HTTP POST to the Supabase REST endpoint.
- **Wear OS**: Utilizes Android `WorkManager` with `PassiveMonitoringClient` to push to the same REST endpoints. 
- **Pairing**: The watch user inputs the 6-digit PIN, which triggers a `SELECT` on `watch_pairing_codes`. If valid, it claims the code and returns a long-lived JWT token or standard session data for future direct-to-cloud operations.
