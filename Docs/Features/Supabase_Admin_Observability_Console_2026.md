# Supabase Admin Mode & Cloud Observability Console

**Date:** November 6, 2026  
**Scope:** Non-intrusive, 100% read-only Cloud Control-Plane & Database Observability Console inside **Settings → Data & Cloud Synchronization**  
**Platforms:** `DailyCore` (Swift 6), `iOS` (`iOS/Daily`), `macOS` (`MacOS/Daily`), `Android` (`core-model`, `core-network`, `app`), `Windows 11` (`WinUI 3` / `.NET 10`)  
**Smartwatches (`watchOS` & `Wear OS`):** Intentionally untouched (zero wrist UI clutter, zero background network impact; watch traffic is audited from companion/desktop clients via ecosystem footprint telemetry).

---

## 1. Architectural Overview & Design Goals

DayOne operates as a multi-device personal cloud ecosystem (`iOS`, `macOS`, `Android`, `WinUI 3`, `watchOS`, `Wear OS`) backed by Supabase project `Daily` (`akkfouifxztnfwwiclwg`), with multi-project selector support when the authenticated admin owns multiple Supabase projects.

Following the egress and wearable retention optimizations documented in `Docs/Features/Supabase_Egress_And_Wearable_Retention_Optimization.md`, this feature adds a **first-party Cloud SRE & Observability Console** directly inside **Settings → Data & Cloud Synchronization** (the penultimate Settings tile across platforms) while adhering to four strict invariants:

1. **Non-Intrusive Entry Point**:
   - Normal users see only a compact, single-line `"Supabase Admin & Usage"` row at the bottom of `Data & Cloud Synchronization`.
   - Zero control-plane, ClickHouse, or `pg_catalog` requests are ever issued unless the user explicitly authenticates and opens or refreshes the console (`10-minute` local snapshot cache TTL).
2. **100% Read-Only Telemetry (v1)**:
   - Every Management API endpoint (`GET`), ClickHouse log analytics query (`GET /v1/projects/{ref}/analytics/endpoints/logs`), and PostgreSQL diagnostic query (`POST /v1/projects/{ref}/database/query/read-only` running under `supabase_read_only_user`) is strictly read-only.
   - Zero `DELETE`, `TRUNCATE`, `VACUUM`, `REINDEX`, config mutations, or Edge Function deployments can be triggered from the client.
3. **Hybrid GitHub OAuth (`Supabase CLI Login`) + Personal Access Token (`sbp_...`) Authentication**:
   - Primary login uses an embedded native WebView (`WKWebView`, Android `WebView`, `WebView2`) pointed at `https://supabase.com/dashboard/cli/login` so admins who sign into Supabase with **GitHub** authenticate in one tap without manually creating tokens.
   - A collapsible manual `Personal Access Token (sbp_...)` drawer is available right inside the login header for headless/token workflows.
4. **Device-Local Credential Isolation**:
   - Admin tokens (`sbp_...` PAT and optional short-lived GoTrue dashboard JWT) are persisted strictly on the local device and **never** written to cloud-synced `user_preferences` or cross-device settings tables:
     - **iOS**: Hardware Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
     - **macOS**: Sandboxed FileVault-encrypted `GroupDefaults.shared.userDefaults` (`7LZ9ZT2Z5B.group.com.intellidream.daily`), avoiding `login.keychain-db` `SecurityAgent` password prompts under App Sandbox.
     - **Android**: AES-256-GCM hardware-backed Android Keystore wrapper over private `SharedPreferences`.
     - **Windows 11 (WinUI 3)**: Windows DPAPI (`DataProtectionProvider("LOCAL=user")`) in `%LocalAppData%\Daily.WinUI\supabase_admin_creds.dpapi`.

---

## 2. Cryptographic Protocol: P-256 ECDH + AES-256-GCM Handshake

Supabase's interactive CLI Login (`https://supabase.com/dashboard/cli/login`) performs end-to-end encryption of the generated `sbp_...` Personal Access Token between the Supabase Dashboard and the native client:

1. **Ephemeral Client Keypair Generation**:
   - Client generates a fresh ephemeral **NIST P-256 (`secp256r1`)** ECDH keypair per login attempt and exports the **65-byte ANSI X9.63 uncompressed public point** (`0x04 || X(32) || Y(32)`) as a 130-character lowercase hex string (`public_key`).
   - Client opens `https://supabase.com/dashboard/cli/login?session_id=<uuid>&token_name=<DayOne-Platform>&public_key=<130-hex>`.
