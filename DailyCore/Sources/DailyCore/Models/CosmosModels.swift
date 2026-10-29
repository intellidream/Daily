import Foundation

// MARK: - Telemetry Provenance (Zero Fabricated Numbers)

public enum TelemetryProvenance: Codable, Equatable, Sendable {
    case live(fetchedAt: Date)
    case cached(fetchedAt: Date, ageMinutes: Int)
    case offlineCalculated(epochAgeHours: Int?)
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    public var badgeLabel: String {
        switch self {
        case .live:
            return "Live"
        case .cached(_, let ageMinutes):
            if ageMinutes < 60 {
                return "Cached (\(max(1, ageMinutes))m)"
            }
            return "Cached (\(ageMinutes / 60)h)"
        case .offlineCalculated(let ageHours):
            if let h = ageHours {
                return h < 24 ? "Offline OMM (\(h)h)" : "Offline OMM (\(h / 24)d)"
            }
            return "Offline Ephemeris"
        case .unavailable:
            return "Unavailable"
        }
    }
}

// MARK: - Celestial Bodies

public enum CelestialBody: String, Codable, CaseIterable, Sendable, Identifiable {
    case sun = "Sun"
    case moon = "Moon"
    case mercury = "Mercury"
    case venus = "Venus"
    case mars = "Mars"
    case jupiter = "Jupiter"
    case saturn = "Saturn"
    case uranus = "Uranus"
    case neptune = "Neptune"
    case pluto = "Pluto"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var sfSymbol: String {
        switch self {
        case .sun: return "sun.max.fill"
        case .moon: return "moon.fill"
        case .mercury: return "circle.fill"
        case .venus: return "sparkles"
        case .mars: return "circle.fill"
        case .jupiter: return "circle.grid.2x1.fill"
        case .saturn: return "circle.circle.fill"
        case .uranus: return "circle.dashed"
        case .neptune: return "circle.dotted"
        case .pluto: return "smallcircle.filled.circle"
        }
    }

    public var baseColorHex: String {
        switch self {
        case .sun: return "#FFD600"
        case .moon: return "#E8EAED"
        case .mercury: return "#B0BEC5"
        case .venus: return "#FFF9C4"
        case .mars: return "#FF6E40"
        case .jupiter: return "#E6D5B8"
        case .saturn: return "#FFE082"
        case .uranus: return "#80DEEA"
        case .neptune: return "#42A5F5"
        case .pluto: return "#CFD8DC"
        }
    }
}

// MARK: - Celestial Coordinates & Rise/Transit/Set

public struct CelestialCoordinates: Codable, Equatable, Sendable {
    public let azimuthDegrees: Double
    public let altitudeDegrees: Double
    public let rightAscensionHours: Double
    public let declinationDegrees: Double
    public let distanceAU: Double
    public let visualMagnitude: Double
    public let illuminatedFraction: Double
    public let brightLimbAngleDegrees: Double
    public let angularDiameterArcsec: Double
    public let isVisible: Bool

    public init(
        azimuthDegrees: Double,
        altitudeDegrees: Double,
        rightAscensionHours: Double,
        declinationDegrees: Double,
        distanceAU: Double,
        visualMagnitude: Double,
        illuminatedFraction: Double = 1.0,
        brightLimbAngleDegrees: Double = 0.0,
        angularDiameterArcsec: Double = 0.0
    ) {
        self.azimuthDegrees = azimuthDegrees
        self.altitudeDegrees = altitudeDegrees
        self.rightAscensionHours = rightAscensionHours
        self.declinationDegrees = declinationDegrees
        self.distanceAU = distanceAU
        self.visualMagnitude = visualMagnitude
        self.illuminatedFraction = illuminatedFraction
        self.brightLimbAngleDegrees = brightLimbAngleDegrees
        self.angularDiameterArcsec = angularDiameterArcsec
        self.isVisible = altitudeDegrees > 0.0
    }

    public var compassDirection: String {
        Self.compassPoint(for: azimuthDegrees)
    }

    public static func compassPoint(for azimuthDegrees: Double) -> String {
        guard azimuthDegrees.isFinite else { return "N" }
        let normalized = (azimuthDegrees.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int(round(normalized / 22.5)) % 16
        return directions[index]
    }
}

public struct BodyRiseTransitSet: Codable, Equatable, Sendable {
    public let rise: Date?
    public let transit: Date?
    public let set: Date?
    public let transitAltitudeDegrees: Double?

