import Foundation
import CAstronomy

/// High-precision, zero-latency local astronomy engine powered by C99 Astronomy Engine (MIT).
/// Computes VSOP87 / ELP2000 planetary & lunar ephemeris, J2000->HOR matrix transforms,
/// zero-trig 120Hz stereographic camera projections, spherical bright-limb position angles,
/// light-time-corrected Galilean moon sky-plane offsets, rise/transit/set times, and unified
/// stargazing & circadian darkness windows.
public final class AstronomyService: Sendable {
    public static let shared = AstronomyService()

    private static let kmPerAU = 149_597_870.69098932
    private static let cAuday = 173.1446326846693
    private static let jupiterEquatorialRadiusKm = 71_492.0
    private static let deg2rad = Double.pi / 180.0
    private static let rad2deg = 180.0 / Double.pi

    public init() {}

    // MARK: - Time & Observer Conversion

    public func makeAstroTime(from date: Date) -> astro_time_t {
        let daysSinceJ2000 = -10957.5 + (date.timeIntervalSince1970 / 86400.0)
        return Astronomy_TimeFromDays(daysSinceJ2000)
    }

    public func date(from astroTime: astro_time_t) -> Date {
        let unixDays = astroTime.ut + 10957.5
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

    private func equatorialDiameterKm(for body: CelestialBody) -> Double {
        switch body {
        case .sun: return 1_392_700.0
        case .moon: return 3_474.8
        case .mercury: return 4_879.4
        case .venus: return 12_103.6
        case .mars: return 6_792.4
        case .jupiter: return 142_984.0
        case .saturn: return 120_536.0
        case .uranus: return 51_118.0
        case .neptune: return 49_528.0
        case .pluto: return 2_376.6
        }
    }

    // MARK: - Planetary & J2000 Star Ephemeris

    public func coordinates(
        of body: CelestialBody,
        for observer: (latitude: Double, longitude: Double, elevation: Double),
        at date: Date = Date()
    ) -> CelestialCoordinates {
        var aTime = makeAstroTime(from: date)
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude, elevationMeters: observer.elevation)
        let cb = cBody(for: body)

        let eq = Astronomy_Equator(cb, &aTime, obs, EQUATOR_OF_DATE, ABERRATION)
        let hor = Astronomy_Horizon(&aTime, obs, eq.ra, eq.dec, REFRACTION_NORMAL)
        let illum = Astronomy_Illumination(cb, aTime)

        let mag = (illum.status == ASTRO_SUCCESS) ? illum.mag : 0.0
        let phaseFrac = (body == .sun) ? 1.0 : ((illum.status == ASTRO_SUCCESS) ? illum.phase_fraction : 1.0)
        let distKm = max(1.0, eq.dist * Self.kmPerAU)
        let angDiamArcsec = (2.0 * atan(equatorialDiameterKm(for: body) / (2.0 * distKm))) * Self.rad2deg * 3600.0

        let limbDeg: Double
        if body == .sun {
            limbDeg = 0.0
        } else {
            limbDeg = brightLimbAngleDegrees(of: body, for: (observer.latitude, observer.longitude), at: date)
        }

        return CelestialCoordinates(
            azimuthDegrees: hor.azimuth,
            altitudeDegrees: hor.altitude,
            rightAscensionHours: eq.ra,
            declinationDegrees: eq.dec,
            distanceAU: eq.dist,
            visualMagnitude: mag,
            illuminatedFraction: phaseFrac,
            brightLimbAngleDegrees: limbDeg,
            angularDiameterArcsec: angDiamArcsec
        )
    }

    /// Converts J2000 catalog (RA hours, Dec degrees) accurately into apparent topocentric (Azimuth, Altitude)
    /// using `Astronomy_Rotation_EQJ_HOR` (accounting for precession, nutation, sidereal spin, and atmospheric refraction).
    public func starHorizontalCoordinates(
        raHours: Double,
        decDegrees: Double,
        for observer: (latitude: Double, longitude: Double, elevation: Double),
        at date: Date = Date(),
        includeRefraction: Bool = true
    ) -> (azimuthDegrees: Double, altitudeDegrees: Double, horNWZ: (Double, Double, Double)) {
        var aTime = makeAstroTime(from: date)
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude, elevationMeters: observer.elevation)
        let rot = Astronomy_Rotation_EQJ_HOR(&aTime, obs)

