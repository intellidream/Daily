# Daily App: Comprehensive Data Architecture & Synchronization Strategy (2026)

This document provides a comprehensive blueprint of the data architecture, local-first synchronization, caching mechanisms, realtime event propagation, watch pairing protocols, and platform-specific implementations for the Daily App ecosystem. It covers the C# .NET MAUI desktop/mobile app, native Apple watchOS, WearOS (Kotlin/Compose), and Huawei HarmonyOS applications.

---

## Table of Contents
1. [Core Architectural Design Patterns](#1-core-architectural-design-patterns)
2. [Data Access & Local Caching Strategy](#2-data-access--local-caching-strategy)
3. [Bidirectional Sync Protocol](#3-bidirectional-sync-protocol)
4. [Supabase Realtime WebSockets & Event Dispatching](#4-supabase-realtime-websockets--event-dispatching)
5. [Watch Companion Pairing & Air-Gap Token Exchange](#5-watch-companion-pairing--air-gap-token-exchange)
6. [Platform-Specific Health/Vitals Data Flow](#6-platform-specific-healthvitals-data-flow)
7. [Supabase Database Schema & RLS Policies](#7-supabase-database-schema--rls-policies)
8. [Edge Functions (Financial Quotes)](#8-edge-functions-financial-quotes)
9. [Rolling Window & Historical Data Consolidation (90-Day Raw Rule)](#9-rolling-window--historical-data-consolidation-90-day-raw-rule)
10. [Chronological Log of Recent Architectural Fixes](#10-chronological-log-of-recent-architectural-fixes)

---

## 1. Core Architectural Design Patterns

The Daily App is architected around three foundational patterns designed to provide a high-performance, offline-capable, battery-friendly, and cost-effective mobile and desktop experience.

```
┌────────────────────────────────────────────────────────┐
│                        Daily UI                        │
└────────────────────────────────────────────────────────┘
                            │ (Reactive Bindings)
                            ▼
┌────────────────────────────────────────────────────────┐
│             Local SQLite Database (Cache)              │
│               [vitals, habits_logs, ...]               │
└────────────────────────────────────────────────────────┘
       ▲                                          ▲
       │ (Push/Pull Background Sync)              │ (Direct Socket Writes)
       ▼                                          │
┌──────────────────────────────┐        ┌─────────────────┐
│     SyncService Engine       │        │ Realtime Socket │
└──────────────────────────────┘        └─────────────────┘
               ▲                                 ▲
               └──────────────┬──────────────────┘
                              ▼
┌────────────────────────────────────────────────────────┐
│               Supabase Cloud Backplane                 │
│               [PostgreSQL DB + Realtime]               │
└────────────────────────────────────────────────────────┘
```

### A. Local-First Pattern
* **Single Source of Truth**: The client applications never read directly from the cloud to render user interfaces. The local database (SQLite `Daily.db3` on the MAUI app; native Local Storage/DataStore on watchOS and WearOS) acts as the absolute source of truth.
* **Instantaneous UI Interactivity**: When a user logs water, completes a habit, or registers an entry, the transaction is written to the local database immediately. The UI re-renders reactively using local event bindings.
* **Resilience to Disconnections**: All reading and writing works seamlessly without an internet connection. Synchronization logic handles uploading offline changes once network connectivity is restored.

### B. Thick-Client Aggregation
* **Bypassing Server Compute**: Rather than delegating statistics, aggregates (such as sums, daily totals, averages, and historical heatmaps) to database views or Supabase Edge Functions, the client devices perform all computations locally.
* **Free-Tier Friendly**: Because raw data calculations occur on-device, server CPU compute cycles are eliminated. The cloud database is treated purely as a synchronized data store.
* **Improved Offline Capability**: Visualizations like the 7-day vitals trends, hydration heatmaps, and financial metrics are calculated on the fly from raw local databases, allowing charts to render instantly offline.

### C. Offline-First Sync Bridge
* **Dirty Flags**: Records generated locally are marked as dirty by setting their `SyncedAt` property to `null`.
* **Background Dispatching**: The app fires background tasks to flush dirty records to Supabase. If these network calls fail, the records remain flagged in the local database and are automatically retried during subsequent sync cycles.

---

## 2. Data Access & Local Caching Strategy

Data persistence is structured across SQLite tables that mirror the core features. The ORM mapping is handled by `sqlite-net-pcl`.

### A. SQLite Schema Mapping & Table Entities

| SQLite Table | C# Model Class | Key Fields | Description |
|---|---|---|---|
| `vitals` | `LocalVitalMetric` | `Id` (GUID string), `UserId`, `TypeString`, `Value`, `Unit`, `Date` (UTC Midnight), `SourceDevice`, `UpdatedAt` (UTC), `SyncedAt` | Local cache for physical vital metrics (Steps, Heart Rate, HRV, etc.) |
| `habits_logs` | `LocalHabitLog` | `Id`, `UserId`, `HabitType`, `Value`, `Unit`, `LoggedAt`, `Metadata`, `SyncedAt` | Individual habit completion timestamps (e.g. coffee, water, cigarettes) |
| `habits_goals` | `LocalHabitGoal` | `Id`, `UserId`, `HabitType`, `TargetValue`, `Unit`, `SyncedAt` | Configured goals per habit |
| `rss_subscriptions` | `LocalRssSubscription` | `Id`, `UserId`, `FeedUrl`, `Title`, `Category`, `SyncedAt` | Subscribed RSS Feeds |
| `saved_articles` | `LocalSavedArticle` | `Id`, `UserId`, `Title`, `Url`, `PublishDate`, `SavedAt`, `SyncedAt` | Bookmarked RSS articles |
| `financial_transactions`| `LocalTransaction`| `Id`, `UserId`, `Amount`, `Category`, `Date`, `Description`, `SyncedAt` | Ledger for manual financial transactions |

### B. Indexing Strategy
To maintain sub-millisecond query performance as raw datasets scale over years of tracking, composite indexes are established:
* **Habits**: Composite index on `[HabitType, LoggedAt]` ensures fast daily summation and historical range grouping.
* **Vitals**: Composite index on `[UserId, Date, TypeString]` guarantees instantaneous daily snapshots and history rendering.

---

## 3. Bidirectional Sync Protocol

The synchronization between the SQLite cache and Supabase PostgreSQL is managed by `SyncService.cs` and `SupabaseHealthService.cs`.

```
PUSH CYCLE (Outgoing):
Local Cache (Dirty: SyncedAt IS NULL) ──▶ Map to Remote Model ──▶ Upsert to Supabase ──▶ Update Local (Set SyncedAt = UTCNOW)

PULL CYCLE (Incoming):
Check Last Pull Timestamp ──▶ Fetch Changed Remote Records (since Timestamp - Buffer) ──▶ Write to Local Cache (Overwrite)
```

### A. Outgoing Sync: The Push Mechanics (`PushAsync`)
1. **Fetch Dirty Records**: The local database is queried for rows matching `SyncedAt == null`.
2. **Batch Mapping**: Entities are mapped from local representations (e.g., `LocalHabitLog`) to remote database models (e.g., `HabitLog`).
3. **Database Upsert**: The remote model collection is uploaded using a bulk `Upsert` request. This operation uses an `ON CONFLICT` clause based on the unique constraints of each table.
4. **Mark Clean**: Upon a successful HTTP 200 response from Supabase, the local rows are updated in a database transaction, setting `SyncedAt = DateTime.UtcNow`.

### B. Incoming Sync: The Pull Mechanics (`PullAsync`)
1. **High-Watermark Delta Query**: The system retrieves the `lastPull` timestamp from local preferences.
   * If `lastPull` is `DateTime.MinValue` (e.g. fresh install), the query window starts from the year 2000.
   * If `lastPull` is populated, the query fetches records where `updated_at > lastPull - BufferTime` (e.g. 5-minute skew buffer for Vitals; 14-day safety window for Habits to catch offline writes from companion devices).
2. **Local Overwrite**: Retrieved cloud records are saved to SQLite. For downloaded data, the cloud database is the absolute source of truth. Consequently, local cache values are directly overwritten by downloaded values to prevent desynchronization.
3. **Update High-Watermark**: The `lastPull` timestamp is updated to the local device time of the sync execution.

---

## 4. Supabase Realtime WebSockets & Event Dispatching

To guarantee instant synchronization across multiple active devices (such as logging an entry on a phone and seeing it immediately on a desktop app), the Daily App establishes persistent WebSockets using the Supabase Realtime client.

### A. Subscribing to Channels
At startup or immediately after a successful authentication state change, the services register Postgres change handlers:
```csharp
_vitalsChannel = _supabase.Realtime.Channel("realtime", "public", "vitals", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
_vitalsChannel.AddPostgresChangeHandler(Supabase.Realtime.Constants.EventType.All, OnVitalReceived);
await _vitalsChannel.Subscribe();
```
* **Event Handlers**: The services listen to all Postgres updates (`Insert`, `Update`, `Delete`).

### B. Direct SQLite Cache Writes
To avoid the overhead of triggering an HTTP REST delta query (`PullDeltasAsync`) whenever a change occurs, the socket payload is written directly to the database cache:

* **Inserts & Updates (`EventType.Insert` / `EventType.Update`)**:
  1. The socket payload is parsed into the domain model (e.g., `VitalMetric`).
  2. The service maps the domain model to the local database model.
  3. `SyncedAt` is set to `DateTime.UtcNow` to prevent a duplicate sync push loop.
  4. In a transaction, the app deletes any legacy duplicate records matching the same user, type, and date that have a different UUID, then inserts the fresh record.
  5. The UI refresh handler `_refreshService.TriggerHealthRefreshAsync()` or event `OnHabitsUpdated` is fired immediately.

* **Deletes (`EventType.Delete`)**:
  1. The payload is checked for the identifier (`Id`).
  2. A raw SQL query is executed to purge the item from the cache:
     ```sql
     DELETE FROM vitals WHERE Id = ?;
     ```
  3. The UI refresh trigger is fired to remove the item from the screen instantly.

---

## 5. Watch Companion Pairing & Air-Gap Token Exchange

Because companion smartwatches (Apple Watch, WearOS, HarmonyOS) often operate on independent networks or lack standard user input mechanisms (keyboards), the Daily App uses a secure, database-driven pairing model to transfer Supabase JWT credentials across devices.

```
┌──────────────┐                       ┌──────────────┐                       ┌──────────────┐
│  Companion   │                       │   Supabase   │                       │  Main Phone  │
│  Watch App   │                       │  Postgres    │                       │     App      │
└──────────────┘                       └──────────────┘                       └──────────────┘
       │                                       │                                      │
       │ 1. Generate random code 'A9B8C7'      │                                      │
       │ 2. Insert blank row (code)            │                                      │
       ├──────────────────────────────────────▶│                                      │
       │                                       │                                      │
       │ 3. Poll watch_pairings for tokens     │                                      │
       ├──────────────────────────────────────▶│                                      │
       │                                       │ 4. User enters 'A9B8C7'              │
       │                                       │ 5. Authenticated token update        │
       │                                       │◀─────────────────────────────────────┤
       │                                       │                                      │
       │ 6. Retrieve JWT & Refresh tokens      │                                      │
       │◀──────────────────────────────────────┤                                      │
       │                                       │                                      │
       │ 7. Delete row from watch_pairings     │                                      │
       ├──────────────────────────────────────▶│                                      │
```

### A. The Pairing Handshake Workflow
1. **Code Generation (Watch)**: The companion watch app generates a unique, short, random alphanumeric code (e.g. `A9B8C7`) and inserts a row into `public.watch_pairings` containing only the code.
2. **Polling (Watch)**: The watch app begins polling the `watch_pairings` table using the generated code:
   ```sql
   SELECT access_token, refresh_token FROM watch_pairings WHERE code = 'A9B8C7';
   ```
3. **Injection (Phone)**: The user enters the 6-character code into the authenticated phone app. The phone app updates the corresponding row in `public.watch_pairings` with its active `access_token` and `refresh_token`.
4. **Token Retrieval & Cleanup (Watch)**: The watch app detects the populated token fields, copies the credentials into its local storage, initializes its native Supabase Client, and deletes the row from `public.watch_pairings` to clean up the table.

### B. Security Policies (RLS)
The `public.watch_pairings` table utilizes Row Level Security (RLS) policies to ensure that unauthenticated watches can negotiate the exchange while preventing unauthorized database exposure:
* **Anonymous Inserts**: The anonymous role (`anon`) can insert rows containing the code.
* **Anonymous Selects**: The anonymous role (`anon`) can query rows to poll for their token update.
* **Anonymous Deletes**: The anonymous role (`anon`) can delete the pairing row after the handshake completes.
* **Authenticated Updates**: Only authenticated users (`authenticated`) can write session tokens to active pairing codes.

---

## 6. Platform-Specific Health/Vitals Data Flow

The Health feature operates on a **"Mobile-as-Bridge"** architecture: mobile operating systems fetch native health database records locally, synchronize them to the cloud database, and all platforms (including desktop Windows/macOS apps) pull the synchronized cloud records to display them.

```
┌─────────────────────────────────┐
│     Native OS Health Database   │
│   [iOS HealthKit / Android HC]  │
└─────────────────────────────────┘
                 │
                 ▼ (Local timezone queries)
┌─────────────────────────────────┐
│   Platform Native Health Store  │
│   [HealthKit / Health Connect]  │
└─────────────────────────────────┘
                 │
                 ▼ (NormalizeToUtcMidnight)
┌─────────────────────────────────┐
│     Supabase Health Service     │
└─────────────────────────────────┘
                 │
                 ▼ (Upload: Max Wins for Cumulative; Last Write Wins for Spot)
┌─────────────────────────────────┐
│      Supabase PostgreSQL        │
└─────────────────────────────────┘
                 │
                 ▼ (Download: Direct Overwrite)
┌─────────────────────────────────┐
│    Local SQLite Vitals Cache    │
└─────────────────────────────────┘
```

### A. iOS HealthKit Integration (`HealthKitService.cs`)
* **Local Timezone Boundary Alignment**: HealthKit is queried using the local device's timezone midnight bounds:
  ```csharp
  DateTime start = DateTime.SpecifyKind(date.Date, DateTimeKind.Local);
  DateTime end = start.AddDays(1);
  ```
  When converting local `DateTime` parameters to iOS `NSDate` timestamps, Xamarin/Apple APIs automatically map local midnight to the corresponding absolute UTC timestamp. This ensures that early-morning steps walked between midnight and 3:00 AM local time are correctly attributed to the current day, rather than drifting to the previous day.
* **Result Normalization**: Mapped dates returned from statistics queries are normalized to UTC midnight using `NormalizeToUtcMidnight()`.

### B. Android Health Connect Integration (`HealthConnectService.cs`)
* Android uses reflection-based SDK loaders to query the Health Connect API.
* Retranslates native record intervals (e.g. `StepsRecord`, `SleepSessionRecord`, `NutritionRecord`) into generic `VitalMetric` objects aligned to the user's local day bounds.

### C. Native Upload Merge Strategy (`SyncNativeHealthDataAsync`)
When uploading native health metrics to the cloud database, a hybrid conflict resolution strategy is enforced:
* **Cumulative Metrics (e.g. Steps, Calories, Distance)**: Uses a **"Max Wins"** comparison. If the remote database has a higher value than the local device (e.g. steps synced from another device earlier), the device keeps the higher cloud value.
* **Spot Metrics (e.g. Heart Rate, HRV, Weight)**: Uses a **"Last Write Wins"** policy based on `updated_at` timestamps.
* **Database Conflict Resolution**: The merge occurs before upsert, and the bulk query uses the unique constraint conflict resolution key `(user_id, date, type)`.

### D. Download Sync Overwrite Strategy
* During delta downloads (`PullDeltasAsync`), the local SQLite cache directly writes incoming records from the cloud without applying "Max Wins" checks. This ensures the cloud database remains the absolute source of truth for the local database cache.

---

## 7. Supabase Database Schema & RLS Policies

Below is the database structure for the core synchronization tables on Supabase.

### A. Vitals Table
```sql
CREATE TABLE public.vitals (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
  type TEXT NOT NULL,
  value DOUBLE PRECISION NOT NULL,
  unit TEXT,
  date DATE NOT NULL,
  source_device TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ,
  CONSTRAINT vitals_user_date_type_key UNIQUE (user_id, date, type)
);

-- Enable RLS
ALTER TABLE public.vitals ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can manage their own vitals"
ON public.vitals FOR ALL
USING ( (SELECT auth.uid()) = user_id )
WITH CHECK ( (SELECT auth.uid()) = user_id );
```

### B. Watch Pairings Table
```sql
CREATE TABLE public.watch_pairings (
    code TEXT PRIMARY KEY,
    access_token TEXT,
    refresh_token TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.watch_pairings ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Allow anon insert watch_pairings" ON public.watch_pairings FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Allow anon select watch_pairings" ON public.watch_pairings FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon delete watch_pairings" ON public.watch_pairings FOR DELETE TO anon USING (true);
CREATE POLICY "Allow auth update watch_pairings" ON public.watch_pairings FOR UPDATE TO authenticated USING (true);
```

---

## 8. Edge Functions (Financial Quotes)

To secure financial API keys, bypass CORS limits, and optimize client networking, the application uses Supabase Edge Functions.

* **Function Endpoint**: `fetch-market-quotes`
* **Trigger Service**: `FinancesService.cs`
* **Workflow**:
  1. The client app initiates a call via `_supabase.Functions.Invoke("fetch-market-quotes", body)`.
  2. The Supabase client automatically attaches the user's active session JSON Web Token (JWT) to the `Authorization` header.
  3. The Edge Function verifies the JWT, retrieves secure API keys stored in Supabase secrets, performs requests to external market providers (Yahoo Finance/Finnhub), and returns a unified JSON format back to the client.

---

## 9. Rolling Window & Historical Data Consolidation (90-Day Raw Rule)

As users generate multiple logs per day, the database size grows. To keep the database size within the limits of the Supabase Free Tier, the application implements a client-driven rolling window consolidation policy.

```
PAST 90 DAYS (Raw Logs):
[Log: 250ml Water] [Log: 300ml Water] [Log: 200ml Water]  ◀── Saved individually

OLDER THAN 90 DAYS (Consolidated):
[Daily Summary: 750ml Water, 3 Logs]                      ◀── Merged into one row, raw logs deleted
```

### A. The Consolidation Protocol
1. **Window Identification**: The client identifies local database entries older than 90 days.
2. **Local Summary Computation**: The client groups raw records by day and computes the `total_value` and `log_count` for each day.
3. **Summary Upload**: The computed summaries are upserted into the `habits_daily_summaries` table on Supabase.
4. **Cloud Pruning**: The client sends a batch delete query to Supabase to remove the raw records older than 90 days.
5. **Local Preservation**: The raw logs are kept locally on the device (unless the user manually deletes them or clears the app cache), maintaining detailed history locally while optimizing cloud storage.

---

## 10. Chronological Log of Recent Architectural Fixes

### A. Extension Helper `SafeUtc` and `NormalizeToUtcMidnight`
* **Issue**: Unspecified datetimes retrieved from SQLite databases were interpreted with local timezone offsets when parsed on device, shifting calendar entries to "yesterday" or "tomorrow".
* **Solution**: Introduced `NormalizeToUtcMidnight()` and `SafeUtc()` extension helpers. All domain mapping, ID generation, and local cache reads now standardize on UTC midnight.

### B. HealthKit Query Midnight Offset
* **Issue**: Steps walked between 12:00 AM and 3:00 AM local time were missing from the current day's metric count because the query was executed using UTC dates.
* **Solution**: Updated iOS `HealthKitService.cs` to fetch using local timezone midnight bounds and normalize returned dates to UTC midnight.

### C. SQLite ORM Column Schema Mapping Crash
* **Issue**: WinUI startup failed with a `SQLiteException` ("no such column: user_id").
* **Solution**: Realigned raw SQL queries inside `SupabaseHealthService` to query C# property names mapped by the ORM (`UserId`, `TypeString`, `Date`, `Id`) instead of the snake_case database schema names.

### D. Realtime Postgres Event Types & Scope Collision
* **Issue**: The Postgres changes delete event check crashed because `PostgresChangesOptions.ListenType.Delete` was used instead of `Supabase.Realtime.Constants.EventType.Delete`. Additionally, declaring `var remoteVital` inside the delete block shadowed the outer scope.
* **Solution**: Corrected the enum comparison and renamed the nested variable to `deletedVital` to ensure clean compilation.