    public init(rise: Date?, transit: Date?, set: Date?, transitAltitudeDegrees: Double? = nil) {
        self.rise = rise
        self.transit = transit
        self.set = set
        self.transitAltitudeDegrees = transitAltitudeDegrees
    }
}

// MARK: - Moon Phase & Terminator

public enum MoonPhaseQuarter: String, Codable, CaseIterable, Sendable {
    case newMoon = "New Moon"
    case waxingCrescent = "Waxing Crescent"
    case firstQuarter = "First Quarter"
    case waxingGibbous = "Waxing Gibbous"
    case fullMoon = "Full Moon"
    case waningGibbous = "Waning Gibbous"
    case thirdQuarter = "Third Quarter"
    case waningCrescent = "Waning Crescent"

    public var displayName: String { rawValue }

    public var sfSymbol: String {
        switch self {
        case .newMoon: return "moonphase.new.moon"
        case .waxingCrescent: return "moonphase.waxing.crescent"
        case .firstQuarter: return "moonphase.first.quarter"
        case .waxingGibbous: return "moonphase.waxing.gibbous"
        case .fullMoon: return "moonphase.full.moon"
        case .waningGibbous: return "moonphase.waning.gibbous"
        case .thirdQuarter: return "moonphase.last.quarter"
        case .waningCrescent: return "moonphase.waning.crescent"
        }
    }
}

public struct MoonPhaseInfo: Codable, Equatable, Sendable {
    public let phaseAngleDegrees: Double // 0 = New, 90 = First Q, 180 = Full, 270 = Third Q
    public let illuminatedFraction: Double // 0.0 to 1.0
    public let quarter: MoonPhaseQuarter
    public let ageDays: Double // 0 to 29.53
    public let isWaxing: Bool
    public let distanceKm: Double // Geocentric Earth-Moon distance (~356,500 - 406,700 km)
    public let topocentricDistanceKm: Double?
    public let brightLimbAngleDegrees: Double // Local zenith-referenced illuminated limb angle

    public init(
        phaseAngleDegrees: Double,
        illuminatedFraction: Double,
        quarter: MoonPhaseQuarter,
        ageDays: Double,
        isWaxing: Bool,
        distanceKm: Double,
        topocentricDistanceKm: Double? = nil,
        brightLimbAngleDegrees: Double = 0.0
    ) {
        self.phaseAngleDegrees = phaseAngleDegrees
        self.illuminatedFraction = illuminatedFraction
        self.quarter = quarter
        self.ageDays = ageDays
        self.isWaxing = isWaxing
        self.distanceKm = distanceKm
        self.topocentricDistanceKm = topocentricDistanceKm
        self.brightLimbAngleDegrees = brightLimbAngleDegrees
    }

    public var illuminationPercent: Int {
        Int(round(illuminatedFraction * 100.0))
    }
}

// MARK: - Sun, Twilight & Circadian Lunar Bio-Context

public struct SunTimes: Codable, Equatable, Sendable {
    public let dawnAstronomical: Date?
    public let dawnNautical: Date?
    public let dawnCivil: Date?
    public let sunrise: Date?
    public let solarNoon: Date?
    public let sunset: Date?
    public let duskCivil: Date?
    public let duskNautical: Date?
    public let duskAstronomical: Date?

    public init(
        dawnAstronomical: Date?,
        dawnNautical: Date?,
        dawnCivil: Date?,
        sunrise: Date?,
        solarNoon: Date?,
        sunset: Date?,
        duskCivil: Date?,
        duskNautical: Date?,
        duskAstronomical: Date?
    ) {
        self.dawnAstronomical = dawnAstronomical
        self.dawnNautical = dawnNautical
        self.dawnCivil = dawnCivil
        self.sunrise = sunrise
        self.solarNoon = solarNoon
        self.sunset = sunset
        self.duskCivil = duskCivil
        self.duskNautical = duskNautical
        self.duskAstronomical = duskAstronomical
    }
}

public struct CircadianSkyContext: Codable, Equatable, Sendable {
    public let trueDarknessOnset: Date?
    public let naturalMoonlightLux: Double
    public let summary: String

    public init(trueDarknessOnset: Date?, naturalMoonlightLux: Double, summary: String) {
        self.trueDarknessOnset = trueDarknessOnset
        self.naturalMoonlightLux = naturalMoonlightLux
        self.summary = summary
    }
}

// MARK: - Galilean Moons & Saturn Rings

public struct MoonVector2D: Codable, Equatable, Sendable {
    public let name: String
    public let xRadius: Double // Rightward sky-plane offset in Jovian equatorial radii
    public let yRadius: Double // Upward sky-plane offset in Jovian equatorial radii
    public let depthRadius: Double // Line-of-sight offset (< 0 = closer to Earth, > 0 = behind)
    public let isFrontOfPlanet: Bool
    public let isTransiting: Bool
    public let isOcculted: Bool

