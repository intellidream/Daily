import XCTest
@testable import DailyCore

final class AstronomyServiceTests: XCTestCase {

    let bucharest = (latitude: 44.4323, longitude: 26.1063, elevation: 85.0)

    func testTimeConversionRoundTrip() {
        let originalDate = Date()
        let astroTime = AstronomyService.shared.makeAstroTime(from: originalDate)
        let restoredDate = AstronomyService.shared.date(from: astroTime)

        // Tolerance within 0.1 seconds
        XCTAssertEqual(originalDate.timeIntervalSince1970, restoredDate.timeIntervalSince1970, accuracy: 0.1)
    }

    func testSunAndPlanetaryCoordinates() {
        let service = AstronomyService.shared
        let date = Date()

        let sun = service.coordinates(of: .sun, for: bucharest, at: date)
        XCTAssertGreaterThan(sun.visualMagnitude, -28.0)
        XCTAssertLessThan(sun.visualMagnitude, -25.0)
        XCTAssertGreaterThan(sun.distanceAU, 0.98)
        XCTAssertLessThan(sun.distanceAU, 1.02)

        let moon = service.coordinates(of: .moon, for: bucharest, at: date)
        XCTAssertGreaterThan(moon.visualMagnitude, -14.0)
        XCTAssertLessThan(moon.visualMagnitude, 0.0)

        let jupiter = service.coordinates(of: .jupiter, for: bucharest, at: date)
        XCTAssertGreaterThan(jupiter.distanceAU, 3.8)
        XCTAssertLessThan(jupiter.distanceAU, 6.5)
        XCTAssertGreaterThan(jupiter.visualMagnitude, -3.2)
        XCTAssertLessThan(jupiter.visualMagnitude, -1.0)

        let saturn = service.coordinates(of: .saturn, for: bucharest, at: date)
        XCTAssertGreaterThan(saturn.distanceAU, 8.0)
        XCTAssertLessThan(saturn.distanceAU, 11.5)
    }

    func testMoonPhaseEvaluation() {
        let service = AstronomyService.shared
        let info = service.moonPhase(at: Date())

        XCTAssertGreaterThanOrEqual(info.illuminatedFraction, 0.0)
        XCTAssertLessThanOrEqual(info.illuminatedFraction, 1.0)
        XCTAssertGreaterThanOrEqual(info.phaseAngleDegrees, 0.0)
        XCTAssertLessThanOrEqual(info.phaseAngleDegrees, 360.0)
        XCTAssertGreaterThanOrEqual(info.ageDays, 0.0)
        XCTAssertLessThanOrEqual(info.ageDays, 30.0)
        XCTAssertFalse(info.quarter.displayNameRo.isEmpty)
        XCTAssertTrue(info.quarter.sfSymbol.contains("moonphase"))
    }

    func testSunTimesChronologicalSequence() {
        let service = AstronomyService.shared
        // Test near equinox
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!

        let times = service.sunTimes(for: (bucharest.latitude, bucharest.longitude), on: date)

        guard let dawnAstro = times.dawnAstronomical,
              let dawnNaut = times.dawnNautical,
              let dawnCivil = times.dawnCivil,
              let sunrise = times.sunrise,
              let noon = times.solarNoon,
              let sunset = times.sunset,
              let duskCivil = times.duskCivil,
              let duskNaut = times.duskNautical,
              let duskAstro = times.duskAstronomical else {
            XCTFail("All sun and twilight times should resolve for mid-latitude")
            return
        }

        XCTAssertLessThan(dawnAstro, dawnNaut)
        XCTAssertLessThan(dawnNaut, dawnCivil)
        XCTAssertLessThan(dawnCivil, sunrise)
        XCTAssertLessThan(sunrise, noon)
        XCTAssertLessThan(noon, sunset)
        XCTAssertLessThan(sunset, duskCivil)
        XCTAssertLessThan(duskCivil, duskNaut)
        XCTAssertLessThan(duskNaut, duskAstro)
    }

    func testJupiterGalileanMoons() {
        let service = AstronomyService.shared
        let moons = service.jupiterMoons(at: Date())

        // Io orbital radius ~ 5.9 R_jup, Callisto ~ 26.5 R_jup
        XCTAssertNotEqual(moons.io.xRadius, 0.0)
        XCTAssertNotEqual(moons.europa.xRadius, 0.0)
        XCTAssertNotEqual(moons.ganymede.xRadius, 0.0)
        XCTAssertNotEqual(moons.callisto.xRadius, 0.0)
    }

    func testStargazingScoreDiscrimination() {
        let service = AstronomyService.shared

        // Midnight UTC on pristine New Moon night, 0% clouds, Bortle 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let nightDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 22, minute: 0))!

        let pristineConditions = service.evaluateStargazingConditions(
            observer: (bucharest.latitude, bucharest.longitude),
            date: nightDate,
            cloudCoverTotal: 0,
            cloudCoverLow: 0,
            cloudCoverMid: 0,
            cloudCoverHigh: 0,
            bortleClass: 1,
            seeingArcseconds: 0.6,
            dewPointDepression: 5.0
        )

        XCTAssertGreaterThanOrEqual(pristineConditions.score, 85)
        XCTAssertEqual(pristineConditions.quality, .pristine)

        // Midday with 100% clouds
        let noonDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 10, minute: 0))!
        let overcastDay = service.evaluateStargazingConditions(
            observer: (bucharest.latitude, bucharest.longitude),
            date: noonDate,
            cloudCoverTotal: 100,
            cloudCoverLow: 100,
            cloudCoverMid: 80,
            cloudCoverHigh: 50,
            bortleClass: 7
        )

        XCTAssertLessThan(overcastDay.score, 20)
        XCTAssertEqual(overcastDay.quality, .poor)
    }

    func testStereographicProjection() {
        let service = AstronomyService.shared
        let date = Date()

        // Polaris: RA ~ 2.5h, Dec ~ +89.3°
        let polarisProjection = service.projectStereographic(
            raHours: 2.53,
            decDegrees: 89.26,
            observerLatitudeDegrees: 44.43,
            observerLongitudeDegrees: 26.10,
            date: date,
            cameraAzimuthDegrees: 0.0, // Looking North
            cameraAltitudeDegrees: 44.43, // Looking at altitude of celestial pole
            cameraRollDegrees: 0.0,
            fovDegrees: 60.0,
            viewportWidth: 800.0,
            viewportHeight: 600.0
        )

        XCTAssertNotNil(polarisProjection)
        guard let p = polarisProjection else { return }

        // Polaris should be near the center of screen when looking directly at celestial pole
        XCTAssertEqual(p.x, 400.0, accuracy: 40.0)
        XCTAssertEqual(p.y, 300.0, accuracy: 40.0)
        XCTAssertTrue(p.isVisible)
    }
}
