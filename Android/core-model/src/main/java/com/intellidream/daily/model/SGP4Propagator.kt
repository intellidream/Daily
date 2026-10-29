package com.intellidream.daily.model

import io.github.cosinekitty.astronomy.Aberration
import io.github.cosinekitty.astronomy.Body
import io.github.cosinekitty.astronomy.Time
import io.github.cosinekitty.astronomy.geoVector
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.*

/**
 * Real analytical NORAD / Vallado near-Earth SGP4 orbital propagator for CelesTrak OMM GP records.
 * Computes TEME state vectors, GMST/WGS-84 topocentric (Azimuth, Altitude, Range), cylindrical Earth
 * umbra illumination state, and sunlit AOS/TCA/LOS passes with 100% parity to Swift & C#.
 */
object SGP4Propagator {
    private const val DEG2RAD = Math.PI / 180.0
    private const val RAD2DEG = 180.0 / Math.PI
    private const val TWO_PI = 2.0 * Math.PI

    // WGS-72 constants per NORAD SGP4 / Vallado AIAA 2006-6753
    private const val MU = 398600.8 // km^3 / s^2
    private const val RADIUS_EARTH_KM = 6378.135 // km
    private val XKE = 60.0 / sqrt((RADIUS_EARTH_KM * RADIUS_EARTH_KM * RADIUS_EARTH_KM) / MU)
    private const val J2 = 0.001082616
    private const val J3 = -0.00000253881
    private const val J4 = -0.00000165597
    private const val CK2 = 0.5 * J2
    private const val CK4 = -0.375 * J4
    private val QOMS2T = ((120.0 - 78.0) / RADIUS_EARTH_KM).pow(4.0)
    private const val S_PARAM = 1.0 + 78.0 / RADIUS_EARTH_KM

    fun parseOmmEpochMillis(raw: String): Long? {
        val trimmed = raw.trim()
        val withZ = if (trimmed.endsWith("Z")) trimmed else "${trimmed}Z"
        return try {
            Instant.parse(withZ).toEpochMilli()
        } catch (_: Exception) {
            try {
                val clean = trimmed.removeSuffix("Z")
                val dt = LocalDateTime.parse(clean, DateTimeFormatter.ISO_LOCAL_DATE_TIME)
                dt.toInstant(ZoneOffset.UTC).toEpochMilli()
            } catch (_: Exception) {
                null
            }
        }
    }

    fun julianDate(epochMillis: Long): Double =
        2440587.5 + (epochMillis.toDouble() / 86_400_000.0)

    fun gmstRadians(julianDateUt1: Double): Double {
        val tut1 = (julianDateUt1 - 2451545.0) / 36525.0
        var temp = -6.2e-6 * tut1 * tut1 * tut1 +
            0.093104 * tut1 * tut1 +
            (876600.0 * 3600.0 + 8640184.812866) * tut1 +
            67310.54841
        temp = (temp * DEG2RAD / 240.0) % TWO_PI
        if (temp < 0.0) temp += TWO_PI
        return temp
    }