    public init(
        name: String = "",
        xRadius: Double,
        yRadius: Double,
        depthRadius: Double = 0.0,
        isFrontOfPlanet: Bool
    ) {
        self.name = name
        self.xRadius = xRadius
        self.yRadius = yRadius
        self.depthRadius = depthRadius
        self.isFrontOfPlanet = isFrontOfPlanet
        let insideDisc = (xRadius * xRadius + yRadius * yRadius) < 1.0
        self.isTransiting = insideDisc && isFrontOfPlanet
        self.isOcculted = insideDisc && !isFrontOfPlanet
    }
}

public struct JupiterMoonsState: Codable, Equatable, Sendable {
    public let io: MoonVector2D
    public let europa: MoonVector2D
    public let ganymede: MoonVector2D
    public let callisto: MoonVector2D

    public var all: [MoonVector2D] { [io, europa, ganymede, callisto] }

    public init(io: MoonVector2D, europa: MoonVector2D, ganymede: MoonVector2D, callisto: MoonVector2D) {
        self.io = io
        self.europa = europa
        self.ganymede = ganymede
        self.callisto = callisto
    }
}

// MARK: - Stargazing Quality & Intelligence

public enum StargazingQuality: String, Codable, Sendable {
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case pristine = "Pristine"

    public var displayName: String { rawValue }

    public var colorHex: String {
        switch self {
        case .poor: return "#FF5252"
        case .fair: return "#FFD740"
        case .good: return "#69F0AE"
        case .pristine: return "#00E5FF"
        }
    }
}

public struct StargazingConditions: Codable, Equatable, Sendable {
    public let score: Int // 0 to 100
    public let quality: StargazingQuality
    public let bortleClass: Int // 1 to 9
    public let limitingMagnitude: Double
    public let cloudCoverTotalPercent: Int?
    public let cloudCoverLowPercent: Int?
    public let cloudCoverMidPercent: Int?
    public let cloudCoverHighPercent: Int?
    public let moonIlluminationPercent: Int
    public let isMoonAboveHorizon: Bool
    public let seeingArcseconds: Double?
    public let transparencyLabel: String?
    public let dewPointDepressionCelsius: Double?
    public let bestWindowDescription: String?
    public let narrativeAdvice: String
    public let provenance: TelemetryProvenance

    public init(
        score: Int,
        quality: StargazingQuality,
        bortleClass: Int,
        limitingMagnitude: Double,
        cloudCoverTotalPercent: Int?,
        cloudCoverLowPercent: Int?,
        cloudCoverMidPercent: Int?,
        cloudCoverHighPercent: Int?,
        moonIlluminationPercent: Int,
        isMoonAboveHorizon: Bool,
        seeingArcseconds: Double?,
        transparencyLabel: String? = nil,
        dewPointDepressionCelsius: Double?,
        bestWindowDescription: String?,
        narrativeAdvice: String,
        provenance: TelemetryProvenance = .offlineCalculated(epochAgeHours: nil)
    ) {
        self.score = max(0, min(100, score))
        self.quality = quality
        self.bortleClass = max(1, min(9, bortleClass))
        self.limitingMagnitude = limitingMagnitude
        self.cloudCoverTotalPercent = cloudCoverTotalPercent
        self.cloudCoverLowPercent = cloudCoverLowPercent
        self.cloudCoverMidPercent = cloudCoverMidPercent
        self.cloudCoverHighPercent = cloudCoverHighPercent
        self.moonIlluminationPercent = moonIlluminationPercent
        self.isMoonAboveHorizon = isMoonAboveHorizon
        self.seeingArcseconds = seeingArcseconds
        self.transparencyLabel = transparencyLabel
        self.dewPointDepressionCelsius = dewPointDepressionCelsius
        self.bestWindowDescription = bestWindowDescription
        self.narrativeAdvice = narrativeAdvice
        self.provenance = provenance
    }
}

// MARK: - Satellite Passes & Live Tracking (Real SGP4)

public struct SatelliteTrajectorySample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let azimuthDegrees: Double
    public let altitudeDegrees: Double
    public let isSunlit: Bool

    public init(timestamp: Date, azimuthDegrees: Double, altitudeDegrees: Double, isSunlit: Bool) {
        self.timestamp = timestamp
        self.azimuthDegrees = azimuthDegrees
        self.altitudeDegrees = altitudeDegrees
        self.isSunlit = isSunlit
    }
}

