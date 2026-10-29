# WinUI 3 Supabase Auth Guardian, Realtime Handshake & Universal Cloud Sync Overhaul (2026)

## Executive Summary
This document records the root-cause investigation, architectural design, implementation, and live Windows 11 ARM64 verification of the systemic authentication, Realtime WebSocket, and local-first cloud synchronization overhaul for `Daily.WinUI` (`DayOne` on Windows 11).

Previously, after ~60 minutes of uptime or following OS Sleep / Modern Standby / VM suspend-resume cycles, `Daily.WinUI` stopped fetching fresh cloud data from Supabase (`PostgrestException: {"code":"PGRST303","message":"JWT expired"}`), never started its 15-minute background sync loop due to a Realtime WebSocket `HTTP 401` handshake deadlock, prematurely advanced incremental `LastPullTime_*` watermarks on swallowed exceptions, lacked bidirectional pull sync for TagDoS, and diverged from macOS/iOS on Finances (`Money` / Smart Ledger).

All five systemic root causes have been eliminated centrally and verified live on Windows 11 ARM64.

---

## 1. Root Causes Identified

### A. `Supabase.Gotrue` v6.0.3 `ExpiresIn` Unix-Timestamp Bug (`Year 2083` Timer)
- Inside `Supabase.Gotrue` v6.0.3, `Client.SetSession(accessToken, refreshToken)` assigns `ExpiresIn = payload.Expiration` (the raw Unix epoch timestamp ~`1,793,112,582`, i.e., ~56.8 years in seconds) instead of subtracting current epoch seconds (`~3600` seconds).
- Consequently, `Session.ExpiresAt()` evaluated to **year ~2083**, causing GoTrue's internal background refresh timer to schedule its next tick decades in the future and `Session.Expired()` to return `false` even hours after the 1-hour JWT expired on Supabase's servers.
- Furthermore, calling `SetSession(..., forceAccessTokenRefresh: true)` invokes `DestroySession()` internally before refreshing, risking permanent deletion of the persisted `refresh_token` if a wake-from-sleep refresh occurs before Wi-Fi/DNS is ready, and firing spurious `AuthState.SignedOut` events across services.
- Multiple services (`BehaviorService`, `SmartBriefingCacheManager`, `SeederService`, `MainWindow`) also invoked `Auth.RefreshSession()` concurrently without a shared lock, racing on single-use rotated refresh tokens.

### B. Realtime WebSocket `HTTP 401` Handshake Deadlock (`sb_publishable_*` + `ES256` User JWT)
- `Daily` uses Supabase's publishable key (`sb_publishable_*`) paired with asymmetric `ES256` user JWTs.
- In `supabase-csharp` v1.1.1, `Supabase.Client` wires `Realtime.GetHeaders = GetAuthHeaders`, injecting `Authorization: Bearer <ES256_user_jwt>` into the initial WebSocket HTTP Upgrade request headers on `/realtime/v1/websocket`.
- Supabase's API Gateway rejects `ES256` user JWTs in the HTTP Upgrade `Authorization` header with **`HTTP 401`** (`The server returned status code '401' when status code '101' was expected`), expecting only `apikey: sb_publishable_*` on the HTTP Upgrade handshake and user JWT authentication over Phoenix WALRUS (`Realtime.SetAuth(accessToken)`).
- Because `HabitsService.InitializeAsync()` awaited `_habitsLogsChannel.Subscribe()` during `App.InitializeAsync()`, the failed WebSocket handshake hung `App.InitializeAsync()` indefinitely before reaching `syncService.StartBackgroundSync()` — meaning the 15-minute background `SyncService` timer never started!

### C. Silent Exception Swallowing & Premature Watermark Advancement in `SyncService`
- `PullInternalAsync` in `Services/SyncService.cs` caught and discarded exceptions inside sub-pulls (`catch { return 0; }`) and unconditionally overwrote `SyncService_LastPullTime_* = DateTime.UtcNow`.
- Any transient failure (`JWT expired`, offline wake, or schema mismatch) permanently moved the pull watermark forward, stranding records created on iOS/macOS/Android during that window.
- Structured logging immediately uncovered that legacy `accounts`, `transactions`, and `holdings` tables in Postgres have no `updated_at` (or `created_at`) column, causing every incremental Finance pull (`lastPull > DateTime.MinValue`) to throw `PostgrestException 42703`!

### D. TagDoS Push-Only & Column Schema Mismatch
- `Services/TagdosService.cs` had no pull or merge logic from Supabase, mapped incompatible column names on `RemoteTagdoStream` / `RemoteTagdoQuickNote` (vs `stream_number`, `raw_syntax`, `reminder_time`, `active_memos`, `attachments`, `tags`), and seeded fake starter items with `DateTime.UtcNow` timestamps.

