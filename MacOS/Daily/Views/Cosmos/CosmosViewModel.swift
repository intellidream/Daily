import SwiftUI
import Combine
import DailyCore

// MARK: - Selectable Target Model

public struct CosmosTarget: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let category: String
    public let iconName: String
    public let azimuth: Double
    public let altitude: Double
    public let rightAscensionHours: Double
    public let declinationDegrees: Double
    public let visualMagnitude: Double?
    public let distanceDescription: String?
    public let constellationName: String?
    public let lore: String
    public let recommendedOptics: String?
    public let accentColorHex: String

    public init(
        id: String,
        name: String,
        subtitle: String,
        category: String,
        iconName: String,
        azimuth: Double,
        altitude: Double,
        rightAscensionHours: Double,
        declinationDegrees: Double,
        visualMagnitude: Double? = nil,
        distanceDescription: String? = nil,
        constellationName: String? = nil,
        lore: String,
        recommendedOptics: String? = nil,
        accentColorHex: String = "#00E5FF"
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.category = category
        self.iconName = iconName
        self.azimuth = azimuth
        self.altitude = altitude
        self.rightAscensionHours = rightAscensionHours
        self.declinationDegrees = declinationDegrees
        self.visualMagnitude = visualMagnitude
        self.distanceDescription = distanceDescription
        self.constellationName = constellationName
        self.lore = lore
        self.recommendedOptics = recommendedOptics
        self.accentColorHex = accentColorHex
    }
}

// MARK: - Projected Visual Element Structs

public struct ProjectedStar: Identifiable {
    public var id: String { star.name }
    public let star: BrightStarRecord
    public let screenX: Double
    public let screenY: Double
    public let altitude: Double
    public let azimuth: Double
    public let diameter: Double
    public let color: Color
}

public struct ProjectedPlanet: Identifiable {
    public var id: String { body.rawValue }
    public let body: CelestialBody
    public let screenX: Double
    public let screenY: Double
    public let altitude: Double
    public let azimuth: Double
    public let coordinates: CelestialCoordinates
    public let diameter: Double
    public let isSunOrMoon: Bool
}

public struct ProjectedDSO: Identifiable {
    public var id: String { dso.id }
    public let dso: DeepSkyObject
    public let screenX: Double
    public let screenY: Double
    public let altitude: Double
    public let azimuth: Double
}

public struct ProjectedConstellationLine: Identifiable {
    public let id: String
    public let startX: Double
    public let startY: Double
    public let endX: Double
    public let endY: Double
}

public struct ProjectedConstellationLabel: Identifiable {
    public var id: String { record.id }
    public let record: ConstellationRecord
    public let screenX: Double
    public let screenY: Double
}

// MARK: - Central Cosmos View Model

@MainActor
public final class CosmosViewModel: ObservableObject {
    public static let shared = CosmosViewModel()

    // MARK: - Dependencies
    private let astronomyService = AstronomyService.shared
    private let catalogService = CosmosCatalogService.shared
    private let liveService = CosmosLiveService.shared
    private let motionService = CosmosMotionService.shared
    private let weatherService = WeatherService.shared

    private var cancellables = Set<AnyCancellable>()
    private var liveTimer: AnyCancellable?

    // MARK: - Camera & Viewport State
    @Published public var cameraAzimuth: Double = 180.0 // Facing South by default
    @Published public var cameraAltitude: Double = 45.0 // Elevated stargazing view
    @Published public var cameraRoll: Double = 0.0
    @Published public var fov: Double = 65.0 // Field of view in degrees (25° - 100°)

    // MARK: - Time Travel State
    @Published public var simulationDate: Date = Date()
    @Published public var isLiveTime: Bool = true

    // MARK: - Display Toggles
    @Published public var isNightVisionMode: Bool = false // Red mode #FF1824
    @Published public var isMotionTrackingEnabled: Bool = false
    @Published public var showConstellationLines: Bool = true
    @Published public var showConstellationLabels: Bool = true
    @Published public var showPlanets: Bool = true
    @Published public var showDeepSkyObjects: Bool = true
    @Published public var showHorizonCompass: Bool = true

    // MARK: - Selection & Search
    @Published public var selectedTarget: CosmosTarget? = nil
    @Published public var searchQuery: String = ""
    @Published public var isSearching: Bool = false

    // MARK: - Observer Geolocation
    public var observerLatitude: Double {
        weatherService.currentWeather?.coord?.lat ?? 44.4268
    }

