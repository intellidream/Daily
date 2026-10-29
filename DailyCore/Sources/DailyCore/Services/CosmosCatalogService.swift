import Foundation

/// High-throughput canonical sky catalog loader for Daily's Night Sky Observatory.
/// Loads 15,544 Hipparcos stars (`stars_mag70.bin`), 515+ IAU proper star names (`star_names_iau.json`),
/// 88 official IAU constellations with branched HIP segment pairs (`constellations_iau88.json`),
/// 257 IAU constellation boundary arcs (`constellation_borders.json`), 14 famous asterisms (`asterisms.json`),
/// 219 Messier + Caldwell Deep-Sky Objects (`dso_catalog.json`), 22 IAU meteor showers (`meteor_showers_iau.json`),
/// 5-layer Milky Way isophotes (`milky_way_isophotes.json`), and a global 0.5° offline Bortle grid (`bortle_world_grid.bin`).
public final class CosmosCatalogService: Sendable {
    public static let shared = CosmosCatalogService()

    public let stars: [PackedStar]
    public let starIndexByHip: [Int: Int]
    public let starDesignationsByHip: [Int: StarDesignation]
    public let brightStars: [BrightStarRecord]
    public let constellations: [ConstellationRecord]
    public let constellationBorders: [ConstellationBorderArc]
    public let asterisms: [AsterismRecord]
    public let deepSkyObjects: [DeepSkyObject]
    public var messierObjects: [DeepSkyObject] { deepSkyObjects }
    public let meteorShowers: [MeteorShowerRecord]
    public let milkyWayLayers: [MilkyWayIsophoteLayer]
    private let bortleGridData: Data?

    public init() {
        let loadedStars = Self.loadBinaryStars()
        self.stars = loadedStars

        var hipIdx: [Int: Int] = [:]
        hipIdx.reserveCapacity(loadedStars.count)
        for (i, s) in loadedStars.enumerated() {
            hipIdx[s.hip] = i
        }
        self.starIndexByHip = hipIdx

        let designations = Self.loadStarDesignations()
        self.starDesignationsByHip = designations

        let loadedConstellations = Self.loadConstellations()
        self.constellations = loadedConstellations

        var constCodeByIndex: [UInt16: String] = [:]
        for c in loadedConstellations {
            constCodeByIndex[UInt16(clamping: c.index)] = c.id
        }

        // Build named / bright star index for Search, Target Inspector, and Accessibility
        var bright: [BrightStarRecord] = []
        bright.reserveCapacity(560)
        for star in loadedStars {
            let desig = designations[star.hip]
            if let properName = desig?.name, !properName.isEmpty {
                let constId = desig?.constellation?.uppercased() ?? constCodeByIndex[star.constellationIndex] ?? "SKY"
                let subLabel: String? = {
                    if let b = desig?.bayer, !b.isEmpty, let c = desig?.constellation {
                        return "\(b) \(c)"
                    }
                    return nil
                }()
                bright.append(
                    BrightStarRecord(
                        hip: star.hip,
                        name: properName,
                        designation: subLabel,
                        constellation: constId,
                        raHours: Double(star.raHours),
                        decDegrees: Double(star.decDegrees),
                        magnitude: Double(star.vMag),
                        colorIndexBV: Double(star.bv)
                    )
                )
            } else if star.vMag <= 3.0 {
                let constId = desig?.constellation?.uppercased() ?? constCodeByIndex[star.constellationIndex] ?? "SKY"
                let label = desig?.primaryLabel ?? "HIP \(star.hip)"
                bright.append(
                    BrightStarRecord(
                        hip: star.hip,
                        name: label,
                        designation: nil,
                        constellation: constId,
                        raHours: Double(star.raHours),
                        decDegrees: Double(star.decDegrees),
                        magnitude: Double(star.vMag),
                        colorIndexBV: Double(star.bv)
                    )
                )
            }
        }
        bright.sort { $0.magnitude < $1.magnitude }
        self.brightStars = bright

        self.constellationBorders = Self.loadConstellationBorders()
        self.asterisms = Self.loadAsterisms()
        self.deepSkyObjects = Self.loadDeepSkyObjects()
        self.meteorShowers = Self.loadMeteorShowers()
        self.milkyWayLayers = Self.loadMilkyWayLayers()
        self.bortleGridData = Self.loadResourceData(name: "bortle_world_grid", ext: "bin")
    }

    // MARK: - Fast Lookups

    @inline(__always)
    public func star(forHip hip: Int) -> PackedStar? {
        guard let idx = starIndexByHip[hip] else { return nil }
        return stars[idx]
    }

    public func starName(forHip hip: Int) -> String? {
        starDesignationsByHip[hip]?.primaryLabel
    }

