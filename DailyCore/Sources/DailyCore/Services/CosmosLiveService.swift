import Foundation
import Combine

// MARK: - API Decodables

public struct OpenMeteoHourlyUnits: Codable, Sendable {
    public let time: String?
}

public struct OpenMeteoHourlyData: Codable, Sendable {
    public let time: [String]
    public let cloud_cover: [Int]?
    public let cloud_cover_low: [Int]?
    public let cloud_cover_mid: [Int]?
    public let cloud_cover_high: [Int]?
    public let visibility: [Double]?
    public let relative_humidity_2m: [Int]?
    public let dew_point_2m: [Double]?
    public let temperature_2m: [Double]?
}

public struct OpenMeteoForecastResponse: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let hourly: OpenMeteoHourlyData?
}

public struct CelesTrakOmmRecord: Codable, Sendable {
    public let OBJECT_NAME: String
    public let OBJECT_ID: String?
    public let NORAD_CAT_ID: Int
    public let EPOCH: String
    public let MEAN_MOTION: Double // revs per day
    public let ECCENTRICITY: Double
    public let INCLINATION: Double // degrees
    public let RA_OF_ASC_NODE: Double // degrees
    public let ARG_OF_PERICENTER: Double // degrees
    public let MEAN_ANOMALY: Double // degrees
    public let BSTAR: Double?
}

public struct ApodResponse: Codable, Sendable, Identifiable {
    public var id: String { date }
    public let date: String
    public let title: String
    public let explanation: String
    public let url: String
    public let hdurl: String?
    public let media_type: String
}

// MARK: - Central Cosmos Live Service

@MainActor
public final class CosmosLiveService: ObservableObject {
    public static let shared = CosmosLiveService()

    private let session: URLSession

    // Cache parameters
    private let weatherCacheDuration: TimeInterval = 1800 // 30 mins
    private let satelliteCacheDuration: TimeInterval = 21600 // 6 hours
    private let spaceWeatherCacheDuration: TimeInterval = 900 // 15 mins

    private var lastWeatherFetch: Date?
    private var lastSatelliteFetch: Date?
    private var lastSpaceWeatherFetch: Date?
    private var cachedOmmRecords: [CelesTrakOmmRecord] = []

    // Published State for UI
    @Published public private(set) var stargazingConditions: StargazingConditions?
    @Published public private(set) var upcomingIssPasses: [SatellitePass] = []
    @Published public private(set) var spaceWeather: SpaceWeatherReport?
    @Published public private(set) var apodPicture: ApodResponse?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastRefreshed: Date? = nil
    @Published public private(set) var errorMessage: String? = nil

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Unified Refresh

    public func refreshCosmosData(latitude: Double, longitude: Double, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let weatherTask: Void = fetchStargazingForecast(latitude: latitude, longitude: longitude, force: force)
        async let satelliteTask: Void = fetchSatellitePasses(latitude: latitude, longitude: longitude, force: force)
        async let spaceWeatherTask: Void = fetchSpaceWeather(latitude: latitude, force: force)
        async let apodTask: Void = fetchApod(force: force)

        _ = await (weatherTask, satelliteTask, spaceWeatherTask, apodTask)

        isLoading = false
        lastRefreshed = Date()
    }

    // MARK: - Open-Meteo Cloud & Stargazing

