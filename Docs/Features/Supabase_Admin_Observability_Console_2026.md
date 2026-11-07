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

## 5. Cross-Platform Biometric Protection Architecture (Face ID / Touch ID / Fingerprint / Windows Hello)

To prevent unauthorized access to live database metrics, query logs, API tokens, and schema catalogs, the Supabase Admin Console implements hardware-backed biometric protection across all client platforms:

```
┌────────────────────────────────────────────────────────────────────────┐
│                      Client Settings Screen                            │
│           "Supabase Admin & Usage" (Penultimate Settings Tile)         │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
                 ┌───────────────────────────────────┐
                 │  Is Admin Session Authenticated?  │
                 └─┬───────────────────────────────┬─┘
                   │ No                            │ Yes
                   ▼                               ▼
       ┌───────────────────────┐   ┌───────────────────────────────────┐
       │ SupabaseAdminLogin     │   │ Credentials.RequireBiometrics?    │
       │ Sheet / Window        │   └─┬───────────────────────────────┬─┘
       │ (WebView / PAT Drawer)│     │ No                            │ Yes
       └───────────────────────┘     ▼                               ▼
                         ┌───────────────────────┐   ┌───────────────────────────────────┐
                         │   Open Admin Console  │◄──┤ Is Session Unlocked In Memory?   │
                         └───────────────────────┘   └─┬───────────────────────────────┬─┘
                                                       │ Yes                           │ No
                                                       │                               ▼
                                                       │   ┌───────────────────────────────────┐
                                                       │   │ Biometric Authentication Gate:    │
                                                       │   │ • iOS: LAContext (Face ID)        │
                                                       │   │ • macOS: LAContext (Touch ID)     │
                                                       │   │ • Android: BiometricPrompt        │
                                                       │   │ • Windows: UserConsentVerifier    │
                                                       │   └─┬───────────────────────────────┬─┘
                                                       │     │ Verified                      │ Failed / Cancelled
                                                       └─────┴───────────────────────────────► Remain on Settings Screen
```

### 5.1 Biometric Lifecycle & In-Memory Lock Invariants
1. **Dynamic Biometry Identification**:
   - **iOS**: Uses `LAContext().biometryType` (`.faceID` on iPhone **Schmitz**, `.touchID` on iPads with home/top button, `.opticID` on Vision Pro). Returns dynamically formatted labels: `"Require Face ID to Open Console"`.
   - **macOS**: Uses `LAContext().biometryType` (`.touchID` on Mac keyboards).
   - **Android**: Uses `android.hardware.biometrics.BiometricPrompt` with `BIOMETRIC_STRONG or DEVICE_CREDENTIAL` (API 28-35).
   - **Windows 11**: Uses `Windows.Security.Credentials.UI.UserConsentVerifier` (`CheckAvailabilityAsync` + `RequestVerificationAsync`).
2. **Pre-Flight Biometric Challenge on Preference Toggle**:
   - Toggling the biometric switch (`Require Face ID` / `Require Touch ID` / `Require Biometric Lock` / `Windows Hello`) in the console requires the user to authenticate successfully **before** the preference is flipped. If cancelled or biometrics fail, the toggle reverts to its previous state.
3. **Strict In-Memory Lock on Exit**:
   - `adminService.lock()` is immediately invoked when:
     - The user taps **Done** / **Close** / **Back**.
     - The console view unmounts (`.onDisappear`, `DisposableEffect { onDispose { ... } }`, `Page.Unloaded`).
     - The app transitions to background (`scenePhase == .background` on iOS/macOS).
     - The user disconnects the admin session (`disconnect()`).
   - Consequently, reopening the console from Settings demands a fresh biometric challenge every single time.
4. **Platform-Specific System Declarations**:
   - **iOS**: Added `NSFaceIDUsageDescription` to `iOS/Daily/Resources/Info.plist`:
     `DayOne uses Face ID to securely protect the Supabase Admin Console and cloud database telemetry.`
   - **Android**: Added `<uses-permission android:name="android.permission.USE_BIOMETRIC" />` to `Android/app/src/main/AndroidManifest.xml`.

---

## 6. Unified Egress Architecture: Billing Cycle Quota & 24h Gateway Egress Forensics

To provide both a comprehensive monthly financial quota picture and high-granularity 24-hour traffic analysis, the console implements a dedicated dual-layer egress pipeline:

```
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│                    Full-Width Billing Cycle Egress Card (Row 0 / Top)                     │
│  "Unified Egress · Billing Cycle" ── 4.50 GB / 250 GB (1.8% OF QUOTA) ── [EXACT INVOICE]  │
│  [======================================== ProgressBar =================================]  │
│  Gateway 24h: 38.4 MB   ·   24h Requests: 1,420   ·   Cached CDN: 12.1 MB                 │
└───────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
              ┌───────────────────────────────┴───────────────────────────────┐
              ▼                                                               ▼
┌───────────────────────────────────────────┐   ┌───────────────────────────────────────────┐
│     Tile 1: Gateway Egress (24h)          │   │         Tile 2: Database Size             │
│   38.4 MB / 1,420 requests (0.5% daily)   │   │     180 MB / 8 GB (2.3% of quota)         │
│   CDN: 12.1 MB · 24h HTTP Traffic         │   │     Heap 120 MB · Indexes 60 MB           │
└───────────────────────────────────────────┘   └───────────────────────────────────────────┘
┌───────────────────────────────────────────┐   ┌───────────────────────────────────────────┐
│       Tile 3: Edge Function Calls         │   │       Tile 4: Realtime & Active Fleet     │
│   142 calls / 2,000,000 quota             │   │   12 live subs · Peak 4 / 500             │
│   3 deployed functions                    │   │   MAU: 1 · Log events: 4,820              │
└───────────────────────────────────────────┘   └───────────────────────────────────────────┘
```

### 6.1 Root Cause & Solution for 24h Egress Visibility
1. **Unified ClickHouse Table Source Filter**: Modern Supabase edge logs may populate either `source = 'edge_logs'` or `source_name = 'edge_logs'`. All ClickHouse SQL queries across platforms now filter via `WHERE (source = 'edge_logs' OR source_name = 'edge_logs')`.
2. **Multi-Field Response Size Extraction**: Streaming responses (e.g. PostgREST `application/json` stream, Edge Function responses, Supavisor pooling) frequently use HTTP chunked transfer encoding (`Transfer-Encoding: chunked`) or HTTP/2 without a static `Content-Length` header. The SQL query extracts sizes using:
   ```sql
   sum(greatest(
       toInt64OrZero(log_attributes['response.headers.content-length']),
       toInt64OrZero(log_attributes['response.headers.content_length']),
       toInt64OrZero(log_attributes['response.size']),
       toInt64OrZero(log_attributes['response.body_size']),
       toInt64OrZero(log_attributes['response.bytes'])
   )) AS resp_bytes
   ```
3. **Payload Heuristic Fallback**: In environments where proxies omit response headers entirely, if `req_count > 0 && resp_bytes == 0`, a route-specific payload size heuristic is applied (`/storage/` ~8 KB, `/rest/` ~1.28 KB, `/functions/` ~1.15 KB, `/auth/` ~850 B, `/realtime/` ~450 B, default ~900 B).
4. **Independent Metric Decoupling**: Billing cycle egress (`egressUsedBytes` / `EgressUsedGb`) and 24h gateway egress (`egress24hBytes` / `GatewayEgressBytes24h`) are persisted and rendered independently, preventing cycle figures from overwriting daily burst visibility.

---

## 7. Supabase Portal 1:1 Metric Parity & Billing Cycle Architecture

To ensure 100% mathematical and visual parity with the official Supabase Web Portal (`Dashboard -> Organizations -> [Org] -> Usage`), the telemetry ingestion layer addresses several critical nuances in the Supabase control plane:

### 7.1 Organization Slug Resolution vs. Numeric ID
- The Supabase Management API `GET /v1/projects` returns `organization_id` as a numeric string (e.g. `"294824"`), while `organization_slug` is frequently omitted or null.
- All Supabase Platform APIs (`/platform/organizations/{slug}/usage`, `/platform/organizations/{slug}/billing/subscription`) require the **alphanumeric organization slug** (e.g. `nvyvhvj...`), returning HTTP 404 when passed a numeric ID.
- **Resolution**: All platforms first query `GET /v1/organizations` to build a lookup dictionary mapping numeric IDs to their true slugs, ensuring all subsequent platform requests use the valid slug.

### 7.2 Organization-Wide Quotas vs. Project Scoping
- Under the Supabase Free tier, billing quotas and allowances (Egress, Database Size, Function Calls, Realtime Messages, Log Ingestion) are shared organization-wide across all projects.
- Querying `/usage?project_ref={ref}` isolates only the individual project's slice, diverging from the Supabase Portal overview.
- **Resolution**: Telemetry first requests `GET /platform/organizations/{slug}/usage` without the `project_ref` query parameter (matching the Studio "All projects" view), falling back to project-scoped endpoints if org-level metrics are restricted.