public struct SatellitePass: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let satelliteName: String
    public let noradCatalogNumber: Int
    public let startTime: Date
    public let maxAltitudeTime: Date
    public let endTime: Date
    public let maxAltitudeDegrees: Double
    public let startAzimuthDegrees: Double
    public let maxAzimuthDegrees: Double
    public let endAzimuthDegrees: Double
    public let startCompass: String
    public let endCompass: String
    public let peakMagnitude: Double
    public let isSunlit: Bool
    public let trajectory: [SatelliteTrajectorySample]

    public init(
        id: String,
        satelliteName: String,
        noradCatalogNumber: Int,
        startTime: Date,
        maxAltitudeTime: Date,
        endTime: Date,
        maxAltitudeDegrees: Double,
        startAzimuthDegrees: Double = 0,
        maxAzimuthDegrees: Double = 0,
        endAzimuthDegrees: Double = 0,
        startCompass: String,
        endCompass: String,
        peakMagnitude: Double,
        isSunlit: Bool,
        trajectory: [SatelliteTrajectorySample] = []
    ) {
        self.id = id
        self.satelliteName = satelliteName
        self.noradCatalogNumber = noradCatalogNumber
        self.startTime = startTime
        self.maxAltitudeTime = maxAltitudeTime
        self.endTime = endTime
        self.maxAltitudeDegrees = maxAltitudeDegrees
        self.startAzimuthDegrees = startAzimuthDegrees
        self.maxAzimuthDegrees = maxAzimuthDegrees
        self.endAzimuthDegrees = endAzimuthDegrees
        self.startCompass = startCompass
        self.endCompass = endCompass
        self.peakMagnitude = peakMagnitude
        self.isSunlit = isSunlit
        self.trajectory = trajectory
    }

    public var durationMinutes: Int {
        max(1, Int(round(endTime.timeIntervalSince(startTime) / 60.0)))
    }
}

public struct LiveSatellitePosition: Codable, Equatable, Sendable {
    public let satelliteName: String
    public let noradCatalogNumber: Int
    public let timestamp: Date
    public let azimuthDegrees: Double
    public let altitudeDegrees: Double
    public let rangeKm: Double
    public let orbitalAltitudeKm: Double
    public let subSatelliteLatitude: Double
    public let subSatelliteLongitude: Double
    public let isSunlit: Bool
    public let estimatedMagnitude: Double

    public init(
        satelliteName: String,
        noradCatalogNumber: Int,
        timestamp: Date,
        azimuthDegrees: Double,
        altitudeDegrees: Double,
        rangeKm: Double,
        orbitalAltitudeKm: Double,
        subSatelliteLatitude: Double,
        subSatelliteLongitude: Double,
        isSunlit: Bool,
        estimatedMagnitude: Double
    ) {
        self.satelliteName = satelliteName
        self.noradCatalogNumber = noradCatalogNumber
        self.timestamp = timestamp
        self.azimuthDegrees = azimuthDegrees
        self.altitudeDegrees = altitudeDegrees
        self.rangeKm = rangeKm
        self.orbitalAltitudeKm = orbitalAltitudeKm
        self.subSatelliteLatitude = subSatelliteLatitude
        self.subSatelliteLongitude = subSatelliteLongitude
        self.isSunlit = isSunlit
        self.estimatedMagnitude = estimatedMagnitude
    }
}

// MARK: - Space Weather & Aurora

public struct SpaceWeatherReport: Codable, Equatable, Sendable {
    public let kpIndex: Double? // nil when unavailable
    public let btTotalFieldNt: Double?
    public let bzMagneticFieldNt: Double? // negative = southward (aurora favorable)
    public let solarWindSpeedKmS: Double?
    public let solarWindDensityCm3: Double?
    public let ovationProbabilityPercent: Int?
    public let isAuroraAlertActive: Bool
    public let statusMessage: String
    public let provenance: TelemetryProvenance

    public init(
        kpIndex: Double?,
        btTotalFieldNt: Double? = nil,
        bzMagneticFieldNt: Double?,
        solarWindSpeedKmS: Double?,
        solarWindDensityCm3: Double? = nil,
        ovationProbabilityPercent: Int?,
        isAuroraAlertActive: Bool,
        statusMessage: String,
        provenance: TelemetryProvenance = .unavailable(reason: "Not yet fetched")
    ) {
        self.kpIndex = kpIndex
        self.btTotalFieldNt = btTotalFieldNt
        self.bzMagneticFieldNt = bzMagneticFieldNt
        self.solarWindSpeedKmS = solarWindSpeedKmS
        self.solarWindDensityCm3 = solarWindDensityCm3
        self.ovationProbabilityPercent = ovationProbabilityPercent
        self.isAuroraAlertActive = isAuroraAlertActive
        self.statusMessage = statusMessage
        self.provenance = provenance
    }
}

