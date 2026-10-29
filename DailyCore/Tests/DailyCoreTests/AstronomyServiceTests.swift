import XCTest
@testable import DailyCore

final class AstronomyServiceTests: XCTestCase {

    let bucharest = (latitude: 44.4323, longitude: 26.1063, elevation: 85.0)

    private struct GoldenFixture: Decodable {
        struct ExpectedPoint: Decodable {
            let x: Double
            let y: Double
            let cz: Double
        }
        struct CameraCase: Decodable {
            let name: String
            let camAz: Double
            let camAlt: Double
            let fov: Double
            let targetAz: Double
            let targetAlt: Double
            let width: Double
            let height: Double
            let expected: ExpectedPoint?
        }
        struct StarCase: Decodable {
            let name: String
            let utc: String
            let lat: Double
            let lon: Double
            let hip: Int
            let raHours: Double
            let decDeg: Double
            let expectedAzDeg: Double
            let expectedAltDeg: Double
            let expectedHorNWZ: [Double]
        }
        struct MoonCase: Decodable {
            let utc: String
            let lat: Double
            let lon: Double
            let expectedGeoDistanceKm: Double
            let expectedTopoDistanceKm: Double
            let expectedPhaseFraction: Double
            let expectedBrightLimbDeg: Double
        }
        struct GalileanMoonExpected: Decodable {
            let name: String
            let offsetRightRadii: Double
            let offsetUpRadii: Double
            let depthRadii: Double
        }
        struct JupiterMoonsCase: Decodable {
            let utc: String
            let lat: Double
            let lon: Double
            let moons: [GalileanMoonExpected]
        }
        struct Sgp4TopocentricExpected: Decodable {
            let utc: String
            let lat: Double
            let lon: Double
            let elevM: Double
            let azDeg: Double
            let altDeg: Double
            let rangeKm: Double
        }
        struct Sgp4Case: Decodable {
            let omm: CelesTrakOmmRecord
            let temeAtEpochKm: [Double]
            let temePlus45MinKm: [Double]
            let topocentricPlus45Min: Sgp4TopocentricExpected
        }
        struct ScoreCase: Decodable {
            let name: String
            let cloudLow: Double
            let cloudMid: Double
            let cloudHigh: Double
            let moonIllum: Double
            let moonAltDeg: Double
            let bortle: Int
            let seeingArcsec: Double
            let tempC: Double
            let dewPointC: Double
            let expectedScore: Int
        }

        let cameraProjectionCases: [CameraCase]
        let starEqjToHorCases: [StarCase]
        let moonMetricsCase: MoonCase
        let jupiterGalileanMoonsCase: JupiterMoonsCase
        let sgp4IssCase: Sgp4Case
        let stargazingScoreCases: [ScoreCase]
    }

