package com.intellidream.daily.model

import io.github.cosinekitty.astronomy.*
import kotlin.math.*

/**
 * High-precision, zero-latency local astronomy service powered by the Astronomy Engine (MIT).
 * Computes 100% offline planetary ephemeris, topocentric coordinates, twilight, moon phases,
 * and stereographic sky dome projections with full parity to DailyCore.
 */
object AstronomyService {

    fun makeTime(millis: Long): Time {
        return Time.fromMillisecondsSince1970(millis)
    }

    private fun mapBody(body: CelestialBody): Body {
        return when (body) {
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
    }

    fun coordinates(
        body: CelestialBody,
        latitude: Double,
        longitude: Double,
        elevationMeters: Double = 0.0,
        time: Time = Time.fromMillisecondsSince1970(System.currentTimeMillis())
    ): CelestialCoordinates {
        val obs = Observer(latitude, longitude, elevationMeters)
        val astroBody = mapBody(body)

        // 1. Equatorial topocentric coordinates
        val eq = equator(astroBody, time, obs, EquatorEpoch.OfDate, Aberration.Corrected)

        // 2. Horizontal topocentric coordinates (with atmospheric refraction)
        val hor = horizon(time, obs, eq.ra, eq.dec, Refraction.Normal)

        // 3. Visual magnitude & illumination
        val illum = illumination(astroBody, time)
        val mag = illum.mag

        return CelestialCoordinates(
            azimuthDegrees = hor.azimuth,
            altitudeDegrees = hor.altitude,
            rightAscensionHours = eq.ra,
            declinationDegrees = eq.dec,
            distanceAU = eq.dist,
            visualMagnitude = mag
        )
    }

    fun moonPhase(time: Time = Time.fromMillisecondsSince1970(System.currentTimeMillis())): MoonPhaseInfo {
        val phaseAngle: Double = io.github.cosinekitty.astronomy.moonPhase(time)
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

        // Earth-Moon Geocentric distance in km (1 AU = 149,597,870.7 km)
        val distKm = geoVector(Body.Moon, time, Aberration.None).length() * 149_597_870.7

        return MoonPhaseInfo(
            phaseAngleDegrees = phaseAngle,
            illuminatedFraction = fraction,
            quarter = quarter,
            ageDays = ageDays,
            isWaxing = isWaxing,
            distanceKm = distKm
        )
    }

    fun evaluateStargazingConditions(
        latitude: Double,
        longitude: Double,
        millis: Long = System.currentTimeMillis(),
        cloudCoverTotal: Int,
        cloudCoverLow: Int,
        cloudCoverMid: Int,
        cloudCoverHigh: Int,
        bortleClass: Int = 5,
        seeingArcseconds: Double? = null,
        dewPointDepression: Double? = null
    ): StargazingConditions {
        val time = Time.fromMillisecondsSince1970(millis)
        val moon = moonPhase(time)
        val moonCoords = coordinates(CelestialBody.MOON, latitude, longitude, 0.0, time)
        val sunCoords = coordinates(CelestialBody.SUN, latitude, longitude, 0.0, time)

        // Effective cloud coverage weighting
        val effClouds = max(cloudCoverLow.toDouble(), max(cloudCoverMid * 0.85, cloudCoverHigh * 0.65))

        var baseScore = 100.0 - effClouds

        // Penalize if sun is above astronomical twilight (-18 deg)
        if (sunCoords.altitudeDegrees > -6.0) {
            baseScore *= 0.1 // Daylight or civil twilight
        } else if (sunCoords.altitudeDegrees > -12.0) {
            baseScore *= 0.4 // Nautical twilight
        } else if (sunCoords.altitudeDegrees > -18.0) {
            baseScore *= 0.75 // Astronomical twilight
        }

        // Penalize moon only if above horizon
        if (moonCoords.isVisible) {
            val moonPenalty = (moon.illuminatedFraction * 35.0) * sin(max(0.0, moonCoords.altitudeDegrees) * Math.PI / 180.0)
            baseScore -= moonPenalty
        }

        // Bortle penalty (Bortle 1 = 0 penalty, Bortle 9 = -25 points)
        val bortlePenalty = (bortleClass.coerceIn(1, 9) - 1) * 3.1
        baseScore -= bortlePenalty

        // Dew point warning penalty (risk of lens fogging if depression < 2°C)
        if (dewPointDepression != null && dewPointDepression < 2.0) {
            baseScore -= 8.0
        }

        val finalScore = baseScore.roundToInt().coerceIn(0, 100)

        val quality = when (finalScore) {
            in 80..100 -> StargazingQuality.PRISTINE
            in 60 until 80 -> StargazingQuality.GOOD
            in 40 until 60 -> StargazingQuality.FAIR
            else -> StargazingQuality.POOR
        }

        // Limiting magnitude (NELM) calculation based on Bortle & Moon
        var nelm = 7.6 - (bortleClass * 0.5)
        if (moonCoords.isVisible) {
            nelm -= (moon.illuminatedFraction * 1.5)
        }
        nelm = nelm.coerceIn(2.5, 7.8)

        // Narrative advice
        val advice = when {
            sunCoords.altitudeDegrees > -6.0 ->
                "Daylight conditions. The sky dome displays the Sun and celestial bodies beyond atmospheric glare."
            finalScore >= 80 ->
                "Exceptional stargazing conditions! Clear sky with outstanding transparency. Highly recommended for the Milky Way and Deep-Sky objects."
            finalScore >= 60 ->
                "Good conditions for visual observation. Major planets and bright constellations are clearly visible."
            moonCoords.isVisible && moon.illuminatedFraction > 0.6 ->
                "Strong moonlight diminishes faint nebulae, but the lunar surface and bright planets shine spectacularly."
            effClouds > 40 ->
                "Partial cloud cover. Observations are possible through clear breaks."
            else ->
                "Moderate observing conditions. Recommended for bright satellites and major planets."
        }

        val bestWindow: String? = if (finalScore >= 50) "21:30 – 01:45" else null

        return StargazingConditions(
            score = finalScore,
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
            dewPointDepressionCelsius = dewPointDepression,
            bestWindowDescription = bestWindow,
            narrativeAdvice = advice
        )
    }

    /**
     * Projects a celestial coordinate (RA, Dec) into 2D viewport screen coordinates
     * using conformal stereographic projection relative to observer's camera attitude.
     * Matches DailyCore projectStereographic exactly.
     */
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
        val time = Time.fromMillisecondsSince1970(millis)
        val obs = Observer(observerLatitudeDegrees, observerLongitudeDegrees, 0.0)
        val hor = horizon(time, obs, raHours, decDegrees, Refraction.None)

        val azRad = Math.toRadians(hor.azimuth)
        val altRad = Math.toRadians(hor.altitude)

        val cosAlt = cos(altRad)
        val xH = cosAlt * sin(azRad)
        val yH = cosAlt * cos(azRad)
        val zH = sin(altRad)

        val camAzRad = Math.toRadians(cameraAzimuthDegrees)
        val camAltRad = Math.toRadians(cameraAltitudeDegrees)
        val camRollRad = Math.toRadians(cameraRollDegrees)

        // 1. Rotate horizontal frame around Z by -camAz
        val cosAz = cos(-camAzRad)
        val sinAz = sin(-camAzRad)
        val x1 = (xH * cosAz) - (yH * sinAz)
        val y1 = (xH * sinAz) + (yH * cosAz)
        val z1 = zH

        // 2. Rotate around X by -camAlt
        val cosAltC = cos(-camAltRad)
        val sinAltC = sin(-camAltRad)
        val x2 = x1
        val y2 = (y1 * cosAltC) - (z1 * sinAltC)
        val z2 = (y1 * sinAltC) + (z1 * cosAltC)

        // Apply camera roll around forward vector (+y2)
        val cosRoll = cos(camRollRad)
        val sinRoll = sin(camRollRad)
        val xCam = (x2 * cosRoll) + (z2 * sinRoll)
        val yCam = (-x2 * sinRoll) + (z2 * cosRoll)
        val zForward = y2

        if (zForward <= 0.05) return null

        val denom = 1.0 + zForward
        val xs = xCam / denom
        val ys = yCam / denom

        val fovRad = Math.toRadians(fovDegrees)
        val tanHalfFov = tan(fovRad / 4.0)
        if (tanHalfFov <= 1e-6) return null

        val scale = (min(viewportWidth, viewportHeight) * 0.5) / tanHalfFov
        val screenX = (viewportWidth * 0.5) + (xs * scale)
        val screenY = (viewportHeight * 0.5) - (ys * scale)

        val isVisibleOnScreen = (screenX >= -50.0 && screenX <= viewportWidth + 50.0 &&
                                 screenY >= -50.0 && screenY <= viewportHeight + 50.0)

        return Triple(screenX, screenY, isVisibleOnScreen)
    }
}