### 7.3 Billing Cycle Period Synchronization
- The console retrieves exact cycle boundaries by querying `GET /platform/organizations/{slug}/billing/subscription` (fallback `GET /v1/organizations/{slug}/billing/subscription`), extracting `current_period_start` and `current_period_end` Unix epoch timestamps.
- Formatted as `d MMM yyyy - d MMM yyyy` (e.g. `19 Oct 2026 - 19 Nov 2026`).
- **Anchor Day Fallback**: If the subscription endpoint is inaccessible, the cycle is computed deterministically using the organization creation date's day-of-month (`created_at`, anchor day 19) clamped to valid calendar ranges (`computeBillingCyclePeriodFromCreation`).

### 7.4 Database Size Quota vs. System Catalog Parity
- In the Supabase portal, **Database Size** displays `0.044 / 0.5 GB (9%)` (reflecting ~47 MB of active user relations).
- Internal PostgreSQL catalog queries (`pg_database_size(current_database())`) include internal system catalogs, Toast tables, temp buffers, and extension files (~68 MB).
- **Resolution**: When exact billing telemetry is available (`isExactBillingUsageAvailable`), `dbSizeBytes` prioritizes `usages.DATABASE_SIZE` directly. Disk heap and index breakdowns remain visible in the subtitle for forensic DBA inspection.

### 7.5 Precision & SI Decimal Gigabyte Parity (`1 GB = 1,000,000,000 bytes`)
- Supabase's billing control plane (`/platform/organizations/{slug}/usage`) measures quotas and byte metrics in **SI decimal gigabytes (`10^9 = 1,000,000,000` bytes)**, **not** binary gibibytes (`2^30 = 1,073,741,824` bytes):
  - Free Plan quotas: Egress `5,000,000,000 B` (`5 GB`), Database Size `500,000,000 B` (`0.5 GB`), Storage / Log Ingestion `1,000,000,000 B` (`1 GB`), Log Query `100,000,000,000 B` (`100 GB`).
  - Example: `usage_original = 3,169,916,695` bytes divided by `1,000,000,000` equals **`3.170 / 5 GB` (`63.4%` → `63%`)**, whereas binary GiB division previously under-reported it as `2.952 GB` (`59%`).
- All models, services, and UI quota cards across `DailyCore`, `iOS`, `macOS`, `Android`, and `WinUI 3` uniformly format byte quotas using SI decimal (`1_000_000_000`) with 3 decimal places (`3.170 / 5 GB (63%)`, `0.044 / 0.5 GB (9%)`).

### 7.6 Dual Control-Plane Authentication, GoTrue Auto-Refresh & Silent Session Self-Healing
- Supabase splits observability across two distinct authentication planes:
  1. **`api.supabase.com/v1/...` (Management API, ClickHouse Logs, Read-Only SQL)**: Accepts durable Personal Access Tokens (`managementAccessToken`, `sbp_...`).
  2. **`api.supabase.com/platform/...` (`/organizations/{slug}/usage`, `/billing/subscription`, `/usage/daily`)**: Strictly requires a **GoTrue Dashboard session JWT (`dashboardAccessToken`, `eyJ...`)** and rejects `sbp_...` PATs with `HTTP 401 Unauthorized`.
- Because GoTrue dashboard JWTs expire after 1 hour (`3,600s`), all platforms implement a three-tier self-healing pipeline:
  1. **`primaryPlatformBearer` Prioritization & Multi-Bearer Fallback**: Prioritizes a valid `dashboardAccessToken` for `/platform/...` endpoints while maintaining `performGetJsonWithFallback` / `getJsonObjectWithFallback` / `PerformGetStringWithFallbackAsync` across both tokens.
  2. **Automatic GoTrue `refresh_token` Rotation**: Before querying `/platform/...` (when `isJwtExpiredOrExpiringSoon` detects `< 180s` remaining) or upon receiving `401`, clients automatically call `POST https://auth.supabase.io/auth/v1/token?grant_type=refresh_token` with `{ "refresh_token": "..." }` and persist the rotated `access_token` + `refresh_token` locally.
  3. **Zero-Friction Session Self-Healing & Committed-Origin Capture**:
     - **iOS & macOS (`WKWebView`)**: Fixed `SupabaseAdminLoginSheet` so `device_code` extraction waits until navigation commits to `https://supabase.com` (rather than inside `decidePolicyFor navigationAction` before origin commit), with brief hydration retry for `localStorage['supabase.dashboard.auth.token']`. For existing sessions missing a refresh token, `WebKitDashboardSessionHarvester` silently reads `localStorage['supabase.dashboard.auth.token']` from `WKWebsiteDataStore.default()` on `https://supabase.com/robots.txt` and refreshes via GoTrue without requiring re-login.
     - **Windows 11 (`WebView2`)**: `SupabaseAdminLoginWindow` captures `?device_code=` and `localStorage['supabase.dashboard.auth.token']` with hydration retry, while `TryRecoverRefreshTokenFromWebView2Storage()` recovers existing GoTrue refresh tokens from the local `EBWebView` LevelDB store so existing Windows sessions self-heal transparently.

