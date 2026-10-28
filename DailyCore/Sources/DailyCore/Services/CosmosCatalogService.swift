import Foundation

/// Fast offline catalog loader for stars, IAU constellations, Messier DSOs, and meteor showers.
public final class CosmosCatalogService: Sendable {
    public static let shared = CosmosCatalogService()

    public let constellations: [ConstellationRecord]
    public let messierObjects: [DeepSkyObject]
    public let brightStars: [BrightStarRecord]
    public let meteorShowers: [MeteorShowerRecord]

    public init() {
        self.constellations = Self.loadDefaultConstellations()
        self.messierObjects = Self.loadDefaultDSOs()
        self.brightStars = Self.loadDefaultStars()
        self.meteorShowers = Self.loadDefaultMeteorShowers()
    }

    // MARK: - In-Memory Embedded Fallback Records

    private static func loadDefaultConstellations() -> [ConstellationRecord] {
        [
            ConstellationRecord(id: "ORI", nameEn: "Orion", nameRo: "Orion", centerRa: 5.6, centerDec: 5.6, stars: ["Betelgeuse", "Rigel", "Bellatrix", "Alnilam", "Alnitak", "Mintaka", "Saiph"]),
            ConstellationRecord(id: "UMA", nameEn: "Ursa Major", nameRo: "Ursa Mare (Carul Mare)", centerRa: 11.3, centerDec: 55.6, stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"]),
            ConstellationRecord(id: "UMI", nameEn: "Ursa Minor", nameRo: "Ursa Mică (Carul Mic)", centerRa: 15.0, centerDec: 77.7, stars: ["Polaris", "Kochab", "Pherkad"]),
            ConstellationRecord(id: "CAS", nameEn: "Cassiopeia", nameRo: "Casiopeea", centerRa: 1.3, centerDec: 62.2, stars: ["Schedar", "Caph", "Tsih", "Ruchbah", "Segin"]),
            ConstellationRecord(id: "CYG", nameEn: "Cygnus", nameRo: "Lebăda", centerRa: 20.6, centerDec: 44.5, stars: ["Deneb", "Sadr", "Gienah", "Albireo"]),
            ConstellationRecord(id: "LYR", nameEn: "Lyra", nameRo: "Lira", centerRa: 18.9, centerDec: 36.7, stars: ["Vega", "Sheliak", "Sulafat"]),
            ConstellationRecord(id: "AQL", nameEn: "Aquila", nameRo: "Vulturul", centerRa: 19.8, centerDec: 3.4, stars: ["Altair", "Tarazed", "Alshain"]),
            ConstellationRecord(id: "TAU", nameEn: "Taurus", nameRo: "Taurul", centerRa: 4.7, centerDec: 19.0, stars: ["Aldebaran", "Elnath", "Alcyone"]),
            ConstellationRecord(id: "SCO", nameEn: "Scorpius", nameRo: "Scorpionul", centerRa: 16.9, centerDec: -27.0, stars: ["Antares", "Shaula", "Sargas"]),
            ConstellationRecord(id: "CMA", nameEn: "Canis Major", nameRo: "Câinele Mare", centerRa: 6.8, centerDec: -22.1, stars: ["Sirius", "Adhara", "Wezen", "Mirzam"]),
            ConstellationRecord(id: "BOO", nameEn: "Boötes", nameRo: "Boarul", centerRa: 14.7, centerDec: 31.2, stars: ["Arcturus", "Izar", "Muphrid"]),
            ConstellationRecord(id: "AND", nameEn: "Andromeda", nameRo: "Andromeda", centerRa: 0.8, centerDec: 37.4, stars: ["Alpheratz", "Mirach", "Almach"])
        ]
    }

    private static func loadDefaultDSOs() -> [DeepSkyObject] {
        [
            DeepSkyObject(id: "M31", name: "Galaxia Andromeda", type: .galaxy, rightAscensionHours: 0.71, declinationDegrees: 41.27, visualMagnitude: 3.4, constellationCode: "AND", descriptionRo: "Cea mai apropiată galaxie spirală gigantă, vizibilă cu ochiul liber pe cer curat.", recommendedOptics: "Ochi liber / Binoclu"),
            DeepSkyObject(id: "M42", name: "Nebuloasa din Orion", type: .emissionNebula, rightAscensionHours: 5.59, declinationDegrees: -5.39, visualMagnitude: 4.0, constellationCode: "ORI", descriptionRo: "Cea mai luminoasă pepinieră stelară vizibilă sub centura lui Orion.", recommendedOptics: "Ochi liber / Binoclu / Telescop"),
            DeepSkyObject(id: "M45", name: "Pleiadele (Cloșca cu Pui)", type: .openCluster, rightAscensionHours: 3.79, declinationDegrees: 24.11, visualMagnitude: 1.6, constellationCode: "TAU", descriptionRo: "Roi stelar deschis spectaculos învăluit în nebuloase albastre de reflexie.", recommendedOptics: "Ochi liber / Binoclu"),
            DeepSkyObject(id: "M13", name: "Marele Roi din Hercule", type: .globularCluster, rightAscensionHours: 16.69, declinationDegrees: 36.46, visualMagnitude: 5.8, constellationCode: "HER", descriptionRo: "Peste 300.000 de stele concentrate într-o sferă gravitațională densă.", recommendedOptics: "Binoclu / Telescop"),
            DeepSkyObject(id: "M57", name: "Nebuloasa Inelară", type: .planetaryNebula, rightAscensionHours: 18.89, declinationDegrees: 33.03, visualMagnitude: 8.8, constellationCode: "LYR", descriptionRo: "Inel de gaz incandescent ejectat de o stea muribundă.", recommendedOptics: "Telescop"),
            DeepSkyObject(id: "M8", name: "Nebuloasa Laguna", type: .emissionNebula, rightAscensionHours: 18.06, declinationDegrees: -24.38, visualMagnitude: 6.0, constellationCode: "SGR", descriptionRo: "Nor de hidrogen ionizat strălucitor în brațul galactic al Săgetătorului.", recommendedOptics: "Binoclu / Telescop")
        ]
    }

    private static func loadDefaultStars() -> [BrightStarRecord] {
        [
            BrightStarRecord(name: "Sirius", constellation: "CMA", raHours: 6.75, decDegrees: -16.72, magnitude: -1.46, colorIndexBV: 0.00, colorHex: "#FFFFFF"),
            BrightStarRecord(name: "Canopus", constellation: "CAR", raHours: 6.40, decDegrees: -52.70, magnitude: -0.74, colorIndexBV: 0.15, colorHex: "#F8F9FA"),
            BrightStarRecord(name: "Arcturus", constellation: "BOO", raHours: 14.26, decDegrees: 19.18, magnitude: -0.05, colorIndexBV: 1.23, colorHex: "#FFB347"),
            BrightStarRecord(name: "Vega", constellation: "LYR", raHours: 18.62, decDegrees: 38.78, magnitude: 0.03, colorIndexBV: 0.00, colorHex: "#E6F0FA"),
            BrightStarRecord(name: "Capella", constellation: "AUR", raHours: 5.28, decDegrees: 46.00, magnitude: 0.08, colorIndexBV: 0.80, colorHex: "#FFF3A8"),
            BrightStarRecord(name: "Rigel", constellation: "ORI", raHours: 5.24, decDegrees: -8.20, magnitude: 0.13, colorIndexBV: -0.03, colorHex: "#BBDEFB"),
            BrightStarRecord(name: "Procyon", constellation: "CMI", raHours: 7.65, decDegrees: 5.22, magnitude: 0.38, colorIndexBV: 0.42, colorHex: "#FFF9E6"),
            BrightStarRecord(name: "Betelgeuse", constellation: "ORI", raHours: 5.92, decDegrees: 7.41, magnitude: 0.50, colorIndexBV: 1.85, colorHex: "#FF6F00"),
            BrightStarRecord(name: "Altair", constellation: "AQL", raHours: 19.85, decDegrees: 8.87, magnitude: 0.77, colorIndexBV: 0.22, colorHex: "#F4F6F9"),
            BrightStarRecord(name: "Aldebaran", constellation: "TAU", raHours: 4.60, decDegrees: 16.51, magnitude: 0.85, colorIndexBV: 1.54, colorHex: "#FF8C00"),
            BrightStarRecord(name: "Antares", constellation: "SCO", raHours: 16.49, decDegrees: -26.43, magnitude: 0.96, colorIndexBV: 1.83, colorHex: "#FF3D00"),
            BrightStarRecord(name: "Spica", constellation: "VIR", raHours: 13.42, decDegrees: -11.16, magnitude: 0.98, colorIndexBV: -0.23, colorHex: "#90CAF9"),
            BrightStarRecord(name: "Pollux", constellation: "GEM", raHours: 7.76, decDegrees: 28.03, magnitude: 1.14, colorIndexBV: 1.00, colorHex: "#FFD54F"),
            BrightStarRecord(name: "Deneb", constellation: "CYG", raHours: 20.69, decDegrees: 45.28, magnitude: 1.25, colorIndexBV: 0.09, colorHex: "#E3F2FD"),
            BrightStarRecord(name: "Regulus", constellation: "LEO", raHours: 10.14, decDegrees: 11.97, magnitude: 1.36, colorIndexBV: -0.11, colorHex: "#BBDEFB"),
            BrightStarRecord(name: "Castor", constellation: "GEM", raHours: 7.58, decDegrees: 31.89, magnitude: 1.58, colorIndexBV: 0.03, colorHex: "#E8EAF6"),
            BrightStarRecord(name: "Polaris", constellation: "UMI", raHours: 2.53, decDegrees: 89.26, magnitude: 1.97, colorIndexBV: 0.60, colorHex: "#FFFDE7")
        ]
    }

    private static func loadDefaultMeteorShowers() -> [MeteorShowerRecord] {
        [
            MeteorShowerRecord(id: "PER", nameRo: "Perseidele", nameEn: "Perseids", peakDateRange: "12-13 August", radiantRa: 3.1, radiantDec: 58.0, zhr: 100, velocityKmS: 59.0),
            MeteorShowerRecord(id: "GEM", nameRo: "Geminidele", nameEn: "Geminids", peakDateRange: "13-14 Decembrie", radiantRa: 7.5, radiantDec: 33.0, zhr: 150, velocityKmS: 35.0),
            MeteorShowerRecord(id: "QUA", nameRo: "Quadrantidele", nameEn: "Quadrantids", peakDateRange: "3-4 Ianuarie", radiantRa: 15.3, radiantDec: 49.0, zhr: 110, velocityKmS: 41.0),
            MeteorShowerRecord(id: "LYR", nameRo: "Liridele", nameEn: "Lyrids", peakDateRange: "21-22 Aprilie", radiantRa: 18.1, radiantDec: 34.0, zhr: 18, velocityKmS: 49.0),
            MeteorShowerRecord(id: "ETA", nameRo: "Eta Aquaridele", nameEn: "Eta Aquariids", peakDateRange: "5-6 Mai", radiantRa: 22.5, radiantDec: -1.0, zhr: 50, velocityKmS: 66.0),
            MeteorShowerRecord(id: "ORI", nameRo: "Orionidele", nameEn: "Orionids", peakDateRange: "21-22 Octombrie", radiantRa: 6.3, radiantDec: 16.0, zhr: 25, velocityKmS: 66.0),
            MeteorShowerRecord(id: "LEO", nameRo: "Leonidele", nameEn: "Leonids", peakDateRange: "17-18 Noiembrie", radiantRa: 10.2, radiantDec: 22.0, zhr: 15, velocityKmS: 71.0)
        ]
    }
}

// MARK: - Supporting Record Types

public struct ConstellationRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let nameEn: String
    public let nameRo: String
    public let centerRa: Double
    public let centerDec: Double
    public let stars: [String]

