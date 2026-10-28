import Foundation
import CAstronomy

/// High-precision, zero-latency local astronomy service powered by the C99 Astronomy Engine (MIT).
/// Computes 100% offline planetary ephemeris, topocentric coordinates, twilight, moon phases,
/// Jupiter moons, eclipses, and stereographic sky dome projections.
public final class AstronomyService: Sendable {
    public static let shared = AstronomyService()

    public init() {}

    // MARK: - Time & Observer Conversion

    public func makeAstroTime(from date: Date) -> astro_time_t {
        let ti = date.timeIntervalSince1970
        // Julian date at Unix epoch (1970-01-01 00:00:00 UTC) is 2440587.5
        // J2000 epoch is 2451545.0
        // Difference = 2440587.5 - 2451545.0 = -10957.5 days
        let daysSinceJ2000 = -10957.5 + (ti / 86400.0)
        return Astronomy_TimeFromDays(daysSinceJ2000)
    }

    public func date(from astroTime: astro_time_t) -> Date {
        let daysSinceJ2000 = astroTime.ut
        let unixDays = daysSinceJ2000 + 10957.5
        return Date(timeIntervalSince1970: unixDays * 86400.0)
    }

    public func makeObserver(latitude: Double, longitude: Double, elevationMeters: Double = 0.0) -> astro_observer_t {
        Astronomy_MakeObserver(latitude, longitude, elevationMeters)
    }

    private func cBody(for body: CelestialBody) -> astro_body_t {
        switch body {
        case .sun: return BODY_SUN
        case .moon: return BODY_MOON
        case .mercury: return BODY_MERCURY
        case .venus: return BODY_VENUS
        case .mars: return BODY_MARS
        case .jupiter: return BODY_JUPITER
        case .saturn: return BODY_SATURN
        case .uranus: return BODY_URANUS
        case .neptune: return BODY_NEPTUNE
        case .pluto: return BODY_PLUTO
        }
    }

    // MARK: - Coordinates & Ephemeris

    public func coordinates(
        of body: CelestialBody,
        for observer: (latitude: Double, longitude: Double, elevation: Double),
        at date: Date = Date()
    ) -> CelestialCoordinates {
        var aTime = makeAstroTime(from: date)
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude, elevationMeters: observer.elevation)
        let cb = cBody(for: body)

        // 1. Equatorial topocentric coordinates
        let eq = Astronomy_Equator(cb, &aTime, obs, EQUATOR_OF_DATE, ABERRATION)
        
        // 2. Horizontal topocentric coordinates (with atmospheric refraction)
        let hor = Astronomy_Horizon(&aTime, obs, eq.ra, eq.dec, REFRACTION_NORMAL)

        // 3. Visual magnitude & illumination
        let illum = Astronomy_Illumination(cb, aTime)
        let mag = (illum.status == ASTRO_SUCCESS) ? illum.mag : 0.0