2. **SPA Verification Code & Dashboard Session Capture**:
   - After GitHub OAuth completes, Supabase's Next.js SPA displays an 8-hex-character `device_code` (or redirects via SPA `pushState`).
   - An injected DOM/history observer captures the 8-char `device_code` automatically (plus `localStorage['supabase.dashboard.auth.token']` when present on `supabase.com` origin for exact billing quota readouts) and posts it to the native bridge (`WKScriptMessageHandler` / `@JavascriptInterface` / `CoreWebView2.WebMessageReceived`).
   - If GitHub OAuth temporarily lands on `/dashboard/projects` or `/dashboard/organizations`, automatic redirect recovery navigates back to the pending `/dashboard/cli/login` URL.
3. **Token Poll & Raw ECDH AES-256-GCM Decryption**:
   - Client polls `GET https://api.supabase.com/platform/cli/login/{session_id}?device_code={8-hex}` to receive `{ public_key, nonce, access_token }`.
   - Client computes the **raw 32-byte ECDH shared secret X-coordinate `Z`** (without HKDF/SHA-256 wrapping):
     - Swift 6 (`CryptoKit`): `sharedSecret.withUnsafeBytes { Data($0) }`
     - Kotlin (`javax.crypto.KeyAgreement`): `KeyAgreement.getInstance("ECDH").generateSecret()`
     - .NET 10 (`System.Security.Cryptography`): `localEcdh.DeriveRawSecretAgreement(peerEcdh.PublicKey)`
   - Client decrypts `access_token` (`ciphertext || 16-byte GCM tag`) using **AES-256-GCM** with the 12-byte `nonce`.

---

## 3. Read-Only Telemetry Pipeline

When the console opens (and the 10-minute local snapshot TTL has expired) or when the user taps **Refresh**, all telemetry queries execute concurrently:

| Domain | Endpoint / Query | Key Metrics Surfaced |
|---|---|---|
| **Projects & Orgs** | `GET /v1/projects`, `GET /v1/organizations`, `GET /v1/projects/{ref}/billing/addons` | Multi-project switcher (defaulting to `akkfouifxztnfwwiclwg`), org plan (`Free`/`Pro`), compute tier (`Nano`/`Micro`/etc.), region, Postgres version |
| **Billing Quotas & Egress** | `GET /platform/organizations/{slug}/usage` (when dashboard JWT active) + gateway fallback | Exact Unified Egress (`GB` vs quota), Cached Egress, DB & Storage quotas, MAU quota |
| **14-Day Stacked Egress** | `GET /v1/projects/{ref}/analytics/endpoints/usage.api-counts?interval=1day` + 24h byte calibration | Daily stacked breakdown across `PostgREST`, `Auth`, `Realtime`, `Storage`, and `Edge Functions` |
| **Database, Bloat & Disk** | `GET /v1/projects/{ref}/config/disk` + `POST /v1/projects/{ref}/database/query/read-only` (`pg_catalog.*`) | `pg_database_size`, Heap vs B-Tree Indexes, per-table live/dead tuples & total DML writes, **`INDEX BLOAT >3x` badge** (`index_bytes > 2 MB` and `index/heap > 3.0`), `gp3` Disk GB / IOPS / MB/s |
| **Cron & SQL Hotspots** | `POST /v1/projects/{ref}/database/query/read-only` (`cron.job`, `cron.job_run_details`, `extensions.pg_stat_statements`) | Health of `pg_cron` retention jobs (`apply_health_data_retention`, etc.), top SQL statements by `total_exec_time`, and `realtime.list_changes` WAL CPU share % |
| **24h Gateway Logs** | `GET /v1/projects/{ref}/analytics/endpoints/logs` (ClickHouse SQL on `FROM logs WHERE source = 'edge_logs'`, `<24h` window) | 24h `2xx`/`4xx`/`5xx` counts, error rate %, top endpoints ranked by `response.headers.content-length`, and recent `4xx/5xx` error inspector |
| **Edge Functions & Realtime** | `GET /v1/projects/{ref}/functions`, `GET /v1/projects/{ref}/analytics/endpoints/functions.combined-stats`, `realtime.subscription` | Deployed functions (`health-engine`, etc.), version, JWT enforcement, 24h invocations/errors/avg ms, active Realtime listener count by table |
| **Ecosystem Fleet & Advisors** | ClickHouse `User-Agent` classifier + `auth.sessions` + `paired_watches` + `/v1/projects/{ref}/advisors/{performance,security}` | 24h request & egress share across `iOS`, `macOS`, `Android`, `Windows 11`, `Smartwatches`, and `Cloud Cron`, plus active Performance & Security Advisor lints |
| **Cloud SRE AI Co-Pilot & Export** | Gemini 2.5 Flash (`iOS`/`macOS`/`Android`), On-Device NPU/LLM (`WinUI 3`), + deterministic SRE analyzer | 4-bullet SRE diagnostic (quota posture, B-tree index bloat remediation, gateway error/egress hotspots, Realtime WAL & `pg_cron` hygiene) + one-click **Copy / Export Forensic Markdown (`.md`)** |

