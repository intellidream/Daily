# Feature: Weather (OpenWeatherMap & Resilient Location)

The Weather feature provides real-time atmospheric metrics and a 5-day forecast. It uses dynamic geolocation fallback layers and cached weather state structures to ensure instant UI rendering even during poor network conditions or disabled GPS permissions.

---

## 1. Functional Specification

### 1.1 Real-Time Weather Metrics
- **Current Conditions**: Displays the temperature, wind speed and direction, humidity, pressure, clouds percentage, and sunrise/sunset times.
- **5-Day Weather Forecast**: Provides an hourly and daily outlook for temperature ranges, precipitation probability, and weather conditions.
- **Configurable Unit Systems**: Supports switching between Imperial (Fahrenheit) and Metric (Celsius) systems. Changes to settings automatically trigger service events to re-fetch and refresh all live weather data.

### 1.2 Resilient Geolocation Strategy
To obtain the user's location without blocking the application startup, the weather service implements a multi-tiered fallback strategy:

1. **Memory Caching**: Checks if a valid user location exists in memory that is less than 15 minutes old. If found, it skips GPS requests entirely.
2. **Permission Check & Request**: Checks for the platform's location permissions (`Permissions.LocationWhenInUse`). If not granted, it requests permission on the main UI thread.
3. **Last Known Location**: Queries the OS for the last cached GPS coordinates. This is instantaneous and does not spin up GPS hardware.
4. **GPS Request**: Launches a GPS request with a strict 10-second timeout to avoid locking the thread if GPS satellite sync takes too long.
5. **IP-based Geolocation Fallback**: If permissions are denied or GPS fails/times out, the app falls back to a free, HTTPS-capable IP geolocation API (`https://freeipapi.com/api/json`) to get estimated coordinates based on the user's internet connection.

---

## 2. Technical Architecture & Data Model

### 2.1 Services & Dependency Injection
- `IWeatherService` / `WeatherService`: Manages coordinate caching, triggering state events, fetching IP locations, and downloading weather JSON.
- `IGeolocation`: A MAUI device abstraction used to fetch system-level GPS coordinates.
- `ISettingsService`: Used to monitor user configurations, such as switching from Fahrenheit to Celsius.

### 2.2 Data Models & Schema
Weather data is retrieved from the OpenWeatherMap API and parsed into POCO structures. It is not saved to the database, but cached in-memory.

#### In-Memory Cache Parameters
- `CacheDuration`: 15 minutes.
- `LocationTolerance`: 0.01 degrees (approximately 1km). If the user moves less than 1km, the cached weather is preserved to save API quota.

#### API Models (`Models/WeatherModels.cs`)
- **`WeatherResponse`**: Captures current weather data matching OpenWeatherMap's `/weather` endpoint (coordinates, weather descriptions, wind, main stats, country, timezone).
- **`ForecastResponse`**: Contains a list of `ForecastItem` objects matching OpenWeatherMap's `/forecast` endpoint (predictive hourly metrics, rain probability).

---

## 3. UI/UX & Layout

### 3.1 Weather Banner & Custom Drawing
- In WinUI, the banner rendering uses `WeatherBannerControl.cs`. This custom control handles drawing high-fidelity weather illustrations, temperature typography, and visual cues matching current conditions.
- Weather details include secondary metrics displayed in stylized pills (e.g. humidity, wind speed, pressure).

### 3.2 Responsive Adaptations
- **Widget Representation**: Displays a compacted card showing current temperature, location name, and condition icon.
- **Detail View**: Opens a full-width layout with a hero weather card on one side and a horizontal scrolling list of 3-hour forecast intervals on the other.

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **UI Technology** | Native XAML Controls (`WeatherWidgetControl.xaml` & `WeatherDetailPage.xaml`) | Blazor Hybrid Razor components (`WeatherWidget.razor` & `WeatherDetail.razor`) |
| **Graphics** | Custom Segoe Fluent Icons and native drawing elements | MudBlazor icons and CSS styling transitions |
| **Layouts** | Grid systems, stack layouts, and XAML VisualStates | MudBlazor cards, flex rows, and responsive CSS breakpoints |
| **Location APIs** | Runs through MAUI's `IGeolocation` bridge on Windows | Runs directly through native MAUI device APIs on iOS, Android, and macOS |