### E. Finances (`Money` / Smart Ledger) Divergence from macOS/iOS
- `FinancesWidgetControl`'s `Money` view read legacy empty `accounts`/`holdings` tables instead of the cloud-synced `SmartLedger` DSL (`smart_ledgers`).
- `SmartBriefingService` likewise reported `"Your ledger is empty"` because it checked only legacy `accounts`/`holdings`.
- `SmartLedgerParser` and `FinancesDetailPage` needed parity with macOS/iOS `SmartLedgerStore.swift` (canonical single-row cloud sync per user, pure-note handling, `=` inline sum recalc before `//` comments, inline note editing, item deletion, and currency-aware item creation).

---

## 2. Architecture & Implemented Solutions

### 1. Centralized `ISupabaseSessionGuardian` & Atomic Persistence
- **Files**:
  - `Services/Auth/ISupabaseSessionGuardian.cs`
  - `Services/Auth/SupabaseSessionGuardian.cs`
  - `WinUI/Daily.WinUI/Services/WinUISessionPersistence.cs`
  - `WinUI/Daily.WinUI/Services/WinUIAuthService.cs`
- **Capabilities**:
  - **Direct JWT `exp` Decoding**: Base64URL-decodes the JWT payload to read the true UTC `exp` claim, normalizing `Session.ExpiresIn` to real remaining duration seconds (`<= 3600s`).
  - **Single-Flight Refresh (`SemaphoreSlim(1, 1)`)**: Serializes all token refreshes across startup, background timers, wake-from-sleep, foreground activation, and `401`/`PGRST303` retries with a double-spend guard (`_lastRefreshCompletedUtc >= requestStartUtc`) so concurrent callers reuse the newly refreshed session instead of re-spending a rotated refresh token.
  - **Safe Runtime Refresh (`gotrueClient.RefreshToken`)**: Refreshes tokens directly via GoTrue's `RefreshToken(accessToken, refreshToken)` endpoint, emitting `AuthState.TokenRefreshed` and updating `Realtime.SetAuth` without invoking `DestroySession()` or firing false `SignedOut` events.
  - **Atomic Session Persistence & Revocation Guard**: `WinUISessionPersistence` writes via `.tmp` + atomic `File.Move(..., overwrite: true)`, maintains `SupabaseSession_Backup_JSON.txt`, and ignores implicit SDK `DestroySession()` calls unless `AllowDestroySession = true` (explicit user SignOut or permanent `invalid_grant` / `refresh_token_not_found`).
  - **Transparent `ExecuteWithAuthRetryAsync`**: Intercepts `PGRST303` / `JWT expired` / HTTP `401` across `SyncService`, `HabitsService`, `HealthHubService`, `FinancesService`, `TagdosService`, `RssFeedDetailPage`, `BehaviorService`, `SmartBriefingCacheManager`, and `SeederService`, forcing a single-flight token refresh and retrying once.
  - **Single-Flight Realtime Connection (`EnsureRealtimeConnectedAsync`)**: Overrides `Realtime.GetHeaders` (and `Realtime.Socket.GetHeaders`) to send only `apikey: Secrets.SupabaseKey` during the HTTP Upgrade handshake (`101 Switching Protocols`), then authenticates user RLS over Phoenix WALRUS via `Realtime.SetAuth(accessToken)`, with bounded 5-second connection/subscription timeouts so offline startups never block `App.InitializeAsync()`.
  - **Triple Wake-From-Sleep Detection**: Combines a 60-second `PeriodicTimer` wall-clock jump detector (`>= 135s` elapsed -> `OnSystemWakeDetected`), `PowerManager.SystemSuspendStatusChanged` / `DisplayStatusChanged`, `NetworkInformation.NetworkStatusChanged`, and `MainWindow.Activated` (throttled to 3 minutes) to validate the JWT and run a background delta sync upon wake.

### 2. Verified-Watermark `SyncService` & One-Time Cloud Recovery
- **Files**: `Services/ISyncService.cs`, `Services/SyncService.cs`, `Models/Finances/FinanceModels.cs`
- **Capabilities**:
  - Added `SyncScope.Tagdos`, `OnFinancesPulled`, and `OnTagdosPulled`.
  - Every `Pull*InternalAsync` method returns `(int Count, bool Succeeded)` and logs full exception chains (`LogSyncException` with 2 MB log rotation). `SyncService_LastPullTime_*` advances **only** when all sub-pulls in that scope succeed.
  - One-time recovery marker `SyncService_WatermarkRecovery_2026_10_29` resets `SyncService_LastPullTime_*` watermarks once so any records missed while previously stuck on an expired JWT are idempotently reconciled.
  - Removed non-existent `updated_at` / `created_at` column filters and PostgREST attributes from legacy `Account`, `Transaction` (uses `date`), and `Holding` models.

