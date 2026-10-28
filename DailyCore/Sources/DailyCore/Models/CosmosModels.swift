import Foundation

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

    public var displayName: String {
        switch self {
        case .sun: return "Soare"
        case .moon: return "Lună"
        case .mercury: return "Mercur"
        case .venus: return "Venus"
        case .mars: return "Marte"
        case .jupiter: return "Jupiter"
        case .saturn: return "Saturn"
        case .uranus: return "Uranus"
        case .neptune: return "Neptun"
        case .pluto: return "Pluto"
        }
    }

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
        case .moon: return "#E0E0E0"
        case .mercury: return "#B0BEC5"
        case .venus: return "#FFF9C4"
        case .mars: return "#FF5722"
        case .jupiter: return "#D7CCC8"
        case .saturn: return "#FFE082"
        case .uranus: return "#80DEEA"
        case .neptune: return "#42A5F5"
        case .pluto: return "#CFD8DC"
        }
    }
}

// MARK: - Celestial Coordinates

public struct CelestialCoordinates: Codable, Equatable, Sendable {
    public let azimuthDegrees: Double
    public let altitudeDegrees: Double
    public let rightAscensionHours: Double
    public let declinationDegrees: Double
    public let distanceAU: Double
    public let visualMagnitude: Double
    public let isVisible: Bool // altitude > 0

    public init(
        azimuthDegrees: Double,
        altitudeDegrees: Double,
        rightAscensionHours: Double,
        declinationDegrees: Double,
        distanceAU: Double,
        visualMagnitude: Double
    ) {
        self.azimuthDegrees = azimuthDegrees
        self.altitudeDegrees = altitudeDegrees
        self.rightAscensionHours = rightAscensionHours
        self.declinationDegrees = declinationDegrees
        self.distanceAU = distanceAU
        self.visualMagnitude = visualMagnitude
        self.isVisible = altitudeDegrees > 0.0
    }

    public var compassDirection: String {
        let normalized = (azimuthDegrees.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int(round(normalized / 22.5)) % 16
        return directions[index]
    }
}

// MARK: - Moon Phase

public enum MoonPhaseQuarter: String, Codable, CaseIterable, Sendable {
    case newMoon = "New Moon"
    case waxingCrescent = "Waxing Crescent"
    case firstQuarter = "First Quarter"
    case waxingGibbous = "Waxing Gibbous"
    case fullMoon = "Full Moon"
    case waningGibbous = "Waning Gibbous"
    case thirdQuarter = "Third Quarter"
    case waningCrescent = "Waning Crescent"

    public var displayNameRo: String {
        switch self {
        case .newMoon: return "Lună Nouă"
        case .waxingCrescent: return "Semilună în Creștere"
        case .firstQuarter: return "Primul Pătrar"
        case .waxingGibbous: return "Lună Giboasă în Creștere"
        case .fullMoon: return "Lună Plină"
        case .waningGibbous: return "Lună Giboasă în Scădere"
        case .thirdQuarter: return "Ultimul Pătrar"
        case .waningCrescent: return "Semilună în Scădere"
        }
    }

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
    public let distanceKm: Double

    public init(
        phaseAngleDegrees: Double,
        illuminatedFraction: Double,
        quarter: MoonPhaseQuarter,
        ageDays: Double,
        isWaxing: Bool,
        distanceKm: Double
    ) {
        self.phaseAngleDegrees = phaseAngleDegrees
        self.illuminatedFraction = illuminatedFraction
        self.quarter = quarter
        self.ageDays = ageDays
        self.isWaxing = isWaxing
        self.distanceKm = distanceKm
    }

    public var illuminationPercent: Int {
        Int(round(illuminatedFraction * 100.0))
    }
}

// MARK: - Sun & Twilight Times

public struct SunTimes: Codable, Equatable, Sendable {
    public let dawnAstronomical: Date? // Sun at -18°
    public let dawnNautical: Date?     // Sun at -12°
    public let dawnCivil: Date?        // Sun at -6°
    public let sunrise: Date?          // Sun at -0.833°
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

// MARK: - Jupiter Moons & Saturn Rings

public struct MoonVector2D: Codable, Equatable, Sendable {
    public let xRadius: Double // Position in apparent radii of parent planet
    public let yRadius: Double
    public let isFrontOfPlanet: Bool

    public init(xRadius: Double, yRadius: Double, isFrontOfPlanet: Bool) {
        self.xRadius = xRadius
        self.yRadius = yRadius
        self.isFrontOfPlanet = isFrontOfPlanet
    }
}

public struct JupiterMoonsState: Codable, Equatable, Sendable {
    public let io: MoonVector2D
    public let europa: MoonVector2D
    public let ganymede: MoonVector2D
    public let callisto: MoonVector2D

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

    public var displayNameRo: String {
        switch self {
        case .poor: return "Nefavorabil"
        case .fair: return "Moderat"
        case .good: return "Bun"
        case .pristine: return "Excepțional"
        }
    }

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
    public let cloudCoverTotalPercent: Int
    public let cloudCoverLowPercent: Int
    public let cloudCoverMidPercent: Int
    public let cloudCoverHighPercent: Int
    public let moonIlluminationPercent: Int
    public let isMoonAboveHorizon: Bool
    public let seeingArcseconds: Double?
    public let dewPointDepressionCelsius: Double? // Temp - DewPoint
    public let bestWindowDescription: String?
    public let narrativeAdvice: String