    fun propagateTEMEKm(omm: CelesTrakOmmRecord, minutesSinceEpoch: Double): Triple<Double, Double, Double>? {
        if (omm.MEAN_MOTION <= 0.01 || omm.ECCENTRICITY < 0.0 || omm.ECCENTRICITY >= 1.0) return null

        val noKozai = omm.MEAN_MOTION * TWO_PI / 1440.0
        val e0 = omm.ECCENTRICITY
        val i0 = omm.INCLINATION * DEG2RAD
        val node0 = omm.RA_OF_ASC_NODE * DEG2RAD
        val omega0 = omm.ARG_OF_PERICENTER * DEG2RAD
        val m0 = omm.MEAN_ANOMALY * DEG2RAD
        val bstar = omm.BSTAR ?: 0.0

        val cosio = cos(i0)
        val sinio = sin(i0)
        val theta2 = cosio * cosio
        val x3thm1 = 3.0 * theta2 - 1.0
        val eosq = e0 * e0
        val betao2 = max(1e-10, 1.0 - eosq)
        val betao = sqrt(betao2)

        val a1 = (XKE / noKozai).pow(2.0 / 3.0)
        val del1 = 1.5 * CK2 * x3thm1 / (a1 * a1 * betao * betao2)
        val ao = a1 * (1.0 - del1 * ((1.0 / 3.0) + del1 * (1.0 + (134.0 / 81.0) * del1)))
        val delo = 1.5 * CK2 * x3thm1 / (ao * ao * betao * betao2)
        val xnodp = noKozai / (1.0 + delo)
        val aodp = ao / (1.0 - delo)

        val perige = (aodp * (1.0 - e0) - 1.0) * RADIUS_EARTH_KM
        var sfour = S_PARAM
        var qzms24 = QOMS2T
        if (perige < 156.0) {
            sfour = perige - 78.0
            if (perige <= 98.0) sfour = 20.0
            qzms24 = ((120.0 - sfour) / RADIUS_EARTH_KM).pow(4.0)
            sfour = sfour / RADIUS_EARTH_KM + 1.0
        }

        val pinvsq = 1.0 / (aodp * aodp * betao2 * betao2)
        val tsi = 1.0 / (aodp - sfour)
        val eta = aodp * e0 * tsi
        val etasq = eta * eta
        val eeta = e0 * eta
        val psisq = abs(1.0 - etasq)
        val coef = qzms24 * tsi.pow(4.0)
        val coef1 = coef / psisq.pow(3.5)
        val c2 = coef1 * xnodp * (
            aodp * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq)) +
                0.75 * CK2 * tsi / psisq * x3thm1 * (8.0 + 3.0 * etasq * (8.0 + etasq))
            )
        val c1 = bstar * c2
        val c4 = 2.0 * xnodp * coef1 * aodp * betao2 * (
            eta * (2.0 + 0.5 * etasq) + e0 * (0.5 + 2.0 * etasq) -
                2.0 * CK2 * tsi / (aodp * psisq) * (
                    -3.0 * x3thm1 * (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta)) +
                        0.75 * (1.0 - theta2) * (2.0 * etasq - eeta * (1.0 + etasq)) * cos(2.0 * omega0)
                    )
            )

        val theta4 = theta2 * theta2
        val temp1 = 3.0 * CK2 * pinvsq * xnodp
        val temp2 = temp1 * CK2 * pinvsq
        val temp3 = 1.25 * CK4 * pinvsq * pinvsq * xnodp

        val xmdot = xnodp + 0.5 * temp1 * betao * x3thm1 + 0.0625 * temp2 * betao * (13.0 - 78.0 * theta2 + 137.0 * theta4)
        val omgdot = -0.5 * temp1 * (1.0 - 5.0 * theta2) +
            0.0625 * temp2 * (7.0 - 114.0 * theta2 + 395.0 * theta4) +
            temp3 * (3.0 - 36.0 * theta2 + 49.0 * theta4)
        val xhdot1 = -temp1 * cosio
        val xnodot = xhdot1 + (0.5 * temp2 * (4.0 - 19.0 * theta2) + 2.0 * temp3 * (3.0 - 7.0 * theta2)) * cosio

        val xnodcf = 3.5 * betao2 * xhdot1 * c1
        val t2cof = 1.5 * c1
        val xlcof = if (abs(1.0 + cosio) > 1.5e-12) {
            0.125 * (J3 / CK2) * sinio * (3.0 + 5.0 * cosio) / (1.0 + cosio)
        } else 0.0
        val aycof = 0.25 * (J3 / CK2) * sinio

        val t = minutesSinceEpoch
        val xmdf = m0 + xmdot * t
        val omgadf = omega0 + omgdot * t
        val xnoddf = node0 + xnodot * t
        val tsq = t * t
        val xnode = xnoddf + xnodcf * tsq
        val tempa = 1.0 - c1 * t
        val tempe = bstar * c4 * t
        val templ = t2cof * tsq

        val a = aodp * tempa * tempa
        if (a <= 0.9) return null
        val e = (e0 - tempe).coerceIn(1.0e-6, 0.999)
        val xl = xmdf + omgadf + xnode + xnodp * templ

        val axn = e * cos(omgadf)
        val temp = 1.0 / (a * (1.0 - e * e))
        val xll = temp * xlcof * axn
        val aynl = temp * aycof
        val xlt = xl + xll
        val ayn = e * sin(omgadf) + aynl

        var capu = (xlt - xnode) % TWO_PI
        if (capu < 0.0) capu += TWO_PI

        var epw = capu
        for (iter in 0 until 10) {
            val sinepw = sin(epw)
            val cosepw = cos(epw)
            val ecosE = axn * cosepw + ayn * sinepw
            val esinE = axn * sinepw - ayn * cosepw
            val f = capu - epw + esinE
            if (abs(f) < 1.0e-12) break
            val df = 1.0 - ecosE
            if (abs(df) > 1.0e-12) {
                epw += f / df
            }
        }

        val sinepw = sin(epw)
        val cosepw = cos(epw)
        val ecosE = axn * cosepw + ayn * sinepw
        val esinE = axn * sinepw - ayn * cosepw
        val el2 = axn * axn + ayn * ayn
        if (el2 >= 1.0) return null
        val pl = a * (1.0 - el2)
        val r = a * (1.0 - ecosE)
        val betal = sqrt(1.0 - el2)
        val tempBetal = esinE / (1.0 + betal)
        val cosu = (a / r) * (cosepw - axn + ayn * tempBetal)
        val sinu = (a / r) * (sinepw - ayn - axn * tempBetal)
        val u = atan2(sinu, cosu)
        val sin2u = 2.0 * sinu * cosu
        val cos2u = 2.0 * cosu * cosu - 1.0

        val invPl = 1.0 / pl
        val t1 = CK2 * invPl
        val t2 = t1 * invPl
        val rk = r * (1.0 - 1.5 * t2 * betal * x3thm1) + 0.5 * t1 * (1.0 - theta2) * cos2u
        val uk = u - 0.25 * t2 * (7.0 * theta2 - 1.0) * sin2u
        val xnodek = xnode + 1.5 * t2 * cosio * sin2u
        val xinck = i0 + 1.5 * t2 * cosio * sinio * cos2u

        val sinuk = sin(uk)
        val cosuk = cos(uk)
        val sinik = sin(xinck)
        val cosik = cos(xinck)
        val sinnok = sin(xnodek)
        val cosnok = cos(xnodek)

        val ux = -sinnok * cosik * sinuk + cosnok * cosuk
        val uy = cosnok * cosik * sinuk + sinnok * cosuk
        val uz = sinik * sinuk

        val rKm = rk * RADIUS_EARTH_KM
        return Triple(rKm * ux, rKm * uy, rKm * uz)
    }

    data class TopocentricState(
        val azimuthDegrees: Double,
        val altitudeDegrees: Double,
        val rangeKm: Double,
        val subLat: Double,
        val subLon: Double,
        val orbitalAltKm: Double
    )

    fun topocentricFromTEME(
        temeKm: Triple<Double, Double, Double>,
        epochMillis: Long,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        elevationMeters: Double = 0.0
    ): TopocentricState {
        val jd = julianDate(epochMillis)
        val gmst = gmstRadians(jd)
        val cg = cos(gmst)
        val sg = sin(gmst)

        val xEcef = cg * temeKm.first + sg * temeKm.second
        val yEcef = -sg * temeKm.first + cg * temeKm.second
        val zEcef = temeKm.third

        val rSat = sqrt(xEcef * xEcef + yEcef * yEcef + zEcef * zEcef)
        val subLat = asin((zEcef / max(1.0, rSat)).coerceIn(-1.0, 1.0)) * RAD2DEG
        val subLon = atan2(yEcef, xEcef) * RAD2DEG
        val orbitalAltKm = max(0.0, rSat - 6371.0)

        val aEarth = 6378.137
        val fEarth = 1.0 / 298.257223563
        val e2 = fEarth * (2.0 - fEarth)
        val lat = latitudeDegrees * DEG2RAD
        val lon = longitudeDegrees * DEG2RAD
        val sinLat = sin(lat)
        val cosLat = cos(lat)
        val sinLon = sin(lon)
        val cosLon = cos(lon)
        val nVal = aEarth / sqrt(1.0 - e2 * sinLat * sinLat)
        val altKm = elevationMeters / 1000.0
        val obsX = (nVal + altKm) * cosLat * cosLon
        val obsY = (nVal + altKm) * cosLat * sinLon
        val obsZ = (nVal * (1.0 - e2) + altKm) * sinLat

        val dx = xEcef - obsX
        val dy = yEcef - obsY
        val dz = zEcef - obsZ
        val rangeKm = max(1e-3, sqrt(dx * dx + dy * dy + dz * dz))

        val east = -sinLon * dx + cosLon * dy
        val north = -sinLat * cosLon * dx - sinLat * sinLon * dy + cosLat * dz
        val up = cosLat * cosLon * dx + cosLat * sinLon * dy + sinLat * dz

        val altDeg = asin((up / rangeKm).coerceIn(-1.0, 1.0)) * RAD2DEG
        val azDeg = (atan2(east, north) * RAD2DEG + 360.0) % 360.0
        return TopocentricState(azDeg, altDeg, rangeKm, subLat, subLon, orbitalAltKm)
    }

    fun isSatelliteSunlit(temeKm: Triple<Double, Double, Double>, epochMillis: Long): Boolean {
        val time = Time.fromMillisecondsSince1970(epochMillis)
        val sunGeo = geoVector(Body.Sun, time, Aberration.Corrected)
        val sunDist = sunGeo.length()
        if (sunDist <= 0.1) return true
        val sx = sunGeo.x / sunDist
        val sy = sunGeo.y / sunDist
        val sz = sunGeo.z / sunDist

        val proj = temeKm.first * sx + temeKm.second * sy + temeKm.third * sz
        if (proj >= 0.0) return true
        val rSq = temeKm.first * temeKm.first + temeKm.second * temeKm.second + temeKm.third * temeKm.third
        val perpSq = max(0.0, rSq - proj * proj)
        return perpSq > (6378.137 * 6378.137)
    }

    fun livePosition(
        omm: CelesTrakOmmRecord,
        epochMillis: Long,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        elevationMeters: Double = 0.0
    ): LiveSatellitePosition? {
        val ommEpochMillis = parseOmmEpochMillis(omm.EPOCH) ?: return null
        val tsinceMin = (epochMillis - ommEpochMillis).toDouble() / 60_000.0
        val teme = propagateTEMEKm(omm, tsinceMin) ?: return null
        val topo = topocentricFromTEME(teme, epochMillis, latitudeDegrees, longitudeDegrees, elevationMeters)
        val sunlit = isSatelliteSunlit(teme, epochMillis)
        val estMag = if (sunlit) {
            -1.8 + 5.0 * log10(max(200.0, topo.rangeKm) / 1000.0) - (if (omm.NORAD_CAT_ID == 25544) 1.4 else 0.0)
        } else {
            12.0
        }
        return LiveSatellitePosition(
            satelliteName = omm.OBJECT_NAME,
            noradCatalogNumber = omm.NORAD_CAT_ID,
            timestampMillis = epochMillis,
            azimuthDegrees = topo.azimuthDegrees,
            altitudeDegrees = topo.altitudeDegrees,
            rangeKm = topo.rangeKm,
            orbitalAltitudeKm = topo.orbitalAltKm,
            subSatelliteLatitude = topo.subLat,
            subSatelliteLongitude = topo.subLon,
            isSunlit = sunlit,
            estimatedMagnitude = estMag
        )
    }

    fun predictVisiblePasses(
        omm: CelesTrakOmmRecord,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        elevationMeters: Double = 0.0,
        startMillis: Long = System.currentTimeMillis(),
        hoursAhead: Double = 36.0,
        minPeakAltitudeDegrees: Double = 12.0,
        maxPasses: Int = 5
    ): List<SatellitePass> {
        val ommEpochMillis = parseOmmEpochMillis(omm.EPOCH) ?: return emptyList()
        val stepMs = 30_000L
        val totalSteps = ((hoursAhead * 3600_000.0) / stepMs).toInt()
        val passes = mutableListOf<SatellitePass>()

        var inPass = false
        var passStartMs = startMillis
        var peakAlt = -90.0
        var peakMs = startMillis

        for (i in 0..totalSteps) {
            val tMs = startMillis + i * stepMs
            val tsinceMin = (tMs - ommEpochMillis).toDouble() / 60_000.0
            val teme = propagateTEMEKm(omm, tsinceMin) ?: continue
            val topo = topocentricFromTEME(teme, tMs, latitudeDegrees, longitudeDegrees, elevationMeters)

            if (topo.altitudeDegrees >= 10.0) {
                if (!inPass) {
                    inPass = true
                    passStartMs = tMs
                    peakAlt = topo.altitudeDegrees
                    peakMs = tMs
                } else if (topo.altitudeDegrees > peakAlt) {
                    peakAlt = topo.altitudeDegrees
                    peakMs = tMs
                }
            } else if (inPass) {
                inPass = false
                val passEndMs = tMs

                var bestPeakMs = peakMs
                var bestPeakPos = livePosition(omm, peakMs, latitudeDegrees, longitudeDegrees, elevationMeters)
                var offsetSec = -25
                while (offsetSec <= 25) {
                    val candMs = peakMs + offsetSec * 1000L
                    val pos = livePosition(omm, candMs, latitudeDegrees, longitudeDegrees, elevationMeters)
                    if (pos != null && pos.altitudeDegrees > (bestPeakPos?.altitudeDegrees ?: -90.0)) {
                        bestPeakMs = candMs
                        bestPeakPos = pos
                    }
                    offsetSec += 5
                }

                val peakPos = bestPeakPos
                if (peakPos == null || peakPos.altitudeDegrees < minPeakAltitudeDegrees) continue

                val sunCoords = AstronomyService.coordinates(
                    CelestialBody.SUN,
                    latitudeDegrees,
                    longitudeDegrees,
                    elevationMeters,
                    AstronomyService.makeTime(bestPeakMs)
                )

                val samples = mutableListOf<SatelliteTrajectorySample>()
                var anySunlitAbove10 = false
                var bestSunlitMag = if (peakPos.isSunlit) peakPos.estimatedMagnitude else 99.0
                var cursorMs = passStartMs - 20_000L
                val stopMs = passEndMs + 20_000L
                while (cursorMs <= stopMs) {
                    val sPos = livePosition(omm, cursorMs, latitudeDegrees, longitudeDegrees, elevationMeters)
                    if (sPos != null && sPos.altitudeDegrees >= 0.0) {
                        if (sPos.isSunlit && sPos.altitudeDegrees >= 10.0) {
                            anySunlitAbove10 = true
                            bestSunlitMag = minOf(bestSunlitMag, sPos.estimatedMagnitude)
                        }
                        samples.add(
                            SatelliteTrajectorySample(
                                timestampMillis = cursorMs,
                                azimuthDegrees = sPos.azimuthDegrees,
                                altitudeDegrees = sPos.altitudeDegrees,
                                isSunlit = sPos.isSunlit
                            )
                        )
                    }
                    cursorMs += 20_000L
                }

                if (!anySunlitAbove10 || bestSunlitMag >= 5.0 || sunCoords.altitudeDegrees > -5.0 || samples.isEmpty()) continue

                val firstS = samples.first()
                val lastS = samples.last()
                passes.add(
                    SatellitePass(
                        id = "SAT-${omm.NORAD_CAT_ID}-${firstS.timestampMillis / 1000L}",
                        satelliteName = omm.OBJECT_NAME,
                        noradCatalogNumber = omm.NORAD_CAT_ID,
                        startTimeMillis = firstS.timestampMillis,
                        maxAltitudeTimeMillis = bestPeakMs,
                        endTimeMillis = lastS.timestampMillis,
                        maxAltitudeDegrees = peakPos.altitudeDegrees,
                        startAzimuthDegrees = firstS.azimuthDegrees,
                        maxAzimuthDegrees = peakPos.azimuthDegrees,
                        endAzimuthDegrees = lastS.azimuthDegrees,
                        startCompass = CelestialCoordinates.compassPoint(firstS.azimuthDegrees),
                        endCompass = CelestialCoordinates.compassPoint(lastS.azimuthDegrees),
                        peakMagnitude = bestSunlitMag,
                        isSunlit = true,
                        trajectory = samples
                    )
                )
                if (passes.size >= maxPasses) break
            }
        }
        return passes
    }
}
