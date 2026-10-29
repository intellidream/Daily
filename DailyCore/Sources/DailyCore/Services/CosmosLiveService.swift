import Foundation
import Combine

// MARK: - API Decodables

public struct OpenMeteoHourlyUnits: Codable, Sendable {
    public let time: String?
}

public struct OpenMeteoHourlyData: Codable, Sendable {
    public let time: [String]
    public let cloud_cover: [Int?]?
    public let cloud_cover_low: [Int?]?
    public let cloud_cover_mid: [Int?]?
    public let cloud_cover_high: [Int?]?
    public let visibility: [Double?]?
    public let relative_humidity_2m: [Int?]?
    public let dew_point_2m: [Double?]?
    public let temperature_2m: [Double?]?
}

public struct OpenMeteoForecastResponse: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let hourly: OpenMeteoHourlyData?
}

public struct SevenTimerAstroSeriesEntry: Codable, Sendable {
    public let timepoint: Int
    public let cloudcover: Int?
    public let seeing: Int?
    public let transparency: Int?
}

public struct SevenTimerAstroResponse: Codable, Sendable {
    public let dataseries: [SevenTimerAstroSeriesEntry]?
}

public struct CelesTrakOmmRecord: Codable, Equatable, Sendable {
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

    public init(
        OBJECT_NAME: String,
        OBJECT_ID: String? = nil,
        NORAD_CAT_ID: Int,
        EPOCH: String,
        MEAN_MOTION: Double,
        ECCENTRICITY: Double,
        INCLINATION: Double,
        RA_OF_ASC_NODE: Double,
        ARG_OF_PERICENTER: Double,
        MEAN_ANOMALY: Double,
        BSTAR: Double? = nil
    ) {
        self.OBJECT_NAME = OBJECT_NAME
        self.OBJECT_ID = OBJECT_ID
        self.NORAD_CAT_ID = NORAD_CAT_ID
        self.EPOCH = EPOCH
        self.MEAN_MOTION = MEAN_MOTION
        self.ECCENTRICITY = ECCENTRICITY
        self.INCLINATION = INCLINATION
        self.RA_OF_ASC_NODE = RA_OF_ASC_NODE
        self.ARG_OF_PERICENTER = ARG_OF_PERICENTER
        self.MEAN_ANOMALY = MEAN_ANOMALY
        self.BSTAR = BSTAR
    }
}

public struct ApodResponse: Codable, Equatable, Sendable, Identifiable {
    public var id: String { date }
    public let date: String
    public let title: String
    public let explanation: String
    public let url: String
    public let hdurl: String?
    public let media_type: String
    public let copyright: String?
}

// MARK: - Central Cosmos Live Telemetry Service (Zero Fabricated Metrics)

@MainActor
public final class CosmosLiveService: ObservableObject {
    public static let shared = CosmosLiveService()

    private let session: URLSession

    private let weatherCacheDuration: TimeInterval = 1800 // 30 mins
    private let satelliteCacheDuration: TimeInterval = 14400 // 4 hours
    private let spaceWeatherCacheDuration: TimeInterval = 900 // 15 mins

    private let ommCacheKey = "daily_cosmos_cached_iss_omm_v2"
    private let ommFetchedAtKey = "daily_cosmos_cached_iss_omm_ts_v2"
    private let spaceWeatherCacheKey = "daily_cosmos_cached_space_weather_v2"
    private let apodCacheKey = "daily_cosmos_cached_apod_v2"
    private let apodFetchedAtKey = "daily_cosmos_cached_apod_ts_v2"

    private var lastWeatherFetch: Date?
    private var lastWeatherCoordinate: (Double, Double)?
    private var lastSatelliteFetch: Date?
    private var lastSpaceWeatherFetch: Date?
    private var cachedIssOmm: CelesTrakOmmRecord?
    private var cachedIssOmmFetchedAt: Date?

    @Published public private(set) var stargazingConditions: StargazingConditions?
    @Published public private(set) var upcomingIssPasses: [SatellitePass] = []
    @Published public private(set) var satelliteProvenance: TelemetryProvenance = .unavailable(reason: "Orbital elements not yet loaded")
    @Published public private(set) var spaceWeather: SpaceWeatherReport?
    @Published public private(set) var apodPicture: ApodResponse?
    @Published public private(set) var apodProvenance: TelemetryProvenance = .unavailable(reason: "APOD not yet loaded")
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastRefreshed: Date? = nil
    @Published public private(set) var errorMessage: String? = nil