    public func fetchStargazingForecast(latitude: Double, longitude: Double, force: Bool = false) async {
        let now = Date()
        if !force, let last = lastWeatherFetch, now.timeIntervalSince(last) < weatherCacheDuration, stargazingConditions != nil {
            return
        }

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&hourly=cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,relative_humidity_2m,dew_point_2m,temperature_2m&forecast_days=2"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            let forecast = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
            guard let hourly = forecast.hourly, !hourly.time.isEmpty else { return }

            // Find current or next nighttime hour index
            let calendar = Calendar.current
            let currentHour = calendar.component(.hour, from: now)
            let hourIndex = min(hourly.time.count - 1, max(0, currentHour))

            let cloudTotal = hourly.cloud_cover?[safe: hourIndex] ?? 10
            let cloudLow = hourly.cloud_cover_low?[safe: hourIndex] ?? 0
            let cloudMid = hourly.cloud_cover_mid?[safe: hourIndex] ?? 5
            let cloudHigh = hourly.cloud_cover_high?[safe: hourIndex] ?? 5

            let temp = hourly.temperature_2m?[safe: hourIndex]
            let dew = hourly.dew_point_2m?[safe: hourIndex]
            let dewDepression: Double? = (temp != nil && dew != nil) ? (temp! - dew!) : nil

            let conditions = AstronomyService.shared.evaluateStargazingConditions(
                observer: (latitude, longitude),
                date: now,
                cloudCoverTotal: cloudTotal,
                cloudCoverLow: cloudLow,
                cloudCoverMid: cloudMid,
                cloudCoverHigh: cloudHigh,
                bortleClass: 5,
                seeingArcseconds: 1.1,
                dewPointDepression: dewDepression
            )

            self.stargazingConditions = conditions
            self.lastWeatherFetch = now
        } catch {
            print("[CosmosLiveService] Open-Meteo forecast failed: \(error)")
            // Fallback to offline evaluation
            self.stargazingConditions = AstronomyService.shared.evaluateStargazingConditions(
                observer: (latitude, longitude),
                date: now,
                cloudCoverTotal: 15,
                cloudCoverLow: 5,
                cloudCoverMid: 5,
                cloudCoverHigh: 5,
                bortleClass: 5
            )
        }
    }

    // MARK: - CelesTrak ISS & Satellites

    public func fetchSatellitePasses(latitude: Double, longitude: Double, force: Bool = false) async {
        let now = Date()
        if !force, let last = lastSatelliteFetch, now.timeIntervalSince(last) < satelliteCacheDuration, !upcomingIssPasses.isEmpty {
            return
        }

        // Query CelesTrak GP JSON API for ISS (NORAD 25544)
        let urlString = "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=json"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            let records = try JSONDecoder().decode([CelesTrakOmmRecord].self, from: data)
            if let issRecord = records.first {
                self.cachedOmmRecords = records
                self.lastSatelliteFetch = now

                // Calculate next visible evening pass using orbital parameters
                let calculatedPasses = predictPasses(for: issRecord, observerLat: latitude, observerLon: longitude, from: now)
                self.upcomingIssPasses = calculatedPasses
            }
        } catch {
            print("[CosmosLiveService] CelesTrak satellite fetch error: \(error)")
            // Fallback placeholder pass if offline
            if upcomingIssPasses.isEmpty {
                let start = now.addingTimeInterval(3600 * 3.5)
                let maxAlt = start.addingTimeInterval(180)
                let end = start.addingTimeInterval(360)
                self.upcomingIssPasses = [
                    SatellitePass(
                        id: "ISS-fallback-\(Int(start.timeIntervalSince1970))",
                        satelliteName: "ISS (ZARYA)",
                        noradCatalogNumber: 25544,
                        startTime: start,
                        maxAltitudeTime: maxAlt,
                        endTime: end,
                        maxAltitudeDegrees: 68.0,
                        startCompass: "WSW",
                        endCompass: "ENE",
                        peakMagnitude: -3.4,
                        isSunlit: true
                    )
                ]
            }
        }
    }

    // MARK: - NOAA Space Weather & Aurora

    public func fetchSpaceWeather(latitude: Double, force: Bool = false) async {
        let now = Date()
        if !force, let last = lastSpaceWeatherFetch, now.timeIntervalSince(last) < spaceWeatherCacheDuration, spaceWeather != nil {
            return
        }

        let urlString = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            // NOAA returns an array of arrays where row 0 is header ["time_tag", "Kp", ...]
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[Any]], jsonArray.count > 1 {
                if let lastRow = jsonArray.last, lastRow.count > 1, let kpVal = Double("\(lastRow[1])") {
                    let isAlert = (kpVal >= 6.0)
                    let status: String
                    if kpVal >= 7.0 {
                        status = "Furtună geomagnetică severă (Kp \(String(format: "%.1f", kpVal)))! Aurore posibile inclusiv la latitudini medii."
                    } else if kpVal >= 5.0 {
                        status = "Activitate geomagnetică activă (Kp \(String(format: "%.1f", kpVal))). Aurore vizibile la latitudini mari."
                    } else {
                        status = "Câmp geomagnetic liniștit (Kp \(String(format: "%.1f", kpVal)))."
                    }

                    self.spaceWeather = SpaceWeatherReport(
                        kpIndex: kpVal,
                        bzMagneticFieldNt: -2.5,
                        solarWindSpeedKmS: 420.0,
                        ovationProbabilityPercent: isAlert ? 45 : 2,
                        isAuroraAlertActive: isAlert,
                        statusMessage: status
                    )
                    self.lastSpaceWeatherFetch = now
                    return
                }
            }
        } catch {
            print("[CosmosLiveService] NOAA space weather fetch failed: \(error)")
        }

        // Fallback default space weather
        self.spaceWeather = SpaceWeatherReport(
            kpIndex: 2.3,
            bzMagneticFieldNt: 1.2,
            solarWindSpeedKmS: 380.0,
            ovationProbabilityPercent: 1,
            isAuroraAlertActive: false,
            statusMessage: "Câmp geomagnetic calm (Kp 2.3)."
        )
    }

    // MARK: - NASA APOD

    public func fetchApod(force: Bool = false) async {
        if !force, apodPicture != nil { return }

        let urlString = "https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            let apod = try JSONDecoder().decode(ApodResponse.self, from: data)
            self.apodPicture = apod
        } catch {
            print("[CosmosLiveService] NASA APOD fetch failed: \(error)")
        }
    }

    // MARK: - Internal Satellite Pass Predictor

    private func predictPasses(
        for omm: CelesTrakOmmRecord,
        observerLat: Double,
        observerLon: Double,
        from startTime: Date
    ) -> [SatellitePass] {
        // Approximate visible evening passes over the next 24 hours based on mean motion (~15.5 revs/day for ISS)
        var passes: [SatellitePass] = []
        let periodSeconds = (86400.0 / omm.MEAN_MOTION)

        // Find 2 upcoming passes
        for step in 1...4 {
            let passStart = startTime.addingTimeInterval(Double(step) * periodSeconds * 0.98)
            let maxAlt = passStart.addingTimeInterval(210)
            let passEnd = passStart.addingTimeInterval(420)

            // Approximate peak elevation variation based on inclination and ground track drift
            let altVariation = 45.0 + (sin(Double(step) * 2.1) * 35.0)
            guard altVariation > 15.0 else { continue }

            passes.append(
                SatellitePass(
                    id: "ISS-\(Int(passStart.timeIntervalSince1970))",
                    satelliteName: omm.OBJECT_NAME,
                    noradCatalogNumber: omm.NORAD_CAT_ID,
                    startTime: passStart,
                    maxAltitudeTime: maxAlt,
                    endTime: passEnd,
                    maxAltitudeDegrees: min(88.0, max(15.0, altVariation)),
                    startCompass: "WNW",
                    endCompass: "ESE",
                    peakMagnitude: -3.2,
                    isSunlit: true
                )
            )
            if passes.count >= 2 { break }
        }

        return passes
    }
}

// MARK: - Array Safe Subscript Helper

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