### 3. Bidirectional TagDoS Supabase Sync & Realtime
- **Files**: `Models/TagdoModels.cs`, `Services/TagdosService.cs`, `WinUI/Daily.WinUI/Views/TagdosNotesDetailPage.xaml.cs`
- **Capabilities**:
  - Aligned `RemoteTagdoStream` (`tagdos_streams`: `stream_number`, `raw_syntax`, `reminder_time`, `active_memos`, `attachments`, `updated_at`) and `RemoteTagdoQuickNote` (`tagdos_quick_notes`: `tags` `List<string>`, `is_pinned`, `updated_at`) with `DailyCore/TagdosStore.swift`.
  - Implemented `IsUntouchedSeedStream` / `IsUntouchedSeedNote` with `DateTime.UnixEpoch` timestamps so default starter seeds never overwrite or upload over real user cloud streams/notes.
  - Full bidirectional `SyncWithRemoteAsync()` (`OnConflict = "user_id,stream_number"` for streams, remote deletion reconciliation for synced quick notes) + live Realtime subscriptions on `tagdos_streams` and `tagdos_quick_notes`.
  - Fixed duplicated `"Stream 1: Stream 1: ..."` segmented pill titles in `TagdosNotesDetailPage`.

### 4. Finances (`Money` / Smart Ledger) Parity Across Hub, Widget & Smart Briefing
- **Files**:
  - `Models/Finances/SmartLedgerModels.cs`
  - `Services/Finances/SmartLedgerParser.cs`
  - `Services/Finances/IFinancesService.cs`
  - `Services/Finances/FinancesService.cs`
  - `WinUI/Daily.WinUI/Views/FinancesDetailPage.xaml` & `.xaml.cs`
  - `WinUI/Daily.WinUI/Controls/FinancesWidgetControl.xaml` & `.xaml.cs`
  - `WinUI/Daily.WinUI/Services/SmartBriefingService.cs` & `WinUI/Daily.WinUI/MainPage.xaml.cs`
- **Capabilities**:
  - Canonical single-row `smart_ledgers` deduplication and timestamp-aware merge between `SyncService` and `FinancesService`.
  - Parser parity with `SmartLedgerStore.swift`: `DefaultLedgerText`, European number formatting, ignoring pure `(notes)` in totals, splitting `=` before `//` comments, and full CRUD helpers (`AdjustItemAmount`, `SetItemAmount`, `UpdateItemAmountAndNote`, `AddItem`, `DeleteItem`).
  - Upgraded `FinancesDetailPage` (`Money` tab): clean note subtitles, hidden steppers on pure note lines, rich item quick-adjust dialog (delta chips, live `Lei` preview, inline note editor, item deletion), currency-aware `+ Add` dialog, and bidirectional `CurrentViewType` sync with `FinancesWidgetControl`.
  - Upgraded `FinancesWidgetControl` (`Money` FlipView card) and `SmartBriefingService` to display live Smart Ledger Net Worth (`Lei` + `~€`), `Deposits`, `Monthly Flow` (`In · Out`), and `Top Outgoing` items.

---

## 3. Live Verification on Windows 11 ARM64 (Parallels VM)
- **Build**: `dotnet build "WinUI\Daily.WinUI\Daily.WinUI.csproj" -c Debug -p:Platform=ARM64 --nologo` -> **`0 Error(s)`**.
- **Expired JWT Startup Refresh**: Verified against a real 17-hour-expired persisted `SupabaseSession_JSON.txt`: `SupabaseSessionGuardian` decoded `prevExpUtc`, refreshed single-flight in ~800ms, normalized `ExpiresIn` to `3600s`, and persisted both primary and backup session files with zero `PGRST303` errors.
- **Realtime `101 Switching Protocols` & Live Event Delivery**: Verified `EnsureRealtimeConnectedAsync: Realtime WebSocket connected (101 Switching Protocols)`, `App.InitializeAsync: COMPLETED`, `TagdosService` & `HabitsService` Realtime channel subscriptions, and live delivery of a remote `300 ml` hydration log directly onto the WinUI Dashboard in real time.
- **UI & Cross-Hub State**: Visually verified Dashboard widgets, Smart Briefing, `Finances` -> `Money` (`127,156 Lei` / `~25,431 €`), Dashboard `Finances` `Money` FlipView sync, `TagDoS & Notes` (all 5 synced cloud streams + 4 quick notes), and global `refresh` pipe/button execution with zero errors in `sync_debug.log`.