// MARK: - Canonical Offline Catalog Types (15,544 Stars, 88 IAU Constellations, 219 DSOs, 22 Showers)

public struct PackedStar: Equatable, Sendable {
    public let hip: Int
    public let ux: Float // J2000 unit vector X
    public let uy: Float // J2000 unit vector Y
    public let uz: Float // J2000 unit vector Z
    public let raHours: Float
    public let decDegrees: Float
    public let vMag: Float
    public let bv: Float
    public let constellationIndex: UInt16

    public init(
        hip: Int,
        ux: Float,
        uy: Float,
        uz: Float,
        raHours: Float,
        decDegrees: Float,
        vMag: Float,
        bv: Float,
        constellationIndex: UInt16
    ) {
        self.hip = hip
        self.ux = ux
        self.uy = uy
        self.uz = uz
        self.raHours = raHours
        self.decDegrees = decDegrees
        self.vMag = vMag
        self.bv = bv
        self.constellationIndex = constellationIndex
    }

    /// Ballesteros (2012) B-V color index -> effective temperature -> normalized sRGB tuple (0...1).
    public var rgbComponents: (r: Double, g: Double, b: Double) {
        Self.ballesterosRGB(bv: Double(bv))
    }

    public static func ballesterosRGB(bv: Double) -> (r: Double, g: Double, b: Double) {
        let clamped = max(-0.40, min(2.00, bv))
        let t = 4600.0 * (1.0 / (0.92 * clamped + 1.7) + 1.0 / (0.92 * clamped + 0.62))
        let tk = t / 100.0

        let r: Double
        let g: Double
        let b: Double

        if tk <= 66.0 {
            r = 1.0
            let gv = 0.3900815787690196 * log(max(1.0, tk)) - 0.6318414437886275
            g = max(0.0, min(1.0, gv))
            if tk <= 19.0 {
                b = 0.0
            } else {
                let bv2 = 0.5432067891101961 * log(max(1.0, tk - 10.0)) - 1.19625408914
                b = max(0.0, min(1.0, bv2))
            }
        } else {
            let rv = 1.292936186062745 * pow(tk - 60.0, -0.1332047592)
            let gv = 1.129890860895294 * pow(tk - 60.0, -0.0755148492)
            r = max(0.0, min(1.0, rv))
            g = max(0.0, min(1.0, gv))
            b = 1.0
        }
        return (r, g, b)
    }
}

public struct StarDesignation: Codable, Equatable, Sendable {
    public let hip: Int
    public let name: String?
    public let bayer: String?
    public let flam: String?
    public let hd: String?
    public let constellation: String?

    public var primaryLabel: String {
        if let name = name, !name.isEmpty { return name }
        if let bayer = bayer, !bayer.isEmpty, !bayer.contains("undefined"), let c = constellation {
            return "\(bayer) \(c)"
        }
        if let flam = flam, !flam.isEmpty, let c = constellation { return "\(flam) \(c)" }
        return "HIP \(hip)"
    }
}

public struct BrightStarRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "HIP-\(hip)" }
    public let hip: Int
    public let name: String
    public let designation: String?
    public let constellation: String
    public let raHours: Double
    public let decDegrees: Double
    public let magnitude: Double
    public let colorIndexBV: Double

    public init(
        hip: Int,
        name: String,
        designation: String? = nil,
        constellation: String,
        raHours: Double,
        decDegrees: Double,
        magnitude: Double,
        colorIndexBV: Double
    ) {
        self.hip = hip
        self.name = name
        self.designation = designation
        self.constellation = constellation
        self.raHours = raHours
        self.decDegrees = decDegrees
        self.magnitude = magnitude
        self.colorIndexBV = colorIndexBV
    }
}

public struct ConstellationRecord: Codable, Identifiable, Equatable, Sendable {
    public let index: Int
    public let id: String // Uppercase 3-letter IAU code e.g. "ORI"
    public let code: String // Mixed-case IAU abbreviation e.g. "Ori"
    public let nameLa: String
    public let nameEn: String
    public let genitive: String
    public let centerRaHours: Double
    public let centerDecDeg: Double
    public let rank: Int
    public let lore: String
    public let segments: [[Int]] // Explicit [hipA, hipB] pairs supporting branched stick figures