    /// Global O(1) offline Bortle Dark-Sky Scale lookup (1 = pristine dark site ... 9 = inner-city core).
    public func bortleClass(latitude: Double, longitude: Double) -> Int {
        guard let data = bortleGridData, data.count >= 16 + 129_600 else {
            return 5
        }
        let y = min(359, max(0, Int(floor((latitude + 90.0) * 2.0))))
        let normLon = ((longitude + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let x = min(719, max(0, Int(floor(normLon * 2.0))))
        let cellIdx = y * 720 + x
        let byteIdx = 16 + (cellIdx >> 1)
        let packed = data[byteIdx]
        let val = (cellIdx & 1) == 0 ? Int(packed >> 4) : Int(packed & 0x0F)
        return max(1, min(9, val))
    }

    public static func limitingMagnitude(forBortle bortle: Int, moonIlluminatedFraction: Double = 0.0, isMoonAboveHorizon: Bool = false) -> Double {
        let baseTable: [Double] = [7.8, 7.8, 7.3, 6.8, 6.3, 5.8, 5.2, 4.6, 4.1, 3.6]
        let clamped = max(1, min(9, bortle))
        var nelm = baseTable[clamped]
        if isMoonAboveHorizon {
            nelm -= moonIlluminatedFraction * 1.45
        }
        return max(2.5, min(7.8, nelm))
    }

    public func thumbnailURL(for relativePath: String?) -> URL? {
        guard let rel = relativePath, !rel.isEmpty else { return nil }
        let fileName = (rel as NSString).lastPathComponent
        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension.isEmpty ? "png" : (fileName as NSString).pathExtension

        return Bundle.module.url(forResource: stem, withExtension: ext, subdirectory: "Cosmos/thumbs")
            ?? Bundle.module.url(forResource: stem, withExtension: ext, subdirectory: "thumbs")
            ?? Bundle.module.url(forResource: stem, withExtension: ext)
    }

    // MARK: - Resource Resolution (Handles SwiftPM Flattened & Subdirectory Bundles)

    private static func resolveResourceURL(name: String, ext: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Cosmos")
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }

    private static func loadResourceData(name: String, ext: String) -> Data? {
        guard let url = resolveResourceURL(name: name, ext: ext) else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    // MARK: - Binary & JSON Decoders

    private static func loadBinaryStars() -> [PackedStar] {
        guard let data = loadResourceData(name: "stars_mag70", ext: "bin"), data.count >= 16 else {
            return []
        }

        return data.withUnsafeBytes { rawBuf -> [PackedStar] in
            guard let base = rawBuf.baseAddress else { return [] }
            let m0 = base.load(fromByteOffset: 0, as: UInt8.self)
            let m1 = base.load(fromByteOffset: 1, as: UInt8.self)
            let m2 = base.load(fromByteOffset: 2, as: UInt8.self)
            let m3 = base.load(fromByteOffset: 3, as: UInt8.self)
            guard m0 == 0x44, m1 == 0x43, m2 == 0x53, m3 == 0x54 else { return [] } // "DCST"

            let count = Int(UInt32(littleEndian: base.loadUnaligned(fromByteOffset: 8, as: UInt32.self)))
            let expectedBytes = 16 + count * 32
            guard rawBuf.count >= expectedBytes else { return [] }

            var result: [PackedStar] = []
            result.reserveCapacity(count)

            for i in 0..<count {
                let off = 16 + i * 32
                let hip = Int(UInt32(littleEndian: base.loadUnaligned(fromByteOffset: off, as: UInt32.self)))
                let ux = Float(bitPattern: UInt32(littleEndian: base.loadUnaligned(fromByteOffset: off + 4, as: UInt32.self)))
                let uy = Float(bitPattern: UInt32(littleEndian: base.loadUnaligned(fromByteOffset: off + 8, as: UInt32.self)))
                let uz = Float(bitPattern: UInt32(littleEndian: base.loadUnaligned(fromByteOffset: off + 12, as: UInt32.self)))
                let raH = Float(bitPattern: UInt32(littleEndian: base.loadUnaligned(fromByteOffset: off + 16, as: UInt32.self)))
                let decD = Float(bitPattern: UInt32(littleEndian: base.loadUnaligned(fromByteOffset: off + 20, as: UInt32.self)))
                let vMag = Float(bitPattern: UInt32(littleEndian: base.loadUnaligned(fromByteOffset: off + 24, as: UInt32.self)))
                let bvMillis = Int16(littleEndian: base.loadUnaligned(fromByteOffset: off + 28, as: Int16.self))
                let constIdx = UInt16(littleEndian: base.loadUnaligned(fromByteOffset: off + 30, as: UInt16.self))

                result.append(
                    PackedStar(
                        hip: hip,
                        ux: ux,
                        uy: uy,
                        uz: uz,
                        raHours: raH,
                        decDegrees: decD,
                        vMag: vMag,
                        bv: Float(bvMillis) / 1000.0,
                        constellationIndex: constIdx
                    )
                )
            }
            return result
        }
    }

    private static func loadStarDesignations() -> [Int: StarDesignation] {
        guard let data = loadResourceData(name: "star_names_iau", ext: "json"),
              let list = try? JSONDecoder().decode([StarDesignation].self, from: data) else {
            return [:]
        }
        var map: [Int: StarDesignation] = [:]
        map.reserveCapacity(list.count)
        for item in list {
            map[item.hip] = item
        }
        return map
    }

    private static func loadConstellations() -> [ConstellationRecord] {
        guard let data = loadResourceData(name: "constellations_iau88", ext: "json"),
              let list = try? JSONDecoder().decode([ConstellationRecord].self, from: data) else {
            return []
        }
        return list
    }

    private static func loadConstellationBorders() -> [ConstellationBorderArc] {
        guard let data = loadResourceData(name: "constellation_borders", ext: "json"),
              let list = try? JSONDecoder().decode([ConstellationBorderArc].self, from: data) else {
            return []
        }
        return list
    }

    private static func loadAsterisms() -> [AsterismRecord] {
        guard let data = loadResourceData(name: "asterisms", ext: "json"),
              let list = try? JSONDecoder().decode([AsterismRecord].self, from: data) else {
            return []
        }
        return list
    }

    private static func loadDeepSkyObjects() -> [DeepSkyObject] {
        struct RawDSO: Decodable {
            let id: String
            let catalog: String
            let ngcIc: String?
            let name: String
            let constellation: String
            let type: String
            let typeCode: String?
            let raHours: Double
            let decDeg: Double
            let visualMag: Double
            let surfaceBrightness: Double?
            let majorAxisArcmin: Double
            let minorAxisArcmin: Double
            let positionAngleDeg: Double?
            let distanceLy: Double?
            let recommendedOptics: String
            let thumbnail: String?
            let description: String
        }

        guard let data = loadResourceData(name: "dso_catalog", ext: "json"),
              let rawList = try? JSONDecoder().decode([RawDSO].self, from: data) else {
            return []
        }

        return rawList.map { r in
            let cleanNgc = (r.ngcIc?.isEmpty == false) ? r.ngcIc : nil
            let cleanThumb = (r.thumbnail?.isEmpty == false) ? r.thumbnail : nil
            return DeepSkyObject(
                id: r.id,
                catalog: r.catalog,
                name: r.name,
                ngc: cleanNgc,
                type: DSOType.fromCatalogCategory(r.type, typeCode: r.typeCode),
                morphType: r.type,
                constellationCode: r.constellation,
                rightAscensionHours: r.raHours,
                declinationDegrees: r.decDeg,
                visualMagnitude: r.visualMag,
                surfaceBrightness: r.surfaceBrightness,
                majorAxisArcmin: r.majorAxisArcmin,
                minorAxisArcmin: r.minorAxisArcmin,
                positionAngleDeg: r.positionAngleDeg ?? 0.0,
                distanceLightYears: r.distanceLy,
                recommendedOptics: r.recommendedOptics,
                thumbnail: cleanThumb,
                description: r.description
            )
        }
    }

    private static func loadMeteorShowers() -> [MeteorShowerRecord] {
        guard let data = loadResourceData(name: "meteor_showers_iau", ext: "json"),
              let list = try? JSONDecoder().decode([MeteorShowerRecord].self, from: data) else {
            return []
        }
        return list
    }

    private static func loadMilkyWayLayers() -> [MilkyWayIsophoteLayer] {
        struct RawLayer: Decodable {
            let level: Int
            let rings: [[[Double]]]
        }
        guard let data = loadResourceData(name: "milky_way_isophotes", ext: "json"),
              let raw = try? JSONDecoder().decode([RawLayer].self, from: data) else {
            return []
        }

        let deg2rad = Double.pi / 180.0
        return raw.map { layer in
            let convertedRings: [[SkyUnitVec3]] = layer.rings.map { ring in
                ring.compactMap { pt in
                    guard pt.count >= 2 else { return nil }
                    let raRad = pt[0] * 15.0 * deg2rad
                    let decRad = pt[1] * deg2rad
                    let ux = Float(cos(decRad) * cos(raRad))
                    let uy = Float(cos(decRad) * sin(raRad))
                    let uz = Float(sin(decRad))
                    return SkyUnitVec3(ux, uy, uz)
                }
            }
            return MilkyWayIsophoteLayer(level: layer.level, rings: convertedRings)
        }
    }
}