### 7.7 Dynamic Billing Cycle Window, Exact Summary Precedence & Daily Deduplication
- **Dynamic Cycle Start Date**: `computeBillingCycleStartDate` dynamically resolves the billing cycle start timestamp (zero hardcoded dates) from:
  1. `current_period_start` from `/billing/subscription`
  2. `billing_cycle_start` or `period_start` from `/usage`
  3. `created_at` anchor day from the organization or project API response
  4. Standard calendar month start (Day 1) as safe fallback.
- **Exact Billing Summary Precedence**: When `/platform/organizations/{slug}/usage` returns exact billing metrics (`isExact && egressUsedBytes > 0`), `resolvedCycleEgress` uses `billingData.egressUsedBytes` (`usages.EGRESS.usage_original`) directly as single source of truth; `sumDailyEgressBytes` is used only as fallback when exact org usage is unavailable.
- **`/usage/daily` Date Deduplication**: Because `/platform/organizations/{slug}/usage/daily` emits multiple metric rows per `YYYY-MM-DD`, all platforms group and sum breakdown slices (`rest` / `functions` / `realtime` / `storage` / `auth`) by date so the Daily Bandwidth chart renders one consolidated stacked bar per calendar day.
- **Snapshot Cache Validation (`v2`)**: Bumped local snapshot cache keys to `v2` across all 4 platforms and bypassed cached snapshots whenever `!isExactBillingUsageAvailable`, ensuring stale 24h fallback snapshots never mask live billing cycle quotas.

### 7.8 Android UX & Header Streamlining
- **Streamlined TopAppBar**: Replaced 5 individual action buttons in the top bar with a single elegant `MoreVert` (3-dots) overflow menu containing Refresh, Multi-project switcher, Markdown export, and Disconnect options.
- **Glass Hero Header Card**: Added `ProjectHeaderCard` at the top of the telemetry feed matching iOS, displaying server rack icon, project name, plan badge (`FREE`), `READ-ONLY` badge, compute tier, PG version, admin identity, and refresh timestamp.
- **Daily Bandwidth & Gateway Activity**: Upgraded the daily stacked egress visualization with service legends (REST Cyan, Edge Purple, Realtime Green, Auth & Storage Blue), rounded bar segments, and date labels.
- **Navigation Bar Inset Padding**: Expanded bottom content padding to 96dp and bottom spacer to 80dp with `.navigationBarsPadding()`, ensuring the Console Security & Biometric Lock card scrolls completely clear of Android gesture and 3-button navigation bars.

### 7.9 Strict Decoupling of 24h Gateway Egress vs Billing Cycle Unified Egress & ClickHouse Query Hygiene
- **Independent 24h Gateway Egress (`egress24hBytes`) vs Unified Egress (`egressUsedBytes`)**:
  - Unified Egress represents the total organization-wide billing cycle quota usage (`3.170 / 5 GB = 63%` over the current 30-day billing cycle).
  - 24h Gateway Egress represents solely the payload delivered by the HTTP API gateway over the last 24 hours (`~38 MB`).
  - Previously, when ClickHouse returned 0 bytes, a fallback attempted to pull from `todayDailyPointBytes`. However, `metric: "EGRESS"` from `/platform/organizations/{slug}/usage` was inadvertently accumulated into daily buckets, dumping the entire 3.17 GB monthly total into the 24h gateway tile!
  - **Resolution**:
    1. Removed `"EGRESS"`, `"UNIFIED_EGRESS"`, and `"TOTAL_EGRESS"` from `/usage/daily` accumulation.
    2. Guarded `resolved24hEgress` across Swift, Kotlin, and C#: only accept `todayDailyPointBytes` if `todayDailyPointBytes < billingData.egressUsedBytes`, otherwise cleanly falling back to `apiCountEstimatedBytes` (~10-40 MB) from `usage.api-counts?interval=1day`.
    3. Aligned `egress24hQuotaPercent` in `DailyCore` to compute against daily budget (`Double(egressQuotaBytes) / 30.0`), matching Android and WinUI 3.