    public var centerRa: Double { centerRaHours }
    public var centerDec: Double { centerDecDeg }

    public init(
        index: Int,
        id: String,
        code: String,
        nameLa: String,
        nameEn: String,
        genitive: String,
        centerRaHours: Double,
        centerDecDeg: Double,
        rank: Int,
        lore: String,
        segments: [[Int]]
    ) {
        self.index = index
        self.id = id
        self.code = code
        self.nameLa = nameLa
        self.nameEn = nameEn
        self.genitive = genitive
        self.centerRaHours = centerRaHours
        self.centerDecDeg = centerDecDeg
        self.rank = rank
        self.lore = lore
        self.segments = segments
    }
}

public struct ConstellationBorderArc: Codable, Equatable, Sendable {
    public let ids: [String]
    public let points: [[Double]] // [[raHours, decDeg], ...]
}

public struct AsterismRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let season: String?
    public let description: String
    public let centerRaHours: Double
    public let centerDecDeg: Double
    public let segments: [[Int]] // [hipA, hipB] pairs
}

public enum DSOType: String, Codable, Sendable {
    case galaxy = "Galaxy"
    case emissionNebula = "Emission Nebula"
    case reflectionNebula = "Reflection Nebula"
    case planetaryNebula = "Planetary Nebula"
    case darkNebula = "Dark Nebula"
    case globularCluster = "Globular Cluster"
    case openCluster = "Open Cluster"
    case supernovaRemnant = "Supernova Remnant"
    case other = "Deep-Sky Object"

    public var displayName: String { rawValue }

    public var sfSymbol: String {
        switch self {
        case .galaxy: return "tornado"
        case .emissionNebula, .reflectionNebula, .darkNebula: return "cloud.fog.fill"
        case .planetaryNebula: return "circle.circle"
        case .globularCluster: return "circle.grid.3x3.fill"
        case .openCluster: return "sparkles"
        case .supernovaRemnant: return "sun.dust.fill"
        case .other: return "sparkle"
        }
    }

    public static func fromCatalogCategory(_ raw: String, typeCode: String? = nil) -> DSOType {
        if let code = typeCode?.uppercased() {
            switch code {
            case "G": return .galaxy
            case "BN", "EN": return .emissionNebula
            case "RN": return .reflectionNebula
            case "PN": return .planetaryNebula
            case "DN": return .darkNebula
            case "GC": return .globularCluster
            case "OC": return .openCluster
            case "SNR": return .supernovaRemnant
            default: break
            }
        }
        let low = raw.lowercased()
        if low.contains("galaxy") { return .galaxy }
        if low.contains("planetary") { return .planetaryNebula }
        if low.contains("reflection") { return .reflectionNebula }
        if low.contains("dark") { return .darkNebula }
        if low.contains("supernova") { return .supernovaRemnant }
        if low.contains("globular") { return .globularCluster }
        if low.contains("open") || low.contains("cluster") && !low.contains("nebula") { return .openCluster }
        if low.contains("nebula") { return .emissionNebula }
        return .other
    }
}

public struct DeepSkyObject: Codable, Identifiable, Equatable, Sendable {
    public let id: String // e.g. "M31", "C65"
    public let catalog: String // "Messier" or "Caldwell"
    public let name: String
    public let ngc: String?
    public let type: DSOType
    public let morphType: String
    public let constellationCode: String
    public let rightAscensionHours: Double
    public let declinationDegrees: Double
    public let ux: Float
    public let uy: Float
    public let uz: Float
    public let visualMagnitude: Double
    public let surfaceBrightness: Double?
    public let majorAxisArcmin: Double
    public let minorAxisArcmin: Double
    public let positionAngleDeg: Double
    public let distanceLightYears: Double?
    public let recommendedOptics: String
    public let thumbnail: String?
    public let description: String

