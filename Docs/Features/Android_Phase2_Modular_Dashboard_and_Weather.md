# Android Phase 2: Modular Dashboard & Weather Station Architecture

## 1. Overview
Phase 2 establishes the core home screen experience of DayOne Android: the coalesced 2-column modular dashboard grid and the complete multi-aspect-ratio Weather Station widget, achieving complete parity with DayOne iOS and `DailyCore`.

## 2. Coalesced 2-Column Grid Engine (`core-model`)
- **File**: `com.intellidream.daily.model.DashboardRowBuilder.kt`
- **Ported from**: iOS `DashboardRowBuilder.swift`
- **Algorithm**:
  - Traverses the user-configured list of enabled widgets (`DashboardWidgetConfig`).
  - Coalesces widgets into hole-free rows:
    - `Full`: A single full-width widget (`2x1 Wide` or `2x2 Large`).
    - `Pair`: Two side-by-side small widgets (`1x1` + `1x1`).
    - `TallWithSmalls`: A tall widget (`1x2`) paired alongside one or two stacked small (`1x1`) widgets.
    - `SingleSmall`: A standalone `1x1` widget spanning one column when unmatched.
  - Ensures a tight, masonry-free, perfectly aligned 2-column layout without gaps or empty space.

## 3. Weather Models & Atmospheric Data (`core-model`)
- **File**: `com.intellidream.daily.model.WeatherModels.kt`
- **Models**:
  - `WeatherResponse`: Current temperature, feels like, min/max, humidity, atmospheric pressure, wind speed, cloud cover, and sunrise/sunset epochs.
  - `ForecastResponse` & `ForecastItem`: 3-hour interval telemetry for 24-hour and 5-day projections.
  - `DailyForecastSummary`: Grouped daily forecast data.
  - `WeatherConditionHelper`: Maps WMO condition codes and OpenWeather icons to Material rounded icons, descriptions, and dynamic ambient color tints (e.g. Amber for Sun, Cyan for Rain, Violet for Storms).

## 4. Atmospheric Networking & Offline Cache (`core-network` & `core-database`)
- **Repository**: `WeatherRepository.kt`
  - Engine: Ktor CIO client with `ContentNegotiation` and `kotlinx.serialization.json`.
  - API: OpenWeatherMap 2.5 (`weather` and `forecast` endpoints).
  - Geolocation Strategy:
    1. Android Fused Location / GPS coordinates when permitted.
    2. Zero-permission IP geolocation fallback via `freeipapi.com` (`latitude`, `longitude`, `cityName`).
    3. Default coordinates fallback (Bucharest: `44.4268, 26.1025`) if offline/unreachable.
  - Unit Systems: Dynamically adapts to `WeatherUnitSystem.Metric` (`units=metric`, °C, m/s) or `WeatherUnitSystem.Imperial` (`units=imperial`, °F, mph).
- **Cache**: `WeatherCacheRepository.kt`
  - Stores cached current weather and 24-hour forecast payloads in Jetpack DataStore Preferences.
  - Instant zero-latency display on application cold launch before network refresh.

## 5. UI Layer & Multi-Aspect Adaptive Cards (`app`)
- **`WeatherDashboardCard.kt`**:
  - Renders all 4 modular grid sizes dynamically based on widget configuration:
    - **`1x1 Small`** (155dp): Minimalist telemetry badge with condition icon, location, 36sp temperature, condition text, and High/Low badge.
    - **`2x1 Wide`** (160dp): Standard banner with location, condition text, 46sp bold temperature, High/Low, humidity pill, and prominent condition icon.
    - **`1x2 Tall`** (324dp): Vertical column card with location, 38sp temperature, divider, and a 4-slot vertical hourly forecast strip with humidity and wind metrics.
    - **`2x2 Large`** (324dp): Comprehensive Weather Station. Features current temperature, condition badge, High/Low, a horizontal 24-hour hourly forecast strip (6 ticks), and a 4-tile atmospheric grid (Humidity, Wind Speed, Atmospheric Pressure, Sunrise).
- **`DashboardView.kt`**:
  - Greeting header with time-of-day greeting ("Good morning", "Good afternoon", "Good evening"), user first name, settings button, and customize button.
  - Dynamic coalesced row rendering via `DashboardRowBuilder`.
  - Pull-to-refresh / refresh button triggers async update of weather data.
- **`CustomizeDashboardScreen.kt`**:
  - Full-screen glass editor for managing dashboard layout.
  - Interactive reordering with Move Up / Move Down buttons.
  - Aspect ratio segmented selectors (`1x1`, `2x1`, `1x2`, `2x2`) for each widget.
  - Visibility toggles (Enable / Disable).
  - Auto-persists layout changes immediately to DataStore `AppSettings`.

## 6. Verification & Visual Inspection
- **Emulator**: `Medium_Phone_API_36.1` (ARM64, Android API 36).
- **Verification Run**:
  1. Live weather fetching verified with Bucharest coordinates (`82°F` in Imperial, `28°C` in Metric).
  2. Metric/Imperial settings toggle live reload verified.
  3. Dashboard Customizer launched; changed Weather from `2x1 Wide` to `2x2 Large`.
  4. Return to Dashboard verified rendering of 24-hr horizontal forecast and 4 atmospheric telemetry tiles (`emulator_weather_large.png`).