- **ClickHouse Analytics Query Hygiene (`source = 'edge_logs'`)**:
  - ClickHouse's `logs` table in Supabase Analytics contains strictly the `source` column (`source = 'edge_logs'`), not `source_name`. Using `(source = 'edge_logs' OR source_name = 'edge_logs')` triggered `Code: 47. DB::Exception: Missing columns: 'source_name'` (HTTP 400).
  - Reverted ClickHouse queries across all platforms back to strictly `WHERE source = 'edge_logs'`.
- **Snapshot Cache Invalidation (`v3`)**:
  - Bumped snapshot cache key prefix to `v3` (`admin_snapshot_v3_`, `supabase_admin_snapshot_v3.json`).
  - Added proactive corrupt snapshot rejection in `loadCachedSnapshot`: if `cached.egress24hBytes >= cached.egressUsedBytes && cached.egressUsedBytes > 500_000_000`, the cache is rejected immediately to purge corrupted 3.17 GB values.

### 7.10 Edge Calls String Formatting & Comprehensive Log Ingestion / Log Query Telemetry
- **Edge Calls Darwin String Formatting Fix**:
  - In Swift on Darwin libc, `String(format: "%,d", ...)` is not a valid format specifier (unlike Java/Kotlin where `%,d` inserts comma groupings), causing Darwin `printf` to output literal `",d"`.
  - Replaced with standard Swift 6 `.formatted()` (`snap.functionInvocations.formatted()` and `snap.functionInvocationsQuota.formatted()`), displaying formatted invocation counts (e.g. `4,218 / 500,000`) cleanly.
- **Log Ingestion & Log Query Quota Tiles Across All Platforms**:
  - Surfaced `Log Ingestion` (`0.411 / 1.0 GB (41%)`) and `Log Query` (`49.563 / 100 GB (50%)`) directly in the executive quota grids across iOS, macOS, Android, and Windows 11 WinUI 3:
    - **iOS**: Expanded `executiveQuotasGrid` from 4 to 6 symmetrical tiles (Gateway 24h, DB Size, Edge Calls, Realtime Peak, Log Ingestion, Log Query).
    - **macOS**: Configured a balanced 3-column desktop layout (2 rows of 3 tiles) featuring dedicated icons (`tray.and.arrow.down.fill`, `magnifyingglass.circle.fill`).
    - **Android**: Updated `ExecutiveQuotaSection` with adaptive 3x2 layout on phones and 2x3 layout on foldable unfolded screens (`isWide`), with event counters (`411 events`).
    - **Windows 11 (WinUI 3)**: Added Row 3 to `BuildQuotaGrid` with purple and cyan accents, displaying SI decimal usage, percentage utilization, and quota limits.
    - **Markdown Exporters**: Added Log Ingestion and Log Query rows to `toMarkdownReport()` / `ToMarkdownReport()` across Swift, Kotlin, and C#.

---

## 8. Verification & Physical Device Delivery Summary

- **`DailyCore` Unit Tests**: `swift test --package-path DailyCore` — **65/65 passed** across all 8 test suites with zero failures.
- **macOS Native Build & Delivery**: `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build` — **`** BUILD SUCCEEDED **`** with automatic `Apple Development` (`7LZ9ZT2Z5B`) codesigning.
- **iOS Physical Device Delivery ("Schmitz" — iPhone 16 Pro, `00008140-000E2C863EFB001C`)**: `xcodebuild -project iOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'id=00008140-000E2C863EFB001C'` — verified and installed via `xcrun devicectl device install app`.
- **Android Physical Foldable Delivery ("Radar" — Samsung Galaxy Z Fold 8, `SM_F971B`)**: `./gradlew :app:assembleDebug` — **`BUILD SUCCESSFUL`**; installed via wireless TLS ADB (`adb -s adb-R3GL70B1LGP-HLPtmw._adb-tls-connect._tcp install -r app-debug.apk` → `Success`).
- **Android Physical Flagship Delivery ("Trapper" — Google Pixel 9 Pro, `Pixel_9_Pro`)**: Installed via wireless TLS ADB (`adb -s adb-48231FDAP0011V-Ma9KPE._adb-tls-connect._tcp install -r app-debug.apk` → `Success`).
- **Windows 11 (`WinUI 3` ARM64 in Parallels)**: `dotnet build WinUI\Daily.WinUI\Daily.WinUI.csproj -c Debug -p:Platform=ARM64` — verified with durable PAT prioritization, daily bandwidth legend, and expanded scroll viewport.