> **Important OpenAPI & Read-Only SQL Notes**:
> - `/v1/projects/{ref}/analytics/endpoints/logs.all` is deprecated (`410 Gone`); all platforms target `GET /v1/projects/{ref}/analytics/endpoints/logs` using ClickHouse SQL (`toInt32OrZero(log_attributes['response.status_code'])`, `toInt64OrZero(log_attributes['response.headers.content-length'])`) with an explicit `[now - 23.8h, now]` window (`< 24h` hard requirement).
> - `POST /v1/projects/{ref}/database/query/read-only` executes under `supabase_read_only_user` and requires schema-qualified catalog calls (`pg_catalog.pg_database_size`, `pg_catalog.pg_total_relation_size`, `pg_catalog.json_agg`, `extensions.pg_stat_statements`).

---

## 4. Platform-Specific Implementations

### 4.1 Shared Swift Core (`DailyCore`)
- `DailyCore/Sources/DailyCore/Models/SupabaseAdminModels.swift`: Sendable domain models + `toMarkdownReport()`.
- `DailyCore/Sources/DailyCore/Services/SupabaseAdminCrypto.swift`: P-256 ECDH + AES-256-GCM handshake, SPA redirect recovery helpers, and platform-conditional credential storage (`GroupDefaults` on macOS vs Keychain on iOS).
- `DailyCore/Sources/DailyCore/Services/SupabaseAdminService.swift`: Swift 6 strict-concurrency `@MainActor` service with parallel `async let` `Data` fetchers, 10-min cache TTL, Gemini 2.5 Flash SRE co-pilot, and deterministic diagnostic fallback.
- `DailyCore/Tests/DailyCoreTests/SupabaseAdminServiceTests.swift`: Unit tests covering P-256 ECDH + AES-256-GCM round-trip, `device_code` extraction, SPA redirect recovery, GoTrue session parsing, and bloat detection.

### 4.2 macOS (`MacOS/Daily`)
- `MacOS/Daily/Views/Settings/DataSyncSettingsSection.swift`: Non-intrusive `"Supabase Admin & Usage"` row inside the penultimate `Data & Cloud Synchronization` section.
- `MacOS/Daily/Views/Settings/SupabaseAdminLoginSheet.swift`: Native `WKWebView` sheet (`didCommit` spinner dismissal + popup handler + collapsible `SecureField` PAT drawer).
- `MacOS/Daily/Views/Settings/SupabaseAdminConsoleView.swift`: Wide Liquid Glass console with `Swift Charts` 14-day stacked egress `BarMark` chart, multi-column executive quota cards, table bloat inspector, `NSSavePanel` `.md` export, and `NSPasteboard` copy.

### 4.3 iOS (`iOS/Daily`)
- `iOS/Daily/Views/Settings/DataSyncSettingsSection.swift`: Matching non-intrusive row inside the penultimate `Data & Cloud Synchronization` section, with optional Face ID (`LAContext`) unlock guard when opening a persisted admin session.
- `iOS/Daily/Views/Settings/SupabaseAdminLoginSheet.swift`: Mobile-optimized `NavigationStack` + `WKWebView` + collapsible PAT bar.
- `iOS/Daily/Views/Settings/SupabaseAdminConsoleView.swift`: Adaptive `fullScreenCover` console supporting both iPhone (**Schmitz**) and foldable/iPad split grids, `Swift Charts` stacked egress bars, `ShareLink` Markdown export, and UIPasteboard copy.