    public init(
        id: String,
        catalog: String = "Messier",
        name: String,
        ngc: String? = nil,
        type: DSOType,
        morphType: String = "",
        constellationCode: String,
        rightAscensionHours: Double,
        declinationDegrees: Double,
        visualMagnitude: Double,
        surfaceBrightness: Double? = nil,
        majorAxisArcmin: Double = 10.0,
        minorAxisArcmin: Double = 10.0,
        positionAngleDeg: Double = 0.0,
        distanceLightYears: Double? = nil,
        recommendedOptics: String,
        thumbnail: String? = nil,
        description: String
    ) {
        self.id = id
        self.catalog = catalog
        self.name = name
        self.ngc = ngc
        self.type = type
        self.morphType = morphType
        self.constellationCode = constellationCode
        self.rightAscensionHours = rightAscensionHours
        self.declinationDegrees = declinationDegrees
        let raRad = rightAscensionHours * 15.0 * (.pi / 180.0)
        let decRad = declinationDegrees * (.pi / 180.0)
        self.ux = Float(cos(decRad) * cos(raRad))
        self.uy = Float(cos(decRad) * sin(raRad))
        self.uz = Float(sin(decRad))
        self.visualMagnitude = visualMagnitude
        self.surfaceBrightness = surfaceBrightness
        self.majorAxisArcmin = majorAxisArcmin
        self.minorAxisArcmin = minorAxisArcmin
        self.positionAngleDeg = positionAngleDeg
        self.distanceLightYears = distanceLightYears
        self.recommendedOptics = recommendedOptics
        self.thumbnail = thumbnail
        self.description = description
    }
}

public struct MeteorShowerRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let constellation: String
    public let startMonth: Int
    public let startDay: Int
    public let endMonth: Int
    public let endDay: Int
    public let peakMonth: Int
    public let peakDay: Int
    public let peakSolarLongitudeDeg: Double
    public let radiantRaHours: Double
    public let radiantDecDeg: Double
    public let driftRaPerDay: Double
    public let driftDecPerDay: Double
    public let zhr: Int
    public let velocityKmS: Double
    public let parentBody: String
    public let description: String

    public var peakDateLabel: String {
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = (peakMonth >= 1 && peakMonth <= 12) ? months[peakMonth] : "Peak"
        return "\(m) \(peakDay)"
    }

    public func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        let cur = m * 100 + d
        let start = startMonth * 100 + startDay
        let end = endMonth * 100 + endDay
        if start <= end {
            return cur >= start && cur <= end
        } else {
            // Year-boundary shower (e.g., Quadrantids Dec 28 - Jan 12)
            return cur >= start || cur <= end
        }
    }
}

public struct SkyUnitVec3: Equatable, Sendable {
    public let x: Float
    public let y: Float
    public let z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct MilkyWayIsophoteLayer: Equatable, Sendable {
    public let level: Int // 1 (outer faintest) ... 5 (brightest galactic core)
    public let rings: [[SkyUnitVec3]] // Precomputed J2000 unit vectors

    public init(level: Int, rings: [[SkyUnitVec3]]) {
        self.level = level
        self.rings = rings
    }
}

// MARK: - Zero-Trig Frame Projection Matrix (120Hz Path)

public struct SkyProjectionMatrix: Equatable, Sendable {
    // Composed EQJ -> CAM 3x3 matrix (row-major for fast dot products)
    public let m00: Double, m01: Double, m02: Double
    public let m10: Double, m11: Double, m12: Double
    public let m20: Double, m21: Double, m22: Double

    // HOR (NWZ) -> CAM 3x3 basis vectors: r = camera right, u = camera up, f = camera forward
    public let rx: Double, ry: Double, rz: Double
    public let ux: Double, uy: Double, uz: Double
    public let fx: Double, fy: Double, fz: Double

    // EQJ -> HOR (NWZ) 3x3 matrix (row-major)
    public let h00: Double, h01: Double, h02: Double
    public let h10: Double, h11: Double, h12: Double
    public let h20: Double, h21: Double, h22: Double

    public let viewportWidth: Double
    public let viewportHeight: Double
    public let halfWidth: Double
    public let halfHeight: Double
    public let scale: Double
    public let fovDegrees: Double

    @inline(__always)
    public func projectEQJUnitVector(ux vx: Double, uy vy: Double, uz vz: Double, margin: Double = 60.0) -> (x: Double, y: Double, cz: Double, isVisible: Bool)? {
        let cx = m00 * vx + m01 * vy + m02 * vz
        let cy = m10 * vx + m11 * vy + m12 * vz
        let cz = m20 * vx + m21 * vy + m22 * vz
        let denom = 1.0 + cz
        guard denom >= 0.08 else { return nil }
        let inv = scale / denom
        let sx = halfWidth + cx * inv
        let sy = halfHeight - cy * inv
        let vis = (sx >= -margin && sx <= viewportWidth + margin && sy >= -margin && sy <= viewportHeight + margin)
        return (sx, sy, cz, vis)
    }