    private func loadGoldenFixture() throws -> GoldenFixture {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent() // DailyCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // DailyCore
            .deletingLastPathComponent() // Daily
        let fixtureURL = repoRoot.appendingPathComponent("Tests/Fixtures/cosmos_golden_vectors.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(GoldenFixture.self, from: data)
    }

    func testTimeConversionRoundTripAndEnglishBodyNames() {
        let originalDate = Date()
        let astroTime = AstronomyService.shared.makeAstroTime(from: originalDate)
        let restoredDate = AstronomyService.shared.date(from: astroTime)
        XCTAssertEqual(originalDate.timeIntervalSince1970, restoredDate.timeIntervalSince1970, accuracy: 0.1)

        // Verify 100% English display names (zero leftover Romanian names)
        XCTAssertEqual(CelestialBody.sun.displayName, "Sun")
        XCTAssertEqual(CelestialBody.moon.displayName, "Moon")
        XCTAssertEqual(CelestialBody.mercury.displayName, "Mercury")
        XCTAssertEqual(CelestialBody.mars.displayName, "Mars")
        XCTAssertEqual(CelestialBody.neptune.displayName, "Neptune")
    }

    func testGoldenCameraProjectionMatrixNorthEastSouthWestZenithWraparound() throws {
        let fixture = try loadGoldenFixture()
        let service = AstronomyService.shared

        for c in fixture.cameraProjectionCases {
            let actual = service.projectHorizontal(
                azimuthDegrees: c.targetAz,
                altitudeDegrees: c.targetAlt,
                cameraAzimuthDegrees: c.camAz,
                cameraAltitudeDegrees: c.camAlt,
                fovDegrees: c.fov,
                viewportWidth: c.width,
                viewportHeight: c.height
            )
            if let exp = c.expected {
                guard let act = actual else {
                    XCTFail("Expected visible projection for \(c.name), got nil")
                    continue
                }
                XCTAssertEqual(act.x, exp.x, accuracy: 0.02, "X mismatch in \(c.name)")
                XCTAssertEqual(act.y, exp.y, accuracy: 0.02, "Y mismatch in \(c.name)")
            } else {
                XCTAssertNil(actual, "Expected behind-camera nil for \(c.name)")
            }
        }
    }

    func testGoldenStarEQJToHorizontalAndUnprojectRoundTrip() throws {
        let fixture = try loadGoldenFixture()
        let service = AstronomyService.shared
        let iso = ISO8601DateFormatter()

        for sc in fixture.starEqjToHorCases {
            let date = try XCTUnwrap(iso.date(from: sc.utc))
            let res = service.starHorizontalCoordinates(
                raHours: sc.raHours,
                decDegrees: sc.decDeg,
                for: (sc.lat, sc.lon, 0.0),
                at: date,
                includeRefraction: true
            )
            XCTAssertEqual(res.azimuthDegrees, sc.expectedAzDeg, accuracy: 0.01, "Azimuth mismatch for \(sc.name)")
            XCTAssertEqual(res.altitudeDegrees, sc.expectedAltDeg, accuracy: 0.01, "Altitude mismatch for \(sc.name)")
            XCTAssertEqual(res.horNWZ.0, sc.expectedHorNWZ[0], accuracy: 1e-4)
            XCTAssertEqual(res.horNWZ.1, sc.expectedHorNWZ[1], accuracy: 1e-4)
            XCTAssertEqual(res.horNWZ.2, sc.expectedHorNWZ[2], accuracy: 1e-4)

            // Verify SkyProjectionMatrix centers the star when camera points at (Az, Alt)
            let mat = service.makeProjectionMatrix(
                observerLatitudeDegrees: sc.lat,
                observerLongitudeDegrees: sc.lon,
                date: date,
                cameraAzimuthDegrees: res.azimuthDegrees,
                cameraAltitudeDegrees: res.altitudeDegrees,
                fovDegrees: 60.0,
                viewportWidth: 1000.0,
                viewportHeight: 800.0
            )
            let raRad = sc.raHours * 15.0 * (.pi / 180.0)
            let decRad = sc.decDeg * (.pi / 180.0)
            let p = try XCTUnwrap(mat.projectEQJUnitVector(
                ux: cos(decRad) * cos(raRad),
                uy: cos(decRad) * sin(raRad),
                uz: sin(decRad)
            ))
            // Unrefracted vs refracted differs by < 0.05° (~1.5 px at 60° FOV)
            XCTAssertEqual(p.x, 500.0, accuracy: 3.0)
            XCTAssertEqual(p.y, 400.0, accuracy: 3.0)

            let unproj = try XCTUnwrap(mat.unprojectToHorizontal(screenX: 500.0, screenY: 400.0))
            XCTAssertEqual(unproj.altitudeDegrees, res.altitudeDegrees, accuracy: 0.01)
        }
    }

    func testGoldenMoonDistanceAndBrightLimbAngleAndGalileanMoons() throws {
        let fixture = try loadGoldenFixture()
        let service = AstronomyService.shared
        let iso = ISO8601DateFormatter()

        let mc = fixture.moonMetricsCase
        let mDate = try XCTUnwrap(iso.date(from: mc.utc))
        let moon = service.moonPhase(at: mDate, observer: (mc.lat, mc.lon))
        // Must be Earth-Moon distance (~365,165 km), NEVER heliocentric 149.6M km!
        XCTAssertGreaterThan(moon.distanceKm, 350_000.0)
        XCTAssertLessThan(moon.distanceKm, 410_000.0)
        XCTAssertEqual(moon.distanceKm, mc.expectedGeoDistanceKm, accuracy: 5.0)
        XCTAssertEqual(try XCTUnwrap(moon.topocentricDistanceKm), mc.expectedTopoDistanceKm, accuracy: 5.0)
        XCTAssertEqual(moon.illuminatedFraction, mc.expectedPhaseFraction, accuracy: 0.001)
        XCTAssertEqual(moon.brightLimbAngleDegrees, mc.expectedBrightLimbDeg, accuracy: 0.05)

        let jc = fixture.jupiterGalileanMoonsCase
        let jDate = try XCTUnwrap(iso.date(from: jc.utc))
        let jMoons = service.jupiterMoons(at: jDate, observer: (jc.lat, jc.lon)).all
        XCTAssertEqual(jMoons.count, 4)
        for (idx, exp) in jc.moons.enumerated() {
            XCTAssertEqual(jMoons[idx].name, exp.name)
            XCTAssertEqual(jMoons[idx].xRadius, exp.offsetRightRadii, accuracy: 0.02)
            XCTAssertEqual(jMoons[idx].yRadius, exp.offsetUpRadii, accuracy: 0.02)
            XCTAssertEqual(jMoons[idx].depthRadius, exp.depthRadii, accuracy: 0.02)
        }
    }

    func testGoldenSGP4OrbitalPropagatorAndPassSolver() throws {
        let fixture = try loadGoldenFixture()
        let sc = fixture.sgp4IssCase

        let teme0 = try XCTUnwrap(SGP4Propagator.propagateTEMEKm(omm: sc.omm, minutesSinceEpoch: 0.0))
        XCTAssertEqual(teme0.x, sc.temeAtEpochKm[0], accuracy: 0.05)
        XCTAssertEqual(teme0.y, sc.temeAtEpochKm[1], accuracy: 0.05)
        XCTAssertEqual(teme0.z, sc.temeAtEpochKm[2], accuracy: 0.05)

        let teme45 = try XCTUnwrap(SGP4Propagator.propagateTEMEKm(omm: sc.omm, minutesSinceEpoch: 45.0))
        XCTAssertEqual(teme45.x, sc.temePlus45MinKm[0], accuracy: 0.05)
        XCTAssertEqual(teme45.y, sc.temePlus45MinKm[1], accuracy: 0.05)
        XCTAssertEqual(teme45.z, sc.temePlus45MinKm[2], accuracy: 0.05)

        let iso = ISO8601DateFormatter()
        let date45 = try XCTUnwrap(iso.date(from: sc.topocentricPlus45Min.utc))
        let livePos = try XCTUnwrap(SGP4Propagator.livePosition(
            omm: sc.omm,
            at: date45,
            latitudeDegrees: sc.topocentricPlus45Min.lat,
            longitudeDegrees: sc.topocentricPlus45Min.lon,
            elevationMeters: sc.topocentricPlus45Min.elevM
        ))
        XCTAssertEqual(livePos.azimuthDegrees, sc.topocentricPlus45Min.azDeg, accuracy: 0.05)
        XCTAssertEqual(livePos.altitudeDegrees, sc.topocentricPlus45Min.altDeg, accuracy: 0.05)
        XCTAssertEqual(livePos.rangeKm, sc.topocentricPlus45Min.rangeKm, accuracy: 0.5)
        XCTAssertGreaterThan(livePos.orbitalAltitudeKm, 390.0)
        XCTAssertLessThan(livePos.orbitalAltitudeKm, 450.0)
    }

    func testGoldenStargazingDeterministicScore() throws {
        let fixture = try loadGoldenFixture()
        for c in fixture.stargazingScoreCases {
            let actual = AstronomyService.computeDeterministicSkyScore(
                cloudLowPercent: c.cloudLow,
                cloudMidPercent: c.cloudMid,
                cloudHighPercent: c.cloudHigh,
                moonIlluminatedFraction: c.moonIllum,
                moonAltitudeDegrees: c.moonAltDeg,
                bortleClass: c.bortle,
                seeingArcseconds: c.seeingArcsec,
                temperatureCelsius: c.tempC,
                dewPointCelsius: c.dewPointC
            )
            XCTAssertEqual(actual, c.expectedScore, "Score mismatch for \(c.name)")
        }
    }

    func testCanonicalOfflineCatalogsIntegrity() {
        let catalog = CosmosCatalogService.shared

        // 15,544 Hipparcos stars (mag <= 7.0 + constellation anchors)
        XCTAssertGreaterThanOrEqual(catalog.stars.count, 15_000)
        XCTAssertNotNil(catalog.star(forHip: 32349), "Sirius (HIP 32349) must be present")
        XCTAssertEqual(catalog.starName(forHip: 32349), "Sirius")
        XCTAssertNotNil(catalog.star(forHip: 11767), "Polaris (HIP 11767) must be present")
        XCTAssertEqual(catalog.starName(forHip: 11767), "Polaris")

        // All 88 official IAU constellations with 100% resolvable HIP stick-figure segments
        XCTAssertEqual(catalog.constellations.count, 88)
        var totalSegments = 0
        for c in catalog.constellations {
            for seg in c.segments {
                XCTAssertEqual(seg.count, 2)
                XCTAssertNotNil(catalog.star(forHip: seg[0]), "Missing star HIP \(seg[0]) in \(c.id)")
                XCTAssertNotNil(catalog.star(forHip: seg[1]), "Missing star HIP \(seg[1]) in \(c.id)")
                totalSegments += 1
            }
        }
        XCTAssertGreaterThan(totalSegments, 600)

        // Constellation borders & famous asterisms
        XCTAssertGreaterThan(catalog.constellationBorders.count, 200)
        XCTAssertEqual(catalog.asterisms.count, 14)

        // 219 Messier (110) + Caldwell (109) Deep-Sky Objects + bundled thumbnails
        XCTAssertEqual(catalog.deepSkyObjects.count, 219)
        let m31 = catalog.deepSkyObjects.first(where: { $0.id == "M31" })
        XCTAssertNotNil(m31)
        XCTAssertNotNil(catalog.thumbnailURL(for: m31?.thumbnail), "M31 thumbnail must resolve from Bundle.module")

        // 22 IAU Meteor Showers & 5 Milky Way isophote layers
        XCTAssertEqual(catalog.meteorShowers.count, 22)
        XCTAssertEqual(catalog.milkyWayLayers.count, 5)

        // Global Bortle grid: urban Bucharest > Atacama desert
        let bucharestBortle = catalog.bortleClass(latitude: 44.4323, longitude: 26.1063)
        let atacamaBortle = catalog.bortleClass(latitude: -24.6272, longitude: -70.4042)
        XCTAssertGreaterThan(bucharestBortle, atacamaBortle)
    }
}
