package com.intellidream.daily.model

import io.github.cosinekitty.astronomy.*
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.*

/**
 * High-precision, zero-latency local astronomy engine powered by CosineKitty Astronomy Engine (MIT).
 * Bit-for-bit aligned with DailyCore (Swift) and WinUI (C#) across golden reference vectors:
 * EQJ_HOR 3x3 camera matrix, true Earth-Moon distance, spherical bright-limb angle,
 * light-time-retarded Galilean moons, rise/transit/set, and unified StargazingConditions.
 */
object AstronomyService {
    private const val KM_PER_AU = 149_597_870.69098932
    private const val C_AUDAY = 173.1446326846693
    private const val JUPITER_EQ_RADIUS_KM = 71_492.0
    private const val DEG2RAD = Math.PI / 180.0
    private const val RAD2DEG = 180.0 / Math.PI

    fun makeTime(millis: Long): Time = Time.fromMillisecondsSince1970(millis)

    fun timeToMillis(time: Time): Long = ((time.ut + 10957.5) * 86_400_000.0).roundToLong()

    private fun mapBody(body: CelestialBody): Body = when (body) {
        CelestialBody.SUN -> Body.Sun
        CelestialBody.MOON -> Body.Moon
        CelestialBody.MERCURY -> Body.Mercury
        CelestialBody.VENUS -> Body.Venus
        CelestialBody.MARS -> Body.Mars
        CelestialBody.JUPITER -> Body.Jupiter
        CelestialBody.SATURN -> Body.Saturn
        CelestialBody.URANUS -> Body.Uranus
        CelestialBody.NEPTUNE -> Body.Neptune
        CelestialBody.PLUTO -> Body.Pluto
    }

    private fun equatorialDiameterKm(body: CelestialBody): Double = when (body) {
        CelestialBody.SUN -> 1_392_700.0
        CelestialBody.MOON -> 3_474.8
        CelestialBody.MERCURY -> 4_879.4
        CelestialBody.VENUS -> 12_103.6
        CelestialBody.MARS -> 6_792.4
        CelestialBody.JUPITER -> 142_984.0
        CelestialBody.SATURN -> 120_536.0
        CelestialBody.URANUS -> 51_118.0
        CelestialBody.NEPTUNE -> 49_528.0
        CelestialBody.PLUTO -> 2_376.6
    }

    // MARK: - Planetary & J2000 Star Ephemeris

    fun coordinates(
        body: CelestialBody,
        latitude: Double,
        longitude: Double,
        elevationMeters: Double = 0.0,
        time: Time = Time.fromMillisecondsSince1970(System.currentTimeMillis())
    ): CelestialCoordinates {
        val obs = Observer(latitude, longitude, elevationMeters)
        val astroBody = mapBody(body)

        val eq = equator(astroBody, time, obs, EquatorEpoch.OfDate, Aberration.Corrected)
        val hor = horizon(time, obs, eq.ra, eq.dec, Refraction.Normal)
        val illum = illumination(astroBody, time)

        val phaseFrac = if (body == CelestialBody.SUN) 1.0 else illum.phaseFraction
        val distKm = max(1.0, eq.dist * KM_PER_AU)
        val angDiamArcsec = (2.0 * atan(equatorialDiameterKm(body) / (2.0 * distKm))) * RAD2DEG * 3600.0
        val limbDeg = if (body == CelestialBody.SUN) 0.0 else brightLimbAngleDegrees(body, latitude, longitude, time)

        return CelestialCoordinates(
            azimuthDegrees = hor.azimuth,
            altitudeDegrees = hor.altitude,
            rightAscensionHours = eq.ra,
            declinationDegrees = eq.dec,
            distanceAU = eq.dist,
            visualMagnitude = illum.mag,
            illuminatedFraction = phaseFrac,
            brightLimbAngleDegrees = limbDeg,
            angularDiameterArcsec = angDiamArcsec
        )
    }

    data class StarHorizontalResult(
        val azimuthDegrees: Double,
        val altitudeDegrees: Double,
        val hx: Double,
        val hy: Double,
        val hz: Double
    )