        let raRad = raHours * 15.0 * Self.deg2rad
        let decRad = decDegrees * Self.deg2rad
        let eqj = astro_vector_t(
            status: ASTRO_SUCCESS,
            x: cos(decRad) * cos(raRad),
            y: cos(decRad) * sin(raRad),
            z: sin(decRad),
            t: aTime
        )
        let hor = Astronomy_RotateVector(rot, eqj)
        let sph = Astronomy_HorizonFromVector(hor, includeRefraction ? REFRACTION_NORMAL : REFRACTION_NONE)
        return (sph.lon, sph.lat, (hor.x, hor.y, hor.z))
    }

    // MARK: - Bright-Limb Position Angle (Spherical Terminator Orientation)

    /// Computes the local horizon-referenced position angle (degrees clockwise from local zenith-up:
    /// 0° = illuminated limb points straight UP, +90° = RIGHT, -90° = LEFT, ±180° = DOWN) for Moon, Venus, Mercury, etc.
    public func brightLimbAngleDegrees(
        of body: CelestialBody,
        for observer: (latitude: Double, longitude: Double),
        at date: Date = Date()
    ) -> Double {
        guard body != .sun else { return 0.0 }
        var aTime = makeAstroTime(from: date)
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude)
        let rot = Astronomy_Rotation_EQJ_HOR(&aTime, obs)

        let bodyEqj = Astronomy_GeoVector(cBody(for: body), aTime, ABERRATION)
        let sunEqj = Astronomy_GeoVector(BODY_SUN, aTime, ABERRATION)
        let mh = Astronomy_RotateVector(rot, bodyEqj)
        let sh = Astronomy_RotateVector(rot, sunEqj)

        let ml = sqrt(mh.x * mh.x + mh.y * mh.y + mh.z * mh.z)
        let sl = sqrt(sh.x * sh.x + sh.y * sh.y + sh.z * sh.z)
        guard ml > 1e-12, sl > 1e-12 else { return 0.0 }

        let bx = mh.x / ml, by = mh.y / ml, bz = mh.z / ml
        let sx = sh.x / sl, sy = sh.y / sl, sz = sh.z / sl

        // Great-circle tangent at body pointing toward Sun
        let dot = sx * bx + sy * by + sz * bz
        let tx = sx - dot * bx
        let ty = sy - dot * by
        let tz = sz - dot * bz

        // Local horizontal right = normalize(b x z_zenith) = normalize((by, -bx, 0))
        let rLen = hypot(by, -bx)
        let rx = (rLen > 1e-9) ? (by / rLen) : 0.0
        let ry = (rLen > 1e-9) ? (-bx / rLen) : -1.0
        let rz = 0.0

        // Local horizontal up = r x b
        let ux = ry * bz - rz * by
        let uy = rz * bx - rx * bz
        let uz = rx * by - ry * bx

        let tr = tx * rx + ty * ry + tz * rz
        let tu = tx * ux + ty * uy + tz * uz
        return atan2(tr, tu) * Self.rad2deg
    }

    // MARK: - Moon Phase & True Geocentric / Topocentric Distance

    public func moonPhase(
        at date: Date = Date(),
        observer: (latitude: Double, longitude: Double)? = nil
    ) -> MoonPhaseInfo {
        var aTime = makeAstroTime(from: date)
        let phaseResult = Astronomy_MoonPhase(aTime)
        let angle = (phaseResult.status == ASTRO_SUCCESS) ? phaseResult.angle : 0.0

        let illum = Astronomy_Illumination(BODY_MOON, aTime)
        let fraction = (illum.status == ASTRO_SUCCESS) ? illum.phase_fraction : 0.0

        let ageDays = (angle / 360.0) * 29.530588
        let isWaxing = angle < 180.0

        let quarter: MoonPhaseQuarter
        switch angle {
        case 0..<22.5, 337.5...360: quarter = .newMoon
        case 22.5..<67.5: quarter = .waxingCrescent
        case 67.5..<112.5: quarter = .firstQuarter
        case 112.5..<157.5: quarter = .waxingGibbous
        case 157.5..<202.5: quarter = .fullMoon
        case 202.5..<247.5: quarter = .waningGibbous
        case 247.5..<292.5: quarter = .thirdQuarter
        default: quarter = .waningCrescent
        }

        // True geocentric Earth-Moon distance (~356,500 - 406,700 km), NOT heliocentric 1 AU!
        let geoMoon = Astronomy_GeoMoon(aTime)
        let geoDistKm: Double
        if geoMoon.status == ASTRO_SUCCESS {
            let rAU = sqrt(geoMoon.x * geoMoon.x + geoMoon.y * geoMoon.y + geoMoon.z * geoMoon.z)
            geoDistKm = rAU * Self.kmPerAU
        } else {
            geoDistKm = 384_400.0
        }

        var topoDistKm: Double? = nil
        var limbAngle = isWaxing ? -90.0 : 90.0
        if let obsCoord = observer {
            let obs = makeObserver(latitude: obsCoord.latitude, longitude: obsCoord.longitude)
            let eq = Astronomy_Equator(BODY_MOON, &aTime, obs, EQUATOR_OF_DATE, ABERRATION)
            if eq.status == ASTRO_SUCCESS {
                topoDistKm = eq.dist * Self.kmPerAU
            }
            limbAngle = brightLimbAngleDegrees(of: .moon, for: obsCoord, at: date)
        }

        return MoonPhaseInfo(
            phaseAngleDegrees: angle,
            illuminatedFraction: fraction,
            quarter: quarter,
            ageDays: ageDays,
            isWaxing: isWaxing,
            distanceKm: geoDistKm,
            topocentricDistanceKm: topoDistKm,
            brightLimbAngleDegrees: limbAngle
        )
    }

    // MARK: - Sun, Twilight & Rise / Transit / Set

    public func sunTimes(
        for observer: (latitude: Double, longitude: Double),
        on date: Date = Date()
    ) -> SunTimes {
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startOfDay = calendar.startOfDay(for: date)
        let startTime = makeAstroTime(from: startOfDay)

        func searchAlt(altitude: Double, direction: astro_direction_t) -> Date? {
            let res = Astronomy_SearchAltitude(BODY_SUN, obs, direction, startTime, 1.3, altitude)
            return (res.status == ASTRO_SUCCESS) ? self.date(from: res.time) : nil
        }

        var solarNoonDate: Date? = nil
        let transit = Astronomy_SearchHourAngleEx(BODY_SUN, obs, 0.0, startTime, 1)
        if transit.status == ASTRO_SUCCESS {
            solarNoonDate = self.date(from: transit.time)
        }

        return SunTimes(
            dawnAstronomical: searchAlt(altitude: -18.0, direction: DIRECTION_RISE),
            dawnNautical: searchAlt(altitude: -12.0, direction: DIRECTION_RISE),
            dawnCivil: searchAlt(altitude: -6.0, direction: DIRECTION_RISE),
            sunrise: searchAlt(altitude: -0.833, direction: DIRECTION_RISE),
            solarNoon: solarNoonDate,
            sunset: searchAlt(altitude: -0.833, direction: DIRECTION_SET),
            duskCivil: searchAlt(altitude: -6.0, direction: DIRECTION_SET),
            duskNautical: searchAlt(altitude: -12.0, direction: DIRECTION_SET),
            duskAstronomical: searchAlt(altitude: -18.0, direction: DIRECTION_SET)
        )
    }

    public func riseTransitSet(
        of body: CelestialBody,
        for observer: (latitude: Double, longitude: Double),
        on date: Date = Date()
    ) -> BodyRiseTransitSet {
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude)
        let cb = cBody(for: body)
        let startTime = makeAstroTime(from: date.addingTimeInterval(-3600.0 * 2.0))

        let riseRes = Astronomy_SearchRiseSetEx(cb, obs, DIRECTION_RISE, startTime, 1.2, 0.0)
        let setRes = Astronomy_SearchRiseSetEx(cb, obs, DIRECTION_SET, startTime, 1.2, 0.0)
        let transitRes = Astronomy_SearchHourAngleEx(cb, obs, 0.0, startTime, 1)

        return BodyRiseTransitSet(
            rise: (riseRes.status == ASTRO_SUCCESS) ? self.date(from: riseRes.time) : nil,
            transit: (transitRes.status == ASTRO_SUCCESS) ? self.date(from: transitRes.time) : nil,
            set: (setRes.status == ASTRO_SUCCESS) ? self.date(from: setRes.time) : nil,
            transitAltitudeDegrees: (transitRes.status == ASTRO_SUCCESS) ? transitRes.hor.altitude : nil
        )
    }

    public func riseTransitSet(
        raHours: Double,
        decDegrees: Double,
        for observer: (latitude: Double, longitude: Double),
        on date: Date = Date()
    ) -> BodyRiseTransitSet {
        Astronomy_DefineStar(BODY_STAR1, raHours, decDegrees, 100.0)
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude)
        let startTime = makeAstroTime(from: date.addingTimeInterval(-3600.0 * 2.0))

        let riseRes = Astronomy_SearchRiseSetEx(BODY_STAR1, obs, DIRECTION_RISE, startTime, 1.1, 0.0)
        let setRes = Astronomy_SearchRiseSetEx(BODY_STAR1, obs, DIRECTION_SET, startTime, 1.1, 0.0)
        let transitRes = Astronomy_SearchHourAngleEx(BODY_STAR1, obs, 0.0, startTime, 1)

        return BodyRiseTransitSet(
            rise: (riseRes.status == ASTRO_SUCCESS) ? self.date(from: riseRes.time) : nil,
            transit: (transitRes.status == ASTRO_SUCCESS) ? self.date(from: transitRes.time) : nil,
            set: (setRes.status == ASTRO_SUCCESS) ? self.date(from: setRes.time) : nil,
            transitAltitudeDegrees: (transitRes.status == ASTRO_SUCCESS) ? transitRes.hor.altitude : nil
        )
    }

    // MARK: - Galilean Moons (Light-Time Corrected + Local Sky-Plane Projection)

    public func jupiterMoons(
        at date: Date = Date(),
        observer: (latitude: Double, longitude: Double) = (44.4323, 26.1063)
    ) -> JupiterMoonsState {
        var aTime = makeAstroTime(from: date)
        let obs = makeObserver(latitude: observer.latitude, longitude: observer.longitude)
        let gj = Astronomy_GeoVector(BODY_JUPITER, aTime, ABERRATION)
        let distAU = sqrt(gj.x * gj.x + gj.y * gj.y + gj.z * gj.z)
        let tRetarded = Astronomy_AddDays(aTime, -distAU / Self.cAuday)
        let jm = Astronomy_JupiterMoons(tRetarded)

        let rot = Astronomy_Rotation_EQJ_HOR(&aTime, obs)
        let jh = Astronomy_RotateVector(rot, gj)
        let jLen = max(1e-12, sqrt(jh.x * jh.x + jh.y * jh.y + jh.z * jh.z))
        let lx = jh.x / jLen, ly = jh.y / jLen, lz = jh.z / jLen

        // Orthonormal local horizontal sky-plane basis at Jupiter
        let rLen = hypot(ly, -lx)
        let rx = (rLen > 1e-9) ? (ly / rLen) : 0.0
        let ry = (rLen > 1e-9) ? (-lx / rLen) : -1.0
        let rz = 0.0
        let ux = ry * lz - rz * ly
        let uy = rz * lx - rx * lz
        let uz = rx * ly - ry * lx

        let rjAU = Self.jupiterEquatorialRadiusKm / Self.kmPerAU

        func projectMoon(name: String, state: astro_state_vector_t) -> MoonVector2D {
            let mv = astro_vector_t(status: ASTRO_SUCCESS, x: state.x, y: state.y, z: state.z, t: tRetarded)
            let mh = Astronomy_RotateVector(rot, mv)
            let rightRadii = (mh.x * rx + mh.y * ry + mh.z * rz) / rjAU
            let upRadii = (mh.x * ux + mh.y * uy + mh.z * uz) / rjAU
            let depthRadii = (mh.x * lx + mh.y * ly + mh.z * lz) / rjAU
            return MoonVector2D(
                name: name,
                xRadius: rightRadii,
                yRadius: upRadii,
                depthRadius: depthRadii,
                isFrontOfPlanet: depthRadii < 0.0
            )
        }

        return JupiterMoonsState(
            io: projectMoon(name: "Io", state: jm.io),
            europa: projectMoon(name: "Europa", state: jm.europa),
            ganymede: projectMoon(name: "Ganymede", state: jm.ganymede),
            callisto: projectMoon(name: "Callisto", state: jm.callisto)
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

    // MARK: - Unified Deterministic Stargazing Score & Dynamic Best Dark Window

    public static func computeDeterministicSkyScore(
        cloudLowPercent: Double,
        cloudMidPercent: Double,
        cloudHighPercent: Double,
        moonIlluminatedFraction: Double,
        moonAltitudeDegrees: Double,
        bortleClass: Int,
        seeingArcseconds: Double,
        temperatureCelsius: Double,
        dewPointCelsius: Double
    ) -> Int {
        let effCloud = min(
            100.0,
            max(cloudLowPercent, max(cloudMidPercent, 0.7 * cloudLowPercent + 0.3 * cloudMidPercent)) * 0.92
                + cloudHighPercent * 0.25
        )
        let cloudPenalty = effCloud * 0.58
        let moonPenalty = (moonAltitudeDegrees > -2.0)
            ? (moonIlluminatedFraction * max(0.0, sin(moonAltitudeDegrees * deg2rad)) * 22.0)
            : 0.0
        let bortlePenalty = Double(max(0, min(9, bortleClass) - 1)) * 2.5
        let seeingPenalty = max(0.0, (seeingArcseconds - 1.2) * 3.0)
        let dewPenalty = ((temperatureCelsius - dewPointCelsius) < 2.0) ? 5.0 : 0.0
        let raw = 100.0 - cloudPenalty - moonPenalty - bortlePenalty - seeingPenalty - dewPenalty
        return max(0, min(100, Int(round(raw))))
    }

    /// Steps every 15 minutes from tonight's sunset to tomorrow's sunrise to compute the genuine optimal dark window.
    public func computeBestDarkWindow(
        observer: (latitude: Double, longitude: Double),
        referenceDate: Date = Date(),
        bortleClass: Int,
        hourlyForecastUTC: [(date: Date, cloudLow: Int, cloudMid: Int, cloudHigh: Int)] = []
    ) -> String {
        let sun = sunTimes(for: observer, on: referenceDate)
        let nextDaySun = sunTimes(for: observer, on: referenceDate.addingTimeInterval(86400.0))

        let windowStart = sun.sunset ?? referenceDate
        var windowEnd = nextDaySun.sunrise ?? windowStart.addingTimeInterval(10.0 * 3600.0)
        if windowEnd <= windowStart {
            windowEnd = windowStart.addingTimeInterval(9.0 * 3600.0)
        }

        func cloudsAt(_ t: Date) -> (Double, Double, Double) {
            guard !hourlyForecastUTC.isEmpty else { return (10.0, 10.0, 10.0) }
            var best = hourlyForecastUTC[0]
            var bestDiff = abs(best.date.timeIntervalSince(t))
            for item in hourlyForecastUTC {
                let d = abs(item.date.timeIntervalSince(t))
                if d < bestDiff {
                    best = item
                    bestDiff = d
                }
            }
            return (Double(best.cloudLow), Double(best.cloudMid), Double(best.cloudHigh))
        }

        var slots: [(date: Date, score: Int, sunAlt: Double)] = []
        var cursor = windowStart
        while cursor <= windowEnd {
            let sunC = coordinates(of: .sun, for: (observer.latitude, observer.longitude, 0.0), at: cursor)
            let moonC = coordinates(of: .moon, for: (observer.latitude, observer.longitude, 0.0), at: cursor)
            let moonP = moonPhase(at: cursor)
            let (cLow, cMid, cHigh) = cloudsAt(cursor)

            var sc = Self.computeDeterministicSkyScore(
                cloudLowPercent: cLow,
                cloudMidPercent: cMid,
                cloudHighPercent: cHigh,
                moonIlluminatedFraction: moonP.illuminatedFraction,
                moonAltitudeDegrees: moonC.altitudeDegrees,
                bortleClass: bortleClass,
                seeingArcseconds: 1.4,
                temperatureCelsius: 12.0,
                dewPointCelsius: 6.0
            )
            if sunC.altitudeDegrees > -12.0 {
                sc = Int(Double(sc) * 0.25)
            } else if sunC.altitudeDegrees > -18.0 {
                sc = Int(Double(sc) * 0.75)
            }
            slots.append((cursor, sc, sunC.altitudeDegrees))
            cursor = cursor.addingTimeInterval(900.0) // 15-minute step
        }

        guard let peakSlot = slots.max(by: { $0.score < $1.score }) else {
            return "Unavailable"
        }
        if slots.allSatisfy({ $0.sunAlt > -12.0 }) {
            return "Twilight all night (White Nights)"
        }
        if peakSlot.score < 32 {
            return "Cloud-limited tonight"
        }

        let threshold = max(45, peakSlot.score - 12)
        let goodSlots = slots.filter { $0.score >= threshold && $0.sunAlt <= -12.0 }
        guard let firstGood = goodSlots.first?.date, let lastGood = goodSlots.last?.date else {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            return "Around \(fmt.string(from: peakSlot.date))"
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let endAdjusted = max(firstGood.addingTimeInterval(1800.0), lastGood)
        return "\(fmt.string(from: firstGood)) – \(fmt.string(from: endAdjusted))"
    }

    public func evaluateStargazingConditions(
        observer: (latitude: Double, longitude: Double),
        date: Date = Date(),
        cloudCoverTotal: Int?,
        cloudCoverLow: Int?,
        cloudCoverMid: Int?,
        cloudCoverHigh: Int?,
        bortleClass: Int? = nil,
        seeingArcseconds: Double? = nil,
        transparencyLabel: String? = nil,
        dewPointDepression: Double? = nil,
        hourlyForecastUTC: [(date: Date, cloudLow: Int, cloudMid: Int, cloudHigh: Int)] = [],
        provenance: TelemetryProvenance = .offlineCalculated(epochAgeHours: nil)
    ) -> StargazingConditions {
        let resolvedBortle = bortleClass ?? CosmosCatalogService.shared.bortleClass(
            latitude: observer.latitude,
            longitude: observer.longitude
        )
        let moon = moonPhase(at: date, observer: observer)
        let moonCoords = coordinates(of: .moon, for: (observer.latitude, observer.longitude, 0.0), at: date)
        let sunCoords = coordinates(of: .sun, for: (observer.latitude, observer.longitude, 0.0), at: date)

        // When cloud forecast is genuinely unavailable offline, compute astronomical sky potential without faking cloud %
        let cLow = Double(cloudCoverLow ?? cloudCoverTotal ?? 0)
        let cMid = Double(cloudCoverMid ?? cloudCoverTotal ?? 0)
        let cHigh = Double(cloudCoverHigh ?? cloudCoverTotal ?? 0)
        let tempSim = 12.0
        let dewSim = (dewPointDepression != nil) ? (tempSim - dewPointDepression!) : 6.0

        var baseScore = Self.computeDeterministicSkyScore(
            cloudLowPercent: cLow,
            cloudMidPercent: cMid,
            cloudHighPercent: cHigh,
            moonIlluminatedFraction: moon.illuminatedFraction,
            moonAltitudeDegrees: moonCoords.altitudeDegrees,
            bortleClass: resolvedBortle,
            seeingArcseconds: seeingArcseconds ?? 1.4,
            temperatureCelsius: tempSim,
            dewPointCelsius: dewSim
        )

        // Evaluate tonight's astronomical dark window even during daytime so Tonight's Score reflects tonight's sky
        let bestWindow = computeBestDarkWindow(
            observer: observer,
            referenceDate: date,
            bortleClass: resolvedBortle,
            hourlyForecastUTC: hourlyForecastUTC
        )

        // If currently daytime, evaluate score at tonight's astronomical dusk + 2h so dashboard shows meaningful Tonight Score
        if sunCoords.altitudeDegrees > -6.0 {
            let sunT = sunTimes(for: observer, on: date)
            if let dusk = sunT.duskAstronomical ?? sunT.duskNautical ?? sunT.sunset {
                let sampleNight = dusk.addingTimeInterval(3600.0)
                let nightMoonC = coordinates(of: .moon, for: (observer.latitude, observer.longitude, 0.0), at: sampleNight)
                let nightMoonP = moonPhase(at: sampleNight, observer: observer)
                baseScore = Self.computeDeterministicSkyScore(
                    cloudLowPercent: cLow,
                    cloudMidPercent: cMid,
                    cloudHighPercent: cHigh,
                    moonIlluminatedFraction: nightMoonP.illuminatedFraction,
                    moonAltitudeDegrees: nightMoonC.altitudeDegrees,
                    bortleClass: resolvedBortle,
                    seeingArcseconds: seeingArcseconds ?? 1.4,
                    temperatureCelsius: tempSim,
                    dewPointCelsius: dewSim
                )
            }
        }

        let quality: StargazingQuality
        switch baseScore {
        case 80...100: quality = .pristine
        case 60..<80: quality = .good
        case 40..<60: quality = .fair
        default: quality = .poor
        }

        let nelm = CosmosCatalogService.limitingMagnitude(
            forBortle: resolvedBortle,
            moonIlluminatedFraction: moon.illuminatedFraction,
            isMoonAboveHorizon: moonCoords.isVisible
        )

        let advice: String
        if cloudCoverTotal == nil {
            advice = "Offline ephemeris mode (Bortle \(resolvedBortle), NELM \(String(format: "%.1f", nelm))). Connect once to include live cloud layers and atmospheric seeing."
        } else if let dp = dewPointDepression, dp < 2.0 {
            advice = "High condensation risk (ΔTd \(String(format: "%.1f°C", dp))). Use a dew shield or heater on telescope and binocular optics."
        } else if sunCoords.altitudeDegrees > -6.0 {
            advice = "Daylight sky active. Tonight's forecast score is \(baseScore)/100 with optimal dark window \(bestWindow)."
        } else if baseScore >= 80 {
            advice = "Pristine dark-sky transparency! Ideal for Milky Way structure, faint Messier/Caldwell galaxies, and nebulae."
        } else if baseScore >= 60 {
            advice = "Crisp stargazing conditions. Bright star clusters, double stars, and planetary discs show sharp contrast."
        } else if moonCoords.isVisible && moon.illuminatedFraction > 0.65 {
            advice = "Bright lunar glare washes out faint nebulae, making tonight ideal for lunar terminator craters, Saturn's rings, and Jupiter's moons."
        } else {
            advice = "Cloud-impacted sky. Target bright planets, the Moon, and clear sky breaks."
        }

        return StargazingConditions(
            score: baseScore,
            quality: quality,
            bortleClass: resolvedBortle,
            limitingMagnitude: nelm,
            cloudCoverTotalPercent: cloudCoverTotal,
            cloudCoverLowPercent: cloudCoverLow,
            cloudCoverMidPercent: cloudCoverMid,
            cloudCoverHighPercent: cloudCoverHigh,
            moonIlluminationPercent: moon.illuminationPercent,
            isMoonAboveHorizon: moonCoords.isVisible,
            seeingArcseconds: seeingArcseconds,
            transparencyLabel: transparencyLabel,
            dewPointDepressionCelsius: dewPointDepression,
            bestWindowDescription: bestWindow,
            narrativeAdvice: advice,
            provenance: provenance
        )
    }

    public func circadianLunarContext(
        for observer: (latitude: Double, longitude: Double),
        on date: Date = Date()
    ) -> CircadianSkyContext {
        let sun = sunTimes(for: observer, on: date)
        let moon = moonPhase(at: date, observer: observer)
        // Empirical natural full-moon zenith illuminance ~ 0.25 lux; scales steeply with phase angle
        let naturalLux = pow(moon.illuminatedFraction, 2.2) * 0.25
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let onsetStr = sun.duskAstronomical.map { fmt.string(from: $0) }
            ?? sun.duskNautical.map { fmt.string(from: $0) }
            ?? "late evening"
        let summary: String
        if moon.illuminatedFraction >= 0.80 {
            summary = "True solar darkness begins at \(onsetStr). \(moon.quarter.displayName) (\(moon.illuminationPercent)%) contributes ~\(String(format: "%.2f", naturalLux)) lx natural skyglow—keep bedroom blinds closed for undisturbed melatonin onset."
        } else {
            summary = "True astronomical darkness begins at \(onsetStr) with minimal lunar skyglow (~\(String(format: "%.3f", naturalLux)) lx), supporting deep circadian darkness."
        }
        return CircadianSkyContext(
            trueDarknessOnset: sun.duskAstronomical ?? sun.duskNautical,
            naturalMoonlightLux: naturalLux,
            summary: summary
        )
    }

    // MARK: - Unified 3D Matrix Stereographic Projection (Zero-Trig Per-Star)

    /// Builds the per-frame `SkyProjectionMatrix` combining `Astronomy_Rotation_EQJ_HOR` with the orthonormal
    /// camera basis `(right, up, forward)` in NWZ (`+X = North, +Y = West, +Z = Zenith`) coordinates.
    public func makeProjectionMatrix(
        observerLatitudeDegrees: Double,
        observerLongitudeDegrees: Double,
        date: Date,
        cameraAzimuthDegrees: Double,
        cameraAltitudeDegrees: Double,
        cameraRollDegrees: Double = 0.0,
        customBasisNWZ: (right: (Double, Double, Double), up: (Double, Double, Double), forward: (Double, Double, Double))? = nil,
        fovDegrees: Double = 60.0,
        viewportWidth: Double,
        viewportHeight: Double
    ) -> SkyProjectionMatrix {
        var aTime = makeAstroTime(from: date)
        let obs = makeObserver(latitude: observerLatitudeDegrees, longitude: observerLongitudeDegrees)
        let rot = Astronomy_Rotation_EQJ_HOR(&aTime, obs)

        // Astronomy Engine stores rot column-major: target.x = rot[0][0]*x + rot[1][0]*y + rot[2][0]*z
        let h00 = rot.rot.0.0, h01 = rot.rot.1.0, h02 = rot.rot.2.0
        let h10 = rot.rot.0.1, h11 = rot.rot.1.1, h12 = rot.rot.2.1
        let h20 = rot.rot.0.2, h21 = rot.rot.1.2, h22 = rot.rot.2.2

        let rx: Double, ry: Double, rz: Double
        let ux: Double, uy: Double, uz: Double
        let fx: Double, fy: Double, fz: Double

        if let basis = customBasisNWZ {
            (rx, ry, rz) = basis.right
            (ux, uy, uz) = basis.up
            (fx, fy, fz) = basis.forward
        } else {
            let az = cameraAzimuthDegrees * Self.deg2rad
            let alt = cameraAltitudeDegrees * Self.deg2rad
            let roll = cameraRollDegrees * Self.deg2rad

            fx = cos(alt) * cos(az)
            fy = -cos(alt) * sin(az)
            fz = sin(alt)

            // Singularity-free right & up vectors across all altitudes [-90°, +90°] including exact Zenith
            let r0x = -sin(az), r0y = -cos(az), r0z = 0.0
            let u0x = -sin(alt) * cos(az)
            let u0y = sin(alt) * sin(az)
            let u0z = cos(alt)

            let cr = cos(roll), sr = sin(roll)
            rx = cr * r0x + sr * u0x
            ry = cr * r0y + sr * u0y
            rz = cr * r0z + sr * u0z

            ux = -sr * r0x + cr * u0x
            uy = -sr * r0y + cr * u0y
            uz = -sr * r0z + cr * u0z
        }

        // Compose M = C * H once per frame
        let m00 = rx * h00 + ry * h10 + rz * h20
        let m01 = rx * h01 + ry * h11 + rz * h21
        let m02 = rx * h02 + ry * h12 + rz * h22

        let m10 = ux * h00 + uy * h10 + uz * h20
        let m11 = ux * h01 + uy * h11 + uz * h21
        let m12 = ux * h02 + uy * h12 + uz * h22

        let m20 = fx * h00 + fy * h10 + fz * h20
        let m21 = fx * h01 + fy * h11 + fz * h21
        let m22 = fx * h02 + fy * h12 + fz * h22

        let clampedFov = max(0.4, min(150.0, fovDegrees))
        let tanQuarterFov = max(1e-6, tan(clampedFov * Self.deg2rad * 0.25))
        let scale = (min(viewportWidth, viewportHeight) * 0.5) / tanQuarterFov

        return SkyProjectionMatrix(
            m00: m00, m01: m01, m02: m02,
            m10: m10, m11: m11, m12: m12,
            m20: m20, m21: m21, m22: m22,
            rx: rx, ry: ry, rz: rz,
            ux: ux, uy: uy, uz: uz,
            fx: fx, fy: fy, fz: fz,
            h00: h00, h01: h01, h02: h02,
            h10: h10, h11: h11, h12: h12,
            h20: h20, h21: h21, h22: h22,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            halfWidth: viewportWidth * 0.5,
            halfHeight: viewportHeight * 0.5,
            scale: scale,
            fovDegrees: clampedFov
        )
    }

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
        let mat = makeProjectionMatrix(
            observerLatitudeDegrees: observerLatitudeDegrees,
            observerLongitudeDegrees: observerLongitudeDegrees,
            date: date,
            cameraAzimuthDegrees: cameraAzimuthDegrees,
            cameraAltitudeDegrees: cameraAltitudeDegrees,
            cameraRollDegrees: cameraRollDegrees,
            fovDegrees: fovDegrees,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
        let raRad = raHours * 15.0 * Self.deg2rad
        let decRad = decDegrees * Self.deg2rad
        let vx = cos(decRad) * cos(raRad)
        let vy = cos(decRad) * sin(raRad)
        let vz = sin(decRad)
        guard let p = mat.projectEQJUnitVector(ux: vx, uy: vy, uz: vz) else { return nil }
        return (p.x, p.y, p.isVisible)
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
        let az = cameraAzimuthDegrees * Self.deg2rad
        let alt = cameraAltitudeDegrees * Self.deg2rad
        let roll = cameraRollDegrees * Self.deg2rad

        let fx = cos(alt) * cos(az)
        let fy = -cos(alt) * sin(az)
        let fz = sin(alt)
        let r0x = -sin(az), r0y = -cos(az), r0z = 0.0
        let u0x = -sin(alt) * cos(az), u0y = sin(alt) * sin(az), u0z = cos(alt)
        let cr = cos(roll), sr = sin(roll)
        let rx = cr * r0x + sr * u0x, ry = cr * r0y + sr * u0y, rz = cr * r0z + sr * u0z
        let ux = -sr * r0x + cr * u0x, uy = -sr * r0y + cr * u0y, uz = -sr * r0z + cr * u0z

        let tAz = azimuthDegrees * Self.deg2rad
        let tAlt = altitudeDegrees * Self.deg2rad
        let cosTAlt = cos(tAlt)
        let hx = cosTAlt * cos(tAz)
        let hy = -cosTAlt * sin(tAz)
        let hz = sin(tAlt)

        let cx = rx * hx + ry * hy + rz * hz
        let cy = ux * hx + uy * hy + uz * hz
        let cz = fx * hx + fy * hy + fz * hz
        let denom = 1.0 + cz
        guard denom >= 0.08 else { return nil }

        let clampedFov = max(0.4, min(150.0, fovDegrees))
        let tanQuarterFov = max(1e-6, tan(clampedFov * Self.deg2rad * 0.25))
        let scale = (min(viewportWidth, viewportHeight) * 0.5) / tanQuarterFov
        let sx = (viewportWidth * 0.5) + (cx / denom) * scale
        let sy = (viewportHeight * 0.5) - (cy / denom) * scale
        let isVis = (sx >= -50.0 && sx <= viewportWidth + 50.0 && sy >= -50.0 && sy <= viewportHeight + 50.0)
        return (sx, sy, isVis)
    }
}