    private var defaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? .standard
    }

    public init(session: URLSession = .shared) {
        self.session = session
        restoreCachedTelemetry()
    }

    private func restoreCachedTelemetry() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: ommCacheKey),
           let omm = try? decoder.decode(CelesTrakOmmRecord.self, from: data) {
            self.cachedIssOmm = omm
            if let ts = defaults.object(forKey: ommFetchedAtKey) as? Double {
                self.cachedIssOmmFetchedAt = Date(timeIntervalSince1970: ts)
            }
        }
        if let apodData = defaults.data(forKey: apodCacheKey),
           let apod = try? decoder.decode(ApodResponse.self, from: apodData) {
            self.apodPicture = apod
            let ts = (defaults.object(forKey: apodFetchedAtKey) as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            let ageMin = max(1, Int(Date().timeIntervalSince(ts) / 60.0))
            self.apodProvenance = .cached(fetchedAt: ts, ageMinutes: ageMin)
        }
        if let swData = defaults.data(forKey: spaceWeatherCacheKey),
           let sw = try? decoder.decode(SpaceWeatherReport.self, from: swData) {
            self.spaceWeather = sw
        }
    }

    // MARK: - Live Real-Time ISS Sky Position (SGP4)

    public func currentIssPosition(
        latitude: Double,
        longitude: Double,
        elevationMeters: Double = 0.0,
        at date: Date = Date()
    ) -> LiveSatellitePosition? {
        guard let omm = cachedIssOmm else { return nil }
        if let epoch = SGP4Propagator.parseOmmEpoch(omm.EPOCH),
           abs(date.timeIntervalSince(epoch)) > 14.0 * 86400.0 {
            return nil // Reject stale LEO orbital elements older than 14 days
        }
        return SGP4Propagator.livePosition(
            omm: omm,
            at: date,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            elevationMeters: elevationMeters
        )
    }

    // MARK: - Unified Refresh

    public func refreshCosmosData(latitude: Double, longitude: Double, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let weatherTask: Void = fetchStargazingForecast(latitude: latitude, longitude: longitude, force: force)
        async let satelliteTask: Void = fetchSatellitePasses(latitude: latitude, longitude: longitude, force: force)
        async let spaceWeatherTask: Void = fetchSpaceWeather(latitude: latitude, longitude: longitude, force: force)
        async let apodTask: Void = fetchApod(force: force)

        _ = await (weatherTask, satelliteTask, spaceWeatherTask, apodTask)

        isLoading = false
        lastRefreshed = Date()

        await CosmosSyncService.shared.evaluateOptInSkyAlerts(
            stargazing: stargazingConditions,
            passes: upcomingIssPasses,
            spaceWeather: spaceWeather
        )

        WidgetDataCoordinator.shared.updateCosmosSnapshot(
            latitude: latitude,
            longitude: longitude,
            stargazing: stargazingConditions,
            nextIssPass: upcomingIssPasses.first,
            spaceWeather: spaceWeather
        )
    }

    // MARK: - Open-Meteo (UTC-Aligned) + 7Timer ASTRO Seeing

    public func fetchStargazingForecast(latitude: Double, longitude: Double, force: Bool = false) async {
        let now = Date()
        let coordMoved: Bool = {
            guard let prev = lastWeatherCoordinate else { return true }
            return abs(prev.0 - latitude) > 0.08 || abs(prev.1 - longitude) > 0.08
        }()

        if !force && !coordMoved,
           let last = lastWeatherFetch,
           now.timeIntervalSince(last) < weatherCacheDuration,
           stargazingConditions != nil {
            return
        }

        let bortle = CosmosCatalogService.shared.bortleClass(latitude: latitude, longitude: longitude)
        let settings = SettingsService.shared.settings
        let baseEndpoint = (settings.cosmosWeatherEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "https://api.open-meteo.com/v1/forecast"

        var urlString = "\(baseEndpoint)?latitude=\(latitude)&longitude=\(longitude)&hourly=cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,relative_humidity_2m,dew_point_2m,temperature_2m&timezone=UTC&forecast_days=2"
        if let apiKey = settings.cosmosWeatherApiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            urlString += "&apikey=\(apiKey)"
        }

        // Fetch 7Timer ASTRO seeing & transparency concurrently (best-effort)
        async let astroSeeingTask = fetchSevenTimerSeeing(latitude: latitude, longitude: longitude)

        guard let url = URL(string: urlString) else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let forecast = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
            guard let hourly = forecast.hourly, !hourly.time.isEmpty else {
                throw URLError(.cannotParseResponse)
            }

            let utcParser = DateFormatter()
            utcParser.locale = Locale(identifier: "en_US_POSIX")
            utcParser.timeZone = TimeZone(secondsFromGMT: 0)
            utcParser.dateFormat = "yyyy-MM-dd'T'HH:mm"

            var parsedSlots: [(index: Int, date: Date, low: Int, mid: Int, high: Int)] = []
            parsedSlots.reserveCapacity(hourly.time.count)
            for (idx, tStr) in hourly.time.enumerated() {
                if let slotDate = utcParser.date(from: tStr) {
                    let lo = hourly.cloud_cover_low?[safe: idx] ?? hourly.cloud_cover?[safe: idx] ?? 0
                    let mi = hourly.cloud_cover_mid?[safe: idx] ?? hourly.cloud_cover?[safe: idx] ?? 0
                    let hi = hourly.cloud_cover_high?[safe: idx] ?? hourly.cloud_cover?[safe: idx] ?? 0
                    parsedSlots.append((idx, slotDate, lo ?? 0, mi ?? 0, hi ?? 0))
                }
            }

            // Strictly match the UTC timestamp closest to `now`
            let matchedIdx = parsedSlots.min(by: {
                abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now))
            })?.index ?? 0

            let cloudTotal = hourly.cloud_cover?[safe: matchedIdx] ?? nil
            let cloudLow = hourly.cloud_cover_low?[safe: matchedIdx] ?? cloudTotal
            let cloudMid = hourly.cloud_cover_mid?[safe: matchedIdx] ?? cloudTotal
            let cloudHigh = hourly.cloud_cover_high?[safe: matchedIdx] ?? cloudTotal

            let temp = hourly.temperature_2m?[safe: matchedIdx] ?? nil
            let dew = hourly.dew_point_2m?[safe: matchedIdx] ?? nil
            let dewDepression: Double? = (temp != nil && dew != nil) ? (temp! - dew!) : nil

            let (seeingArcsec, transparencyLabel) = await astroSeeingTask

            let hourlyTuples = parsedSlots.map { (date: $0.date, cloudLow: $0.low, cloudMid: $0.mid, cloudHigh: $0.high) }

            let conditions = AstronomyService.shared.evaluateStargazingConditions(
                observer: (latitude, longitude),
                date: now,
                cloudCoverTotal: cloudTotal ?? 0,
                cloudCoverLow: cloudLow ?? 0,
                cloudCoverMid: cloudMid ?? 0,
                cloudCoverHigh: cloudHigh ?? 0,
                bortleClass: bortle,
                seeingArcseconds: seeingArcsec,
                transparencyLabel: transparencyLabel,
                dewPointDepression: dewDepression,
                hourlyForecastUTC: hourlyTuples,
                provenance: .live(fetchedAt: now)
            )

            self.stargazingConditions = conditions
            self.lastWeatherFetch = now
            self.lastWeatherCoordinate = (latitude, longitude)
        } catch {
            // Honest offline fallback: compute astronomical darkness + Bortle NELM with nil cloud % (no fake 15% clouds!)
            self.stargazingConditions = AstronomyService.shared.evaluateStargazingConditions(
                observer: (latitude, longitude),
                date: now,
                cloudCoverTotal: nil,
                cloudCoverLow: nil,
                cloudCoverMid: nil,
                cloudCoverHigh: nil,
                bortleClass: bortle,
                seeingArcseconds: nil,
                transparencyLabel: nil,
                dewPointDepression: nil,
                hourlyForecastUTC: [],
                provenance: .offlineCalculated(epochAgeHours: nil)
            )
        }
    }

    private func fetchSevenTimerSeeing(latitude: Double, longitude: Double) async -> (Double?, String?) {
        let urlStr = String(
            format: "https://www.7timer.info/bin/astro.php?lon=%.3f&lat=%.3f&ac=0&unit=metric&output=json&tzshift=0",
            longitude, latitude
        )
        guard let url = URL(string: urlStr) else { return (nil, nil) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return (nil, nil)
            }
            let decoded = try JSONDecoder().decode(SevenTimerAstroResponse.self, from: data)
            guard let first = decoded.dataseries?.first else { return (nil, nil) }

            // 7Timer ASTRO seeing index 1..8 -> arcseconds
            let seeingTable: [Int: Double] = [
                1: 0.7, 2: 0.9, 3: 1.1, 4: 1.4, 5: 1.8, 6: 2.3, 7: 3.0, 8: 3.8
            ]
            let transTable: [Int: String] = [
                1: "Exceptional (<0.3 mag)",
                2: "Crisp (0.3–0.4 mag)",
                3: "Good (0.4–0.5 mag)",
                4: "Moderate (0.5–0.6 mag)",
                5: "Slightly Hazy",
                6: "Hazy",
                7: "Poor Transparency",
                8: "Opaque"
            ]
            let sVal = first.seeing.flatMap { seeingTable[$0] }
            let tVal = first.transparency.flatMap { transTable[$0] }
            return (sVal, tVal)
        } catch {
            return (nil, nil)
        }
    }

    // MARK: - CelesTrak OMM + Native SGP4 Pass Solver

    public func fetchSatellitePasses(latitude: Double, longitude: Double, force: Bool = false) async {
        let now = Date()
        if !force,
           let last = lastSatelliteFetch,
           now.timeIntervalSince(last) < satelliteCacheDuration,
           cachedIssOmm != nil {
            if let omm = cachedIssOmm {
                self.upcomingIssPasses = SGP4Propagator.predictVisiblePasses(
                    omm: omm,
                    latitudeDegrees: latitude,
                    longitudeDegrees: longitude,
                    from: now,
                    hoursAhead: 48.0
                )
            }
            return
        }

        let urlString = "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=json"
        if let url = URL(string: urlString) {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 8.0
                let (data, response) = try await session.data(for: req)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    let records = try JSONDecoder().decode([CelesTrakOmmRecord].self, from: data)
                    if let issRecord = records.first {
                        self.cachedIssOmm = issRecord
                        self.cachedIssOmmFetchedAt = now
                        self.lastSatelliteFetch = now

                        if let encoded = try? JSONEncoder().encode(issRecord) {
                            defaults.set(encoded, forKey: ommCacheKey)
                            defaults.set(now.timeIntervalSince1970, forKey: ommFetchedAtKey)
                        }

                        self.upcomingIssPasses = SGP4Propagator.predictVisiblePasses(
                            omm: issRecord,
                            latitudeDegrees: latitude,
                            longitudeDegrees: longitude,
                            from: now,
                            hoursAhead: 48.0
                        )
                        self.satelliteProvenance = .live(fetchedAt: now)
                        return
                    }
                }
            } catch {
                // Fall through to cached OMM if within 7-day SGP4 validity window
            }
        }

        // Honest cached OMM propagation (up to 7 days) — ZERO fake sine-wave passes!
        if let cached = cachedIssOmm,
           let epoch = SGP4Propagator.parseOmmEpoch(cached.EPOCH),
           abs(now.timeIntervalSince(epoch)) <= 7.0 * 86400.0 {
            let ageHours = max(1, Int(abs(now.timeIntervalSince(cachedIssOmmFetchedAt ?? epoch)) / 3600.0))
            self.upcomingIssPasses = SGP4Propagator.predictVisiblePasses(
                omm: cached,
                latitudeDegrees: latitude,
                longitudeDegrees: longitude,
                from: now,
                hoursAhead: 48.0
            )
            self.satelliteProvenance = .offlineCalculated(epochAgeHours: ageHours)
        } else {
            self.upcomingIssPasses = []
            self.satelliteProvenance = .unavailable(reason: "Connect once to cache CelesTrak ISS orbital elements")
        }
    }

    // MARK: - NOAA SWPC Real Planetary Kp + RTSW IMF Bz + Solar Wind + OVATION Aurora

    public func fetchSpaceWeather(latitude: Double, longitude: Double = 0.0, force: Bool = false) async {
        let now = Date()
        if !force,
           let last = lastSpaceWeatherFetch,
           now.timeIntervalSince(last) < spaceWeatherCacheDuration,
           spaceWeather != nil {
            return
        }

        async let kpValTask = fetchNoaaKp()
        async let magTask = fetchNoaaRtswMag()
        async let windTask = fetchNoaaRtswWind()
        async let ovationTask = fetchNoaaOvationProbability(latitude: latitude, longitude: longitude)

        let kpVal = await kpValTask
        let (btVal, bzVal) = await magTask
        let (speedVal, densityVal) = await windTask
        let ovationVal = await ovationTask

        if kpVal != nil || bzVal != nil || speedVal != nil {
            let kp = kpVal
            let isAlert = (kp ?? 0.0) >= 5.0 || ((bzVal ?? 0.0) <= -7.0 && (speedVal ?? 0.0) >= 500.0)
            let status: String
            if let k = kp {
                if k >= 7.0 {
                    status = String(format: "Severe geomagnetic storm (Kp %.1f) — mid-latitude aurora possible!", k)
                } else if k >= 5.0 {
                    status = String(format: "Active geomagnetic storm (Kp %.1f) — high-latitude aurora favorable.", k)
                } else if let bz = bzVal, bz <= -5.0 {
                    status = String(format: "Southward IMF Bz (%.1f nT, Kp %.1f) — elevated auroral coupling.", bz, k)
                } else {
                    status = String(format: "Quiet geomagnetic field (Kp %.1f).", k)
                }
            } else {
                status = "Partial NOAA DSCOVR solar-wind telemetry active."
            }

            let report = SpaceWeatherReport(
                kpIndex: kp,
                btTotalFieldNt: btVal,
                bzMagneticFieldNt: bzVal,
                solarWindSpeedKmS: speedVal,
                solarWindDensityCm3: densityVal,
                ovationProbabilityPercent: ovationVal,
                isAuroraAlertActive: isAlert,
                statusMessage: status,
                provenance: .live(fetchedAt: now)
            )
            self.spaceWeather = report
            self.lastSpaceWeatherFetch = now
            if let encoded = try? JSONEncoder().encode(report) {
                defaults.set(encoded, forKey: spaceWeatherCacheKey)
            }
            return
        }

        // Honest cached or unavailable state — ZERO fabricated Kp 2.3 / Bz -2.5!
        if let existing = self.spaceWeather, case .live(let fetchedAt) = existing.provenance {
            let ageMin = max(1, Int(now.timeIntervalSince(fetchedAt) / 60.0))
            self.spaceWeather = SpaceWeatherReport(
                kpIndex: existing.kpIndex,
                btTotalFieldNt: existing.btTotalFieldNt,
                bzMagneticFieldNt: existing.bzMagneticFieldNt,
                solarWindSpeedKmS: existing.solarWindSpeedKmS,
                solarWindDensityCm3: existing.solarWindDensityCm3,
                ovationProbabilityPercent: existing.ovationProbabilityPercent,
                isAuroraAlertActive: existing.isAuroraAlertActive,
                statusMessage: existing.statusMessage,
                provenance: .cached(fetchedAt: fetchedAt, ageMinutes: ageMin)
            )
        } else if self.spaceWeather == nil {
            self.spaceWeather = SpaceWeatherReport(
                kpIndex: nil,
                btTotalFieldNt: nil,
                bzMagneticFieldNt: nil,
                solarWindSpeedKmS: nil,
                solarWindDensityCm3: nil,
                ovationProbabilityPercent: nil,
                isAuroraAlertActive: false,
                statusMessage: "Live NOAA space weather unavailable offline.",
                provenance: .unavailable(reason: "Offline")
            )
        }
    }

    private func fetchNoaaKp() async -> Double? {
        guard let url = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json") else { return nil }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 7.0
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let jsonObj = try JSONSerialization.jsonObject(with: data)
            if let dicts = jsonObj as? [[String: Any]] {
                for dict in dicts.reversed() {
                    if let raw = dict["Kp"] ?? dict["kp_index"] ?? dict["kp"] {
                        if let d = raw as? Double, d.isFinite { return d }
                        if let n = raw as? NSNumber { return n.doubleValue }
                        if let v = Double("\(raw)"), v.isFinite { return v }
                    }
                }
            } else if let rows = jsonObj as? [[Any]], rows.count > 1 {
                for row in rows.reversed() {
                    if row.count > 1, let v = Double("\(row[1])"), v.isFinite {
                        return v
                    }
                }
            }
        } catch {}
        return nil
    }

    private func fetchNoaaRtswMag() async -> (Double?, Double?) {
        guard let url = URL(string: "https://services.swpc.noaa.gov/json/rtsw/rtsw_mag_1m.json") else { return (nil, nil) }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 7.0
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return (nil, nil) }
            for item in items.reversed() {
                let bt = (item["bt"] as? NSNumber)?.doubleValue ?? (item["bt"] as? String).flatMap(Double.init)
                let bz = (item["bz_gsm"] as? NSNumber)?.doubleValue ?? (item["bz_gsm"] as? String).flatMap(Double.init)
                if bt != nil || bz != nil {
                    return (bt, bz)
                }
            }
        } catch {}
        return (nil, nil)
    }

    private func fetchNoaaRtswWind() async -> (Double?, Double?) {
        guard let url = URL(string: "https://services.swpc.noaa.gov/json/rtsw/rtsw_wind_1m.json") else { return (nil, nil) }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 7.0
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return (nil, nil) }
            for item in items.reversed() {
                let speed = (item["proton_speed"] as? NSNumber)?.doubleValue ?? (item["proton_speed"] as? String).flatMap(Double.init)
                let density = (item["proton_density"] as? NSNumber)?.doubleValue ?? (item["proton_density"] as? String).flatMap(Double.init)
                if let s = speed, s > 0 {
                    return (s, density)
                }
            }
        } catch {}
        return (nil, nil)
    }

    private func fetchNoaaOvationProbability(latitude: Double, longitude: Double) async -> Int? {
        guard let url = URL(string: "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json") else { return nil }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 7.0
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let coords = root["coordinates"] as? [[Any]] else { return nil }
            let targetLon = Int(round(((longitude.truncatingRemainder(dividingBy: 360.0)) + 360.0).truncatingRemainder(dividingBy: 360.0))) % 360
            let targetLat = max(-90, min(90, Int(round(latitude))))
            var bestProb: Int? = nil
            var bestDist = Int.max
            for entry in coords where entry.count >= 3 {
                let lon = (entry[0] as? Int) ?? Int((entry[0] as? Double) ?? -999)
                let lat = (entry[1] as? Int) ?? Int((entry[1] as? Double) ?? -999)
                let prob = (entry[2] as? Int) ?? Int((entry[2] as? Double) ?? 0)
                let d = abs(lon - targetLon) + abs(lat - targetLat)
                if d < bestDist {
                    bestDist = d
                    bestProb = max(0, min(100, prob))
                    if d == 0 { break }
                }
            }
            return bestProb
        } catch {}
        return nil
    }

    // MARK: - NASA APOD (Configured API Key + Persistent Cache)

    public func fetchApod(force: Bool = false) async {
        let now = Date()
        if !force, let existing = apodPicture, case .live = apodProvenance {
            let todayUTC: String = {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "yyyy-MM-dd"
                return df.string(from: now)
            }()
            if existing.date == todayUTC { return }
        }

        let customKey = SettingsService.shared.settings.nasaApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (customKey?.isEmpty == false) ? customKey! : "DEMO_KEY"
        guard let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.nasa.gov/planetary/apod?api_key=\(encodedKey)") else {
            return
        }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8.0
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let apod = try JSONDecoder().decode(ApodResponse.self, from: data)
            self.apodPicture = apod
            self.apodProvenance = .live(fetchedAt: now)
            if let encoded = try? JSONEncoder().encode(apod) {
                defaults.set(encoded, forKey: apodCacheKey)
                defaults.set(now.timeIntervalSince1970, forKey: apodFetchedAtKey)
            }
        } catch {
            if apodPicture != nil, let ts = defaults.object(forKey: apodFetchedAtKey) as? Double {
                let fetchedDate = Date(timeIntervalSince1970: ts)
                let ageMin = max(1, Int(now.timeIntervalSince(fetchedDate) / 60.0))
                self.apodProvenance = .cached(fetchedAt: fetchedDate, ageMinutes: ageMin)
            } else {
                self.apodProvenance = .unavailable(reason: "Add a free NASA API key in Settings if DEMO_KEY is rate-limited")
            }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