    fun starHorizontalCoordinates(
        raHours: Double,
        decDegrees: Double,
        latitude: Double,
        longitude: Double,
        elevationMeters: Double = 0.0,
        time: Time = Time.fromMillisecondsSince1970(System.currentTimeMillis()),
        includeRefraction: Boolean = true
    ): StarHorizontalResult {
        val obs = Observer(latitude, longitude, elevationMeters)
        val rot = rotationEqjHor(time, obs)
        val raRad = raHours * 15.0 * DEG2RAD
        val decRad = decDegrees * DEG2RAD
        val eqj = Vector(
            cos(decRad) * cos(raRad),
            cos(decRad) * sin(raRad),
            sin(decRad),
            time
        )
        val hor = rot.rotate(eqj)
        val azDeg = (atan2(-hor.y, hor.x) * RAD2DEG + 360.0) % 360.0
        var altDeg = asin(hor.z.coerceIn(-1.0, 1.0)) * RAD2DEG
        if (includeRefraction && altDeg in -90.0..90.0) {
            val hd = max(-1.0, altDeg)
            var refr = (1.02 / tan((hd + 10.3 / (hd + 5.11)) * DEG2RAD)) / 60.0
            if (altDeg < -1.0) {
                refr *= (altDeg + 90.0) / 89.0
            }
            altDeg += refr
        }
        return StarHorizontalResult(azDeg, altDeg, hor.x, hor.y, hor.z)
    }

    // MARK: - Bright-Limb Position Angle

    fun brightLimbAngleDegrees(
        body: CelestialBody,
        latitude: Double,
        longitude: Double,
        time: Time = Time.fromMillisecondsSince1970(System.currentTimeMillis())
    ): Double {
        if (body == CelestialBody.SUN) return 0.0
        val obs = Observer(latitude, longitude, 0.0)
        val rot = rotationEqjHor(time, obs)

        val bodyEqj = geoVector(mapBody(body), time, Aberration.Corrected)
        val sunEqj = geoVector(Body.Sun, time, Aberration.Corrected)
        val mh = rot.rotate(bodyEqj)
        val sh = rot.rotate(sunEqj)

        val ml = mh.length()
        val sl = sh.length()
        if (ml <= 1e-12 || sl <= 1e-12) return 0.0

        val bx = mh.x / ml; val by = mh.y / ml; val bz = mh.z / ml
        val sx = sh.x / sl; val sy = sh.y / sl; val sz = sh.z / sl

        val dot = sx * bx + sy * by + sz * bz
        val tx = sx - dot * bx
        val ty = sy - dot * by
        val tz = sz - dot * bz

        val rLen = hypot(by, -bx)
        val rx = if (rLen > 1e-9) by / rLen else 0.0
        val ry = if (rLen > 1e-9) -bx / rLen else -1.0
        val rz = 0.0

        val ux = ry * bz - rz * by
        val uy = rz * bx - rx * bz
        val uz = rx * by - ry * bx

        val tr = tx * rx + ty * ry + tz * rz
        val tu = tx * ux + ty * uy + tz * uz
        return atan2(tr, tu) * RAD2DEG
    }

    // MARK: - Moon Phase & True Distance

    fun moonPhase(
        time: Time = Time.fromMillisecondsSince1970(System.currentTimeMillis()),
        observerLatitude: Double? = null,
        observerLongitude: Double? = null
    ): MoonPhaseInfo {
        val phaseAngle = io.github.cosinekitty.astronomy.moonPhase(time)
        val illum = illumination(Body.Moon, time)
        val fraction = illum.phaseFraction

        val ageDays = (phaseAngle / 360.0) * 29.530588
        val isWaxing = phaseAngle < 180.0

        val quarter = when {
            phaseAngle < 22.5 || phaseAngle >= 337.5 -> MoonPhaseQuarter.NEW_MOON
            phaseAngle < 67.5 -> MoonPhaseQuarter.WAXING_CRESCENT
            phaseAngle < 112.5 -> MoonPhaseQuarter.FIRST_QUARTER
            phaseAngle < 157.5 -> MoonPhaseQuarter.WAXING_GIBBOUS
            phaseAngle < 202.5 -> MoonPhaseQuarter.FULL_MOON
            phaseAngle < 247.5 -> MoonPhaseQuarter.WANING_GIBBOUS
            phaseAngle < 292.5 -> MoonPhaseQuarter.THIRD_QUARTER
            else -> MoonPhaseQuarter.WANING_CRESCENT
        }

        val geoDistKm = geoMoon(time).length() * KM_PER_AU
        var topoDistKm: Double? = null
        var limbAngle = if (isWaxing) -90.0 else 90.0
        if (observerLatitude != null && observerLongitude != null) {
            val obs = Observer(observerLatitude, observerLongitude, 0.0)
            val eq = equator(Body.Moon, time, obs, EquatorEpoch.OfDate, Aberration.Corrected)
            topoDistKm = eq.dist * KM_PER_AU
            limbAngle = brightLimbAngleDegrees(CelestialBody.MOON, observerLatitude, observerLongitude, time)
        }

        return MoonPhaseInfo(
            phaseAngleDegrees = phaseAngle,
            illuminatedFraction = fraction,
            quarter = quarter,
            ageDays = ageDays,
            isWaxing = isWaxing,
            distanceKm = geoDistKm,
            topocentricDistanceKm = topoDistKm,
            brightLimbAngleDegrees = limbAngle
        )
    }

