import Foundation
import Combine

public enum LocationSource: String, Sendable {
    case unknown = "Locating"
    case gps = "GPS"
    case ip = "Network"
    case manual = "Custom"
}

/// Central Weather service managing real-time conditions, 5-day forecasts, resilient geolocation, and city search.
@MainActor
public final class WeatherService: ObservableObject {
    public static let shared = WeatherService()

    private let apiKey = "eebcefca9dbf33a96cb6d583481235d2"
    private let baseUrl = "https://api.openweathermap.org/data/2.5"
    private let geoUrl = "https://api.openweathermap.org/geo/1.0"
    private let ipUrl = "https://freeipapi.com/api/json"

    // Caching parameters
    private let cacheDuration: TimeInterval = 900 // 15 minutes
    private let locationTolerance: Double = 0.01   // ~1 km

    private var cachedCurrentWeather: WeatherResponse?
    private var cachedForecast: ForecastResponse?
    private var lastFetchTime: Date?
    private var lastCoordinates: (lat: Double, lon: Double)?

    // Published state for UI bindings
    @Published public private(set) var currentWeather: WeatherResponse?
    @Published public private(set) var forecast: ForecastResponse?
    @Published public private(set) var dailySummaries: [DailyForecastSummary] = []
    @Published public private(set) var hourlyForecasts: [ForecastItem] = []
    @Published public private(set) var currentLocationName: String = "Detecting..."
    @Published public private(set) var isAutoLocation: Bool = true
    @Published public private(set) var locationSource: LocationSource = .unknown
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()

    public init(session: URLSession = .shared) {
        self.session = session
        setupSettingsListener()
    }

    private func setupSettingsListener() {
        SettingsService.shared.$settings
            .map { $0.weatherUnitSystem }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.refreshWeather(force: true)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Resilient Location Determination

    public func getResilientCoordinates() async -> (lat: Double, lon: Double, source: LocationSource, cityName: String?) {
        // 1. Check in-memory cache
        if let lastCoords = lastCoordinates,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            return (lastCoords.lat, lastCoords.lon, locationSource, currentLocationName)
        }

        // 2. Try CoreLocation GPS
        do {
            let coords = try await LocationManager.shared.requestCurrentLocation(timeoutSeconds: 8)
            return (coords.latitude, coords.longitude, .gps, nil)
        } catch {
            print("[WeatherService] GPS unavailable (\(error.localizedDescription)), falling back to IP geolocation...")
        }

        // 3. Fallback to IP Geolocation (freeipapi.com)
        if let ipCoords = await getLocationFromIP() {
            return (ipCoords.lat, ipCoords.lon, .ip, ipCoords.cityName)
        }

        // 4. Default fallback: New York if all network/GPS fails
        return (40.7128, -74.0060, .unknown, "New York")
    }