    @inline(__always)
    public func projectHorizontal(azimuthDegrees: Double, altitudeDegrees: Double, margin: Double = 60.0) -> (x: Double, y: Double, cz: Double, isVisible: Bool)? {
        let az = azimuthDegrees * (.pi / 180.0)
        let alt = altitudeDegrees * (.pi / 180.0)
        let cosAlt = cos(alt)
        let hx = cosAlt * cos(az)
        let hy = -cosAlt * sin(az)
        let hz = sin(alt)
        let cx = rx * hx + ry * hy + rz * hz
        let cy = ux * hx + uy * hy + uz * hz
        let cz = fx * hx + fy * hy + fz * hz
        let denom = 1.0 + cz
        guard denom >= 0.08 else { return nil }
        let inv = scale / denom
        let sx = halfWidth + cx * inv
        let sy = halfHeight - cy * inv
        let vis = (sx >= -margin && sx <= viewportWidth + margin && sy >= -margin && sy <= viewportHeight + margin)
        return (sx, sy, cz, vis)
    }

    /// Unprojects a 2D screen tap/hover coordinate back to topocentric (Azimuth, Altitude) degrees.
    public func unprojectToHorizontal(screenX: Double, screenY: Double) -> (azimuthDegrees: Double, altitudeDegrees: Double)? {
        guard scale > 1e-6 else { return nil }
        let xp = (screenX - halfWidth) / scale
        let yp = (halfHeight - screenY) / scale
        let r2 = xp * xp + yp * yp
        let inv = 1.0 / (1.0 + r2)
        let cx = 2.0 * xp * inv
        let cy = 2.0 * yp * inv
        let cz = (1.0 - r2) * inv

        // Transform from CAM back to NWZ horizontal: h = cx*r + cy*u + cz*f
        let hx = cx * rx + cy * ux + cz * fx
        let hy = cx * ry + cy * uy + cz * fy
        let hz = cx * rz + cy * uz + cz * fz
        let altDeg = asin(max(-1.0, min(1.0, hz))) * (180.0 / .pi)
        let azDeg = (atan2(-hy, hx) * (180.0 / .pi) + 360.0).truncatingRemainder(dividingBy: 360.0)
        return (azDeg, altDeg)
    }
}

// MARK: - Synced Bookmarks & Sky Observations (Supabase + TagDoS #sky)

public struct CosmosBookmark: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var userId: String?
    public let objectId: String
    public let objectName: String
    public let category: String
    public let raHours: Double?
    public let decDeg: Double?
    public let magnitude: Double?
    public let constellation: String?
    public var notes: String
    public let createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, category, magnitude, constellation, notes
        case userId = "user_id"
        case objectId = "object_id"
        case objectName = "object_name"
        case raHours = "ra_hours"
        case decDeg = "dec_deg"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID = UUID(),
        userId: String? = nil,
        objectId: String,
        objectName: String,
        category: String,
        raHours: Double? = nil,
        decDeg: Double? = nil,
        magnitude: Double? = nil,
        constellation: String? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.objectId = objectId
        self.objectName = objectName
        self.category = category
        self.raHours = raHours
        self.decDeg = decDeg
        self.magnitude = magnitude
        self.constellation = constellation
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CosmosObservation: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var userId: String?
    public let objectId: String
    public let objectName: String
    public let category: String
    public let observedAt: Date
    public let latitude: Double
    public let longitude: Double
    public let locationName: String
    public let azimuthDeg: Double?
    public let altitudeDeg: Double?
    public let bortleClass: Int?
    public let stargazingScore: Int?
    public let optics: String
    public var notes: String
    public var tagdosNoteId: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, category, latitude, longitude, optics, notes
        case userId = "user_id"
        case objectId = "object_id"
        case objectName = "object_name"
        case observedAt = "observed_at"
        case locationName = "location_name"
        case azimuthDeg = "azimuth_deg"
        case altitudeDeg = "altitude_deg"
        case bortleClass = "bortle_class"
        case stargazingScore = "stargazing_score"
        case tagdosNoteId = "tagdos_note_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID = UUID(),
        userId: String? = nil,
        objectId: String,
        objectName: String,
        category: String,
        observedAt: Date = Date(),
        latitude: Double,
        longitude: Double,
        locationName: String,
        azimuthDeg: Double? = nil,
        altitudeDeg: Double? = nil,
        bortleClass: Int? = nil,
        stargazingScore: Int? = nil,
        optics: String = "Naked Eye",
        notes: String = "",
        tagdosNoteId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.objectId = objectId
        self.objectName = objectName
        self.category = category
        self.observedAt = observedAt
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.azimuthDeg = azimuthDeg
        self.altitudeDeg = altitudeDeg
        self.bortleClass = bortleClass
        self.stargazingScore = stargazingScore
        self.optics = optics
        self.notes = notes
        self.tagdosNoteId = tagdosNoteId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