    // MARK: - Sun Times & Rise / Transit / Set

    fun sunTimes(latitude: Double, longitude: Double, millis: Long = System.currentTimeMillis()): SunTimes {
        val obs = Observer(latitude, longitude, 0.0)
        val zone = ZoneId.systemDefault()
        val startOfDayMillis = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
            .atStartOfDay(zone).toInstant().toEpochMilli()
        val startTime = makeTime(startOfDayMillis)

        fun searchAlt(alt: Double, dir: Direction): Long? {
            return try {
                searchAltitude(Body.Sun, obs, dir, startTime, 1.3, alt)?.let { timeToMillis(it) }
            } catch (_: Exception) {
                null
            }
        }

        val solarNoon = try {
            timeToMillis(searchHourAngle(Body.Sun, obs, 0.0, startTime, +1).time)
        } catch (_: Exception) {
            null
        }

        return SunTimes(
            dawnAstronomicalMillis = searchAlt(-18.0, Direction.Rise),
            dawnNauticalMillis = searchAlt(-12.0, Direction.Rise),
            dawnCivilMillis = searchAlt(-6.0, Direction.Rise),
            sunriseMillis = searchAlt(-0.833, Direction.Rise),
            solarNoonMillis = solarNoon,
            sunsetMillis = searchAlt(-0.833, Direction.Set),
            duskCivilMillis = searchAlt(-6.0, Direction.Set),
            duskNauticalMillis = searchAlt(-12.0, Direction.Set),
            duskAstronomicalMillis = searchAlt(-18.0, Direction.Set)
        )
    }

    fun riseTransitSet(
        body: CelestialBody,
        latitude: Double,
        longitude: Double,
        millis: Long = System.currentTimeMillis()
    ): BodyRiseTransitSet {
        val obs = Observer(latitude, longitude, 0.0)
        val astroBody = mapBody(body)
        val startTime = makeTime(millis - 2 * 3_600_000L)

        val rise = try { searchRiseSet(astroBody, obs, Direction.Rise, startTime, 1.2)?.let { timeToMillis(it) } } catch (_: Exception) { null }
        val set = try { searchRiseSet(astroBody, obs, Direction.Set, startTime, 1.2)?.let { timeToMillis(it) } } catch (_: Exception) { null }
        val transitEvent = try { searchHourAngle(astroBody, obs, 0.0, startTime, +1) } catch (_: Exception) { null }

        return BodyRiseTransitSet(
            riseMillis = rise,
            transitMillis = transitEvent?.let { timeToMillis(it.time) },
            setMillis = set,
            transitAltitudeDegrees = transitEvent?.hor?.altitude
        )
    }

    fun riseTransitSetStar(
        raHours: Double,
        decDegrees: Double,
        latitude: Double,
        longitude: Double,
        millis: Long = System.currentTimeMillis()
    ): BodyRiseTransitSet {
        defineStar(Body.Star1, raHours, decDegrees, 100.0)
        val obs = Observer(latitude, longitude, 0.0)
        val startTime = makeTime(millis - 2 * 3_600_000L)

        val rise = try { searchRiseSet(Body.Star1, obs, Direction.Rise, startTime, 1.1)?.let { timeToMillis(it) } } catch (_: Exception) { null }
        val set = try { searchRiseSet(Body.Star1, obs, Direction.Set, startTime, 1.1)?.let { timeToMillis(it) } } catch (_: Exception) { null }
        val transitEvent = try { searchHourAngle(Body.Star1, obs, 0.0, startTime, +1) } catch (_: Exception) { null }

        return BodyRiseTransitSet(
            riseMillis = rise,
            transitMillis = transitEvent?.let { timeToMillis(it.time) },
            setMillis = set,
            transitAltitudeDegrees = transitEvent?.hor?.altitude
        )
    }