    private func getLocationFromIP() async -> (lat: Double, lon: Double, cityName: String?)? {
        guard let url = URL(string: ipUrl) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            let ipInfo = try JSONDecoder().decode(IpLocationResponse.self, from: data)
            if let lat = ipInfo.latitude, let lon = ipInfo.longitude {
                return (lat, lon, ipInfo.cityName)
            }
        } catch {
            print("[WeatherService] IP Geolocation error: \(error)")
        }
        return nil
    }

    // MARK: - Weather Refreshing

    public func refreshWeather(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let targetLat: Double
        let targetLon: Double
        let targetSource: LocationSource
        var inferredCityName: String?

        if isAutoLocation {
            let res = await getResilientCoordinates()
            targetLat = res.lat
            targetLon = res.lon
            targetSource = res.source
            inferredCityName = res.cityName
        } else if let coords = lastCoordinates {
            targetLat = coords.lat
            targetLon = coords.lon
            targetSource = .manual
        } else {
            targetLat = 40.7128
            targetLon = -74.0060
            targetSource = .unknown
        }

        do {
            async let currentTask = fetchCurrentWeather(latitude: targetLat, longitude: targetLon, forceRefresh: force)
            async let forecastTask = fetchForecast(latitude: targetLat, longitude: targetLon, forceRefresh: force)

            let (currentResult, forecastResult) = try await (currentTask, forecastTask)

            self.currentWeather = currentResult
            self.forecast = forecastResult
            self.lastCoordinates = (targetLat, targetLon)
            self.lastFetchTime = Date()
            self.locationSource = targetSource

            // Set display city name
            if !currentResult.name.isEmpty {
                self.currentLocationName = currentResult.name
            } else if let cityName = inferredCityName, !cityName.isEmpty {
                self.currentLocationName = cityName
            } else {
                self.currentLocationName = "Local Area"
            }

            // Process forecast summaries
            self.hourlyForecasts = Array(forecastResult.list.prefix(8))
            self.dailySummaries = aggregateDailyForecasts(from: forecastResult.list)
        } catch {
            self.errorMessage = error.localizedDescription
            print("[WeatherService] Weather fetch failed: \(error)")
        }

        self.isLoading = false
    }

    // MARK: - Manual City Selection

    public func setManualLocation(name: String, latitude: Double, longitude: Double) async {
        self.isAutoLocation = false
        self.currentLocationName = name
        self.locationSource = .manual
        self.lastCoordinates = (latitude, longitude)
        await refreshWeather(force: true)
    }

    public func resetToAutoLocation() async {
        self.isAutoLocation = true
        self.lastCoordinates = nil
        self.lastFetchTime = nil
        await refreshWeather(force: true)
    }

    // MARK: - API Calls

    public func fetchCurrentWeather(latitude: Double, longitude: Double, forceRefresh: Bool = false) async throws -> WeatherResponse {
        if !forceRefresh,
           let cached = cachedCurrentWeather,
           let lastCoords = lastCoordinates,
           isLocationClose(latitude, longitude, lastCoords.lat, lastCoords.lon),
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            return cached
        }

        let unitParam = SettingsService.shared.settings.weatherUnitSystem.rawValue
        let urlString = "\(baseUrl)/weather?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)&units=\(unitParam)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let weather = try JSONDecoder().decode(WeatherResponse.self, from: data)
        self.cachedCurrentWeather = weather
        return weather
    }

    public func fetchForecast(latitude: Double, longitude: Double, forceRefresh: Bool = false) async throws -> ForecastResponse {
        if !forceRefresh,
           let cached = cachedForecast,
           let lastCoords = lastCoordinates,
           isLocationClose(latitude, longitude, lastCoords.lat, lastCoords.lon),
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            return cached
        }

        let unitParam = SettingsService.shared.settings.weatherUnitSystem.rawValue
        let urlString = "\(baseUrl)/forecast?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)&units=\(unitParam)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: data)
        self.cachedForecast = forecast
        return forecast
    }

    // MARK: - City Search (Direct Geocoding)

    public func searchLocations(query: String, limit: Int = 8) async -> [LocationSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        let urlString = "\(geoUrl)/direct?q=\(encoded)&limit=\(limit)&appid=\(apiKey)"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            return try JSONDecoder().decode([LocationSuggestion].self, from: data)
        } catch {
            print("[WeatherService] Location search failed: \(error)")
            return []
        }
    }

    // MARK: - Aggregation Helpers

    private func aggregateDailyForecasts(from items: [ForecastItem]) -> [DailyForecastSummary] {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        let dateNumFormatter = DateFormatter()
        dateNumFormatter.dateFormat = "MMM d"

        // Group items by calendar day
        var grouped: [Date: [ForecastItem]] = [:]
        for item in items {
            let startOfDay = calendar.startOfDay(for: item.date)
            grouped[startOfDay, default: []].append(item)
        }

        let sortedDays = grouped.keys.sorted()

        return sortedDays.prefix(5).map { dayDate in
            let dayItems = grouped[dayDate] ?? []
            let minTemp = dayItems.map { $0.main.tempMin }.min() ?? 0
            let maxTemp = dayItems.map { $0.main.tempMax }.max() ?? 0
            let popMax = dayItems.compactMap { $0.pop }.max() ?? 0

            // Choose midday item (around 12:00-15:00) for representative condition
            let middayItem = dayItems.first { item in
                let hour = calendar.component(.hour, from: item.date)
                return hour >= 11 && hour <= 15
            } ?? dayItems.first

            let iconCode = middayItem?.weather.first?.icon ?? "01d"
            let conditionText = middayItem?.weather.first?.description.capitalized ?? "Clear"
            let sfSymbol = WeatherConditionHelper.sfSymbol(for: iconCode)

            let isToday = calendar.isDateInToday(dayDate)
            let dayName = isToday ? "Today" : dayFormatter.string(from: dayDate)
            let dateFormatted = dateNumFormatter.string(from: dayDate)
            let id = ISO8601DateFormatter().string(from: dayDate)

            return DailyForecastSummary(
                id: id,
                date: dayDate,
                dayName: dayName,
                dateFormatted: dateFormatted,
                tempMin: minTemp,
                tempMax: maxTemp,
                iconCode: iconCode,
                sfSymbolName: sfSymbol,
                conditionText: conditionText,
                popMax: popMax
            )
        }
    }

    private func isLocationClose(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Bool {
        abs(lat1 - lat2) < locationTolerance && abs(lon1 - lon2) < locationTolerance
    }
}
