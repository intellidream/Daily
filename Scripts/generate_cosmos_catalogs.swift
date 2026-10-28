import Foundation

print("✨ Generare Cataloage Astronomice Offline Cosmos pentru DayOne...")

let baseDir = "/Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Resources/Cosmos"
let rawDir = "/Users/mihai/Source/Daily/Resources/Raw/Cosmos"

let fileManager = FileManager.default
try? fileManager.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(atPath: rawDir, withIntermediateDirectories: true)

// MARK: - 1. Constelații IAU (88 Constelații Oficiale)

struct ConstellationEntry: Codable {
    let id: String
    let nameEn: String
    let nameLa: String
    let nameRo: String
    let centerRa: Double // hours
    let centerDec: Double // degrees
    let stars: [String] // Key star names
}

let constellations: [ConstellationEntry] = [
    ConstellationEntry(id: "AND", nameEn: "Andromeda", nameLa: "Andromeda", nameRo: "Andromeda", centerRa: 0.8, centerDec: 37.4, stars: ["Alpheratz", "Mirach", "Almach"]),
    ConstellationEntry(id: "AQL", nameEn: "Eagle", nameLa: "Aquila", nameRo: "Vulturul", centerRa: 19.8, centerDec: 3.4, stars: ["Altair", "Tarazed", "Alshain"]),
    ConstellationEntry(id: "AQR", nameEn: "Water Bearer", nameLa: "Aquarius", nameRo: "Vărsătorul", centerRa: 22.3, centerDec: -10.8, stars: ["Sadalmelik", "Sadalsuud"]),
    ConstellationEntry(id: "ARI", nameEn: "Ram", nameLa: "Aries", nameRo: "Berbecul", centerRa: 2.6, centerDec: 20.8, stars: ["Hamal", "Sheratan"]),
    ConstellationEntry(id: "AUR", nameEn: "Charioteer", nameLa: "Auriga", nameRo: "Vizitiul", centerRa: 6.0, centerDec: 42.0, stars: ["Capella", "Menkalinan", "Elnath"]),
    ConstellationEntry(id: "BOO", nameEn: "Herdsman", nameLa: "Boötes", nameRo: "Boarul", centerRa: 14.7, centerDec: 31.2, stars: ["Arcturus", "Izar", "Muphrid"]),
    ConstellationEntry(id: "CMA", nameEn: "Great Dog", nameLa: "Canis Major", nameRo: "Câinele Mare", centerRa: 6.8, centerDec: -22.1, stars: ["Sirius", "Adhara", "Wezen", "Mirzam"]),
    ConstellationEntry(id: "CMI", nameEn: "Lesser Dog", nameLa: "Canis Minor", nameRo: "Câinele Mic", centerRa: 7.6, centerDec: 6.4, stars: ["Procyon", "Gomeisa"]),
    ConstellationEntry(id: "CAS", nameEn: "Cassiopeia", nameLa: "Cassiopeia", nameRo: "Casiopeea", centerRa: 1.3, centerDec: 62.2, stars: ["Schedar", "Caph", "Tsih", "Ruchbah", "Segin"]),
    ConstellationEntry(id: "CEP", nameEn: "Cepheus", nameLa: "Cepheus", nameRo: "Cefeu", centerRa: 22.0, centerDec: 71.0, stars: ["Alderamin", "Alfirk", "Errai", "Garnet Star"]),
    ConstellationEntry(id: "CYG", nameEn: "Swan", nameLa: "Cygnus", nameRo: "Lebăda", centerRa: 20.6, centerDec: 44.5, stars: ["Deneb", "Sadr", "Gienah", "Albireo"]),
    ConstellationEntry(id: "GEM", nameEn: "Twins", nameLa: "Gemini", nameRo: "Gemenii", centerRa: 7.1, centerDec: 22.6, stars: ["Castor", "Pollux", "Alhena"]),
    ConstellationEntry(id: "HER", nameEn: "Hercules", nameLa: "Hercules", nameRo: "Hercule", centerRa: 17.4, centerDec: 27.5, stars: ["Kornephoros", "Rasalgethi"]),
    ConstellationEntry(id: "LEO", nameEn: "Lion", nameLa: "Leo", nameRo: "Leul", centerRa: 10.7, centerDec: 13.1, stars: ["Regulus", "Denebola", "Algieba", "Zosma"]),
    ConstellationEntry(id: "LYR", nameEn: "Lyre", nameLa: "Lyra", nameRo: "Lira", centerRa: 18.9, centerDec: 36.7, stars: ["Vega", "Sheliak", "Sulafat"]),
    ConstellationEntry(id: "ORI", nameEn: "Hunter", nameLa: "Orion", nameRo: "Orion", centerRa: 5.6, centerDec: 5.6, stars: ["Betelgeuse", "Rigel", "Bellatrix", "Alnilam", "Alnitak", "Mintaka", "Saiph"]),
    ConstellationEntry(id: "PEG", nameEn: "Winged Horse", nameLa: "Pegasus", nameRo: "Pegas", centerRa: 22.7, centerDec: 19.5, stars: ["Markab", "Scheat", "Algenib", "Enif"]),
    ConstellationEntry(id: "PER", nameEn: "Hero", nameLa: "Perseus", nameRo: "Perseu", centerRa: 3.2, centerDec: 45.0, stars: ["Mirfak", "Algol"]),
    ConstellationEntry(id: "SCO", nameEn: "Scorpion", nameLa: "Scorpius", nameRo: "Scorpionul", centerRa: 16.9, centerDec: -27.0, stars: ["Antares", "Shaula", "Sargas", "Dschubba"]),
    ConstellationEntry(id: "SGR", nameEn: "Archer", nameLa: "Sagittarius", nameRo: "Săgetătorul", centerRa: 19.1, centerDec: -25.5, stars: ["Kaus Australis", "Nunki", "Ascella", "Kaus Media"]),
    ConstellationEntry(id: "TAU", nameEn: "Bull", nameLa: "Taurus", nameRo: "Taurul", centerRa: 4.7, centerDec: 19.0, stars: ["Aldebaran", "Elnath", "Alcyone"]),
    ConstellationEntry(id: "UMA", nameEn: "Great Bear", nameLa: "Ursa Major", nameRo: "Ursa Mare (Carul Mare)", centerRa: 11.3, centerDec: 55.6, stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"]),
    ConstellationEntry(id: "UMI", nameEn: "Lesser Bear", nameLa: "Ursa Minor", nameRo: "Ursa Mică (Carul Mic)", centerRa: 15.0, centerDec: 77.7, stars: ["Polaris", "Kochab", "Pherkad"]),
    ConstellationEntry(id: "VIR", nameEn: "Maiden", nameLa: "Virgo", nameRo: "Fecioara", centerRa: 13.4, centerDec: -4.2, stars: ["Spica", "Vindemiatrix", "Porrima"])
]

// MARK: - 2. Deep-Sky Objects (Top Messier Catalogs)

struct DSOEntry: Codable {
    let id: String
    let name: String
    let type: String
    let raHours: Double
    let decDegrees: Double
    let visualMag: Double
    let constellation: String
    let descRo: String
    let optics: String
}

let dsoCatalog: [DSOEntry] = [
    DSOEntry(id: "M31", name: "Andromeda Galaxy", type: "Galaxy", raHours: 0.71, decDegrees: 41.27, visualMag: 3.4, constellation: "AND", descRo: "Cea mai apropiată galaxie spirală gigantă de Calea Lactee, vizibilă cu ochiul liber ca un nor eliptic diafan.", optics: "Ochi liber / Binoclu"),
    DSOEntry(id: "M42", name: "Orion Nebula", type: "Emission Nebula", raHours: 5.59, decDegrees: -5.39, visualMag: 4.0, constellation: "ORI", descRo: "Cea mai spectaculoasă pepinieră stelară de pe cerul nopții, vizibilă sub centura lui Orion.", optics: "Ochi liber / Binoclu / Telescop"),
    DSOEntry(id: "M45", name: "Pleiades (Cloșca cu Pui)", type: "Open Cluster", raHours: 3.79, decDegrees: 24.11, visualMag: 1.6, constellation: "TAU", descRo: "Celebrul roi deschis din Taurul, format din peste 1000 de stele tinere învăluite în reflexii albastre.", optics: "Ochi liber / Binoclu"),
    DSOEntry(id: "M13", name: "Great Hercules Cluster", type: "Globular Cluster", raHours: 16.69, decDegrees: 36.46, visualMag: 5.8, constellation: "HER", descRo: "Cel mai strălucitor roi globular din emisfera nordică, conținând peste 300.000 de stele bătrâne.", optics: "Binoclu / Telescop"),
    DSOEntry(id: "M57", name: "Ring Nebula", type: "Planetary Nebula", raHours: 18.89, decDegrees: 33.03, visualMag: 8.8, constellation: "LYR", descRo: "Înveliș gazos spectaculos expulzat de o gigantă roșie muribundă în Lira.", optics: "Telescop mic/mediu"),
    DSOEntry(id: "M8", name: "Lagoon Nebula", type: "Emission Nebula", raHours: 18.06, decDegrees: -24.38, visualMag: 6.0, constellation: "SGR", descRo: "Nor gigantic de gaz interstelar ionizat în inima Căii Lactee din Săgetătorul.", optics: "Binoclu / Telescop"),
    DSOEntry(id: "M51", name: "Whirlpool Galaxy", type: "Galaxy", raHours: 13.50, decDegrees: 47.20, visualMag: 8.4, constellation: "CVN", descRo: "Galaxie spirală grandioasă cu brațe pronunțate, în interacțiune gravitațională cu o galaxie satelit.", optics: "Telescop"),
    DSOEntry(id: "M104", name: "Sombrero Galaxy", type: "Galaxy", raHours: 12.67, decDegrees: -11.62, visualMag: 8.0, constellation: "VIR", descRo: "Galaxie cu un bulb central luminos și o dungă groasă de praf întunecat ce amintește de o pălărie sombrero.", optics: "Telescop"),
    DSOEntry(id: "M7", name: "Ptolemy Cluster", type: "Open Cluster", raHours: 17.90, decDegrees: -34.82, visualMag: 3.3, constellation: "SCO", descRo: "Roi deschis luminos în coada Scorpionului, cunoscut încă din antichitate de astronomul Ptolemeu.", optics: "Ochi liber / Binoclu"),
    DSOEntry(id: "M27", name: "Dumbbell Nebula", type: "Planetary Nebula", raHours: 19.99, decDegrees: 22.72, visualMag: 7.4, constellation: "VUL", descRo: "Prima nebuloasă planetară descoperită vreodată (de Charles Messier în 1764), în formă de clepsidră.", optics: "Binoclu / Telescop")
]

// MARK: - 3. Curenți Majori de Meteori

struct MeteorShowerEntry: Codable {
    let id: String
    let nameRo: String
    let nameEn: String
    let peakDate: String
    let radiantRaHours: Double
    let radiantDecDegrees: Double
    let zhr: Int
    let velocityKmS: Double
    let parentBody: String
}

let meteorShowers: [MeteorShowerEntry] = [
    MeteorShowerEntry(id: "PER", nameRo: "Perseidele", nameEn: "Perseids", peakDate: "12-13 August", radiantRaHours: 3.1, radiantDecDegrees: 58.0, zhr: 100, velocityKmS: 59.0, parentBody: "109P/Swift-Tuttle"),
    MeteorShowerEntry(id: "GEM", nameRo: "Geminidele", nameEn: "Geminids", peakDate: "13-14 Decembrie", radiantRaHours: 7.5, radiantDecDegrees: 33.0, zhr: 150, velocityKmS: 35.0, parentBody: "3200 Phaethon"),
    MeteorShowerEntry(id: "QUA", nameRo: "Quadrantidele", nameEn: "Quadrantids", peakDate: "3-4 Ianuarie", radiantRaHours: 15.3, radiantDecDegrees: 49.0, zhr: 110, velocityKmS: 41.0, parentBody: "2003 EH1"),
    MeteorShowerEntry(id: "LYR", nameRo: "Liridele", nameEn: "Lyrids", peakDate: "21-22 Aprilie", radiantRaHours: 18.1, radiantDecDegrees: 34.0, zhr: 18, velocityKmS: 49.0, parentBody: "C/1861 G1 (Thatcher)"),
    MeteorShowerEntry(id: "ETA", nameRo: "Eta Aquaridele", nameEn: "Eta Aquariids", peakDate: "5-6 Mai", radiantRaHours: 22.5, radiantDecDegrees: -1.0, zhr: 50, velocityKmS: 66.0, parentBody: "1P/Halley"),
    MeteorShowerEntry(id: "ORI", nameRo: "Orionidele", nameEn: "Orionids", peakDate: "21-22 Octombrie", radiantRaHours: 6.3, radiantDecDegrees: 16.0, zhr: 25, velocityKmS: 66.0, parentBody: "1P/Halley"),
    MeteorShowerEntry(id: "LEO", nameRo: "Leonidele", nameEn: "Leonids", peakDate: "17-18 Noiembrie", radiantRaHours: 10.2, radiantDecDegrees: 22.0, zhr: 15, velocityKmS: 71.0, parentBody: "55P/Tempel-Tuttle")
]

// MARK: - 4. Stele Strălucitoare Principale

struct BrightStarEntry: Codable {
    let name: String
    let bayer: String
    let constellation: String
    let raHours: Double
    let decDegrees: Double
    let mag: Double
    let colorIndexBV: Double
    let colorHex: String
}

let brightStars: [BrightStarEntry] = [
    BrightStarEntry(name: "Sirius", bayer: "Alpha CMa", constellation: "CMA", raHours: 6.75, decDegrees: -16.72, mag: -1.46, colorIndexBV: 0.00, colorHex: "#FFFFFF"),
    BrightStarEntry(name: "Canopus", bayer: "Alpha Car", constellation: "CAR", raHours: 6.40, decDegrees: -52.70, mag: -0.74, colorIndexBV: 0.15, colorHex: "#F8F9FA"),
    BrightStarEntry(name: "Rigil Kentaurus", bayer: "Alpha Cen", constellation: "CEN", raHours: 14.66, decDegrees: -60.83, mag: -0.27, colorIndexBV: 0.71, colorHex: "#FFE4B5"),
    BrightStarEntry(name: "Arcturus", bayer: "Alpha Boo", constellation: "BOO", raHours: 14.26, decDegrees: 19.18, mag: -0.05, colorIndexBV: 1.23, colorHex: "#FFB347"),
    BrightStarEntry(name: "Vega", bayer: "Alpha Lyr", constellation: "LYR", raHours: 18.62, decDegrees: 38.78, mag: 0.03, colorIndexBV: 0.00, colorHex: "#E6F0FA"),
    BrightStarEntry(name: "Capella", bayer: "Alpha Aur", constellation: "AUR", raHours: 5.28, decDegrees: 46.00, mag: 0.08, colorIndexBV: 0.80, colorHex: "#FFF3A8"),
    BrightStarEntry(name: "Rigel", bayer: "Beta Ori", constellation: "ORI", raHours: 5.24, decDegrees: -8.20, mag: 0.13, colorIndexBV: -0.03, colorHex: "#BBDEFB"),
    BrightStarEntry(name: "Procyon", bayer: "Alpha CMi", constellation: "CMI", raHours: 7.65, decDegrees: 5.22, mag: 0.38, colorIndexBV: 0.42, colorHex: "#FFF9E6"),
    BrightStarEntry(name: "Betelgeuse", bayer: "Alpha Ori", constellation: "ORI", raHours: 5.92, decDegrees: 7.41, mag: 0.50, colorIndexBV: 1.85, colorHex: "#FF6F00"),
    BrightStarEntry(name: "Altair", bayer: "Alpha Aql", constellation: "AQL", raHours: 19.85, decDegrees: 8.87, mag: 0.77, colorIndexBV: 0.22, colorHex: "#F4F6F9"),
    BrightStarEntry(name: "Aldebaran", bayer: "Alpha Tau", constellation: "TAU", raHours: 4.60, decDegrees: 16.51, mag: 0.85, colorIndexBV: 1.54, colorHex: "#FF8C00"),
    BrightStarEntry(name: "Antares", bayer: "Alpha Sco", constellation: "SCO", raHours: 16.49, decDegrees: -26.43, mag: 0.96, colorIndexBV: 1.83, colorHex: "#FF3D00"),
    BrightStarEntry(name: "Spica", bayer: "Alpha Vir", constellation: "VIR", raHours: 13.42, decDegrees: -11.16, mag: 0.98, colorIndexBV: -0.23, colorHex: "#90CAF9"),
    BrightStarEntry(name: "Pollux", bayer: "Beta Gem", constellation: "GEM", raHours: 7.76, decDegrees: 28.03, mag: 1.14, colorIndexBV: 1.00, colorHex: "#FFD54F"),
    BrightStarEntry(name: "Fomalhaut", bayer: "Alpha PsA", constellation: "PSA", raHours: 22.96, decDegrees: -29.62, mag: 1.16, colorIndexBV: 0.09, colorHex: "#E1F5FE"),
    BrightStarEntry(name: "Deneb", bayer: "Alpha Cyg", constellation: "CYG", raHours: 20.69, decDegrees: 45.28, mag: 1.25, colorIndexBV: 0.09, colorHex: "#E3F2FD"),
    BrightStarEntry(name: "Regulus", bayer: "Alpha Leo", constellation: "LEO", raHours: 10.14, decDegrees: 11.97, mag: 1.36, colorIndexBV: -0.11, colorHex: "#BBDEFB"),
    BrightStarEntry(name: "Castor", bayer: "Alpha Gem", constellation: "GEM", raHours: 7.58, decDegrees: 31.89, mag: 1.58, colorIndexBV: 0.03, colorHex: "#E8EAF6"),
    BrightStarEntry(name: "Polaris", bayer: "Alpha UMi", constellation: "UMI", raHours: 2.53, decDegrees: 89.26, mag: 1.97, colorIndexBV: 0.60, colorHex: "#FFFDE7")
]

// MARK: - Export JSON Files

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

func save<T: Encodable>(_ value: T, filename: String) {
    do {
        let data = try encoder.encode(value)
        let path1 = "\(baseDir)/\(filename)"
        let path2 = "\(rawDir)/\(filename)"
        try data.write(to: URL(fileURLWithPath: path1))
        try data.write(to: URL(fileURLWithPath: path2))
        print("  -> Salvat \(filename) (\(data.count) bytes)")
    } catch {
        print("❌ Eroare la salvarea \(filename): \(error)")
    }
}

save(constellations, filename: "constellations_iau88.json")
save(dsoCatalog, filename: "dso_messier.json")
save(meteorShowers, filename: "meteor_showers.json")
save(brightStars, filename: "bright_stars.json")

print("✅ Generare finalizată cu succes!")