    // MARK: - Galilean Moons & Saturn Ring Tilt

    fun jupiterMoons(
        time: Time = Time.fromMillisecondsSince1970(System.currentTimeMillis()),
        latitude: Double = 44.4323,
        longitude: Double = 26.1063
    ): JupiterMoonsState {
        val obs = Observer(latitude, longitude, 0.0)
        val gj = geoVector(Body.Jupiter, time, Aberration.Corrected)
        val distAU = gj.length()
        val tRetarded = time.addDays(-distAU / C_AUDAY)
        val jm = io.github.cosinekitty.astronomy.jupiterMoons(tRetarded)

        val rot = rotationEqjHor(time, obs)
        val jh = rot.rotate(gj)
        val jLen = max(1e-12, jh.length())
        val lx = jh.x / jLen; val ly = jh.y / jLen; val lz = jh.z / jLen

        val rLen = hypot(ly, -lx)
        val rx = if (rLen > 1e-9) ly / rLen else 0.0
        val ry = if (rLen > 1e-9) -lx / rLen else -1.0
        val rz = 0.0
        val ux = ry * lz - rz * ly
        val uy = rz * lx - rx * lz
        val uz = rx * ly - ry * lx

        val rjAU = JUPITER_EQ_RADIUS_KM / KM_PER_AU

        fun projectMoon(name: String, state: StateVector): MoonVector2D {
            val mh = rot.rotate(state.position())
            val rightRadii = (mh.x * rx + mh.y * ry + mh.z * rz) / rjAU
            val upRadii = (mh.x * ux + mh.y * uy + mh.z * uz) / rjAU
            val depthRadii = (mh.x * lx + mh.y * ly + mh.z * lz) / rjAU
            return MoonVector2D(
                name = name,
                xRadius = rightRadii,
                yRadius = upRadii,
                depthRadius = depthRadii,
                isFrontOfPlanet = depthRadii < 0.0
            )
        }

        return JupiterMoonsState(
            io = projectMoon("Io", jm.io),
            europa = projectMoon("Europa", jm.europa),
            ganymede = projectMoon("Ganymede", jm.ganymede),
            callisto = projectMoon("Callisto", jm.callisto)
        )
    }

    fun saturnRingTilt(time: Time = Time.fromMillisecondsSince1970(System.currentTimeMillis())): Double =
        illumination(Body.Saturn, time).ringTilt

    // MARK: - Unified Deterministic Stargazing Score & Best Dark Window

    fun computeDeterministicSkyScore(
        cloudLowPercent: Double,
        cloudMidPercent: Double,
        cloudHighPercent: Double,
        moonIlluminatedFraction: Double,
        moonAltitudeDegrees: Double,
        bortleClass: Int,
        seeingArcseconds: Double,
        temperatureCelsius: Double,
        dewPointCelsius: Double
    ): Int {
        val effCloud = min(
            100.0,
            max(cloudLowPercent, max(cloudMidPercent, 0.7 * cloudLowPercent + 0.3 * cloudMidPercent)) * 0.92 +
                cloudHighPercent * 0.25
        )
        val cloudPenalty = effCloud * 0.58
        val moonPenalty = if (moonAltitudeDegrees > -2.0) {
            moonIlluminatedFraction * max(0.0, sin(moonAltitudeDegrees * DEG2RAD)) * 22.0
        } else 0.0
        val bortlePenalty = max(0, bortleClass.coerceIn(1, 9) - 1) * 2.5
        val seeingPenalty = max(0.0, (seeingArcseconds - 1.2) * 3.0)
        val dewPenalty = if ((temperatureCelsius - dewPointCelsius) < 2.0) 5.0 else 0.0
        val raw = 100.0 - cloudPenalty - moonPenalty - bortlePenalty - seeingPenalty - dewPenalty
        return raw.roundToInt().coerceIn(0, 100)
    }