    public init(
        score: Int,
        quality: StargazingQuality,
        bortleClass: Int,
        limitingMagnitude: Double,
        cloudCoverTotalPercent: Int,
        cloudCoverLowPercent: Int,
        cloudCoverMidPercent: Int,
        cloudCoverHighPercent: Int,
        moonIlluminationPercent: Int,
        isMoonAboveHorizon: Bool,
        seeingArcseconds: Double?,
        dewPointDepressionCelsius: Double?,
        bestWindowDescription: String?,
        narrativeAdvice: String
    ) {
        self.score = max(0, min(100, score))
        self.quality = quality
        self.bortleClass = bortleClass
        self.limitingMagnitude = limitingMagnitude
        self.cloudCoverTotalPercent = cloudCoverTotalPercent
        self.cloudCoverLowPercent = cloudCoverLowPercent
        self.cloudCoverMidPercent = cloudCoverMidPercent
        self.cloudCoverHighPercent = cloudCoverHighPercent
        self.moonIlluminationPercent = moonIlluminationPercent
        self.isMoonAboveHorizon = isMoonAboveHorizon
        self.seeingArcseconds = seeingArcseconds
        self.dewPointDepressionCelsius = dewPointDepressionCelsius
        self.bestWindowDescription = bestWindowDescription
        self.narrativeAdvice = narrativeAdvice
    }
}

// MARK: - Satellite Passes (ISS)

public struct SatellitePass: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let satelliteName: String
    public let noradCatalogNumber: Int
    public let startTime: Date
    public let maxAltitudeTime: Date
    public let endTime: Date
    public let maxAltitudeDegrees: Double
    public let startCompass: String
    public let endCompass: String
    public let peakMagnitude: Double
    public let isSunlit: Bool

    public init(
        id: String,
        satelliteName: String,
        noradCatalogNumber: Int,
        startTime: Date,
        maxAltitudeTime: Date,
        endTime: Date,
        maxAltitudeDegrees: Double,
        startCompass: String,
        endCompass: String,
        peakMagnitude: Double,
        isSunlit: Bool
    ) {
        self.id = id
        self.satelliteName = satelliteName
        self.noradCatalogNumber = noradCatalogNumber
        self.startTime = startTime
        self.maxAltitudeTime = maxAltitudeTime
        self.endTime = endTime
        self.maxAltitudeDegrees = maxAltitudeDegrees
        self.startCompass = startCompass
        self.endCompass = endCompass
        self.peakMagnitude = peakMagnitude
        self.isSunlit = isSunlit
    }

    public var durationMinutes: Int {
        Int(round(endTime.timeIntervalSince(startTime) / 60.0))
    }
}

// MARK: - Space Weather & Aurora

public struct SpaceWeatherReport: Codable, Equatable, Sendable {
    public let kpIndex: Double // 0.0 to 9.0
    public let bzMagneticFieldNt: Double? // negative is southward (aurora favorable!)
    public let solarWindSpeedKmS: Double?
    public let ovationProbabilityPercent: Int // for observer's latitude
    public let isAuroraAlertActive: Bool
    public let statusMessage: String

    public init(
        kpIndex: Double,
        bzMagneticFieldNt: Double?,
        solarWindSpeedKmS: Double?,
        ovationProbabilityPercent: Int,
        isAuroraAlertActive: Bool,
        statusMessage: String
    ) {
        self.kpIndex = kpIndex
        self.bzMagneticFieldNt = bzMagneticFieldNt
        self.solarWindSpeedKmS = solarWindSpeedKmS
        self.ovationProbabilityPercent = ovationProbabilityPercent
        self.isAuroraAlertActive = isAuroraAlertActive
        self.statusMessage = statusMessage
    }
}

// MARK: - Deep Sky & Catalogs

public enum DSOType: String, Codable, Sendable {
    case galaxy = "Galaxy"
    case emissionNebula = "Emission Nebula"
    case planetaryNebula = "Planetary Nebula"
    case globularCluster = "Globular Cluster"
    case openCluster = "Open Cluster"
    case supernovaRemnant = "Supernova Remnant"

    public var sfSymbol: String {
        switch self {
        case .galaxy: return "tornado"
        case .emissionNebula: return "cloud.fog.fill"
        case .planetaryNebula: return "circle.circle"
        case .globularCluster: return "circle.grid.3x3.fill"
        case .openCluster: return "sparkles"
        case .supernovaRemnant: return "sun.dust.fill"
        }
    }
}

public struct DeepSkyObject: Codable, Identifiable, Equatable, Sendable {
    public let id: String // e.g. "M31"
    public let name: String // "Andromeda Galaxy"
    public let type: DSOType
    public let rightAscensionHours: Double
    public let declinationDegrees: Double
    public let visualMagnitude: Double
    public let constellationCode: String // "AND"
    public let descriptionRo: String
    public let recommendedOptics: String // "Naked Eye", "Binoculars 10x50", "Telescope"

    public init(
        id: String,
        name: String,
        type: DSOType,
        rightAscensionHours: Double,
        declinationDegrees: Double,
        visualMagnitude: Double,
        constellationCode: String,
        descriptionRo: String,
        recommendedOptics: String
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.rightAscensionHours = rightAscensionHours
        self.declinationDegrees = declinationDegrees
        self.visualMagnitude = visualMagnitude
        self.constellationCode = constellationCode
        self.descriptionRo = descriptionRo
        self.recommendedOptics = recommendedOptics
    }
}
