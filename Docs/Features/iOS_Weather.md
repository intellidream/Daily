# Feature: iOS Weather (Liquid Glass Experience & Multiplatform Core)

This document details the design, architecture, and implementation of the **Weather** feature for the native DayOne iOS application and its shared multiplatform foundation (`DailyCore`), modeled after the WinUI 3 desktop application with modern tactile glassmorphism.

---

## 1. Functional Specification

### 1.1 Real-Time Atmospheric Telemetry
The DayOne Weather feature delivers atmospheric data powered by OpenWeatherMap API:
- **Current Conditions**: Temperature, "Feels Like" index, minimum / maximum daily range, human-readable condition description, and dynamic atmospheric tinting.
- **24-Hour Forecast Carousel**: Horizontal scrolling Liquid Glass pills displaying 3-hour forecast steps with native multicolor SF Symbols, temperatures, and precipitation probability badges (`pop` %).
- **5-Day Predictive Outlook**: Grouped daily forecast cards featuring weekday, date, condition icon, precipitation chance, and a relative temperature range track bar (visual min-to-max gradient fill).
- **2x3 Atmospheric Metrics Grid**:
  1. **Wind**: Velocity (`m/s` or `mph`), cardinal direction ("N", "NE", "SSW", etc.), and degree heading.
  2. **Humidity**: Percentage with comfort classification ("High moisture", "Comfortable", "Dry air").
  3. **Pressure**: Barometric pressure in `hPa` with barometric trend indication.
  4. **Visibility**: Visual distance in kilometers or miles.
  5. **Cloudiness**: Cloud coverage percentage.
  6. **Sun Schedule**: Sunrise and Sunset timestamps formatted to local time.

### 1.2 Resilient Multi-Tier Location Resolution
To guarantee instant UI rendering without freezing or hanging when GPS hardware is inaccessible (such as on Wi-Fi simulators or indoors), `WeatherService` implements a resilient multi-tier location fallback strategy:
1. **In-Memory Cache (15 Minutes / 1km Tolerance)**: If valid weather data and coordinates exist that are less than 15 minutes old and within ~1km (`0.01°`), remote network calls are bypassed.
2. **CoreLocation GPS (Hardware Accuracy)**: Queries `LocationManager.shared.requestCurrentLocation(timeoutSeconds: 8)` with an async/await timeout.
3. **IP Geolocation Fallback (`freeipapi.com`)**: If location permissions are denied, disabled, or GPS satellite lock times out, the service falls back to HTTPS IP geolocation (`https://freeipapi.com/api/json`) to resolve coordinates from the user's internet connection.
4. **Manual City Search & Override**: Users can search any city worldwide (`/geo/1.0/direct`) and switch to custom coordinates, with an auto-location reset option to return to GPS.

---

## 2. Technical Architecture & Data Model

### 2.1 Shared Multiplatform Engine: `DailyCore`
Located at `/Users/mihai/Source/Daily/DailyCore`, structured for 100% reuse between iOS and the future macOS application:
- **`Models/WeatherModels.swift`**:
  - `WeatherResponse`: Codable schema matching OpenWeatherMap's `/weather` endpoint.
  - `ForecastResponse` & `ForecastItem`: 5-day / 3-hour predictive metrics with precipitation probabilities.
  - `LocationSuggestion`: Direct geocoding models for city search autocompletion.
  - `DailyForecastSummary`: Clean daily aggregates containing day name, date, min/max temps, SF symbol, and max precipitation chance.
  - `WeatherConditionHelper`: Maps OpenWeather condition IDs and icon codes to native multicolor SF Symbols and glow aura colors.
- **`Services/LocationManager.swift`**:
  - Thread-safe actor-isolated wrapper over `CLLocationManager`.
  - Supports async/await one-shot requests with configurable timeout.
- **`Services/WeatherService.swift`**:
  - Central `@MainActor` observable singleton (`WeatherService.shared`).
  - Manages API communication, in-memory caching, unit switching, and daily forecast aggregation.
  - Listens to `SettingsService.shared.$settings` for live unit changes (`metric` vs `imperial`).

### 2.2 Native iOS UI: `iOS/Daily`
- **`FloatingGlassCapsule.swift`**:
  - Expanded `NavigationTab` to include `.weather` (`cloud.sun.fill`) alongside `.dashboard` and `.settings`.
- **`Views/Dashboard/WeatherDashboardCard.swift`**:
  - Live card on the main Dashboard displaying real-time temperature, condition label, min/max, glowing SF Symbol, and tap-to-navigate action.
- **`Views/Weather/WeatherDetailView.swift`**:
  - Full-screen weather experience with top location bar, GPS/Network/Custom badge, hero temperature card, hourly carousel, 5-day forecast card, and 2x3 atmospheric grid.
- **`Views/Weather/HourlyForecastCarousel.swift`**:
  - Horizontal scrolling glass pills showing time, SF Symbol, rain probability, and temperature.
- **`Views/Weather/DailyForecastCard.swift`**:
  - 5-day outlook rows with dynamic temperature range gradient bars.
- **`Views/Weather/AtmosphericMetricTile.swift`**:
  - Tactile Liquid Glass tiles for atmospheric metrics.
- **`Views/Weather/CitySearchSheet.swift`**:
  - Interactive search modal with debounced autocompletion and popular city quick-picks.

---

## 3. Verification & Test Suite

1. **DailyCore Unit Tests (`DailyCoreTests/WeatherServiceTests.swift`)**:
   - `testDecodeWeatherResponse`: Verified JSON parsing of realistic OpenWeatherMap current conditions payload.
   - `testDecodeForecastResponse`: Verified 5-day predictive forecast decoding and city metadata.
   - `testLocationSuggestionDecoding`: Verified direct geocoding model decoding.
   - `testWeatherConditionHelper`: Verified SF Symbol mapping across weather conditions.
   - `testWindCardinalDirections`: Verified wind degree-to-compass conversion.
   - **Result**: 100% passing (`swift test`).
2. **Xcode Build**:
   - Clean compilation (`** BUILD SUCCEEDED **`) with zero warnings.
3. **Simulator Execution (`SimulaPhone`)**:
   - Tested CoreLocation prompt, GPS detection, and IP fallback.
   - Verified real-time temperature and condition rendering on the Dashboard.
   - Verified 24-hour carousel, 5-day forecast, and 2x3 atmospheric metric grid in the dedicated Weather tab.
   - Verified city search modal and location switching.