    public var observerLongitude: Double {
        weatherService.currentWeather?.coord?.lon ?? 26.1025
    }

    public var observerLocationName: String {
        weatherService.currentLocationName.isEmpty ? "Bucharest" : weatherService.currentLocationName
    }

    // MARK: - Ephemeris & Live State
    @Published public private(set) var currentMoonPhase: MoonPhaseInfo
    @Published public private(set) var stargazingScore: Int = 85
    @Published public private(set) var stargazingVerdict: String = "Pristine Conditions"
    @Published public private(set) var visiblePlanetsCount: Int = 0
    @Published public private(set) var nextIssPass: SatellitePass? = nil

    public init() {
        self.currentMoonPhase = astronomyService.moonPhase(at: Date())
        setupSubscriptions()
        startLiveClock()
        recomputeEphemeris()
    }

    // MARK: - Subscriptions
    private func setupSubscriptions() {
        // Sync with gyro motion tracker
        motionService.$currentAzimuth
            .sink { [weak self] az in
                guard let self = self, self.isMotionTrackingEnabled else { return }
                self.cameraAzimuth = az
            }
            .store(in: &cancellables)

        motionService.$currentAltitude
            .sink { [weak self] alt in
                guard let self = self, self.isMotionTrackingEnabled else { return }
                self.cameraAltitude = alt
            }
            .store(in: &cancellables)

        motionService.$currentRoll
            .sink { [weak self] roll in
                guard let self = self, self.isMotionTrackingEnabled else { return }
                self.cameraRoll = roll
            }
            .store(in: &cancellables)

        // Observe live service updates
        liveService.$stargazingConditions
            .sink { [weak self] _ in
                self?.recomputeEphemeris()
            }
            .store(in: &cancellables)

        liveService.$upcomingIssPasses
            .sink { [weak self] passes in
                self?.nextIssPass = passes.first
            }
            .store(in: &cancellables)
    }

