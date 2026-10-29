import SwiftUI
import Observation
import Combine
import DailyCore
#if canImport(EventKit)
import EventKit
#endif

// MARK: - Strict Astronomical Red Night-Vision & Cosmos Palette

public struct CosmosPalette {
    public let isNightVision: Bool

    public init(isNightVision: Bool) {
        self.isNightVision = isNightVision
    }

    public var primaryRed: Color { Color(hex: "#FF1824") }
    public var softRed: Color { Color(hex: "#FF5258") }
    public var mutedRed: Color { Color(hex: "#A81018") }
    public var deepRedSurface: Color { Color(hex: "#190204") }
    public var deepRedBorder: Color { Color(hex: "#FF1824").opacity(0.32) }

    public var fgPrimary: Color { isNightVision ? primaryRed : .white }
    public var fgSecondary: Color { isNightVision ? softRed.opacity(0.86) : Color.white.opacity(0.82) }
    public var fgMuted: Color { isNightVision ? mutedRed : ThemeColors.fgMutedDark }
    public var accent: Color { isNightVision ? primaryRed : ThemeColors.accentCyan }
    public var accentSecondary: Color { isNightVision ? softRed : ThemeColors.accentPink }
    public var positive: Color { isNightVision ? primaryRed : ThemeColors.accentGreen }
    public var warning: Color { isNightVision ? softRed : ThemeColors.accentOrange }
    public var cardBackground: Color { isNightVision ? deepRedSurface.opacity(0.92) : Color.black.opacity(0.58) }
    public var pillBackground: Color { isNightVision ? Color(hex: "#2B0307").opacity(0.88) : Color.white.opacity(0.08) }
    public var border: Color { isNightVision ? deepRedBorder : Color.white.opacity(0.14) }
    public var sheetBackgroundTop: Color { isNightVision ? Color(hex: "#140103") : Color(hex: "#080E21") }
    public var sheetBackgroundBottom: Color { isNightVision ? Color.black : Color(hex: "#02040A") }
}

// MARK: - Isolated 120Hz Camera Controller (@Observable — Zero HUD Re-evaluation)

@Observable
@MainActor
public final class CosmosCameraController {
    public var azimuth: Double = 180.0
    public var altitude: Double = 38.0
    public var roll: Double = 0.0
    public var fov: Double = 60.0 // 0.5° (High-Power Telescope) ... 120.0° (Wide Dome)
    public var isZenithPlanisphereLocked: Bool = false
    public var hoverLocation: CGPoint? = nil

    public init() {}

    public var effectiveAzimuth: Double {
        azimuth
    }

    public var effectiveAltitude: Double {
        isZenithPlanisphereLocked ? 89.9 : altitude
    }

    public var effectiveRoll: Double {
        isZenithPlanisphereLocked ? 0.0 : roll
    }
}

// MARK: - Zoom Presets

public enum CosmosZoomPreset: String, CaseIterable, Identifiable, Sendable {
    case wide = "120° Wide"
    case nakedEye = "60° Eye"
    case binoculars = "8° 7×50"
    case telescope = "2° Scope"

    public var id: String { rawValue }

    public var fovDegrees: Double {
        switch self {
        case .wide: return 120.0
        case .nakedEye: return 60.0
        case .binoculars: return 8.0
        case .telescope: return 2.0
        }
    }

    public var iconName: String {
        switch self {
        case .wide: return "pano.fill"
        case .nakedEye: return "eye"
        case .binoculars: return "binoculars.fill"
        case .telescope: return "scope"
        }
    }
}

// MARK: - Selectable Target & Live Metrics

public enum CosmosTargetKind: Equatable, Sendable {
    case body(CelestialBody)
    case star(hip: Int)
    case dso(id: String)
    case constellation(id: String)
    case asterism(id: String)
    case meteorShower(id: String)
    case iss
}

public struct CosmosTarget: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: CosmosTargetKind
    public let name: String
    public let subtitle: String
    public let category: String
    public let iconName: String
    public let rightAscensionHours: Double
    public let declinationDegrees: Double
    public let visualMagnitude: Double?
    public let distanceDescription: String?
    public let constellationName: String?
    public let lore: String
    public let recommendedOptics: String?
    public let accentColorHex: String
    public let thumbnailRelativePath: String?

    public init(
        id: String,
        kind: CosmosTargetKind,
        name: String,
        subtitle: String,
        category: String,
        iconName: String,
        rightAscensionHours: Double,
        declinationDegrees: Double,
        visualMagnitude: Double? = nil,
        distanceDescription: String? = nil,
        constellationName: String? = nil,
        lore: String,
        recommendedOptics: String? = nil,
        accentColorHex: String = "#00E5FF",
        thumbnailRelativePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.category = category
        self.iconName = iconName
        self.rightAscensionHours = rightAscensionHours
        self.declinationDegrees = declinationDegrees
        self.visualMagnitude = visualMagnitude
        self.distanceDescription = distanceDescription
        self.constellationName = constellationName
        self.lore = lore
        self.recommendedOptics = recommendedOptics
        self.accentColorHex = accentColorHex
        self.thumbnailRelativePath = thumbnailRelativePath
    }
}

public struct CosmosTargetLiveMetrics: Sendable {
    public let azimuthDegrees: Double
    public let altitudeDegrees: Double
    public let compassDirection: String
    public let rightAscensionHours: Double
    public let declinationDegrees: Double
    public let riseTime: Date?
    public let transitTime: Date?
    public let setTime: Date?
    public let distanceLabel: String?
    public let phaseOrDetailLabel: String?
    public let isAboveHorizon: Bool
}

// MARK: - Projected Scene Value Types (Fast Canvas Pass)

public struct ProjectedPackedStar {
    public let hip: Int
    public let x: Double
    public let y: Double
    public let diameter: Double
    public let r: Double
    public let g: Double
    public let b: Double
    public let alpha: Double
    public let magnitude: Float
    public let label: String?
}

public struct ProjectedSegment {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double
}

public struct ProjectedConstellationLabel: Identifiable {
    public var id: String { record.id }
    public let record: ConstellationRecord
    public let screenX: Double
    public let screenY: Double
}

public struct ProjectedGalileanMoon {
    public let name: String
    public let x: Double
    public let y: Double
    public let isFrontOfPlanet: Bool
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
    public let brightLimbAngleDeg: Double
    public let saturnRingTiltDeg: Double
    public let galileanMoons: [ProjectedGalileanMoon]
}

public struct ProjectedDSO: Identifiable {
    public var id: String { dso.id }
    public let dso: DeepSkyObject
    public let screenX: Double
    public let screenY: Double
    public let radiusPx: Double
    public let aspectRatio: Double
    public let positionAngleDeg: Double
}

public struct ProjectedMeteorRadiant: Identifiable {
    public var id: String { shower.id }
    public let shower: MeteorShowerRecord
    public let screenX: Double
    public let screenY: Double
    public let isActiveTonight: Bool
}

public struct ProjectedIssState {
    public let position: LiveSatellitePosition
    public let screenX: Double
    public let screenY: Double
    public let trajectoryPoints: [(point: CGPoint, isSunlit: Bool)]
}

public struct SkyTargetGuideState {
    public let angleRadians: Double
    public let angularSeparationDeg: Double
    public let targetName: String
}

public struct SkyAccessibilityLandmark: Identifiable {
    public let id: String
    public let label: String
    public let valueSummary: String
    public let frame: CGRect
    public let target: CosmosTarget
}

public struct ProjectedSkyScene {
    public let matrix: SkyProjectionMatrix
    public let sunAltitudeDegrees: Double
    public let sunScreenPoint: CGPoint?
    public let milkyWayRings: [(level: Int, points: [CGPoint])]
    public let borderPolylines: [[CGPoint]]
    public let altAzGridPolylines: [[CGPoint]]
    public let raDecGridPolylines: [[CGPoint]]
    public let eclipticPolyline: [CGPoint]
    public let constellationSegments: [ProjectedSegment]
    public let asterismSegments: [ProjectedSegment]
    public let constellationLabels: [ProjectedConstellationLabel]
    public let stars: [ProjectedPackedStar]
    public let dsos: [ProjectedDSO]
    public let meteorRadiants: [ProjectedMeteorRadiant]
    public let planets: [ProjectedPlanet]
    public let issState: ProjectedIssState?
    public let horizonPoints: [CGPoint]
    public let cardinals: [(label: String, x: Double, y: Double, isPrimary: Bool)]
    public let zenithPoint: CGPoint?
    public let targetGuide: SkyTargetGuideState?
    public let hoverSummary: (point: CGPoint, title: String, subtitle: String)?
    public let accessibilityLandmarks: [SkyAccessibilityLandmark]
}

// MARK: - Central Cosmos View Model (Per-Window Safe + Shared Dashboard Instance)

@MainActor
public final class CosmosViewModel: ObservableObject {
    public static let shared = CosmosViewModel()

    // MARK: - Dependencies
    private let astronomyService = AstronomyService.shared
    public let catalogService = CosmosCatalogService.shared
    private let liveService = CosmosLiveService.shared
    public let motionService = CosmosMotionService.shared
    public let syncService = CosmosSyncService.shared
    private let weatherService = WeatherService.shared

