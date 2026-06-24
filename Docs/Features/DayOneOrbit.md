# DayOne Orbit

**DayOne Orbit** represents a standalone direct-to-cloud wearable architecture for the DayOne ecosystem.

## Functional Overview
Instead of relying on a mobile companion app running constantly on your phone, your smartwatch (Apple Watch or Android Wear) directly syncs your health data to the DayOne cloud backend. The WinUI 3 desktop application acts as the "center of gravity" (hence, Orbit), directly subscribing to cloud events to update your health dashboard in real time.

### Key Features
- **Standalone Watch Pairing**: Securely link your smartwatch directly to your DayOne account using a 6-digit OTP (One Time Password) generated from the WinUI settings dashboard. The pairing code is enriched with the desktop's active access and refresh tokens, seamlessly onboarding the watch into the cloud ecosystem without requiring mobile phone login prompts.
- **Direct Cloud Sync**: The smartwatch routinely batches and uploads raw health metrics (Heart Rate, Steps, Energy, etc.) straight to the Supabase cloud without waking up your phone.
- **Configurable Sync Frequency**: You can adjust how often the watch wakes up to sync (Every 15 mins, 30 mins, or Hourly) directly from the WinUI settings, allowing you to optimize for real-time data vs. battery life.
- **Real-Time Desktop UI**: As soon as the watch uploads raw telemetry data to the cloud, the data is automatically aggregated and pushed in real-time to the WinUI desktop application via WebSockets, instantly updating your dashboard.