    // MARK: - Time Machine
    public func startLiveClock() {
        liveTimer?.cancel()
        liveTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self = self, self.isLiveTime else { return }
                self.simulationDate = date
                self.recomputeEphemeris()
            }
    }

    public func adjustSimulationTime(byHours hours: Double) {
        isLiveTime = false
        simulationDate = simulationDate.addingTimeInterval(hours * 3600.0)
        recomputeEphemeris()
    }

    public func setSimulationDate(_ date: Date) {
        isLiveTime = false
        simulationDate = date
        recomputeEphemeris()
    }

    public func resetToLive() {
        isLiveTime = true
        simulationDate = Date()
        recomputeEphemeris()
    }

    public func toggleMotionTracking() {
        isMotionTrackingEnabled.toggle()
        if isMotionTrackingEnabled {
            motionService.startTracking()
        } else {
            motionService.stopTracking()
        }
    }

    // MARK: - Gesture Handling
    public func handlePan(deltaX: Double, deltaY: Double, viewportWidth: Double, viewportHeight: Double) {
        guard !isMotionTrackingEnabled else { return }

        // Scale pan sensitivity with current FOV
        let factor = (fov / 65.0) * 0.22

        // Dragging left moves view east (increasing azimuth), dragging right moves west
        var newAzimuth = cameraAzimuth - (deltaX * factor)
        if newAzimuth < 0 { newAzimuth += 360.0 }
        if newAzimuth >= 360.0 { newAzimuth -= 360.0 }
        cameraAzimuth = newAzimuth

        // Dragging down moves view up (increasing altitude)
        let newAltitude = max(-10.0, min(90.0, cameraAltitude + (deltaY * factor)))
        cameraAltitude = newAltitude
    }

    public func handleZoom(deltaMagnification: Double) {
        let newFov = fov / (1.0 + (deltaMagnification - 1.0) * 0.8)
        fov = max(20.0, min(100.0, newFov))
    }

    public func centerOn(target: CosmosTarget) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            self.cameraAzimuth = target.azimuth
            self.cameraAltitude = max(5.0, min(88.0, target.altitude))
            self.selectedTarget = target
        }
    }

    // MARK: - Ephemeris & Stargazing Scoring
    public func recomputeEphemeris() {
        self.currentMoonPhase = astronomyService.moonPhase(at: simulationDate)

        let cloudTotal = liveService.stargazingConditions?.cloudCoverTotalPercent ?? 10
        let cloudLow = liveService.stargazingConditions?.cloudCoverLowPercent ?? 5
        let cloudMid = liveService.stargazingConditions?.cloudCoverMidPercent ?? 5
        let cloudHigh = liveService.stargazingConditions?.cloudCoverHighPercent ?? 5

        let conds = astronomyService.evaluateStargazingConditions(
            observer: (latitude: observerLatitude, longitude: observerLongitude),
            date: simulationDate,
            cloudCoverTotal: cloudTotal,
            cloudCoverLow: cloudLow,
            cloudCoverMid: cloudMid,
            cloudCoverHigh: cloudHigh,
            bortleClass: liveService.stargazingConditions?.bortleClass ?? 5,
            seeingArcseconds: liveService.stargazingConditions?.seeingArcseconds,
            dewPointDepression: liveService.stargazingConditions?.dewPointDepressionCelsius
        )

        self.stargazingScore = conds.score
        self.stargazingVerdict = conds.quality.displayName

        // Count visible planets above horizon
        var count = 0
        let planetList: [CelestialBody] = [.venus, .mars, .jupiter, .saturn, .mercury]
        let obs = (latitude: observerLatitude, longitude: observerLongitude, elevation: 50.0)
        for p in planetList {
            let coords = astronomyService.coordinates(of: p, for: obs, at: simulationDate)
            if coords.altitudeDegrees > 0 {
                count += 1
            }
        }
        self.visiblePlanetsCount = count
    }

    // MARK: - Sky Projection Rendering
    public func projectElements(in size: CGSize) -> (
        stars: [ProjectedStar],
        planets: [ProjectedPlanet],
        dsos: [ProjectedDSO],
        lines: [ProjectedConstellationLine],
        labels: [ProjectedConstellationLabel]
    ) {
        let obsLat = observerLatitude
        let obsLon = observerLongitude
        let date = simulationDate
        let az = cameraAzimuth
        let alt = cameraAltitude
        let roll = cameraRoll
        let currentFov = fov
        let vw = Double(size.width)
        let vh = Double(size.height)

        guard vw > 0, vh > 0 else {
            return ([], [], [], [], [])
        }

        // 1. Project Stars
        var projectedStars: [ProjectedStar] = []
        var starScreenPositions: [String: (x: Double, y: Double)] = [:]

        for star in catalogService.brightStars {
            if let proj = astronomyService.projectStereographic(
                raHours: star.raHours,
                decDegrees: star.decDegrees,
                observerLatitudeDegrees: obsLat,
                observerLongitudeDegrees: obsLon,
                date: date,
                cameraAzimuthDegrees: az,
                cameraAltitudeDegrees: alt,
                cameraRollDegrees: roll,
                fovDegrees: currentFov,
                viewportWidth: vw,
                viewportHeight: vh
            ) {
                // Calculate size based on visual magnitude (brighter = larger)
                let clampedMag = max(-1.5, min(4.5, star.magnitude))
                let diameter = max(2.5, (4.5 - clampedMag) * 1.8)
                let starColor = isNightVisionMode ? Color(hex: "#FF1824") : Color(hex: star.colorHex)

                let pStar = ProjectedStar(
                    star: star,
                    screenX: proj.x,
                    screenY: proj.y,
                    altitude: 0,
                    azimuth: 0,
                    diameter: diameter,
                    color: starColor
                )
                projectedStars.append(pStar)
                starScreenPositions[star.name] = (proj.x, proj.y)
            }
        }

        // 2. Project Constellation Lines
        var projectedLines: [ProjectedConstellationLine] = []
        if showConstellationLines {
            for const in catalogService.constellations {
                let stars = const.stars
                guard stars.count >= 2 else { continue }
                for i in 0..<(stars.count - 1) {
                    let s1 = stars[i]
                    let s2 = stars[i + 1]
                    if let pos1 = starScreenPositions[s1], let pos2 = starScreenPositions[s2] {
                        let line = ProjectedConstellationLine(
                            id: "\(const.id)_\(i)",
                            startX: pos1.x,
                            startY: pos1.y,
                            endX: pos2.x,
                            endY: pos2.y
                        )
                        projectedLines.append(line)
                    }
                }
            }
        }

        // 3. Project Constellation Labels
        var projectedLabels: [ProjectedConstellationLabel] = []
        if showConstellationLabels {
            for const in catalogService.constellations {
                if let proj = astronomyService.projectStereographic(
                    raHours: const.centerRa,
                    decDegrees: const.centerDec,
                    observerLatitudeDegrees: obsLat,
                    observerLongitudeDegrees: obsLon,
                    date: date,
                    cameraAzimuthDegrees: az,
                    cameraAltitudeDegrees: alt,
                    cameraRollDegrees: roll,
                    fovDegrees: currentFov,
                    viewportWidth: vw,
                    viewportHeight: vh
                ), proj.isVisible {
                    projectedLabels.append(ProjectedConstellationLabel(record: const, screenX: proj.x, screenY: proj.y))
                }
            }
        }

        // 4. Project Planets & Major Celestial Bodies
        var projectedPlanets: [ProjectedPlanet] = []
        if showPlanets {
            let obs = (latitude: obsLat, longitude: obsLon, elevation: 50.0)
            let majorBodies: [CelestialBody] = [.moon, .sun, .jupiter, .saturn, .mars, .venus, .mercury]

            for body in majorBodies {
                let coords = astronomyService.coordinates(of: body, for: obs, at: date)
                if let proj = astronomyService.projectStereographic(
                    raHours: coords.rightAscensionHours,
                    decDegrees: coords.declinationDegrees,
                    observerLatitudeDegrees: obsLat,
                    observerLongitudeDegrees: obsLon,
                    date: date,
                    cameraAzimuthDegrees: az,
                    cameraAltitudeDegrees: alt,
                    cameraRollDegrees: roll,
                    fovDegrees: currentFov,
                    viewportWidth: vw,
                    viewportHeight: vh
                ) {
                    let diameter: Double
                    switch body {
                    case .sun, .moon: diameter = 28.0
                    case .jupiter: diameter = 14.0
                    case .saturn: diameter = 12.0
                    case .venus: diameter = 11.0
                    case .mars: diameter = 10.0
                    default: diameter = 8.0
                    }

                    let pPlanet = ProjectedPlanet(
                        body: body,
                        screenX: proj.x,
                        screenY: proj.y,
                        altitude: coords.altitudeDegrees,
                        azimuth: coords.azimuthDegrees,
                        coordinates: coords,
                        diameter: diameter,
                        isSunOrMoon: body == .sun || body == .moon
                    )
                    projectedPlanets.append(pPlanet)
                }
            }
        }

        // 5. Project Messier DSOs
        var projectedDSOs: [ProjectedDSO] = []
        if showDeepSkyObjects {
            for dso in catalogService.messierObjects {
                if let proj = astronomyService.projectStereographic(
                    raHours: dso.rightAscensionHours,
                    decDegrees: dso.declinationDegrees,
                    observerLatitudeDegrees: obsLat,
                    observerLongitudeDegrees: obsLon,
                    date: date,
                    cameraAzimuthDegrees: az,
                    cameraAltitudeDegrees: alt,
                    cameraRollDegrees: roll,
                    fovDegrees: currentFov,
                    viewportWidth: vw,
                    viewportHeight: vh
                ) {
                    projectedDSOs.append(ProjectedDSO(dso: dso, screenX: proj.x, screenY: proj.y, altitude: 0, azimuth: 0))
                }
            }
        }

        return (projectedStars, projectedPlanets, projectedDSOs, projectedLines, projectedLabels)
    }

    public func projectHorizon(in size: CGSize) -> (
        horizonPoints: [CGPoint],
        cardinals: [(label: String, x: Double, y: Double, isPrimary: Bool)],
        zenith: (x: Double, y: Double)?
    ) {
        let vw = Double(size.width)
        let vh = Double(size.height)
        guard vw > 0, vh > 0 else { return ([], [], nil) }

        var hPoints: [CGPoint] = []
        for step in 0..<72 {
            let azDeg = Double(step * 5)
            if let p = astronomyService.projectHorizontal(
                azimuthDegrees: azDeg,
                altitudeDegrees: 0.0,
                cameraAzimuthDegrees: cameraAzimuth,
                cameraAltitudeDegrees: cameraAltitude,
                cameraRollDegrees: cameraRoll,
                fovDegrees: fov,
                viewportWidth: vw,
                viewportHeight: vh
            ) {
                hPoints.append(CGPoint(x: p.x, y: p.y))
            }
        }

        let cardinalList: [(String, Double, Bool)] = [
            ("N", 0.0, true), ("NE", 45.0, false),
            ("E", 90.0, true), ("SE", 135.0, false),
            ("S", 180.0, true), ("SW", 225.0, false),
            ("W", 270.0, true), ("NW", 315.0, false)
        ]

        var cards: [(label: String, x: Double, y: Double, isPrimary: Bool)] = []
        for (lbl, azDeg, isPri) in cardinalList {
            if let p = astronomyService.projectHorizontal(
                azimuthDegrees: azDeg,
                altitudeDegrees: 0.0,
                cameraAzimuthDegrees: cameraAzimuth,
                cameraAltitudeDegrees: cameraAltitude,
                cameraRollDegrees: cameraRoll,
                fovDegrees: fov,
                viewportWidth: vw,
                viewportHeight: vh
            ) {
                cards.append((lbl, p.x, p.y, isPri))
            }
        }

        var zenithPt: (Double, Double)? = nil
        if let zp = astronomyService.projectHorizontal(
            azimuthDegrees: cameraAzimuth,
            altitudeDegrees: 90.0,
            cameraAzimuthDegrees: cameraAzimuth,
            cameraAltitudeDegrees: cameraAltitude,
            cameraRollDegrees: cameraRoll,
            fovDegrees: fov,
            viewportWidth: vw,
            viewportHeight: vh
        ) {
            zenithPt = (zp.x, zp.y)
        }

        return (hPoints, cards, zenithPt)
    }

    // MARK: - Search Catalog
    public var searchResults: [CosmosTarget] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let query = searchQuery.lowercased()
        var results: [CosmosTarget] = []
        let obs = (latitude: observerLatitude, longitude: observerLongitude, elevation: 50.0)

        // 1. Match Planets
        let bodies: [(CelestialBody, String, String)] = [
            (.moon, "Moon", "Earth's sole natural satellite"),
            (.jupiter, "Jupiter", "The gas giant with 4 Galilean moons"),
            (.saturn, "Saturn", "The jewel of the solar system with iconic rings"),
            (.mars, "Mars", "The Red Planet with towering volcanoes and polar ice caps"),
            (.venus, "Venus", "The brilliant morning and evening star"),
            (.mercury, "Mercury", "The innermost planet closest to the Sun")
        ]

        for (body, name, lore) in bodies {
            if name.lowercased().contains(query) || body.rawValue.lowercased().contains(query) {
                let coords = astronomyService.coordinates(of: body, for: obs, at: simulationDate)
                results.append(
                    CosmosTarget(
                        id: "body_\(body.rawValue)",
                        name: name,
                        subtitle: "\(body.rawValue.capitalized) · Mag \(String(format: "%.1f", coords.visualMagnitude))",
                        category: "Planets & Moons",
                        iconName: body == .moon ? "moon.fill" : "circle.fill",
                        azimuth: coords.azimuthDegrees,
                        altitude: coords.altitudeDegrees,
                        rightAscensionHours: coords.rightAscensionHours,
                        declinationDegrees: coords.declinationDegrees,
                        visualMagnitude: coords.visualMagnitude,
                        distanceDescription: "\(String(format: "%.2f", coords.distanceAU)) AU",
                        lore: lore,
                        recommendedOptics: body == .jupiter || body == .saturn ? "Telescope / Binoculars" : "Naked Eye"
                    )
                )
            }
        }

        // 2. Match Stars
        for star in catalogService.brightStars {
            if star.name.lowercased().contains(query) || star.constellation.lowercased().contains(query) {
                results.append(
                    CosmosTarget(
                        id: "star_\(star.name)",
                        name: star.name,
                        subtitle: "Star in \(star.constellation) · Mag \(String(format: "%.2f", star.magnitude))",
                        category: "Bright Stars",
                        iconName: "sparkle",
                        azimuth: 0,
                        altitude: 0,
                        rightAscensionHours: star.raHours,
                        declinationDegrees: star.decDegrees,
                        visualMagnitude: star.magnitude,
                        constellationName: star.constellation,
                        lore: "Star with spectral color index B-V \(star.colorIndexBV), cataloged in standard astronomical surveys.",
                        accentColorHex: star.colorHex
                    )
                )
            }
        }

        // 3. Match DSOs
        for dso in catalogService.messierObjects {
            if dso.name.lowercased().contains(query) || dso.id.lowercased().contains(query) || dso.constellationCode.lowercased().contains(query) {
                results.append(
                    CosmosTarget(
                        id: "dso_\(dso.id)",
                        name: "\(dso.id) - \(dso.name)",
                        subtitle: "\(dso.type.displayName) · \(dso.constellationCode)",
                        category: "Deep Sky Objects (Messier)",
                        iconName: "camera.macro",
                        azimuth: 0,
                        altitude: 0,
                        rightAscensionHours: dso.rightAscensionHours,
                        declinationDegrees: dso.declinationDegrees,
                        visualMagnitude: dso.visualMagnitude,
                        constellationName: dso.constellationCode,
                        lore: dso.descriptionRo,
                        recommendedOptics: dso.recommendedOptics
                    )
                )
            }
        }

        return results
    }

    public func target(for body: CelestialBody) -> CosmosTarget {
        let obs = (latitude: observerLatitude, longitude: observerLongitude, elevation: 50.0)
        let coords = astronomyService.coordinates(of: body, for: obs, at: simulationDate)
        let name: String
        let lore: String
        switch body {
        case .sun:
            name = "Sun"
            lore = "The central star of the Solar System, powering light and life on Earth."
        case .moon:
            name = "Moon"
            lore = "Earth's natural satellite, in \(currentMoonPhase.quarter.displayName) phase, illuminated \(currentMoonPhase.illuminationPercent)%."
        case .mercury:
            name = "Mercury"
            lore = "The smallest planet in the solar system, enduring extreme temperature swings."
        case .venus:
            name = "Venus"
            lore = "The brightest planet in the night sky, shrouded in a dense carbon dioxide atmosphere."
        case .mars:
            name = "Mars"
            lore = "The Red Planet featuring ancient riverbeds and the towering Olympus Mons volcano."
        case .jupiter:
            name = "Jupiter"
            lore = "The massive gas giant featuring the Great Red Spot and four large Galilean moons."
        case .saturn:
            name = "Saturn"
            lore = "Famous for its magnificent ice ring system and its massive moon Titan."
        case .uranus:
            name = "Uranus"
            lore = "Ice giant tilted dramatically on its side with a 98-degree axial tilt."
        case .neptune:
            name = "Neptune"
            lore = "The most distant major planet, driven by supersonic winds exceeding 2,000 km/h."
        case .pluto:
            name = "Pluto"
            lore = "Dwarf planet in the Kuiper Belt featuring a nitrogen-ice heart (Tombaugh Regio)."
        }

        return CosmosTarget(
            id: "body_\(body.rawValue)",
            name: name,
            subtitle: "\(body.rawValue.capitalized) · Mag \(String(format: "%.1f", coords.visualMagnitude))",
            category: "Planets & Moons",
            iconName: body == .moon ? "moon.fill" : "circle.fill",
            azimuth: coords.azimuthDegrees,
            altitude: coords.altitudeDegrees,
            rightAscensionHours: coords.rightAscensionHours,
            declinationDegrees: coords.declinationDegrees,
            visualMagnitude: coords.visualMagnitude,
            distanceDescription: "\(String(format: "%.2f", coords.distanceAU)) AU",
            lore: lore,
            recommendedOptics: body == .jupiter || body == .saturn ? "Telescope / Binoculars" : "Naked Eye"
        )
    }

    public func target(for star: BrightStarRecord) -> CosmosTarget {
        return CosmosTarget(
            id: "star_\(star.name)",
            name: star.name,
            subtitle: "Star in \(star.constellation) · Mag \(String(format: "%.2f", star.magnitude))",
            category: "Bright Stars",
            iconName: "sparkle",
            azimuth: 0,
            altitude: 0,
            rightAscensionHours: star.raHours,
            declinationDegrees: star.decDegrees,
            visualMagnitude: star.magnitude,
            constellationName: star.constellation,
            lore: "Star with spectral color index B-V \(star.colorIndexBV), cataloged in standard astronomical surveys.",
            accentColorHex: star.colorHex
        )
    }

    public func target(for dso: DeepSkyObject) -> CosmosTarget {
        return CosmosTarget(
            id: "dso_\(dso.id)",
            name: "\(dso.id) - \(dso.name)",
            subtitle: "\(dso.type.displayName) · \(dso.constellationCode)",
            category: "Deep Sky Objects (Messier)",
            iconName: "camera.macro",
            azimuth: 0,
            altitude: 0,
            rightAscensionHours: dso.rightAscensionHours,
            declinationDegrees: dso.declinationDegrees,
            visualMagnitude: dso.visualMagnitude,
            constellationName: dso.constellationCode,
            lore: dso.descriptionRo,
            recommendedOptics: dso.recommendedOptics
        )
    }
}