    private var cancellables = Set<AnyCancellable>()
    private var liveTimer: AnyCancellable?
    private var playbackTimer: AnyCancellable?
    private var isObservatoryActive: Bool = false

    // Pre-baked star sRGB lookup parallel to `catalogService.stars` (zero per-frame log/pow math)
    private let prebakedStarRGB: [(r: Float, g: Float, b: Float)]
    private let constellationCodeByIndex: [UInt16: String]

    // Isolated 120Hz camera controller
    public let camera = CosmosCameraController()

    // Legacy forwarded properties for any external callers
    public var cameraAzimuth: Double {
        get { camera.azimuth }
        set { camera.azimuth = newValue }
    }
    public var cameraAltitude: Double {
        get { camera.altitude }
        set { camera.altitude = newValue }
    }
    public var cameraRoll: Double {
        get { camera.roll }
        set { camera.roll = newValue }
    }
    public var fov: Double {
        get { camera.fov }
        set { camera.fov = max(0.5, min(120.0, newValue)) }
    }

    // MARK: - Time Machine State
    @Published public var simulationDate: Date = Date()
    @Published public var isLiveTime: Bool = true
    @Published public var scrubberMinutesOffset: Double = 0.0 // -720 ... +720 (±12h continuous slider)
    @Published public var playbackSpeedMultiplier: Double = 0.0 // 0 = paused, 1 = 1x, 60 = 1m/s, 600 = 10m/s
    private var scrubberAnchorDate: Date = Date()

    // MARK: - Layer & Observatory Toggles
    @Published public var isNightVisionMode: Bool = false
    @Published public var isMotionTrackingEnabled: Bool = false
    @Published public var showAtmosphere: Bool = true
    @Published public var showMilkyWay: Bool = true
    @Published public var showConstellationLines: Bool = true
    @Published public var showConstellationLabels: Bool = true
    @Published public var showConstellationBorders: Bool = false
    @Published public var showAsterisms: Bool = true
    @Published public var showAltAzGrid: Bool = false
    @Published public var showEquatorialGrid: Bool = false
    @Published public var showEcliptic: Bool = true
    @Published public var showPlanets: Bool = true
    @Published public var showDeepSkyObjects: Bool = true
    @Published public var showMeteorRadiants: Bool = true
    @Published public var showSatellites: Bool = true
    @Published public var showHorizonCompass: Bool = true

    // MARK: - Selection, Search & Toast Feedback
    @Published public var selectedTarget: CosmosTarget? = nil
    @Published public var searchQuery: String = ""
    @Published public var statusBannerMessage: String? = nil

    // MARK: - Observer Geolocation
    public var observerLatitude: Double {
        if let loc = LocationManager.shared.lastKnownLocation {
            return loc.latitude
        }
        return weatherService.currentWeather?.coord?.lat ?? 44.4268
    }

    public var observerLongitude: Double {
        if let loc = LocationManager.shared.lastKnownLocation {
            return loc.longitude
        }
        return weatherService.currentWeather?.coord?.lon ?? 26.1025
    }

    public var observerLocationName: String {
        weatherService.currentLocationName.isEmpty ? "Local Horizon" : weatherService.currentLocationName
    }

    public var palette: CosmosPalette {
        CosmosPalette(isNightVision: isNightVisionMode)
    }

    // MARK: - Ephemeris & Live Summary State (1Hz)
    @Published public private(set) var currentMoonPhase: MoonPhaseInfo
    @Published public private(set) var stargazingConditions: StargazingConditions
    @Published public private(set) var stargazingScore: Int = 78
    @Published public private(set) var stargazingVerdict: String = "Good Conditions"
    @Published public private(set) var visiblePlanetsCount: Int = 0
    @Published public private(set) var nextIssPass: SatellitePass? = nil
    @Published public private(set) var sunTimes: SunTimes
    @Published public private(set) var circadianContext: CircadianSkyContext

    public init() {
        let stars = CosmosCatalogService.shared.stars
        var rgb: [(Float, Float, Float)] = []
        rgb.reserveCapacity(stars.count)
        for s in stars {
            let c = PackedStar.ballesterosRGB(bv: Double(s.bv))
            rgb.append((Float(c.r), Float(c.g), Float(c.b)))
        }
        self.prebakedStarRGB = rgb

        var cMap: [UInt16: String] = [:]
        for c in CosmosCatalogService.shared.constellations {
            cMap[UInt16(clamping: c.index)] = c.nameEn
        }
        self.constellationCodeByIndex = cMap

        let now = Date()
        let defaultObs = (latitude: 44.4268, longitude: 26.1025)
        self.currentMoonPhase = AstronomyService.shared.moonPhase(at: now, observer: defaultObs)
        self.sunTimes = AstronomyService.shared.sunTimes(for: defaultObs, on: now)
        self.circadianContext = AstronomyService.shared.circadianLunarContext(for: defaultObs, on: now)
        self.stargazingConditions = AstronomyService.shared.evaluateStargazingConditions(
            observer: defaultObs,
            date: now,
            cloudCoverTotal: nil,
            cloudCoverLow: nil,
            cloudCoverMid: nil,
            cloudCoverHigh: nil
        )
        self.stargazingScore = stargazingConditions.score
        self.stargazingVerdict = stargazingConditions.quality.displayName

        setupSubscriptions()
        recomputeEphemeris()
    }

    // MARK: - Lifecycle Gate (Stops Background Battery Drain When Hidden)

    public func onObservatoryAppear() {
        isObservatoryActive = true
        scrubberAnchorDate = Date()
        startLiveClock()
        recomputeEphemeris()
    }

    public func onObservatoryDisappear() {
        isObservatoryActive = false
        liveTimer?.cancel()
        liveTimer = nil
        playbackTimer?.cancel()
        playbackTimer = nil
        playbackSpeedMultiplier = 0.0
        if isMotionTrackingEnabled {
            isMotionTrackingEnabled = false
            motionService.stopTracking()
        }
    }

    // MARK: - Subscriptions

    private func setupSubscriptions() {
        motionService.$currentAzimuth
            .sink { [weak self] az in
                guard let self = self, self.isMotionTrackingEnabled else { return }
                self.camera.azimuth = az
            }
            .store(in: &cancellables)

        motionService.$currentAltitude
            .sink { [weak self] alt in
                guard let self = self, self.isMotionTrackingEnabled else { return }
                self.camera.altitude = alt
            }
            .store(in: &cancellables)

        motionService.$currentRoll
            .sink { [weak self] roll in
                guard let self = self, self.isMotionTrackingEnabled else { return }
                self.camera.roll = roll
            }
            .store(in: &cancellables)

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

    // MARK: - Time Machine & Playback

    public func startLiveClock() {
        liveTimer?.cancel()
        guard isObservatoryActive else { return }
        liveTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self = self else { return }
                if self.isLiveTime && self.playbackSpeedMultiplier == 0.0 {
                    self.simulationDate = date
                    self.scrubberAnchorDate = date
                    self.recomputeEphemeris()
                }
            }
    }

    public func adjustSimulationTime(byHours hours: Double) {
        isLiveTime = false
        simulationDate = simulationDate.addingTimeInterval(hours * 3600.0)
        scrubberMinutesOffset = max(-720.0, min(720.0, simulationDate.timeIntervalSince(scrubberAnchorDate) / 60.0))
        recomputeEphemeris()
    }

    public func scrubTimeOffset(minutes: Double) {
        let clamped = max(-720.0, min(720.0, minutes))
        scrubberMinutesOffset = clamped
        if abs(clamped) < 1.0 && playbackSpeedMultiplier == 0.0 {
            resetToLive()
            return
        }
        isLiveTime = false
        simulationDate = scrubberAnchorDate.addingTimeInterval(clamped * 60.0)
        recomputeEphemeris()
    }

    public func setSimulationDate(_ date: Date) {
        let minDate = Date(timeIntervalSince1970: -2_208_988_800) // 1900-01-01
        let maxDate = Date(timeIntervalSince1970: 4_102_444_800)  // 2100-01-01
        let clamped = min(maxDate, max(minDate, date))
        isLiveTime = false
        playbackSpeedMultiplier = 0.0
        playbackTimer?.cancel()
        simulationDate = clamped
        scrubberAnchorDate = clamped
        scrubberMinutesOffset = 0.0
        recomputeEphemeris()
    }

    public func cyclePlaybackSpeed() {
        let nextSpeed: Double
        switch playbackSpeedMultiplier {
        case 0.0: nextSpeed = 60.0
        case 60.0: nextSpeed = 600.0
        default: nextSpeed = 0.0
        }
        setPlaybackSpeed(nextSpeed)
    }