    public init(id: String, nameEn: String, nameRo: String, centerRa: Double, centerDec: Double, stars: [String]) {
        self.id = id
        self.nameEn = nameEn
        self.nameRo = nameRo
        self.centerRa = centerRa
        self.centerDec = centerDec
        self.stars = stars
    }
}

public struct BrightStarRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let constellation: String
    public let raHours: Double
    public let decDegrees: Double
    public let magnitude: Double
    public let colorIndexBV: Double
    public let colorHex: String

    public init(name: String, constellation: String, raHours: Double, decDegrees: Double, magnitude: Double, colorIndexBV: Double, colorHex: String) {
        self.name = name
        self.constellation = constellation
        self.raHours = raHours
        self.decDegrees = decDegrees
        self.magnitude = magnitude
        self.colorIndexBV = colorIndexBV
        self.colorHex = colorHex
    }
}

public struct MeteorShowerRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let nameRo: String
    let nameEn: String
    public let peakDateRange: String
    public let radiantRa: Double
    public let radiantDec: Double
    public let zhr: Int
    public let velocityKmS: Double

    public init(id: String, nameRo: String, nameEn: String, peakDateRange: String, radiantRa: Double, radiantDec: Double, zhr: Int, velocityKmS: Double) {
        self.id = id
        self.nameRo = nameRo
        self.nameEn = nameEn
        self.peakDateRange = peakDateRange
        self.radiantRa = radiantRa
        self.radiantDec = radiantDec
        self.zhr = zhr
        self.velocityKmS = velocityKmS
    }
}
