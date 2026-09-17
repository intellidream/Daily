# Android Phase 1: Authentication & Settings Architecture

## 1. Overview
Phase 1 establishes user session management and persistent application settings for DayOne Android, fully matching the contract and UX behavior of DayOne iOS and `DailyCore`.

## 2. Authentication Architecture (`core-network`)
- **Library**: Supabase Kotlin SDK 3.0.0 (`postgrest-kt`, `auth-kt`, `realtime-kt`, `functions-kt`) with Ktor 3.0.
- **Provider**: Google OAuth with PKCE flow.
- **Deep Link Intent Filter**:
  - Scheme: `com.intellidream.daily`
  - Host: `login-callback`
  - Manifest Config: `android:launchMode="singleTask"`
- **Offline / Guest Mode**:
  - Enables full app experience without a network or cloud account requirement.
  - Generates a local `UserProfile.Guest` ("Guest User") with `firstName` = "Guest".
  - Persisted in DataStore Preferences so app restarts preserve the guest session state without re-prompting.

## 3. Settings Persistence (`core-database`)
- **Storage**: Jetpack DataStore Preferences (`androidx.datastore.preferences.core`).
- **Data Model**: `AppSettings` (serialized with `kotlinx.serialization.json`):
  - `isGuestMode: Boolean`
  - `theme: AppTheme` (System, Dark, Light)
  - `glassIntensity: GlassIntensity` (Subtle, Medium, Prominent)
  - `hapticsEnabled: Boolean`
  - `healthSleepTargetHours: Double` (default 8.0)
  - `habitsWaterTargetLiters: Double` (default 2.0)
  - `weatherUnitSystem: WeatherUnitSystem` (Metric, Imperial)
  - `weatherAlwaysAutoLocation: Boolean`
  - `dashboardWidgets: List<DashboardWidgetConfig>` (modular 2-column coalesced layout configuration)

## 4. UI Layer (`app/src/main/java/com/intellidream/daily/presentation`)
- **`LoginScreen.kt`**:
  - Glowing Cyan/Blue lock glass badge.
  - Google OAuth action button with tactile spring feedback.
  - "Continue without signing in" button for zero-barrier guest access.
- **`SettingsScreen.kt`**:
  - Account Card displaying avatar/badge, full name, email, and Sign Out / Sign In action.
  - Appearance section with segmented glass selectors for Theme and Glass Intensity, plus Haptic toggle.
  - Health & Habits Goals section for nocturnal sleep duration and daily water hydration targets.
  - Weather & Atmosphere section with Metric/Imperial segmented selector and auto-location GPS/IP toggle.

## 5. Verification & Testing
- **Emulator**: `Medium_Phone_API_36.1` (ARM64, Android API 36).
- **Test Scenarios**:
  1. Cold launch unauthenticated -> renders `LoginScreen`.
  2. Tap "Continue without signing in" -> transitions to `DailyRootScreen` displaying "Welcome, Guest".
  3. Navigate to Settings -> change Glass Intensity to `Prominent` and Units to `Imperial`.
  4. Force stop process and relaunch -> restores active guest session and persistent settings immediately.
  5. Sign out -> returns cleanly to `LoginScreen` and clears guest state.
