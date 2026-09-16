# DayOne Orbit

**DayOne Orbit** represents a standalone direct-to-cloud wearable architecture for the DayOne ecosystem.

## Functional Overview
Instead of relying on a mobile companion app running constantly on your phone, your smartwatch (Apple Watch, Wear OS, Zepp OS, or HarmonyOS) directly syncs your health data to the DayOne cloud backend. The companion applications (WinUI 3 desktop and now native iOS / macOS) act as centers of gravity, directly managing pairing, sync frequencies, and cloud subscriptions to update your health dashboard in real time.

### Key Features
- **Standalone Watch Pairing ("Noul Mod")**: Securely link any smartwatch directly to your DayOne account using a 6-digit OTP (One Time Password) generated on the watch screen. Entering the PIN in WinUI or iOS Settings invokes `generate_watch_token()` RPC on Supabase, issuing a non-expiring 10-year watch JWT that prevents token rotation conflicts during watch sleep cycles.
- **Cross-Platform Wearable Support**: Fully operational across watchOS (Apple Watch), Wear OS (Pixel Watch, Galaxy Watch, OnePlus Watch), HarmonyOS (Huawei Watch GT), and Zepp OS (Amazfit Balance, Active 2).
- **Native iOS Settings Integration**:
  - Implemented via `OrbitSettingsSection` using the Liquid Glass design language.
  - Displays live linked smartwatches from `paired_watches` with platform icons, names, and pairing timestamps.
  - Collapsible device cards (compact view for $\le 3$ watches, expandable for multi-watch collectors).
  - Custom platform pill selectors for Apple Watch, Wear OS, HarmonyOS, and Zepp OS.
  - Interactive 6-box numeric PIN entry with real-time feedback banners.
  - Destructive remote unpair action with confirmation alerts.
- **Configurable Sync Frequency**: Users can configure how frequently the smartwatch wakes up in the background to batch upload health telemetry and habit logs (Every 15 min, Every 30 min, Hourly), persisted in `AppSettings.watchSyncFrequency`.
- **Direct Cloud Sync**: Smartwatches upload raw telemetry (`health_telemetry`) and habit logs directly to Supabase via Wi-Fi or Cellular LTE, which are aggregated into `health_vitals` and reflected in real time on mobile and desktop dashboards.

## Architecture & Data Contracts
- **`watch_pairing_codes`**: Temporary 6-digit PIN table with 10-minute expiration, claimed by the companion app injecting the user's JWT.
- **`paired_watches`**: Persistent ledger tracking linked smartwatches (`id`, `user_id`, `platform`, `device_name`, `paired_at`, `is_active`). When unpaired remotely, watches clear local credentials on next foreground.
- **`OrbitWatchService` (`DailyCore`)**: Centralized observable service managing reactive state, PIN claims, and unpair routines for iOS and macOS.