    fun limitingMagnitude(bortle: Int, moonIllumFraction: Double = 0.0, isMoonAboveHorizon: Boolean = false): Double {
        val baseTable = doubleArrayOf(7.8, 7.8, 7.3, 6.8, 6.3, 5.8, 5.2, 4.6, 4.1, 3.6)
        var nelm = baseTable[bortle.coerceIn(1, 9)]
        if (isMoonAboveHorizon) nelm -= moonIllumFraction * 1.45
        return nelm.coerceIn(2.5, 7.8)
    }

    data class HourlyCloudSlot(
        val epochMillis: Long,
        val cloudLow: Int,
        val cloudMid: Int,
        val cloudHigh: Int
    )

    fun computeBestDarkWindow(
        latitude: Double,
        longitude: Double,
        referenceMillis: Long = System.currentTimeMillis(),
        bortleClass: Int = 5,
        hourlyForecastUTC: List<HourlyCloudSlot> = emptyList()
    ): String {
        val sun = sunTimes(latitude, longitude, referenceMillis)
        val nextDaySun = sunTimes(latitude, longitude, referenceMillis + 86_400_000L)
        val windowStart = sun.sunsetMillis ?: referenceMillis
        var windowEnd = nextDaySun.sunriseMillis ?: (windowStart + 10 * 3_600_000L)
        if (windowEnd <= windowStart) windowEnd = windowStart + 9 * 3_600_000L

        fun cloudsAt(ms: Long): Triple<Double, Double, Double> {
            if (hourlyForecastUTC.isEmpty()) return Triple(10.0, 10.0, 10.0)
            val best = hourlyForecastUTC.minByOrNull { abs(it.epochMillis - ms) } ?: return Triple(10.0, 10.0, 10.0)
            return Triple(best.cloudLow.toDouble(), best.cloudMid.toDouble(), best.cloudHigh.toDouble())
        }

        data class EvalSlot(val ms: Long, val score: Int, val sunAlt: Double)
        val slots = mutableListOf<EvalSlot>()
        var cursor = windowStart
        while (cursor <= windowEnd) {
            val t = makeTime(cursor)
            val sunC = coordinates(CelestialBody.SUN, latitude, longitude, 0.0, t)
            val moonC = coordinates(CelestialBody.MOON, latitude, longitude, 0.0, t)
            val moonP = moonPhase(t)
            val (cL, cM, cH) = cloudsAt(cursor)
            var sc = computeDeterministicSkyScore(
                cL, cM, cH, moonP.illuminatedFraction, moonC.altitudeDegrees, bortleClass, 1.4, 12.0, 6.0
            )
            if (sunC.altitudeDegrees > -12.0) sc = (sc * 0.25).toInt()
            else if (sunC.altitudeDegrees > -18.0) sc = (sc * 0.75).toInt()
            slots.add(EvalSlot(cursor, sc, sunC.altitudeDegrees))
            cursor += 900_000L // 15-minute step
        }

        val peakSlot = slots.maxByOrNull { it.score } ?: return "Unavailable"
        if (slots.all { it.sunAlt > -12.0 }) return "Twilight all night (White Nights)"
        if (peakSlot.score < 32) return "Cloud-limited tonight"

        val fmt = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault())
        val threshold = max(45, peakSlot.score - 12)
        val goodSlots = slots.filter { it.score >= threshold && it.sunAlt <= -12.0 }
        if (goodSlots.isEmpty()) {
            return "Around ${fmt.format(Instant.ofEpochMilli(peakSlot.ms))}"
        }
        val firstGood = goodSlots.first().ms
        val lastGood = max(firstGood + 1_800_000L, goodSlots.last().ms)
        return "${fmt.format(Instant.ofEpochMilli(firstGood))} – ${fmt.format(Instant.ofEpochMilli(lastGood))}"
    }

    fun evaluateStargazingConditions(
        latitude: Double,
        longitude: Double,
        millis: Long = System.currentTimeMillis(),
        cloudCoverTotal: Int?,
        cloudCoverLow: Int?,
        cloudCoverMid: Int?,
        cloudCoverHigh: Int?,
        bortleClass: Int = 5,
        seeingArcseconds: Double? = null,
        transparencyLabel: String? = null,
        dewPointDepression: Double? = null,
        hourlyForecastUTC: List<HourlyCloudSlot> = emptyList(),
        provenance: TelemetryProvenance = TelemetryProvenance.offlineCalculated()
    ): StargazingConditions {
        val time = makeTime(millis)
        val moon = moonPhase(time, latitude, longitude)
        val moonCoords = coordinates(CelestialBody.MOON, latitude, longitude, 0.0, time)
        val sunCoords = coordinates(CelestialBody.SUN, latitude, longitude, 0.0, time)

        val cLow = (cloudCoverLow ?: cloudCoverTotal ?: 0).toDouble()
        val cMid = (cloudCoverMid ?: cloudCoverTotal ?: 0).toDouble()
        val cHigh = (cloudCoverHigh ?: cloudCoverTotal ?: 0).toDouble()
        val tempSim = 12.0
        val dewSim = if (dewPointDepression != null) (tempSim - dewPointDepression) else 6.0

        var baseScore = computeDeterministicSkyScore(
            cLow, cMid, cHigh,
            moon.illuminatedFraction,
            moonCoords.altitudeDegrees,
            bortleClass,
            seeingArcseconds ?: 1.4,
            tempSim,
            dewSim
        )

        val bestWindow = computeBestDarkWindow(latitude, longitude, millis, bortleClass, hourlyForecastUTC)

        if (sunCoords.altitudeDegrees > -6.0) {
            val sunT = sunTimes(latitude, longitude, millis)
            val duskMs = sunT.duskAstronomicalMillis ?: sunT.duskNauticalMillis ?: sunT.sunsetMillis
            if (duskMs != null) {
                val sampleNight = makeTime(duskMs + 3_600_000L)
                val nightMoonC = coordinates(CelestialBody.MOON, latitude, longitude, 0.0, sampleNight)
                val nightMoonP = moonPhase(sampleNight, latitude, longitude)
                baseScore = computeDeterministicSkyScore(
                    cLow, cMid, cHigh,
                    nightMoonP.illuminatedFraction,
                    nightMoonC.altitudeDegrees,
                    bortleClass,
                    seeingArcseconds ?: 1.4,
                    tempSim,
                    dewSim
                )
            }
        }

        val quality = when (baseScore) {
            in 80..100 -> StargazingQuality.PRISTINE
            in 60 until 80 -> StargazingQuality.GOOD
            in 40 until 60 -> StargazingQuality.FAIR
            else -> StargazingQuality.POOR
        }

        val nelm = limitingMagnitude(bortleClass, moon.illuminatedFraction, moonCoords.isVisible)

        val advice = when {
            cloudCoverTotal == null ->
                "Offline ephemeris mode (Bortle $bortleClass, NELM ${"%.1f".format(nelm)}). Connect once for live cloud layers and seeing."
            dewPointDepression != null && dewPointDepression < 2.0 ->
                "High condensation risk (ΔTd ${"%.1f°C".format(dewPointDepression)}). Use a dew shield on optics."
            sunCoords.altitudeDegrees > -6.0 ->
                "Daylight sky active. Tonight's forecast score is $baseScore/100 with optimal dark window $bestWindow."
            baseScore >= 80 ->
                "Pristine dark-sky transparency! Ideal for Milky Way structure and faint Messier/Caldwell objects."
            baseScore >= 60 ->
                "Crisp stargazing conditions. Bright star clusters, constellations, and planetary discs show sharp contrast."
            moonCoords.isVisible && moon.illuminatedFraction > 0.65 ->
                "Bright lunar glare washes out faint nebulae—ideal tonight for lunar craters, Saturn's rings, and Jupiter's moons."
            else ->
                "Cloud-impacted sky. Target bright planets, the Moon, and clear sky breaks."
        }

        return StargazingConditions(
            score = baseScore,
            quality = quality,
            bortleClass = bortleClass,
            limitingMagnitude = nelm,
            cloudCoverTotalPercent = cloudCoverTotal,
            cloudCoverLowPercent = cloudCoverLow,
            cloudCoverMidPercent = cloudCoverMid,
            cloudCoverHighPercent = cloudCoverHigh,
            moonIlluminationPercent = moon.illuminationPercent,
            isMoonAboveHorizon = moonCoords.isVisible,
            seeingArcseconds = seeingArcseconds,
            transparencyLabel = transparencyLabel,
            dewPointDepressionCelsius = dewPointDepression,
            bestWindowDescription = bestWindow,
            narrativeAdvice = advice,
            provenance = provenance
        )
    }

    fun circadianLunarContext(latitude: Double, longitude: Double, millis: Long = System.currentTimeMillis()): CircadianSkyContext {
        val sun = sunTimes(latitude, longitude, millis)
        val moon = moonPhase(makeTime(millis), latitude, longitude)
        val naturalLux = moon.illuminatedFraction.pow(2.2) * 0.25
        val fmt = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault())
        val onsetMs = sun.duskAstronomicalMillis ?: sun.duskNauticalMillis
        val onsetStr = onsetMs?.let { fmt.format(Instant.ofEpochMilli(it)) } ?: "late evening"
        val summary = if (moon.illuminatedFraction >= 0.80) {
            "True solar darkness begins at $onsetStr. ${moon.quarter.displayName} (${moon.illuminationPercent}%) adds ~${"%.2f".format(naturalLux)} lx natural skyglow—close blinds for undisturbed melatonin onset."
        } else {
            "True astronomical darkness begins at $onsetStr with minimal lunar skyglow (~${"%.3f".format(naturalLux)} lx), supporting deep circadian recovery."
        }
        return CircadianSkyContext(onsetMs, naturalLux, summary)
    }

    // MARK: - Unified 3D Matrix Stereographic Projection (Zero-Trig Per-Star)

    fun makeProjectionMatrix(
        observerLatitudeDegrees: Double,
        observerLongitudeDegrees: Double,
        millis: Long,
        cameraAzimuthDegrees: Double,
        cameraAltitudeDegrees: Double,
        cameraRollDegrees: Double = 0.0,
        customBasisNWZ: Array<DoubleArray>? = null, // [0]=right(3), [1]=up(3), [2]=forward(3)
        fovDegrees: Double = 60.0,
        viewportWidth: Double,
        viewportHeight: Double
    ): SkyProjectionMatrix {
        val time = makeTime(millis)
        val obs = Observer(observerLatitudeDegrees, observerLongitudeDegrees, 0.0)
        val rot = rotationEqjHor(time, obs)

        val h00 = rot.rot[0][0]; val h01 = rot.rot[1][0]; val h02 = rot.rot[2][0]
        val h10 = rot.rot[0][1]; val h11 = rot.rot[1][1]; val h12 = rot.rot[2][1]
        val h20 = rot.rot[0][2]; val h21 = rot.rot[1][2]; val h22 = rot.rot[2][2]

        val rx: Double; val ry: Double; val rz: Double
        val ux: Double; val uy: Double; val uz: Double
        val fx: Double; val fy: Double; val fz: Double

        if (customBasisNWZ != null && customBasisNWZ.size == 3) {
            rx = customBasisNWZ[0][0]; ry = customBasisNWZ[0][1]; rz = customBasisNWZ[0][2]
            ux = customBasisNWZ[1][0]; uy = customBasisNWZ[1][1]; uz = customBasisNWZ[1][2]
            fx = customBasisNWZ[2][0]; fy = customBasisNWZ[2][1]; fz = customBasisNWZ[2][2]
        } else {
            val az = cameraAzimuthDegrees * DEG2RAD
            val alt = cameraAltitudeDegrees * DEG2RAD
            val roll = cameraRollDegrees * DEG2RAD

            fx = cos(alt) * cos(az)
            fy = -cos(alt) * sin(az)
            fz = sin(alt)

            val r0x = -sin(az); val r0y = -cos(az); val r0z = 0.0
            val u0x = -sin(alt) * cos(az)
            val u0y = sin(alt) * sin(az)
            val u0z = cos(alt)

            val cr = cos(roll); val sr = sin(roll)
            rx = cr * r0x + sr * u0x
            ry = cr * r0y + sr * u0y
            rz = cr * r0z + sr * u0z

            ux = -sr * r0x + cr * u0x
            uy = -sr * r0y + cr * u0y
            uz = -sr * r0z + cr * u0z
        }

        val m00 = rx * h00 + ry * h10 + rz * h20
        val m01 = rx * h01 + ry * h11 + rz * h21
        val m02 = rx * h02 + ry * h12 + rz * h22

        val m10 = ux * h00 + uy * h10 + uz * h20
        val m11 = ux * h01 + uy * h11 + uz * h21
        val m12 = ux * h02 + uy * h12 + uz * h22

        val m20 = fx * h00 + fy * h10 + fz * h20
        val m21 = fx * h01 + fy * h11 + fz * h21
        val m22 = fx * h02 + fy * h12 + fz * h22

        return SkyProjectionMatrix(
            m00, m01, m02,
            m10, m11, m12,
            m20, m21, m22,
            rx, ry, rz,
            ux, uy, uz,
            fx, fy, fz,
            h00, h01, h02,
            h10, h11, h12,
            h20, h21, h22,
            viewportWidth, viewportHeight, fovDegrees
        )
    }

    fun projectStereographic(
        raHours: Double,
        decDegrees: Double,
        observerLatitudeDegrees: Double,
        observerLongitudeDegrees: Double,
        millis: Long,
        cameraAzimuthDegrees: Double,
        cameraAltitudeDegrees: Double,
        cameraRollDegrees: Double = 0.0,
        fovDegrees: Double = 60.0,
        viewportWidth: Double,
        viewportHeight: Double
    ): Triple<Double, Double, Boolean>? {
        val mat = makeProjectionMatrix(
            observerLatitudeDegrees = observerLatitudeDegrees,
            observerLongitudeDegrees = observerLongitudeDegrees,
            millis = millis,
            cameraAzimuthDegrees = cameraAzimuthDegrees,
            cameraAltitudeDegrees = cameraAltitudeDegrees,
            cameraRollDegrees = cameraRollDegrees,
            fovDegrees = fovDegrees,
            viewportWidth = viewportWidth,
            viewportHeight = viewportHeight
        )
        val raRad = raHours * 15.0 * DEG2RAD
        val decRad = decDegrees * DEG2RAD
        val p = mat.projectEQJUnitVector(
            cos(decRad) * cos(raRad),
            cos(decRad) * sin(raRad),
            sin(decRad)
        ) ?: return null
        return Triple(p.x, p.y, p.isVisible)
    }

    fun projectHorizontal(
        azimuthDegrees: Double,
        altitudeDegrees: Double,
        cameraAzimuthDegrees: Double,
        cameraAltitudeDegrees: Double,
        cameraRollDegrees: Double = 0.0,
        fovDegrees: Double = 60.0,
        viewportWidth: Double,
        viewportHeight: Double
    ): Triple<Double, Double, Boolean>? {
        val az = cameraAzimuthDegrees * DEG2RAD
        val alt = cameraAltitudeDegrees * DEG2RAD
        val roll = cameraRollDegrees * DEG2RAD

        val fx = cos(alt) * cos(az)
        val fy = -cos(alt) * sin(az)
        val fz = sin(alt)
        val r0x = -sin(az); val r0y = -cos(az); val r0z = 0.0
        val u0x = -sin(alt) * cos(az); val u0y = sin(alt) * sin(az); val u0z = cos(alt)
        val cr = cos(roll); val sr = sin(roll)
        val rx = cr * r0x + sr * u0x; val ry = cr * r0y + sr * u0y; val rz = cr * r0z + sr * u0z
        val ux = -sr * r0x + cr * u0x; val uy = -sr * r0y + cr * u0y; val uz = -sr * r0z + cr * u0z

        val tAz = azimuthDegrees * DEG2RAD
        val tAlt = altitudeDegrees * DEG2RAD
        val cosTAlt = cos(tAlt)
        val hx = cosTAlt * cos(tAz)
        val hy = -cosTAlt * sin(tAz)
        val hz = sin(tAlt)

        val cx = rx * hx + ry * hy + rz * hz
        val cy = ux * hx + uy * hy + uz * hz
        val cz = fx * hx + fy * hy + fz * hz
        val denom = 1.0 + cz
        if (denom < 0.08) return null

        val clampedFov = fovDegrees.coerceIn(0.4, 150.0)
        val scale = (min(viewportWidth, viewportHeight) * 0.5) / max(1e-6, tan(clampedFov * DEG2RAD * 0.25))
        val sx = viewportWidth * 0.5 + (cx / denom) * scale
        val sy = viewportHeight * 0.5 - (cy / denom) * scale
        val isVis = (sx >= -50.0 && sx <= viewportWidth + 50.0 && sy >= -50.0 && sy <= viewportHeight + 50.0)
        return Triple(sx, sy, isVis)
    }
}