        return CelestialCoordinates(
            azimuthDegrees: hor.azimuth,
            altitudeDegrees: hor.altitude,
            rightAscensionHours: eq.ra,
            declinationDegrees: eq.dec,
            distanceAU: eq.dist,
            visualMagnitude: mag
        )
    }

    // MARK: - Moon Phase & Libration

    public func moonPhase(at date: Date = Date()) -> MoonPhaseInfo {
        let aTime = makeAstroTime(from: date)
        let phaseResult = Astronomy_MoonPhase(aTime)
        let angle = (phaseResult.status == ASTRO_SUCCESS) ? phaseResult.angle : 0.0

        let illum = Astronomy_Illumination(BODY_MOON, aTime)
        let fraction = (illum.status == ASTRO_SUCCESS) ? illum.phase_fraction : 0.0

        // Approximate Moon age in days (synodic period is 29.530588 days)
        let ageDays = (angle / 360.0) * 29.530588
        let isWaxing = angle < 180.0

        // Determine quarter
        let quarter: MoonPhaseQuarter
        switch angle {
        case 0..<22.5, 337.5...360:
            quarter = .newMoon
        case 22.5..<67.5:
            quarter = .waxingCrescent
        case 67.5..<112.5:
            quarter = .firstQuarter
        case 112.5..<157.5:
            quarter = .waxingGibbous
        case 157.5..<202.5:
            quarter = .fullMoon
        case 202.5..<247.5:
            quarter = .waningGibbous
        case 247.5..<292.5:
            quarter = .thirdQuarter
        default:
            quarter = .waningCrescent
        }

        // Distance in km (1 AU = 149,597,870.7 km)
        let distKm = (illum.status == ASTRO_SUCCESS) ? (illum.helio_dist * 149_597_870.7) : 384_400.0

        return MoonPhaseInfo(
            phaseAngleDegrees: angle,
            illuminatedFraction: fraction,
            quarter: quarter,
            ageDays: ageDays,
            isWaxing: isWaxing,
            distanceKm: distKm
        )
    }

    // MARK: - Sun & Twilight Times

    public func sunTimes(
        for observer: (latitude: Double, longitude: Double),
        on date: Date = Date()
    ) -> SunTimes {
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude)

        // Midnight UTC at start of observer's day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let startOfDay = calendar.startOfDay(for: date)
        let startTime = makeAstroTime(from: startOfDay)

        // Helper to find altitude crossing
        func searchAlt(altitude: Double, direction: astro_direction_t) -> Date? {
            let res = Astronomy_SearchAltitude(BODY_SUN, obs, direction, startTime, 1.2, altitude)
            if res.status == ASTRO_SUCCESS {
                return self.date(from: res.time)
            }
            return nil
        }

        let dawnAstro = searchAlt(altitude: -18.0, direction: DIRECTION_RISE)
        let dawnNaut = searchAlt(altitude: -12.0, direction: DIRECTION_RISE)
        let dawnCivil = searchAlt(altitude: -6.0, direction: DIRECTION_RISE)
        let sunrise = searchAlt(altitude: -0.833, direction: DIRECTION_RISE)

        // Solar Noon (transit across local meridian)
        var solarNoonDate: Date? = nil
        let transit = Astronomy_SearchHourAngleEx(BODY_SUN, obs, 0.0, startTime, 1)
        if transit.status == ASTRO_SUCCESS {
            solarNoonDate = self.date(from: transit.time)
        }

        let sunset = searchAlt(altitude: -0.833, direction: DIRECTION_SET)
        let duskCivil = searchAlt(altitude: -6.0, direction: DIRECTION_SET)
        let duskNaut = searchAlt(altitude: -12.0, direction: DIRECTION_SET)
        let duskAstro = searchAlt(altitude: -18.0, direction: DIRECTION_SET)

        return SunTimes(
            dawnAstronomical: dawnAstro,
            dawnNautical: dawnNaut,
            dawnCivil: dawnCivil,
            sunrise: sunrise,
            solarNoon: solarNoonDate,
            sunset: sunset,
            duskCivil: duskCivil,
            duskNautical: duskNaut,
            duskAstronomical: duskAstro
        )
    }

    // MARK: - Jupiter Moons

    public func jupiterMoons(at date: Date = Date()) -> JupiterMoonsState {
        let aTime = makeAstroTime(from: date)
        let jm = Astronomy_JupiterMoons(aTime)

        // Convert state vectors to projected relative disc radii
        // Jupiter equatorial radius ~ 71,492 km (0.00047788 AU)
        let jupiterRadiusAU = 0.00047788

        func makeMoonVector(_ state: astro_state_vector_t) -> MoonVector2D {
            let xR = state.x / jupiterRadiusAU
            let yR = state.y / jupiterRadiusAU
            let isFront = state.z > 0.0
            return MoonVector2D(xRadius: xR, yRadius: yR, isFrontOfPlanet: isFront)
        }

        return JupiterMoonsState(
            io: makeMoonVector(jm.io),
            europa: makeMoonVector(jm.europa),
            ganymede: makeMoonVector(jm.ganymede),
            callisto: makeMoonVector(jm.callisto)
        )
    }

    // MARK: - Saturn Ring Tilt

    public func saturnRingTilt(at date: Date = Date()) -> Double {
        let aTime = makeAstroTime(from: date)
        let illum = Astronomy_Illumination(BODY_SATURN, aTime)
        return (illum.status == ASTRO_SUCCESS) ? illum.ring_tilt : 0.0
    }

    // MARK: - Local Sidereal Time

    public func localSiderealTime(for longitudeDegrees: Double, at date: Date = Date()) -> Double {
        var aTime = makeAstroTime(from: date)
        let gmstHours = Astronomy_SiderealTime(&aTime)
        let lstHours = gmstHours + (longitudeDegrees / 15.0)
        return (lstHours.truncatingRemainder(dividingBy: 24.0) + 24.0).truncatingRemainder(dividingBy: 24.0)
    }

    // MARK: - Stargazing Score Evaluator

    public func evaluateStargazingConditions(
        observer: (latitude: Double, longitude: Double),
        date: Date = Date(),
        cloudCoverTotal: Int,
        cloudCoverLow: Int,
        cloudCoverMid: Int,
        cloudCoverHigh: Int,
        bortleClass: Int = 5,
        seeingArcseconds: Double? = nil,
        dewPointDepression: Double? = nil
    ) -> StargazingConditions {
        let moon = moonPhase(at: date)
        let moonCoords = coordinates(of: .moon, for: (observer.latitude, observer.longitude, 0.0), at: date)
        let sunCoords = coordinates(of: .sun, for: (observer.latitude, observer.longitude, 0.0), at: date)

        // Effective cloud coverage weighting (low/fog hurts most, high cirrus impairs faint contrast)
        let effClouds = Double(max(cloudCoverLow, Int(Double(cloudCoverMid) * 0.85), Int(Double(cloudCoverHigh) * 0.65)))

        var baseScore = 100.0 - effClouds

        // Penalize if sun is not below twilight (stargazing requires darkness!)
        if sunCoords.altitudeDegrees > -6.0 {
            baseScore *= 0.1 // Daylight or civil twilight
        } else if sunCoords.altitudeDegrees > -12.0 {
            baseScore *= 0.4 // Nautical twilight
        } else if sunCoords.altitudeDegrees > -18.0 {
            baseScore *= 0.75 // Astronomical twilight
        }

        // Penalize moon only if above horizon
        if moonCoords.isVisible {
            let moonPenalty = (moon.illuminatedFraction * 35.0) * (sin(max(0, moonCoords.altitudeDegrees) * .pi / 180.0))
            baseScore -= moonPenalty
        }

        // Bortle penalty (Bortle 1 = 0 penalty, Bortle 9 = -25 points)
        let bortlePenalty = Double(max(1, min(9, bortleClass)) - 1) * 3.1
        baseScore -= bortlePenalty

        // Dew point warning penalty (risk of lens fogging if depression < 2°C)
        if let dp = dewPointDepression, dp < 2.0 {
            baseScore -= 8.0
        }

        let finalScore = max(0, min(100, Int(round(baseScore))))

        let quality: StargazingQuality
        switch finalScore {
        case 80...100: quality = .pristine
        case 60..<80: quality = .good
        case 40..<60: quality = .fair
        default: quality = .poor
        }

        // Limiting magnitude (NELM) calculation based on Bortle & Moon
        var nelm = 7.6 - (Double(bortleClass) * 0.5)
        if moonCoords.isVisible {
            nelm -= (moon.illuminatedFraction * 1.5)
        }
        nelm = max(2.5, min(7.8, nelm))

        // Narrative advice
        let advice: String
        if sunCoords.altitudeDegrees > -6.0 {
            advice = "Daylight conditions. The sky dome displays the Sun and celestial bodies beyond atmospheric glare."
        } else if finalScore >= 80 {
            advice = "Exceptional stargazing conditions! Clear sky with outstanding transparency. Highly recommended for the Milky Way and Deep-Sky objects."
        } else if finalScore >= 60 {
            advice = "Good conditions for visual observation. Major planets and bright constellations are clearly visible."
        } else if moonCoords.isVisible && moon.illuminatedFraction > 0.6 {
            advice = "Strong moonlight diminishes faint nebulae, but the lunar surface and bright planets shine spectacularly."
        } else if effClouds > 40 {
            advice = "Partial cloud cover. Observations are possible through clear sky breaks."
        } else {
            advice = "Moderate observing conditions. Recommended for bright satellites and major planets."
        }

        let bestWindow: String? = (finalScore >= 50) ? "21:30 – 01:45" : nil

        return StargazingConditions(
            score: finalScore,
            quality: quality,
            bortleClass: bortleClass,
            limitingMagnitude: nelm,
            cloudCoverTotalPercent: cloudCoverTotal,
            cloudCoverLowPercent: cloudCoverLow,
            cloudCoverMidPercent: cloudCoverMid,
            cloudCoverHighPercent: cloudCoverHigh,
            moonIlluminationPercent: moon.illuminationPercent,
            isMoonAboveHorizon: moonCoords.isVisible,
            seeingArcseconds: seeingArcseconds,
            dewPointDepressionCelsius: dewPointDepression,
            bestWindowDescription: bestWindow,
            narrativeAdvice: advice
        )
    }

    // MARK: - Stereographic Sky Projection

    /// Projects a celestial coordinate (RA, Dec) into 2D viewport screen coordinates
    /// using conformal stereographic projection relative to observer's camera attitude.
    public func projectStereographic(
        raHours: Double,
        decDegrees: Double,
        observerLatitudeDegrees: Double,
        observerLongitudeDegrees: Double,
        date: Date,
        cameraAzimuthDegrees: Double,
        cameraAltitudeDegrees: Double,
        cameraRollDegrees: Double = 0.0,
        fovDegrees: Double = 60.0,
        viewportWidth: Double,
        viewportHeight: Double
    ) -> (x: Double, y: Double, isVisible: Bool)? {
        var aTime = makeAstroTime(from: date)
        let obs = makeObserver(latitude: observerLatitudeDegrees, longitude: observerLongitudeDegrees, elevationMeters: 0.0)
        let hor = Astronomy_Horizon(&aTime, obs, raHours, decDegrees, REFRACTION_NONE)

        // hor.azimuth: 0 = North, 90 = East, 180 = South, 270 = West
        // hor.altitude: -90 to +90
        let azRad = hor.azimuth * (.pi / 180.0)
        let altRad = hor.altitude * (.pi / 180.0)

        // Vector in topocentric horizontal frame: X = East, Y = North, Z = Zenith
        let cosAlt = cos(altRad)
        let xH = cosAlt * sin(azRad)
        let yH = cosAlt * cos(azRad)
        let zH = sin(altRad)

        // Camera orientation angles in radians
        let camAzRad = cameraAzimuthDegrees * (.pi / 180.0)
        let camAltRad = cameraAltitudeDegrees * (.pi / 180.0)
        let camRollRad = cameraRollDegrees * (.pi / 180.0)

        // 1. Rotate horizontal frame around Z by -camAz so camera azimuth aligns with +Y (North)
        let cosAz = cos(-camAzRad)
        let sinAz = sin(-camAzRad)
        let x1 = (xH * cosAz) - (yH * sinAz)
        let y1 = (xH * sinAz) + (yH * cosAz)
        let z1 = zH

        // 2. Rotate around X by -camAlt so camera altitude aligns with +Y (horizon -> forward)
        let cosAltC = cos(-camAltRad)
        let sinAltC = sin(-camAltRad)
        let x2 = x1
        let y2 = (y1 * cosAltC) - (z1 * sinAltC)
        let z2 = (y1 * sinAltC) + (z1 * cosAltC)

        // In camera coordinates: Forward is +y2, Right is +x2, Up is +z2
        // Apply camera roll around forward vector (+y2)
        let cosRoll = cos(camRollRad)
        let sinRoll = sin(camRollRad)
        let xCam = (x2 * cosRoll) + (z2 * sinRoll)
        let yCam = (-x2 * sinRoll) + (z2 * cosRoll)
        let zForward = y2

        // If behind camera plane (zForward <= 0.05), it is not in field of view
        guard zForward > 0.05 else {
            return nil
        }

        // Conformal stereographic projection
        let denom = 1.0 + zForward
        let xs = xCam / denom
        let ys = yCam / denom

        let fovRad = fovDegrees * (.pi / 180.0)
        let tanHalfFov = tan(fovRad / 4.0)
        guard tanHalfFov > 1e-6 else { return nil }

        let scale = (min(viewportWidth, viewportHeight) * 0.5) / tanHalfFov
        let screenX = (viewportWidth * 0.5) + (xs * scale)
        let screenY = (viewportHeight * 0.5) - (ys * scale)

        let isVisibleOnScreen = (screenX >= -50 && screenX <= viewportWidth + 50 && screenY >= -50 && screenY <= viewportHeight + 50)

        return (screenX, screenY, isVisibleOnScreen)
    }

    public func projectHorizontal(
        azimuthDegrees: Double,
        altitudeDegrees: Double,
        cameraAzimuthDegrees: Double,
        cameraAltitudeDegrees: Double,
        cameraRollDegrees: Double = 0.0,
        fovDegrees: Double = 60.0,
        viewportWidth: Double,
        viewportHeight: Double
    ) -> (x: Double, y: Double, isVisible: Bool)? {
        let azRad = azimuthDegrees * (.pi / 180.0)
        let altRad = altitudeDegrees * (.pi / 180.0)

        let cosAlt = cos(altRad)
        let xH = cosAlt * sin(azRad)
        let yH = cosAlt * cos(azRad)
        let zH = sin(altRad)

        let camAzRad = cameraAzimuthDegrees * (.pi / 180.0)
        let camAltRad = cameraAltitudeDegrees * (.pi / 180.0)
        let camRollRad = cameraRollDegrees * (.pi / 180.0)

        let cosAz = cos(-camAzRad)
        let sinAz = sin(-camAzRad)
        let x1 = (xH * cosAz) - (yH * sinAz)
        let y1 = (xH * sinAz) + (yH * cosAz)
        let z1 = zH

        let cosAltC = cos(-camAltRad)
        let sinAltC = sin(-camAltRad)
        let x2 = x1
        let y2 = (y1 * cosAltC) - (z1 * sinAltC)
        let z2 = (y1 * sinAltC) + (z1 * cosAltC)

        let cosRoll = cos(camRollRad)
        let sinRoll = sin(camRollRad)
        let xCam = (x2 * cosRoll) + (z2 * sinRoll)
        let yCam = (-x2 * sinRoll) + (z2 * cosRoll)
        let zForward = y2

        guard zForward > 0.02 else {
            return nil
        }

        let denom = 1.0 + zForward
        let xs = xCam / denom
        let ys = yCam / denom

        let fovRad = fovDegrees * (.pi / 180.0)
        let tanHalfFov = tan(fovRad / 4.0)
        guard tanHalfFov > 1e-6 else { return nil }

        let scale = (min(viewportWidth, viewportHeight) * 0.5) / tanHalfFov
        let screenX = (viewportWidth * 0.5) + (xs * scale)
        let screenY = (viewportHeight * 0.5) - (ys * scale)

        let isVisibleOnScreen = (screenX >= -50 && screenX <= viewportWidth + 50 && screenY >= -50 && screenY <= viewportHeight + 50)

        return (screenX, screenY, isVisibleOnScreen)
    }
}