    public func setPlaybackSpeed(_ multiplier: Double) {
        playbackSpeedMultiplier = multiplier
        playbackTimer?.cancel()
        playbackTimer = nil
        guard multiplier > 0.0 else { return }

        isLiveTime = false
        playbackTimer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.playbackSpeedMultiplier > 0.0 else { return }
                self.simulationDate = self.simulationDate.addingTimeInterval((1.0 / 20.0) * self.playbackSpeedMultiplier)
                self.scrubberMinutesOffset = max(-720.0, min(720.0, self.simulationDate.timeIntervalSince(self.scrubberAnchorDate) / 60.0))
                self.recomputeEphemeris()
            }
    }

    public func resetToLive() {
        playbackSpeedMultiplier = 0.0
        playbackTimer?.cancel()
        playbackTimer = nil
        isLiveTime = true
        let now = Date()
        simulationDate = now
        scrubberAnchorDate = now
        scrubberMinutesOffset = 0.0
        recomputeEphemeris()
    }

    public func toggleMotionTracking() {
        guard motionService.isAvailable else { return }
        isMotionTrackingEnabled.toggle()
        if isMotionTrackingEnabled {
            camera.isZenithPlanisphereLocked = false
            motionService.startTracking()
        } else {
            camera.roll = 0.0
            motionService.stopTracking()
        }
    }

    // MARK: - Camera Gestures & Zoom Presets

    public func handlePan(deltaX: Double, deltaY: Double, viewportWidth: Double, viewportHeight: Double) {
        if isMotionTrackingEnabled {
            isMotionTrackingEnabled = false
            camera.roll = 0.0
            motionService.stopTracking()
        }
        if camera.isZenithPlanisphereLocked {
            camera.isZenithPlanisphereLocked = false
        }

        let minDim = max(240.0, min(viewportWidth, viewportHeight))
        let degPerPixel = camera.fov / minDim

        var newAz = (camera.azimuth - deltaX * degPerPixel).truncatingRemainder(dividingBy: 360.0)
        if newAz < 0.0 { newAz += 360.0 }
        camera.azimuth = newAz

        let newAlt = max(-25.0, min(90.0, camera.altitude + deltaY * degPerPixel))
        camera.altitude = newAlt
    }

    public func handleZoom(deltaMagnification: Double, anchorPoint: CGPoint? = nil, viewportSize: CGSize? = nil) {
        guard deltaMagnification > 0.01 else { return }
        let oldFov = camera.fov
        let newFov = max(0.5, min(120.0, oldFov / pow(deltaMagnification, 0.92)))

        if let anchor = anchorPoint, let size = viewportSize, size.width > 10, size.height > 10, !camera.isZenithPlanisphereLocked {
            let beforeMat = astronomyService.makeProjectionMatrix(
                observerLatitudeDegrees: observerLatitude,
                observerLongitudeDegrees: observerLongitude,
                date: simulationDate,
                cameraAzimuthDegrees: camera.azimuth,
                cameraAltitudeDegrees: camera.altitude,
                cameraRollDegrees: camera.roll,
                fovDegrees: oldFov,
                viewportWidth: Double(size.width),
                viewportHeight: Double(size.height)
            )
            if let worldBefore = beforeMat.unprojectToHorizontal(screenX: Double(anchor.x), screenY: Double(anchor.y)) {
                camera.fov = newFov
                let afterMat = astronomyService.makeProjectionMatrix(
                    observerLatitudeDegrees: observerLatitude,
                    observerLongitudeDegrees: observerLongitude,
                    date: simulationDate,
                    cameraAzimuthDegrees: camera.azimuth,
                    cameraAltitudeDegrees: camera.altitude,
                    cameraRollDegrees: camera.roll,
                    fovDegrees: newFov,
                    viewportWidth: Double(size.width),
                    viewportHeight: Double(size.height)
                )
                if let worldAfter = afterMat.unprojectToHorizontal(screenX: Double(anchor.x), screenY: Double(anchor.y)) {
                    var dAz = worldBefore.azimuthDegrees - worldAfter.azimuthDegrees
                    if dAz > 180.0 { dAz -= 360.0 }
                    if dAz < -180.0 { dAz += 360.0 }
                    camera.azimuth = ((camera.azimuth + dAz).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
                    camera.altitude = max(-25.0, min(90.0, camera.altitude + (worldBefore.altitudeDegrees - worldAfter.altitudeDegrees)))
                    return
                }
            }
        }

        camera.fov = newFov
    }

    public func applyZoomPreset(_ preset: CosmosZoomPreset) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            camera.fov = preset.fovDegrees
        }
    }

    public func centerOn(target: CosmosTarget) {
        if isMotionTrackingEnabled {
            isMotionTrackingEnabled = false
            camera.roll = 0.0
            motionService.stopTracking()
        }
        camera.isZenithPlanisphereLocked = false
        let live = liveMetrics(for: target)
        withAnimation(.spring(response: 0.48, dampingFraction: 0.80)) {
            camera.azimuth = live.azimuthDegrees
            camera.altitude = max(-15.0, min(89.5, live.altitudeDegrees))
            selectedTarget = target
        }
    }

    // MARK: - Ephemeris & Stargazing Scoring (Zero Hardcoded Fallbacks)

    public func recomputeEphemeris() {
        let obs = (latitude: observerLatitude, longitude: observerLongitude)
        self.currentMoonPhase = astronomyService.moonPhase(at: simulationDate, observer: obs)
        self.sunTimes = astronomyService.sunTimes(for: obs, on: simulationDate)
        self.circadianContext = astronomyService.circadianLunarContext(for: obs, on: simulationDate)

        let liveCond = liveService.stargazingConditions
        let evaluated = astronomyService.evaluateStargazingConditions(
            observer: obs,
            date: simulationDate,
            cloudCoverTotal: liveCond?.cloudCoverTotalPercent,
            cloudCoverLow: liveCond?.cloudCoverLowPercent,
            cloudCoverMid: liveCond?.cloudCoverMidPercent,
            cloudCoverHigh: liveCond?.cloudCoverHighPercent,
            bortleClass: liveCond?.bortleClass,
            seeingArcseconds: liveCond?.seeingArcseconds,
            transparencyLabel: liveCond?.transparencyLabel,
            dewPointDepression: liveCond?.dewPointDepressionCelsius,
            provenance: liveCond?.provenance ?? .offlineCalculated(epochAgeHours: nil)
        )
        self.stargazingConditions = evaluated
        self.stargazingScore = evaluated.score
        self.stargazingVerdict = evaluated.quality.displayName

        var count = 0
        let obs3 = (latitude: obs.latitude, longitude: obs.longitude, elevation: 50.0)
        for p in [CelestialBody.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune] {
            if astronomyService.coordinates(of: p, for: obs3, at: simulationDate).altitudeDegrees > 0.0 {
                count += 1
            }
        }
        self.visiblePlanetsCount = count
    }

    // MARK: - Live Target Coordinates & Rise/Transit/Set

    public func liveMetrics(for target: CosmosTarget) -> CosmosTargetLiveMetrics {
        let obs = (latitude: observerLatitude, longitude: observerLongitude)
        let obs3 = (latitude: observerLatitude, longitude: observerLongitude, elevation: 50.0)

        switch target.kind {
        case .body(let body):
            let coords = astronomyService.coordinates(of: body, for: obs3, at: simulationDate)
            let rts = astronomyService.riseTransitSet(of: body, for: obs, on: simulationDate)
            let distLabel: String
            let detailLabel: String?
            if body == .moon {
                let moon = astronomyService.moonPhase(at: simulationDate, observer: obs)
                let km = Int((moon.topocentricDistanceKm ?? moon.distanceKm).rounded())
                distLabel = "\(km.formatted()) km"
                detailLabel = "\(moon.quarter.displayName) · \(moon.illuminationPercent)% lit"
            } else if body == .saturn {
                distLabel = String(format: "%.2f AU", coords.distanceAU)
                let tilt = astronomyService.saturnRingTilt(at: simulationDate)
                detailLabel = String(format: "Ring tilt %.1f°", abs(tilt))
            } else if body == .jupiter {
                distLabel = String(format: "%.2f AU", coords.distanceAU)
                detailLabel = "Io · Europa · Ganymede · Callisto"
            } else if body == .venus || body == .mercury {
                distLabel = String(format: "%.2f AU", coords.distanceAU)
                detailLabel = "\(Int((coords.illuminatedFraction * 100.0).rounded()))% illuminated"
            } else {
                distLabel = String(format: "%.2f AU", coords.distanceAU)
                detailLabel = nil
            }
            return CosmosTargetLiveMetrics(
                azimuthDegrees: coords.azimuthDegrees,
                altitudeDegrees: coords.altitudeDegrees,
                compassDirection: coords.compassDirection,
                rightAscensionHours: coords.rightAscensionHours,
                declinationDegrees: coords.declinationDegrees,
                riseTime: rts.rise,
                transitTime: rts.transit,
                setTime: rts.set,
                distanceLabel: distLabel,
                phaseOrDetailLabel: detailLabel,
                isAboveHorizon: coords.altitudeDegrees > 0.0
            )

        case .iss:
            if let live = liveService.currentIssPosition(latitude: obs.latitude, longitude: obs.longitude, at: simulationDate) {
                return CosmosTargetLiveMetrics(
                    azimuthDegrees: live.azimuthDegrees,
                    altitudeDegrees: live.altitudeDegrees,
                    compassDirection: CelestialCoordinates.compassPoint(for: live.azimuthDegrees),
                    rightAscensionHours: target.rightAscensionHours,
                    declinationDegrees: target.declinationDegrees,
                    riseTime: nextIssPass?.startTime,
                    transitTime: nextIssPass?.maxAltitudeTime,
                    setTime: nextIssPass?.endTime,
                    distanceLabel: "\(Int(live.rangeKm.rounded())) km range · \(Int(live.orbitalAltitudeKm.rounded())) km orbit",
                    phaseOrDetailLabel: live.isSunlit ? "Sunlit in orbit" : "In Earth's umbra shadow",
                    isAboveHorizon: live.altitudeDegrees > 0.0
                )
            }
            return fallbackEquatorialMetrics(for: target, observer: obs)

        default:
            return fallbackEquatorialMetrics(for: target, observer: obs)
        }
    }

    private func fallbackEquatorialMetrics(
        for target: CosmosTarget,
        observer: (latitude: Double, longitude: Double)
    ) -> CosmosTargetLiveMetrics {
        let mat = astronomyService.makeProjectionMatrix(
            observerLatitudeDegrees: observer.latitude,
            observerLongitudeDegrees: observer.longitude,
            date: simulationDate,
            cameraAzimuthDegrees: 180.0,
            cameraAltitudeDegrees: 45.0,
            viewportWidth: 100.0,
            viewportHeight: 100.0
        )
        let raRad = target.rightAscensionHours * 15.0 * (.pi / 180.0)
        let decRad = target.declinationDegrees * (.pi / 180.0)
        let vx = cos(decRad) * cos(raRad)
        let vy = cos(decRad) * sin(raRad)
        let vz = sin(decRad)

        let hx = mat.h00 * vx + mat.h01 * vy + mat.h02 * vz
        let hy = mat.h10 * vx + mat.h11 * vy + mat.h12 * vz
        let hz = mat.h20 * vx + mat.h21 * vy + mat.h22 * vz
        let altDeg = asin(max(-1.0, min(1.0, hz))) * (180.0 / .pi)
        let azDeg = (atan2(-hy, hx) * (180.0 / .pi) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let rts = astronomyService.riseTransitSet(
            raHours: target.rightAscensionHours,
            decDegrees: target.declinationDegrees,
            for: observer,
            on: simulationDate
        )

        return CosmosTargetLiveMetrics(
            azimuthDegrees: azDeg,
            altitudeDegrees: altDeg,
            compassDirection: CelestialCoordinates.compassPoint(for: azDeg),
            rightAscensionHours: target.rightAscensionHours,
            declinationDegrees: target.declinationDegrees,
            riseTime: rts.rise,
            transitTime: rts.transit,
            setTime: rts.set,
            distanceLabel: target.distanceDescription,
            phaseOrDetailLabel: nil,
            isAboveHorizon: altDeg > 0.0
        )
    }

    // MARK: - Bookmarks, TagDoS #sky Sighting Logger & Calendar Scheduling

    public func isBookmarked(_ target: CosmosTarget) -> Bool {
        syncService.isBookmarked(objectId: target.id)
    }

    public func toggleBookmark(for target: CosmosTarget) {
        syncService.toggleBookmark(
            objectId: target.id,
            objectName: target.name,
            category: target.category,
            raHours: target.rightAscensionHours,
            decDeg: target.declinationDegrees,
            magnitude: target.visualMagnitude,
            constellation: target.constellationName
        )
        showTransientBanner(isBookmarked(target) ? "Bookmarked \(target.name)" : "Removed \(target.name) from Bookmarks")
    }

    public func logSightingToTagdos(for target: CosmosTarget, optics: String = "Naked Eye", notes: String = "") {
        let live = liveMetrics(for: target)
        syncService.logSighting(
            objectId: target.id,
            objectName: target.name,
            category: target.category,
            latitude: observerLatitude,
            longitude: observerLongitude,
            locationName: observerLocationName,
            azimuthDeg: live.azimuthDegrees,
            altitudeDeg: live.altitudeDegrees,
            bortleClass: stargazingConditions.bortleClass,
            stargazingScore: stargazingScore,
            optics: target.recommendedOptics ?? optics,
            notes: notes,
            mirrorToTagdos: true
        )
        showTransientBanner("Logged \(target.name) sighting to TagDoS (#sky)")
    }

    public func scheduleObservationInCalendar(title: String, startDate: Date, durationMinutes: Int = 30, notes: String) async {
        #if canImport(EventKit)
        let store = EKEventStore()
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else {
                showTransientBanner("Calendar access not granted in System Settings.")
                return
            }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = startDate
            event.endDate = startDate.addingTimeInterval(Double(durationMinutes) * 60.0)
            event.notes = notes
            event.location = observerLocationName
            event.calendar = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent)
            showTransientBanner("Scheduled \"\(title)\" in Calendar")
        } catch {
            showTransientBanner("Could not save Calendar event: \(error.localizedDescription)")
        }
        #else
        showTransientBanner("Calendar integration unavailable on this platform.")
        #endif
    }

    private func showTransientBanner(_ message: String) {
        statusBannerMessage = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if self?.statusBannerMessage == message {
                self?.statusBannerMessage = nil
            }
        }
    }

    // MARK: - High-Throughput 120Hz Sky Scene Projection

    public func projectSkyScene(in size: CGSize, renderTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) -> ProjectedSkyScene {
        let vw = max(1.0, Double(size.width))
        let vh = max(1.0, Double(size.height))
        let obsLat = observerLatitude
        let obsLon = observerLongitude
        let date = simulationDate
        let camAz = camera.effectiveAzimuth
        let camAlt = camera.effectiveAltitude
        let camRoll = camera.effectiveRoll
        let currentFov = camera.fov

        let mat = astronomyService.makeProjectionMatrix(
            observerLatitudeDegrees: obsLat,
            observerLongitudeDegrees: obsLon,
            date: date,
            cameraAzimuthDegrees: camAz,
            cameraAltitudeDegrees: camAlt,
            cameraRollDegrees: camRoll,
            fovDegrees: currentFov,
            viewportWidth: vw,
            viewportHeight: vh
        )

        let obs3 = (latitude: obsLat, longitude: obsLon, elevation: 50.0)
        let sunCoords = astronomyService.coordinates(of: .sun, for: obs3, at: date)
        let sunPt: CGPoint? = mat.projectHorizontal(
            azimuthDegrees: sunCoords.azimuthDegrees,
            altitudeDegrees: sunCoords.altitudeDegrees,
            margin: max(vw, vh)
        ).map { CGPoint(x: $0.x, y: $0.y) }

        let daylightFactor: Double = showAtmosphere ? max(0.0, min(1.0, (sunCoords.altitudeDegrees + 8.0) / 11.0)) : 0.0
        let zoomGain = max(0.0, log10(max(1.0, 65.0 / currentFov)) * 2.35)
        let baseNelm = showAtmosphere ? stargazingConditions.limitingMagnitude : 6.8
        let dynamicMagLimit = Float(min(7.5, max(1.8, (baseNelm - daylightFactor * 2.6) + zoomGain)))

        var mwRings: [(level: Int, points: [CGPoint])] = []
        if showMilkyWay && daylightFactor < 0.55 && currentFov >= 6.0 {
            for layer in catalogService.milkyWayLayers {
                for ring in layer.rings {
                    var pts: [CGPoint] = []
                    pts.reserveCapacity(ring.count)
                    var anyInside = false
                    for v in ring {
                        if let p = mat.projectEQJUnitVector(ux: Double(v.x), uy: Double(v.y), uz: Double(v.z), margin: vw * 0.6) {
                            pts.append(CGPoint(x: p.x, y: p.y))
                            if p.isVisible { anyInside = true }
                        } else {
                            pts.removeAll(keepingCapacity: true)
                            break
                        }
                    }
                    if anyInside && pts.count >= 4 {
                        mwRings.append((layer.level, pts))
                    }
                }
            }
        }

        var projectedStars: [ProjectedPackedStar] = []
        projectedStars.reserveCapacity(2200)
        var hipScreenMap: [Int: (x: Double, y: Double)] = [:]
        hipScreenMap.reserveCapacity(1400)

        let labelMagThreshold: Float = currentFov <= 15.0 ? 3.6 : (currentFov <= 45.0 ? 2.4 : 1.7)
        let seeingFactor = min(2.2, max(0.4, (stargazingConditions.seeingArcseconds ?? 1.5) / 1.5))

        for (idx, star) in catalogService.stars.enumerated() {
            let needsHipForStick = showConstellationLines || showAsterisms
            if star.vMag > dynamicMagLimit && !(needsHipForStick && star.vMag <= 5.6) {
                continue
            }

            guard let proj = mat.projectEQJUnitVector(
                ux: Double(star.ux),
                uy: Double(star.uy),
                uz: Double(star.uz),
                margin: 90.0
            ) else { continue }

            if needsHipForStick {
                hipScreenMap[star.hip] = (proj.x, proj.y)
            }

            guard proj.isVisible, star.vMag <= dynamicMagLimit else { continue }

            let sinAlt = mat.h20 * Double(star.ux) + mat.h21 * Double(star.uy) + mat.h22 * Double(star.uz)
            if showHorizonCompass && sinAlt < -0.02 {
                continue
            }

            let magDelta = Double(dynamicMagLimit - star.vMag)
            let flux = pow(10.0, 0.21 * min(7.5, max(0.0, magDelta)))
            let fovScale = max(0.75, min(2.1, sqrt(60.0 / max(4.0, currentFov))))
            let diameter = min(10.5, max(1.05, 0.72 * flux * fovScale * 0.42))

            var alpha = min(1.0, max(0.18, 0.22 + 0.16 * magDelta)) * (1.0 - daylightFactor * 0.85)
            if sinAlt > 0.0 && sinAlt < 0.38 && star.vMag < 4.2 {
                let airmassDepth = (0.38 - sinAlt) / 0.38
                let phase = renderTimestamp * 7.5 + Double(star.hip % 97) * 0.37
                let twinkle = 1.0 - (0.22 * airmassDepth * seeingFactor * (0.5 + 0.5 * sin(phase)))
                alpha *= max(0.35, twinkle)
            }

            let c = prebakedStarRGB[idx]
            let lbl: String?
            if star.vMag <= labelMagThreshold, let proper = catalogService.starDesignationsByHip[star.hip]?.name, !proper.isEmpty {
                lbl = proper
            } else {
                lbl = nil
            }

            projectedStars.append(
                ProjectedPackedStar(
                    hip: star.hip,
                    x: proj.x,
                    y: proj.y,
                    diameter: diameter,
                    r: Double(c.r),
                    g: Double(c.g),
                    b: Double(c.b),
                    alpha: alpha,
                    magnitude: star.vMag,
                    label: lbl
                )
            )
        }

        let maxSegSpan2 = pow(max(vw, vh) * 0.85, 2.0)
        var constSegments: [ProjectedSegment] = []
        if showConstellationLines {
            constSegments.reserveCapacity(520)
            for const in catalogService.constellations {
                for pair in const.segments where pair.count == 2 {
                    let posA = hipScreenMap[pair[0]] ?? projectHipFallback(pair[0], matrix: mat)
                    let posB = hipScreenMap[pair[1]] ?? projectHipFallback(pair[1], matrix: mat)
                    if let a = posA, let b = posB {
                        let dx = a.x - b.x, dy = a.y - b.y
                        if (dx * dx + dy * dy) <= maxSegSpan2 {
                            constSegments.append(ProjectedSegment(x1: a.x, y1: a.y, x2: b.x, y2: b.y))
                        }
                    }
                }
            }
        }

        var astSegments: [ProjectedSegment] = []
        if showAsterisms {
            for ast in catalogService.asterisms {
                for pair in ast.segments where pair.count == 2 {
                    let posA = hipScreenMap[pair[0]] ?? projectHipFallback(pair[0], matrix: mat)
                    let posB = hipScreenMap[pair[1]] ?? projectHipFallback(pair[1], matrix: mat)
                    if let a = posA, let b = posB {
                        let dx = a.x - b.x, dy = a.y - b.y
                        if (dx * dx + dy * dy) <= maxSegSpan2 {
                            astSegments.append(ProjectedSegment(x1: a.x, y1: a.y, x2: b.x, y2: b.y))
                        }
                    }
                }
            }
        }

        var constLabels: [ProjectedConstellationLabel] = []
        if showConstellationLabels && currentFov >= 8.0 {
            for const in catalogService.constellations {
                if currentFov > 95.0 && const.rank > 2 { continue }
                let raRad = const.centerRaHours * 15.0 * (.pi / 180.0)
                let decRad = const.centerDecDeg * (.pi / 180.0)
                let vx = cos(decRad) * cos(raRad)
                let vy = cos(decRad) * sin(raRad)
                let vz = sin(decRad)
                let sinAlt = mat.h20 * vx + mat.h21 * vy + mat.h22 * vz
                if showHorizonCompass && sinAlt < 0.02 { continue }
                if let p = mat.projectEQJUnitVector(ux: vx, uy: vy, uz: vz, margin: 20.0), p.isVisible {
                    constLabels.append(ProjectedConstellationLabel(record: const, screenX: p.x, screenY: p.y))
                }
            }
        }

        var borderLines: [[CGPoint]] = []
        if showConstellationBorders {
            for arc in catalogService.constellationBorders {
                var poly: [CGPoint] = []
                for pt in arc.points where pt.count >= 2 {
                    let raRad = pt[0] * 15.0 * (.pi / 180.0)
                    let decRad = pt[1] * (.pi / 180.0)
                    if let p = mat.projectEQJUnitVector(
                        ux: cos(decRad) * cos(raRad),
                        uy: cos(decRad) * sin(raRad),
                        uz: sin(decRad),
                        margin: 120.0
                    ) {
                        poly.append(CGPoint(x: p.x, y: p.y))
                    } else {
                        if poly.count >= 2 { borderLines.append(poly) }
                        poly.removeAll(keepingCapacity: true)
                    }
                }
                if poly.count >= 2 { borderLines.append(poly) }
            }
        }

        let altAzPolylines = showAltAzGrid ? buildAltAzGrid(matrix: mat) : []
        let raDecPolylines = showEquatorialGrid ? buildEquatorialGrid(matrix: mat) : []
        let eclipticPoly = showEcliptic ? buildEclipticLine(matrix: mat) : []

        var projectedDSOs: [ProjectedDSO] = []
        if showDeepSkyObjects && daylightFactor < 0.7 {
            let dsoMagLimit = Double(dynamicMagLimit) + 2.2
            for dso in catalogService.deepSkyObjects where dso.visualMagnitude <= dsoMagLimit {
                let sinAlt = mat.h20 * Double(dso.ux) + mat.h21 * Double(dso.uy) + mat.h22 * Double(dso.uz)
                if showHorizonCompass && sinAlt < -0.02 { continue }
                if let p = mat.projectEQJUnitVector(ux: Double(dso.ux), uy: Double(dso.uy), uz: Double(dso.uz), margin: 30.0), p.isVisible {
                    let angularDeg = max(0.12, dso.majorAxisArcmin / 60.0)
                    let pxPerDeg = min(vw, vh) / max(0.5, currentFov)
                    let radiusPx = max(6.0, min(64.0, angularDeg * pxPerDeg * 0.5))
                    let aspect = max(0.32, min(1.0, dso.minorAxisArcmin / max(0.1, dso.majorAxisArcmin)))
                    projectedDSOs.append(
                        ProjectedDSO(
                            dso: dso,
                            screenX: p.x,
                            screenY: p.y,
                            radiusPx: radiusPx,
                            aspectRatio: aspect,
                            positionAngleDeg: dso.positionAngleDeg
                        )
                    )
                }
            }
        }

        var radiants: [ProjectedMeteorRadiant] = []
        if showMeteorRadiants && daylightFactor < 0.5 {
            for shower in catalogService.meteorShowers {
                let isActive = shower.isActive(on: date)
                if !isActive && shower.zhr < 25 { continue }
                let raRad = shower.radiantRaHours * 15.0 * (.pi / 180.0)
                let decRad = shower.radiantDecDeg * (.pi / 180.0)
                let vx = cos(decRad) * cos(raRad)
                let vy = cos(decRad) * sin(raRad)
                let vz = sin(decRad)
                let sinAlt = mat.h20 * vx + mat.h21 * vy + mat.h22 * vz
                if showHorizonCompass && sinAlt < 0.0 { continue }
                if let p = mat.projectEQJUnitVector(ux: vx, uy: vy, uz: vz, margin: 24.0), p.isVisible {
                    radiants.append(ProjectedMeteorRadiant(shower: shower, screenX: p.x, screenY: p.y, isActiveTonight: isActive))
                }
            }
        }

        var projectedPlanets: [ProjectedPlanet] = []
        if showPlanets {
            let bodies: [CelestialBody] = [.sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune]
            let saturnTilt = astronomyService.saturnRingTilt(at: date)
            let jupMoonsState: JupiterMoonsState? = (currentFov <= 10.0)
                ? astronomyService.jupiterMoons(at: date, observer: (obsLat, obsLon))
                : nil

            for body in bodies {
                if currentFov > 45.0 && (body == .uranus || body == .neptune) { continue }
                let coords = astronomyService.coordinates(of: body, for: obs3, at: date)
                if showHorizonCompass && coords.altitudeDegrees < -1.0 { continue }
                guard let p = mat.projectHorizontal(
                    azimuthDegrees: coords.azimuthDegrees,
                    altitudeDegrees: coords.altitudeDegrees,
                    margin: 48.0
                ), p.isVisible else { continue }

                let pxPerDeg = min(vw, vh) / max(0.5, currentFov)
                let trueRadiusDeg = (coords.angularDiameterArcsec / 3600.0)
                let minIconDiameter: Double = {
                    switch body {
                    case .sun, .moon: return 22.0
                    case .jupiter: return 13.0
                    case .saturn: return 12.0
                    case .venus: return 10.5
                    case .mars: return 9.5
                    default: return 7.5
                    }
                }()
                let diameter = min(140.0, max(minIconDiameter, trueRadiusDeg * pxPerDeg))

                var gMoons: [ProjectedGalileanMoon] = []
                if body == .jupiter, let jm = jupMoonsState {
                    let jupRadiusPx = max(7.0, diameter * 0.5)
                    let rollRad = camRoll * (.pi / 180.0)
                    let cr = cos(rollRad), sr = sin(rollRad)
                    for m in jm.all {
                        let dxLocal = m.xRadius * jupRadiusPx
                        let dyLocal = m.yRadius * jupRadiusPx
                        let sx = p.x + (dxLocal * cr - dyLocal * sr)
                        let sy = p.y - (dxLocal * sr + dyLocal * cr)
                        gMoons.append(ProjectedGalileanMoon(name: m.name, x: sx, y: sy, isFrontOfPlanet: m.isFrontOfPlanet))
                    }
                }

                let limbAngle = (body == .moon)
                    ? currentMoonPhase.brightLimbAngleDegrees - camRoll
                    : coords.brightLimbAngleDegrees - camRoll

                projectedPlanets.append(
                    ProjectedPlanet(
                        body: body,
                        screenX: p.x,
                        screenY: p.y,
                        altitude: coords.altitudeDegrees,
                        azimuth: coords.azimuthDegrees,
                        coordinates: coords,
                        diameter: diameter,
                        brightLimbAngleDeg: limbAngle,
                        saturnRingTiltDeg: body == .saturn ? saturnTilt : 0.0,
                        galileanMoons: gMoons
                    )
                )
            }
        }

        var issProjected: ProjectedIssState? = nil
        if showSatellites, let liveIss = liveService.currentIssPosition(latitude: obsLat, longitude: obsLon, at: date) {
            if let p = mat.projectHorizontal(
                azimuthDegrees: liveIss.azimuthDegrees,
                altitudeDegrees: liveIss.altitudeDegrees,
                margin: 80.0
            ) {
                var arc: [(point: CGPoint, isSunlit: Bool)] = []
                for step in -10...20 {
                    let sampleTime = date.addingTimeInterval(Double(step) * 20.0)
                    if let sp = liveService.currentIssPosition(latitude: obsLat, longitude: obsLon, at: sampleTime),
                       sp.altitudeDegrees >= -2.0,
                       let spProj = mat.projectHorizontal(azimuthDegrees: sp.azimuthDegrees, altitudeDegrees: sp.altitudeDegrees, margin: 120.0) {
                        arc.append((CGPoint(x: spProj.x, y: spProj.y), sp.isSunlit))
                    }
                }
                if p.isVisible || !arc.isEmpty {
                    issProjected = ProjectedIssState(
                        position: liveIss,
                        screenX: p.x,
                        screenY: p.y,
                        trajectoryPoints: arc
                    )
                }
            }
        }

        var hPoints: [CGPoint] = []
        hPoints.reserveCapacity(91)
        if camera.isZenithPlanisphereLocked {
            for step in 0...90 {
                let azDeg = Double(step * 4)
                if let p = mat.projectHorizontal(azimuthDegrees: azDeg, altitudeDegrees: 0.0, margin: max(vw, vh) * 1.5) {
                    hPoints.append(CGPoint(x: p.x, y: p.y))
                }
            }
        } else {
            var lastX: Double = -.infinity
            for offset in stride(from: -102, through: 102, by: 3) {
                let azDeg = (camAz + Double(offset) + 360.0).truncatingRemainder(dividingBy: 360.0)
                let azRad = azDeg * (.pi / 180.0)
                let hx = cos(azRad)
                let hy = -sin(azRad)
                let cz = mat.fx * hx + mat.fy * hy
                guard cz > 0.05,
                      let p = mat.projectHorizontal(azimuthDegrees: azDeg, altitudeDegrees: 0.0, margin: max(vw, vh) * 0.9),
                      p.x > lastX else { continue }
                lastX = p.x
                hPoints.append(CGPoint(x: p.x, y: p.y))
            }
        }

        let cardinalDefs: [(String, Double, Bool)] = [
            ("N", 0.0, true), ("NE", 45.0, false),
            ("E", 90.0, true), ("SE", 135.0, false),
            ("S", 180.0, true), ("SW", 225.0, false),
            ("W", 270.0, true), ("NW", 315.0, false)
        ]
        var cards: [(label: String, x: Double, y: Double, isPrimary: Bool)] = []
        for (lbl, azDeg, isPri) in cardinalDefs {
            if let p = mat.projectHorizontal(azimuthDegrees: azDeg, altitudeDegrees: 0.0, margin: 36.0), p.isVisible {
                cards.append((lbl, p.x, p.y, isPri))
            }
        }

        let zPt: CGPoint? = mat.projectHorizontal(azimuthDegrees: camAz, altitudeDegrees: 90.0, margin: 24.0).flatMap {
            $0.isVisible ? CGPoint(x: $0.x, y: $0.y) : nil
        }

        var guide: SkyTargetGuideState? = nil
        if let sel = selectedTarget {
            let live = liveMetrics(for: sel)
            let azRad = live.azimuthDegrees * (.pi / 180.0)
            let altRad = live.altitudeDegrees * (.pi / 180.0)
            let hx = cos(altRad) * cos(azRad)
            let hy = -cos(altRad) * sin(azRad)
            let hz = sin(altRad)
            let cx = mat.rx * hx + mat.ry * hy + mat.rz * hz
            let cy = mat.ux * hx + mat.uy * hy + mat.uz * hz
            let cz = mat.fx * hx + mat.fy * hy + mat.fz * hz
            let sepDeg = acos(max(-1.0, min(1.0, cz))) * (180.0 / .pi)
            if sepDeg > currentFov * 0.42 {
                let angle = atan2(-cy, cx)
                guide = SkyTargetGuideState(angleRadians: angle, angularSeparationDeg: sepDeg, targetName: sel.name)
            }
        }

        var hoverInfo: (point: CGPoint, title: String, subtitle: String)? = nil
        if let hp = camera.hoverLocation {
            if let hit = hitTestTarget(
                at: hp,
                planets: projectedPlanets,
                iss: issProjected,
                dsos: projectedDSOs,
                stars: projectedStars,
                constellationLabels: constLabels
            ) {
                hoverInfo = (hp, hit.name, hit.subtitle)
            } else if let skyCoord = mat.unprojectToHorizontal(screenX: Double(hp.x), screenY: Double(hp.y)) {
                let dir = CelestialCoordinates.compassPoint(for: skyCoord.azimuthDegrees)
                hoverInfo = (
                    hp,
                    String(format: "Az %.1f° (%@) · Alt %.1f°", skyCoord.azimuthDegrees, dir, skyCoord.altitudeDegrees),
                    "Click any star, planet, or nebula to inspect"
                )
            }
        }

        var landmarks: [SkyAccessibilityLandmark] = []
        for p in projectedPlanets where p.altitude > -2.0 {
            let t = target(for: p.body)
            let frame = CGRect(x: p.screenX - 22, y: p.screenY - 22, width: 44, height: 44)
            landmarks.append(
                SkyAccessibilityLandmark(
                    id: t.id,
                    label: t.name,
                    valueSummary: String(format: "Azimuth %.0f degrees %@, Altitude %.0f degrees", p.azimuth, p.coordinates.compassDirection, p.altitude),
                    frame: frame,
                    target: t
                )
            )
        }
        if let iss = issProjected, iss.position.altitudeDegrees > 0 {
            let t = issTarget(from: iss.position)
            landmarks.append(
                SkyAccessibilityLandmark(
                    id: t.id,
                    label: "International Space Station",
                    valueSummary: String(format: "Altitude %.0f degrees, %@", iss.position.altitudeDegrees, iss.position.isSunlit ? "Sunlit" : "In shadow"),
                    frame: CGRect(x: iss.screenX - 22, y: iss.screenY - 22, width: 44, height: 44),
                    target: t
                )
            )
        }
        for s in projectedStars.prefix(12) where s.label != nil {
            if let bStar = catalogService.brightStars.first(where: { $0.hip == s.hip }) {
                let t = target(for: bStar)
                landmarks.append(
                    SkyAccessibilityLandmark(
                        id: t.id,
                        label: bStar.name,
                        valueSummary: String(format: "Star in %@, Magnitude %.1f", bStar.constellation, bStar.magnitude),
                        frame: CGRect(x: s.x - 18, y: s.y - 18, width: 36, height: 36),
                        target: t
                    )
                )
            }
        }

        return ProjectedSkyScene(
            matrix: mat,
            sunAltitudeDegrees: sunCoords.altitudeDegrees,
            sunScreenPoint: sunPt,
            milkyWayRings: mwRings,
            borderPolylines: borderLines,
            altAzGridPolylines: altAzPolylines,
            raDecGridPolylines: raDecPolylines,
            eclipticPolyline: eclipticPoly,
            constellationSegments: constSegments,
            asterismSegments: astSegments,
            constellationLabels: constLabels,
            stars: projectedStars,
            dsos: projectedDSOs,
            meteorRadiants: radiants,
            planets: projectedPlanets,
            issState: issProjected,
            horizonPoints: hPoints,
            cardinals: cards,
            zenithPoint: zPt,
            targetGuide: guide,
            hoverSummary: hoverInfo,
            accessibilityLandmarks: landmarks
        )
    }

    private func projectHipFallback(_ hip: Int, matrix: SkyProjectionMatrix) -> (x: Double, y: Double)? {
        guard let s = catalogService.star(forHip: hip),
              let p = matrix.projectEQJUnitVector(ux: Double(s.ux), uy: Double(s.uy), uz: Double(s.uz), margin: 180.0) else {
            return nil
        }
        return (p.x, p.y)
    }

    private func buildAltAzGrid(matrix: SkyProjectionMatrix) -> [[CGPoint]] {
        var lines: [[CGPoint]] = []
        for alt in stride(from: 15, through: 75, by: 15) {
            var poly: [CGPoint] = []
            for az in stride(from: 0, through: 360, by: 6) {
                if let p = matrix.projectHorizontal(azimuthDegrees: Double(az), altitudeDegrees: Double(alt), margin: 120.0) {
                    poly.append(CGPoint(x: p.x, y: p.y))
                } else {
                    if poly.count >= 2 { lines.append(poly) }
                    poly.removeAll(keepingCapacity: true)
                }
            }
            if poly.count >= 2 { lines.append(poly) }
        }
        for az in stride(from: 0, to: 360, by: 30) {
            var poly: [CGPoint] = []
            for alt in stride(from: 0, through: 90, by: 5) {
                if let p = matrix.projectHorizontal(azimuthDegrees: Double(az), altitudeDegrees: Double(alt), margin: 120.0) {
                    poly.append(CGPoint(x: p.x, y: p.y))
                } else {
                    if poly.count >= 2 { lines.append(poly) }
                    poly.removeAll(keepingCapacity: true)
                }
            }
            if poly.count >= 2 { lines.append(poly) }
        }
        return lines
    }

    private func buildEquatorialGrid(matrix: SkyProjectionMatrix) -> [[CGPoint]] {
        var lines: [[CGPoint]] = []
        for dec in stride(from: -60, through: 60, by: 30) {
            let decRad = Double(dec) * (.pi / 180.0)
            let cosD = cos(decRad), sinD = sin(decRad)
            var poly: [CGPoint] = []
            for raStep in 0...72 {
                let raRad = Double(raStep * 5) * (.pi / 180.0)
                if let p = matrix.projectEQJUnitVector(ux: cosD * cos(raRad), uy: cosD * sin(raRad), uz: sinD, margin: 120.0) {
                    poly.append(CGPoint(x: p.x, y: p.y))
                } else {
                    if poly.count >= 2 { lines.append(poly) }
                    poly.removeAll(keepingCapacity: true)
                }
            }
            if poly.count >= 2 { lines.append(poly) }
        }
        for raHour in stride(from: 0, to: 24, by: 2) {
            let raRad = Double(raHour * 15) * (.pi / 180.0)
            let cosR = cos(raRad), sinR = sin(raRad)
            var poly: [CGPoint] = []
            for dec in stride(from: -75, through: 75, by: 5) {
                let decRad = Double(dec) * (.pi / 180.0)
                let cosD = cos(decRad)
                if let p = matrix.projectEQJUnitVector(ux: cosD * cosR, uy: cosD * sinR, uz: sin(decRad), margin: 120.0) {
                    poly.append(CGPoint(x: p.x, y: p.y))
                } else {
                    if poly.count >= 2 { lines.append(poly) }
                    poly.removeAll(keepingCapacity: true)
                }
            }
            if poly.count >= 2 { lines.append(poly) }
        }
        return lines
    }

    private func buildEclipticLine(matrix: SkyProjectionMatrix) -> [CGPoint] {
        let eps = 23.4392911 * (.pi / 180.0)
        let cosEps = cos(eps), sinEps = sin(eps)
        var pts: [CGPoint] = []
        for lonDeg in stride(from: 0, through: 360, by: 4) {
            let lam = Double(lonDeg) * (.pi / 180.0)
            let ux = cos(lam)
            let uy = sin(lam) * cosEps
            let uz = sin(lam) * sinEps
            if let p = matrix.projectEQJUnitVector(ux: ux, uy: uy, uz: uz, margin: 120.0) {
                pts.append(CGPoint(x: p.x, y: p.y))
            }
        }
        return pts
    }

    // MARK: - Spatial Hit Testing

    public func hitTestTarget(at point: CGPoint, in scene: ProjectedSkyScene) -> CosmosTarget? {
        hitTestTarget(
            at: point,
            planets: scene.planets,
            iss: scene.issState,
            dsos: scene.dsos,
            stars: scene.stars,
            constellationLabels: scene.constellationLabels
        )
    }

    private func hitTestTarget(
        at point: CGPoint,
        planets: [ProjectedPlanet],
        iss: ProjectedIssState?,
        dsos: [ProjectedDSO],
        stars: [ProjectedPackedStar],
        constellationLabels: [ProjectedConstellationLabel]
    ) -> CosmosTarget? {
        if let iss = iss {
            let d = hypot(point.x - iss.screenX, point.y - iss.screenY)
            if d <= 22.0 {
                return issTarget(from: iss.position)
            }
        }

        for p in planets {
            let d = hypot(point.x - p.screenX, point.y - p.screenY)
            if d <= max(20.0, p.diameter * 0.85) {
                return target(for: p.body)
            }
        }

        for dso in dsos {
            let d = hypot(point.x - dso.screenX, point.y - dso.screenY)
            if d <= max(18.0, dso.radiusPx * 1.15) {
                return target(for: dso.dso)
            }
        }

        var bestStar: ProjectedPackedStar? = nil
        var bestScore = Double.greatestFiniteMagnitude
        for s in stars where s.magnitude <= 5.5 {
            let d = hypot(point.x - s.x, point.y - s.y)
            if d <= 18.0 {
                let weighted = d + Double(max(0.0, s.magnitude)) * 1.4
                if weighted < bestScore {
                    bestScore = weighted
                    bestStar = s
                }
            }
        }
        if let hitStar = bestStar {
            return targetForHip(hitStar.hip)
        }

        for lbl in constellationLabels {
            if abs(point.x - lbl.screenX) <= 36.0 && abs(point.y - lbl.screenY) <= 14.0 {
                return target(for: lbl.record)
            }
        }

        return nil
    }

    // MARK: - Search & Target Builders (100% English, Live-Ready)

    public var searchResults: [CosmosTarget] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tonightFeaturedTargets }

        var results: [CosmosTarget] = []

        if "iss international space station zarya".contains(q),
           let liveIss = liveService.currentIssPosition(latitude: observerLatitude, longitude: observerLongitude, at: simulationDate) {
            results.append(issTarget(from: liveIss))
        }

        for body in CelestialBody.allCases {
            if body.displayName.lowercased().contains(q) {
                results.append(target(for: body))
            }
        }

        for c in catalogService.constellations {
            if c.nameEn.lowercased().contains(q) || c.nameLa.lowercased().contains(q) || c.id.lowercased() == q {
                results.append(target(for: c))
            }
        }
        for ast in catalogService.asterisms {
            if ast.name.lowercased().contains(q) {
                results.append(
                    CosmosTarget(
                        id: "ast_\(ast.id)",
                        kind: .asterism(id: ast.id),
                        name: ast.name,
                        subtitle: "Asterism · \(ast.season ?? "All-Sky")",
                        category: "Asterism",
                        iconName: "sparkles",
                        rightAscensionHours: ast.centerRaHours,
                        declinationDegrees: ast.centerDecDeg,
                        lore: ast.description,
                        recommendedOptics: "Naked Eye"
                    )
                )
            }
        }

        for star in catalogService.brightStars {
            if star.name.lowercased().contains(q)
                || (star.designation?.lowercased().contains(q) == true)
                || star.constellation.lowercased() == q {
                results.append(target(for: star))
                if results.count >= 60 { break }
            }
        }

        for dso in catalogService.deepSkyObjects {
            if dso.id.lowercased().contains(q)
                || dso.name.lowercased().contains(q)
                || (dso.ngc?.lowercased().contains(q) == true)
                || dso.constellationCode.lowercased() == q {
                results.append(target(for: dso))
                if results.count >= 90 { break }
            }
        }

        for sh in catalogService.meteorShowers {
            if sh.name.lowercased().contains(q) {
                results.append(
                    CosmosTarget(
                        id: "meteor_\(sh.id)",
                        kind: .meteorShower(id: sh.id),
                        name: sh.name,
                        subtitle: "Peak \(sh.peakDateLabel) · ZHR \(sh.zhr)/hr",
                        category: "IAU Meteor Shower",
                        iconName: "sparkle.magnifyingglass",
                        rightAscensionHours: sh.radiantRaHours,
                        declinationDegrees: sh.radiantDecDeg,
                        constellationName: sh.constellation,
                        lore: "\(sh.description) Parent body: \(sh.parentBody) (\(Int(sh.velocityKmS)) km/s).",
                        recommendedOptics: "Naked Eye (Wide Dark Sky)"
                    )
                )
            }
        }

        return results
    }

    public var tonightFeaturedTargets: [CosmosTarget] {
        var items: [CosmosTarget] = []
        let obs3 = (latitude: observerLatitude, longitude: observerLongitude, elevation: 50.0)

        for body in [CelestialBody.moon, .jupiter, .saturn, .venus, .mars] {
            let c = astronomyService.coordinates(of: body, for: obs3, at: simulationDate)
            if c.altitudeDegrees > 5.0 {
                items.append(target(for: body))
            }
        }
        for dso in catalogService.deepSkyObjects.prefix(35) {
            let t = target(for: dso)
            if liveMetrics(for: t).altitudeDegrees > 18.0 {
                items.append(t)
                if items.count >= 12 { break }
            }
        }
        return items
    }

    public func issTarget(from pos: LiveSatellitePosition) -> CosmosTarget {
        CosmosTarget(
            id: "sat_25544",
            kind: .iss,
            name: "ISS (Zarya)",
            subtitle: String(format: "NORAD 25544 · Alt %.0f° · %@", pos.altitudeDegrees, pos.isSunlit ? "Sunlit" : "Umbra"),
            category: "Low-Earth Orbit Station",
            iconName: "satellite.fill",
            rightAscensionHours: 0,
            declinationDegrees: 0,
            visualMagnitude: pos.estimatedMagnitude,
            distanceDescription: "\(Int(pos.rangeKm.rounded())) km",
            lore: "Humanity's permanent orbital outpost traveling at 7.66 km/s (~420 km altitude), propagated live via analytical SGP4 orbital elements.",
            recommendedOptics: "Naked Eye / 7×50 Binoculars",
            accentColorHex: "#FF5E7E"
        )
    }

    public func target(for body: CelestialBody) -> CosmosTarget {
        let obs3 = (latitude: observerLatitude, longitude: observerLongitude, elevation: 50.0)
        let coords = astronomyService.coordinates(of: body, for: obs3, at: simulationDate)
        let lore: String
        switch body {
        case .sun:
            lore = "G2V main-sequence star at the center of the Solar System. Never observe directly through unfiltered optics."
        case .moon:
            let m = astronomyService.moonPhase(at: simulationDate, observer: (observerLatitude, observerLongitude))
            lore = "Earth's natural satellite in \(m.quarter.displayName) phase (\(m.illuminationPercent)% illuminated). Crater relief is sharpest along the lunar terminator."
        case .mercury:
            lore = "Innermost terrestrial planet showing crisp crescent phases near greatest eastern or western elongation."
        case .venus:
            lore = "Brilliant cloud-shrouded terrestrial world exhibiting dramatic Galilean phases in small telescopes."
        case .mars:
            lore = "The Red Planet, revealing polar ice caps and dark albedo plains such as Syrtis Major near opposition."
        case .jupiter:
            lore = "Solar System's largest gas giant. Zoom below 8° FOV to track Io, Europa, Ganymede, and Callisto in real time."
        case .saturn:
            let tilt = astronomyService.saturnRingTilt(at: simulationDate)
            lore = String(format: "Ringed gas giant with current ring plane inclination of %.1f° as seen from Earth, accompanied by bright moon Titan.", abs(tilt))
        case .uranus:
            lore = "Cyan-tinted ice giant at ~19 AU, visible as a mag 5.7 star-like point in binoculars under dark skies."
        case .neptune:
            lore = "Outermost major ice giant at ~30 AU (mag 7.8), resolvable as a deep-blue disc in telescopes."
        case .pluto:
            lore = "Kuiper Belt dwarf planet featuring the nitrogen-ice glacier Sputnik Planitia."
        }

        let distStr: String
        if body == .moon {
            let m = astronomyService.moonPhase(at: simulationDate, observer: (observerLatitude, observerLongitude))
            distStr = "\(Int((m.topocentricDistanceKm ?? m.distanceKm).rounded()).formatted()) km"
        } else {
            distStr = String(format: "%.2f AU", coords.distanceAU)
        }

        return CosmosTarget(
            id: "body_\(body.rawValue.lowercased())",
            kind: .body(body),
            name: body.displayName,
            subtitle: "\(body.displayName) · Mag \(String(format: "%.1f", coords.visualMagnitude)) · Alt \(Int(coords.altitudeDegrees.rounded()))°",
            category: "Solar System",
            iconName: body.sfSymbol,
            rightAscensionHours: coords.rightAscensionHours,
            declinationDegrees: coords.declinationDegrees,
            visualMagnitude: coords.visualMagnitude,
            distanceDescription: distStr,
            lore: lore,
            recommendedOptics: (body == .uranus || body == .neptune || body == .saturn || body == .jupiter) ? "Binoculars / Telescope" : "Naked Eye",
            accentColorHex: body.baseColorHex
        )
    }

    public func target(for star: BrightStarRecord) -> CosmosTarget {
        let rgb = PackedStar.ballesterosRGB(bv: star.colorIndexBV)
        let hex = String(format: "#%02X%02X%02X", Int(rgb.r * 255), Int(rgb.g * 255), Int(rgb.b * 255))
        let sub = [star.designation, star.constellation, String(format: "Mag %.2f", star.magnitude)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return CosmosTarget(
            id: "hip_\(star.hip)",
            kind: .star(hip: star.hip),
            name: star.name,
            subtitle: sub,
            category: "IAU / Hipparcos Star",
            iconName: "sparkle",
            rightAscensionHours: star.raHours,
            declinationDegrees: star.decDegrees,
            visualMagnitude: star.magnitude,
            constellationName: star.constellation,
            lore: String(format: "Cataloged in ESA Hipparcos (HIP %d) with color index B–V %+.2f.", star.hip, star.colorIndexBV),
            recommendedOptics: star.magnitude <= 5.5 ? "Naked Eye" : "Binoculars",
            accentColorHex: hex
        )
    }

    public func targetForHip(_ hip: Int) -> CosmosTarget? {
        if let bright = catalogService.brightStars.first(where: { $0.hip == hip }) {
            return target(for: bright)
        }
        guard let packed = catalogService.star(forHip: hip) else { return nil }
        let desig = catalogService.starDesignationsByHip[hip]
        let name = desig?.primaryLabel ?? "HIP \(hip)"
        let constName = desig?.constellation ?? constellationCodeByIndex[packed.constellationIndex] ?? "Field Star"
        let rgb = PackedStar.ballesterosRGB(bv: Double(packed.bv))
        let hex = String(format: "#%02X%02X%02X", Int(rgb.r * 255), Int(rgb.g * 255), Int(rgb.b * 255))
        return CosmosTarget(
            id: "hip_\(hip)",
            kind: .star(hip: hip),
            name: name,
            subtitle: String(format: "%@ · Mag %.2f", constName, packed.vMag),
            category: "Hipparcos Star",
            iconName: "sparkle",
            rightAscensionHours: Double(packed.raHours),
            declinationDegrees: Double(packed.decDegrees),
            visualMagnitude: Double(packed.vMag),
            constellationName: constName,
            lore: String(format: "ESA Hipparcos catalog entry HIP %d (V = %.2f, B–V = %+.2f).", hip, packed.vMag, packed.bv),
            recommendedOptics: packed.vMag <= 5.8 ? "Naked Eye" : "Binoculars",
            accentColorHex: hex
        )
    }

    public func target(for dso: DeepSkyObject) -> CosmosTarget {
        let distStr: String? = dso.distanceLightYears.map { ly in
            if ly >= 1_000_000 {
                return String(format: "%.2f Mly", ly / 1_000_000.0)
            } else if ly >= 1_000 {
                return String(format: "%.1f kly", ly / 1_000.0)
            }
            return "\(Int(ly.rounded())) ly"
        }
        return CosmosTarget(
            id: "dso_\(dso.id)",
            kind: .dso(id: dso.id),
            name: "\(dso.id) · \(dso.name)",
            subtitle: "\(dso.type.displayName) · \(dso.constellationCode) · Mag \(String(format: "%.1f", dso.visualMagnitude))",
            category: "\(dso.catalog) Deep-Sky Object",
            iconName: dso.type.sfSymbol,
            rightAscensionHours: dso.rightAscensionHours,
            declinationDegrees: dso.declinationDegrees,
            visualMagnitude: dso.visualMagnitude,
            distanceDescription: distStr,
            constellationName: dso.constellationCode,
            lore: dso.description,
            recommendedOptics: dso.recommendedOptics,
            accentColorHex: "#FF6EC7",
            thumbnailRelativePath: dso.thumbnail
        )
    }

    public func target(for constellation: ConstellationRecord) -> CosmosTarget {
        CosmosTarget(
            id: "const_\(constellation.id)",
            kind: .constellation(id: constellation.id),
            name: constellation.nameEn,
            subtitle: "\(constellation.nameLa) (\(constellation.code)) · \(constellation.segments.count) star segments",
            category: "IAU Constellation",
            iconName: "point.3.connected.trianglepath.dotted",
            rightAscensionHours: constellation.centerRaHours,
            declinationDegrees: constellation.centerDecDeg,
            constellationName: constellation.code,
            lore: constellation.lore,
            recommendedOptics: "Naked Eye"
        )
    }
}