### 4.4 Android (`Android/`)
- `Android/core-model/src/main/java/com/intellidream/daily/model/SupabaseAdminModels.kt`: Immutable Kotlin models + Markdown exporter.
- `Android/core-network/src/main/java/com/intellidream/daily/network/SupabaseAdminRepository.kt` & `SupabaseAdminTest.kt`: Hardware `AndroidKeyStore` AES-256-GCM credential encryption, JCA P-256 `KeyAgreement("ECDH")` handshake, parallel `Dispatchers.IO` aggregator, and Gemini + deterministic SRE analyzer.
- `Android/app/src/main/java/com/intellidream/daily/presentation/SettingsScreen.kt`: Repositioned `CloudSyncSettingsCard` to the **penultimate tile** (immediately above `AboutSettingsCard`), titled `"Data & Cloud Synchronization"`, with the subtle `"Supabase Admin & Usage"` row.
- `Android/app/src/main/java/com/intellidream/daily/presentation/SupabaseAdminLoginSheet.kt` & `SupabaseAdminScreen.kt`: Full-screen Liquid Glass Compose console with adaptive 2-column layout for **Samsung Galaxy Z Fold 8 ("Radar")** (`screenWidthDp >= 600`), custom Compose `Canvas` stacked egress chart, and Android Share Sheet / Clipboard export.

### 4.5 Windows 11 (`WinUI/Daily.WinUI`)
- `WinUI/Daily.WinUI/Models/SupabaseAdminModels.cs` & `WinUI/Daily.WinUI/Services/SupabaseAdminService.cs`: `.NET 10` `ECDiffieHellman.DeriveRawSecretAgreement` + `AesGcm` handshake, `DataProtectionProvider("LOCAL=user")` DPAPI storage, parallel `HttpClient` telemetry pipeline, and on-device `ISmartIntelligenceService` (NPU / Phi-Silica / Local GGUF) + deterministic SRE fallback.
- `WinUI/Daily.WinUI/Views/DataSyncSettingsPage.xaml` (`.cs`): Replaced the `{ "Data", typeof(AboutPage) }` stub in `SettingsPage.xaml.cs` with a full Fluent `Data & Cloud Synchronization` page (`Supabase Cloud Engine` status, `Sync Now`, `Test Latency`, `Local SQLite Offline Cache` footprint, and the non-intrusive `Supabase Admin & Usage` card).
- `WinUI/Daily.WinUI/Views/SupabaseAdminLoginWindow.cs`: DPI-aware centered Mica `Window` hosting `WebView2` (`CoreWebView2Environment` with `LocalApplicationData\Daily.WinUI\WebView2`) + collapsible `PasswordBox` PAT drawer.
- `WinUI/Daily.WinUI/Views/SupabaseAdminPage.xaml` (`.cs`): Full Fluent telemetry console inside `SettingsPage`'s `ContentFrame` with filter pills, 2x2 quota progress cards, stacked 14-day egress bars, PostgreSQL bloat & `pg_cron` cards, gateway error inspector, and `FileSavePicker` / `Clipboard` `.md` export.

---

## 5. Verification Summary

- **`DailyCore` Unit Tests**: `swift test --package-path DailyCore --filter SupabaseAdminServiceTests` — **5/5 passed** (`0.005s`).
- **macOS Native Build & Live Run**: `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` — **`** BUILD SUCCEEDED **`** with automatic `Apple Development` (`7LZ9ZT2Z5B`) signing; verified live on macOS (`Data & Cloud Synchronization` + `SupabaseAdminLoginSheet` WebView + PAT drawer) with zero `SecurityAgent` Keychain prompts.
- **iOS Build**: `xcodebuild -project iOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'generic/platform=iOS' build` — **`** BUILD SUCCEEDED **`** (ready for live device verification on **Schmitz**).
- **Android Unit Tests & APK Build**: `./gradlew :core-network:testDebugUnitTest :app:assembleDebug` — **`BUILD SUCCESSFUL`** with zero Kotlin warnings in new files (ready for live device verification on **Radar**).
- **Windows 11 (`WinUI 3` ARM64 in Parallels)**: `dotnet build WinUI\Daily.WinUI\Daily.WinUI.csproj -c Debug -p:Platform=ARM64` — **`0 Error(s)`**, zero warnings in new files; registered MSIX and verified `Data & Cloud Synchronization` + `SupabaseAdminLoginWindow` (`WebView2`) live on Windows 11 at 200% DPI.
