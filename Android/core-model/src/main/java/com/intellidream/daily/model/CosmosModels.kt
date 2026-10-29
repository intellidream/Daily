package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.*

// MARK: - Telemetry Provenance

@Serializable
data class TelemetryProvenance(
    val kind: String = "offline", // "live", "cached", "offline", "unavailable"
    val fetchedAtMillis: Long? = null,
    val ageMinutes: Int = 0,
    val epochAgeHours: Int? = null,
    val reason: String? = null
) {
    val isAvailable: Boolean get() = kind != "unavailable"

    val badgeLabel: String
        get() = when (kind) {
            "live" -> "Live"
            "cached" -> if (ageMinutes < 60) "Cached (${max(1, ageMinutes)}m)" else "Cached (${ageMinutes / 60}h)"
            "offline" -> {
                val h = epochAgeHours
                if (h != null) {
                    if (h < 24) "Offline OMM (${h}h)" else "Offline OMM (${h / 24}d)"
                } else {
                    "Offline Ephemeris"
                }
            }
            else -> "Unavailable"
        }

    companion object {
        fun live(nowMillis: Long = System.currentTimeMillis()) =
            TelemetryProvenance(kind = "live", fetchedAtMillis = nowMillis)

        fun live(source: String) =
            TelemetryProvenance(kind = "live", fetchedAtMillis = System.currentTimeMillis(), reason = source)

        fun cached(fetchedAtMillis: Long, ageMinutes: Int) =
            TelemetryProvenance(kind = "cached", fetchedAtMillis = fetchedAtMillis, ageMinutes = ageMinutes)

        fun cached(ageSeconds: Long, source: String) =
            TelemetryProvenance(
                kind = "cached",
                fetchedAtMillis = System.currentTimeMillis() - ageSeconds * 1000L,
                ageMinutes = max(1, (ageSeconds / 60L).toInt()),
                reason = source
            )

        fun offlineCalculated(epochAgeHours: Int? = null) =
            TelemetryProvenance(kind = "offline", epochAgeHours = epochAgeHours)

        fun offlineCalculated(source: String) =
            TelemetryProvenance(kind = "offline", reason = source)

        fun unavailable(reason: String = "Unavailable") =
            TelemetryProvenance(kind = "unavailable", reason = reason)
    }
}

// MARK: - Celestial Bodies & Ephemeris

@Serializable
enum class CelestialBody(
    val code: String,
    val displayName: String,
    val symbol: String,
    val colorHex: String
) {
    SUN("Sun", "Sun", "☉", "#FFD700"),
    MOON("Moon", "Moon", "☽", "#F0F3F4"),
    MERCURY("Mercury", "Mercury", "☿", "#B0BEC5"),
    VENUS("Venus", "Venus", "♀", "#FFF9C4"),
    MARS("Mars", "Mars", "♂", "#FF7043"),
    JUPITER("Jupiter", "Jupiter", "♃", "#E6D5B8"),
    SATURN("Saturn", "Saturn", "♄", "#FFE082"),
    URANUS("Uranus", "Uranus", "♅", "#80DEEA"),
    NEPTUNE("Neptune", "Neptune", "♆", "#42A5F5"),
    PLUTO("Pluto", "Pluto", "♇", "#BCAAA4");

    companion object {
        val majorPlanets = listOf(MERCURY, VENUS, MARS, JUPITER, SATURN, URANUS, NEPTUNE)
        val skyBodies = listOf(SUN, MOON, MERCURY, VENUS, MARS, JUPITER, SATURN, URANUS, NEPTUNE)
        val allBodies = entries.toList()
    }
}

@Serializable
data class CelestialCoordinates(
    val azimuthDegrees: Double,
    val altitudeDegrees: Double,
    val rightAscensionHours: Double,
    val declinationDegrees: Double,
    val distanceAU: Double,
    val visualMagnitude: Double,
    val illuminatedFraction: Double = 1.0,
    val brightLimbAngleDegrees: Double = 0.0,
    val angularDiameterArcsec: Double = 0.0
) {
    val isVisible: Boolean get() = altitudeDegrees > 0.0
    val compassDirection: String get() = compassPoint(azimuthDegrees)

    companion object {
        private val COMPASS_DIRS = arrayOf(
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
        )

        fun compassPoint(azimuthDegrees: Double): String {
            if (!azimuthDegrees.isFinite()) return "N"
            val norm = ((azimuthDegrees % 360.0) + 360.0) % 360.0
            val idx = (norm / 22.5).roundToInt() % 16
            return COMPASS_DIRS[idx]
        }
    }
}

@Serializable
data class BodyRiseTransitSet(
    val riseMillis: Long? = null,
    val transitMillis: Long? = null,
    val setMillis: Long? = null,
    val transitAltitudeDegrees: Double? = null
)

@Serializable
enum class MoonPhaseQuarter(val displayName: String, val symbol: String) {
    NEW_MOON("New Moon", "🌑"),
    WAXING_CRESCENT("Waxing Crescent", "🌒"),
    FIRST_QUARTER("First Quarter", "🌓"),
    WAXING_GIBBOUS("Waxing Gibbous", "🌔"),
    FULL_MOON("Full Moon", "🌕"),
    WANING_GIBBOUS("Waning Gibbous", "🌖"),
    THIRD_QUARTER("Third Quarter", "🌗"),
    WANING_CRESCENT("Waning Crescent", "🌘")
}

@Serializable
data class MoonPhaseInfo(
    val phaseAngleDegrees: Double,
    val illuminatedFraction: Double,
    val quarter: MoonPhaseQuarter,
    val ageDays: Double,
    val isWaxing: Boolean,
    val distanceKm: Double,
    val topocentricDistanceKm: Double? = null,
    val brightLimbAngleDegrees: Double = 0.0
) {
    val illuminationPercent: Int get() = (illuminatedFraction * 100.0).roundToInt().coerceIn(0, 100)
}

@Serializable
data class SunTimes(
    val dawnAstronomicalMillis: Long? = null,
    val dawnNauticalMillis: Long? = null,
    val dawnCivilMillis: Long? = null,
    val sunriseMillis: Long? = null,
    val solarNoonMillis: Long? = null,
    val sunsetMillis: Long? = null,
    val duskCivilMillis: Long? = null,
    val duskNauticalMillis: Long? = null,
    val duskAstronomicalMillis: Long? = null
)

@Serializable
data class CircadianSkyContext(
    val trueDarknessOnsetMillis: Long? = null,
    val naturalMoonlightLux: Double = 0.0,
    val summary: String = ""
)

@Serializable
data class MoonVector2D(
    val name: String,
    val xRadius: Double,
    val yRadius: Double,
    val depthRadius: Double,
    val isFrontOfPlanet: Boolean
) {
    val isTransiting: Boolean get() = (xRadius * xRadius + yRadius * yRadius < 1.0) && isFrontOfPlanet
    val isOcculted: Boolean get() = (xRadius * xRadius + yRadius * yRadius < 1.0) && !isFrontOfPlanet
}

@Serializable
data class JupiterMoonsState(
    val io: MoonVector2D,
    val europa: MoonVector2D,
    val ganymede: MoonVector2D,
    val callisto: MoonVector2D
) {
    val all: List<MoonVector2D> get() = listOf(io, europa, ganymede, callisto)
}

// MARK: - Stargazing Intelligence

@Serializable
enum class StargazingQuality(val displayName: String, val colorHex: String) {
    PRISTINE("Pristine", "#00E5FF"),
    GOOD("Good", "#69F0AE"),
    FAIR("Fair", "#FFD740"),
    POOR("Poor", "#FF5252")
}

@Serializable
data class StargazingConditions(
    val score: Int,
    val quality: StargazingQuality,
    val bortleClass: Int,
    val limitingMagnitude: Double,
    val cloudCoverTotalPercent: Int? = null,
    val cloudCoverLowPercent: Int? = null,
    val cloudCoverMidPercent: Int? = null,
    val cloudCoverHighPercent: Int? = null,
    val moonIlluminationPercent: Int,
    val isMoonAboveHorizon: Boolean,
    val seeingArcseconds: Double? = null,
    val transparencyLabel: String? = null,
    val dewPointDepressionCelsius: Double? = null,
    val bestWindowDescription: String? = null,
    val narrativeAdvice: String,
    val provenance: TelemetryProvenance = TelemetryProvenance.offlineCalculated()
)

// MARK: - Satellites (SGP4), Space Weather & APOD

@Serializable
data class CelesTrakOmmRecord(
    val OBJECT_NAME: String,
    val OBJECT_ID: String? = null,
    val NORAD_CAT_ID: Int,
    val EPOCH: String,
    val MEAN_MOTION: Double,
    val ECCENTRICITY: Double,
    val INCLINATION: Double,
    val RA_OF_ASC_NODE: Double,
    val ARG_OF_PERICENTER: Double,
    val MEAN_ANOMALY: Double,
    val BSTAR: Double? = null
)

@Serializable
data class SatelliteTrajectorySample(
    val timestampMillis: Long,
    val azimuthDegrees: Double,
    val altitudeDegrees: Double,
    val isSunlit: Boolean
)

@Serializable
data class SatellitePass(
    val id: String,
    val satelliteName: String,
    val noradCatalogNumber: Int,
    val startTimeMillis: Long,
    val maxAltitudeTimeMillis: Long,
    val endTimeMillis: Long,
    val maxAltitudeDegrees: Double,
    val startAzimuthDegrees: Double = 0.0,
    val maxAzimuthDegrees: Double = 0.0,
    val endAzimuthDegrees: Double = 0.0,
    val startCompass: String,
    val endCompass: String,
    val peakMagnitude: Double,
    val isSunlit: Boolean,
    val trajectory: List<SatelliteTrajectorySample> = emptyList()
) {
    val durationMinutes: Int get() = max(1, ((endTimeMillis - startTimeMillis) / 60_000.0).roundToInt())
}

@Serializable
data class LiveSatellitePosition(
    val satelliteName: String,
    val noradCatalogNumber: Int,
    val timestampMillis: Long,
    val azimuthDegrees: Double,
    val altitudeDegrees: Double,
    val rangeKm: Double,
    val orbitalAltitudeKm: Double,
    val subSatelliteLatitude: Double,
    val subSatelliteLongitude: Double,
    val isSunlit: Boolean,
    val estimatedMagnitude: Double
)

@Serializable
data class SpaceWeatherReport(
    val kpIndex: Double? = null,
    val btTotalFieldNt: Double? = null,
    val bzMagneticFieldNt: Double? = null,
    val solarWindSpeedKmS: Double? = null,
    val solarWindDensityCm3: Double? = null,
    val ovationProbabilityPercent: Int? = null,
    val isAuroraAlertActive: Boolean = false,
    val statusMessage: String = "Space weather unavailable offline.",
    val provenance: TelemetryProvenance = TelemetryProvenance.unavailable("Not yet fetched")
)

@Serializable
data class ApodResponse(
    val date: String,
    val title: String,
    val explanation: String,
    val url: String,
    val hdurl: String? = null,
    val media_type: String = "image",
    val copyright: String? = null
)

// MARK: - Canonical Catalog Records

/**
 * Zero-allocation Structure-of-Arrays (SoA) container for all 15,544 Hipparcos stars (`stars_mag70.bin`),
 * enabling 120Hz batch projection without per-star object boxing or garbage collection.
 */
class PackedStarCatalog(
    val count: Int,
    val hipIds: IntArray,
    val ux: FloatArray,
    val uy: FloatArray,
    val uz: FloatArray,
    val raHours: FloatArray,
    val decDegrees: FloatArray,
    val vMag: FloatArray,
    val bv: FloatArray,
    val constellationIdx: ShortArray,
    val packedArgbColors: IntArray,
    val indexByHip: Map<Int, Int>
) {
    companion object {
        val EMPTY = PackedStarCatalog(
            0, IntArray(0), FloatArray(0), FloatArray(0), FloatArray(0),
            FloatArray(0), FloatArray(0), FloatArray(0), FloatArray(0),
            ShortArray(0), IntArray(0), emptyMap()
        )

        /**
         * Ballesteros (2012) B-V index -> packed sRGB 0xFFRRGGBB color.
         */
        fun ballesterosArgb(bv: Double): Int {
            val c = bv.coerceIn(-0.40, 2.00)
            val t = 4600.0 * (1.0 / (0.92 * c + 1.7) + 1.0 / (0.92 * c + 0.62))
            val tk = t / 100.0
            val r: Double
            val g: Double
            val b: Double
            if (tk <= 66.0) {
                r = 1.0
                g = (0.3900815787690196 * ln(max(1.0, tk)) - 0.6318414437886275).coerceIn(0.0, 1.0)
                b = if (tk <= 19.0) 0.0 else (0.5432067891101961 * ln(max(1.0, tk - 10.0)) - 1.19625408914).coerceIn(0.0, 1.0)
            } else {
                r = (1.292936186062745 * (tk - 60.0).pow(-0.1332047592)).coerceIn(0.0, 1.0)
                g = (1.129890860895294 * (tk - 60.0).pow(-0.0755148492)).coerceIn(0.0, 1.0)
                b = 1.0
            }
            val ri = (r * 255.0).roundToInt().coerceIn(0, 255)
            val gi = (g * 255.0).roundToInt().coerceIn(0, 255)
            val bi = (b * 255.0).roundToInt().coerceIn(0, 255)
            return (0xFF shl 24) or (ri shl 16) or (gi shl 8) or bi
        }
    }
}

@Serializable
data class StarDesignationRecord(
    val hip: Int,
    val name: String? = null,
    val bayer: String? = null,
    val flam: String? = null,
    val hd: String? = null,
    val constellation: String? = null
) {
    val primaryLabel: String
        get() = when {
            !name.isNullOrBlank() -> name
            !bayer.isNullOrBlank() && !bayer.contains("undefined") && !constellation.isNullOrBlank() -> "$bayer $constellation"
            !flam.isNullOrBlank() && !constellation.isNullOrBlank() -> "$flam $constellation"
            else -> "HIP $hip"
        }
}

@Serializable
data class CosmosStar(
    val hip: Int = 0,
    val name: String,
    val bayer: String? = null,
    val constellation: String,
    val raHours: Double,
    val decDegrees: Double,
    val mag: Double,
    val colorIndexBV: Double = 0.0
) {
    val visualMag: Double get() = mag
    val decDeg: Double get() = decDegrees
    val nameEn: String get() = name
    val constellationCode: String get() = constellation
}

@Serializable
data class CosmosConstellation(
    val index: Int = 0,
    val id: String,
    val code: String = id,
    val nameLa: String,
    val nameEn: String,
    val genitive: String = nameLa,
    val centerRaHours: Double,
    val centerDecDeg: Double,
    val rank: Int = 2,
    val lore: String = "",
    val segments: List<List<Int>> = emptyList()
) {
    val latinName: String get() = nameLa
    val raCenterHours: Double get() = centerRaHours
    val decCenterDeg: Double get() = centerDecDeg
}

@Serializable
data class CosmosConstellationBorderArc(
    val ids: List<String> = emptyList(),
    val points: List<List<Double>> = emptyList()
)

@Serializable
data class CosmosAsterism(
    val id: String,
    val name: String,
    val season: String = "",
    val description: String = "",
    val centerRaHours: Double,
    val centerDecDeg: Double,
    val segments: List<List<Int>> = emptyList()
)

@Serializable
data class CosmosDeepSkyObject(
    val id: String,
    val catalog: String = "Messier",
    val ngcIc: String? = null,
    val name: String,
    val constellation: String,
    val type: String = "Deep-Sky Object",
    val typeCode: String = "DSO",
    val raHours: Double,
    val decDeg: Double,
    val visualMag: Double,
    val surfaceBrightness: Double? = null,
    val majorAxisArcmin: Double = 10.0,
    val minorAxisArcmin: Double = 10.0,
    val positionAngleDeg: Double = 0.0,
    val distanceLy: Double? = null,
    val recommendedOptics: String = "Binoculars 7x50",
    val thumbnail: String? = null,
    val description: String = ""
) {
    val catalogNumber: String get() = id
    val commonNameEn: String get() = name
    val objectType: String get() = type
    val category: String get() = type
    val ngc: String? get() = ngcIc?.takeIf { it.isNotBlank() }
    val optics: String get() = recommendedOptics
    val constellationCode: String get() = constellation
    val vMag: Double get() = visualMag
    val decDegrees: Double get() = decDeg

    val ux: Float
        get() {
            val raRad = Math.toRadians(raHours * 15.0)
            val decRad = Math.toRadians(decDeg)
            return (cos(decRad) * cos(raRad)).toFloat()
        }
    val uy: Float
        get() {
            val raRad = Math.toRadians(raHours * 15.0)
            val decRad = Math.toRadians(decDeg)
            return (cos(decRad) * sin(raRad)).toFloat()
        }
    val uz: Float
        get() = sin(Math.toRadians(decDeg)).toFloat()
}

@Serializable
data class MeteorShower(
    val id: String,
    val name: String,
    val constellation: String,
    val startMonth: Int,
    val startDay: Int,
    val endMonth: Int,
    val endDay: Int,
    val peakMonth: Int,
    val peakDay: Int,
    val peakSolarLongitudeDeg: Double = 0.0,
    val radiantRaHours: Double,
    val radiantDecDeg: Double,
    val driftRaPerDay: Double = 0.0,
    val driftDecPerDay: Double = 0.0,
    val zhr: Int,
    val velocityKmS: Double,
    val parentBody: String,
    val description: String = ""
) {
    fun isActiveOn(monthOneBased: Int, dayOfMonth: Int): Boolean {
        val cur = monthOneBased * 100 + dayOfMonth
        val start = startMonth * 100 + startDay
        val end = endMonth * 100 + endDay
        return if (start <= end) (cur in start..end) else (cur >= start || cur <= end)
    }
}

class MilkyWayContourLayer(
    val level: Int,
    val ringsUx: Array<FloatArray>,
    val ringsUy: Array<FloatArray>,
    val ringsUz: Array<FloatArray>
)

// MARK: - Zero-Trig Frame Projection Matrix (120Hz Path)

data class ProjectedPoint(
    val x: Double,
    val y: Double,
    val cz: Double,
    val isVisible: Boolean
)

class SkyProjectionMatrix(
    val m00: Double, val m01: Double, val m02: Double,
    val m10: Double, val m11: Double, val m12: Double,
    val m20: Double, val m21: Double, val m22: Double,
    val rx: Double, val ry: Double, val rz: Double,
    val ux: Double, val uy: Double, val uz: Double,
    val fx: Double, val fy: Double, val fz: Double,
    val h00: Double, val h01: Double, val h02: Double,
    val h10: Double, val h11: Double, val h12: Double,
    val h20: Double, val h21: Double, val h22: Double,
    val viewportWidth: Double,
    val viewportHeight: Double,
    val fovDegrees: Double
) {
    val halfWidth: Double = viewportWidth * 0.5
    val halfHeight: Double = viewportHeight * 0.5
    val scale: Double = (min(viewportWidth, viewportHeight) * 0.5) /
        max(1e-6, tan(Math.toRadians(fovDegrees.coerceIn(0.4, 150.0)) * 0.25))

    fun projectEQJUnitVector(vx: Double, vy: Double, vz: Double, margin: Double = 60.0): ProjectedPoint? {
        val cx = m00 * vx + m01 * vy + m02 * vz
        val cy = m10 * vx + m11 * vy + m12 * vz
        val cz = m20 * vx + m21 * vy + m22 * vz
        val denom = 1.0 + cz
        if (denom < 0.08) return null
        val inv = scale / denom
        val sx = halfWidth + cx * inv
        val sy = halfHeight - cy * inv
        val vis = (sx >= -margin && sx <= viewportWidth + margin && sy >= -margin && sy <= viewportHeight + margin)
        return ProjectedPoint(sx, sy, cz, vis)
    }

    fun projectHorizontal(azimuthDegrees: Double, altitudeDegrees: Double, margin: Double = 60.0): ProjectedPoint? {
        val az = Math.toRadians(azimuthDegrees)
        val alt = Math.toRadians(altitudeDegrees)
        val cosAlt = cos(alt)
        val hx = cosAlt * cos(az)
        val hy = -cosAlt * sin(az)
        val hz = sin(alt)
        val cx = rx * hx + ry * hy + rz * hz
        val cy = ux * hx + uy * hy + uz * hz
        val cz = fx * hx + fy * hy + fz * hz
        val denom = 1.0 + cz
        if (denom < 0.08) return null
        val inv = scale / denom
        val sx = halfWidth + cx * inv
        val sy = halfHeight - cy * inv
        val vis = (sx >= -margin && sx <= viewportWidth + margin && sy >= -margin && sy <= viewportHeight + margin)
        return ProjectedPoint(sx, sy, cz, vis)
    }

    fun unprojectToHorizontal(screenX: Double, screenY: Double): Pair<Double, Double>? {
        if (scale <= 1e-6) return null
        val xp = (screenX - halfWidth) / scale
        val yp = (halfHeight - screenY) / scale
        val r2 = xp * xp + yp * yp
        val inv = 1.0 / (1.0 + r2)
        val cx = 2.0 * xp * inv
        val cy = 2.0 * yp * inv
        val cz = (1.0 - r2) * inv
        val hx = cx * rx + cy * ux + cz * fx
        val hy = cx * ry + cy * uy + cz * fy
        val hz = cx * rz + cy * uz + cz * fz
        val altDeg = Math.toDegrees(asin(hz.coerceIn(-1.0, 1.0)))
        val azDeg = (Math.toDegrees(atan2(-hy, hx)) + 360.0) % 360.0
        return Pair(azDeg, altDeg)
    }
}

// MARK: - Synced Bookmarks & Sky Observations

@Serializable
data class CosmosBookmark(
    val id: String,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("object_id") val objectId: String,
    @SerialName("object_name") val objectName: String,
    val category: String = "star",
    @SerialName("ra_hours") val raHours: Double? = null,
    @SerialName("dec_deg") val decDeg: Double? = null,
    val magnitude: Double? = null,
    val constellation: String? = null,
    val notes: String = "",
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String
)

@Serializable
data class CosmosObservation(
    val id: String,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("object_id") val objectId: String,
    @SerialName("object_name") val objectName: String,
    val category: String = "star",
    @SerialName("observed_at") val observedAt: String,
    val latitude: Double,
    val longitude: Double,
    @SerialName("location_name") val locationName: String = "",
    @SerialName("azimuth_deg") val azimuthDeg: Double? = null,
    @SerialName("altitude_deg") val altitudeDeg: Double? = null,
    @SerialName("bortle_class") val bortleClass: Int? = null,
    @SerialName("stargazing_score") val stargazingScore: Int? = null,
    val optics: String = "Naked Eye",
    val notes: String = "",
    @SerialName("tagdos_note_id") val tagdosNoteId: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String
)

@Serializable
data class CosmosSkySnapshot(
    val dateTimeIso: String,
    val latitude: Double,
    val longitude: Double,
    val conditions: StargazingConditions,
    val moon: MoonPhaseInfo,
    val planets: Map<CelestialBody, CelestialCoordinates>,
    val visiblePlanetsCount: Int,
    val nextVisiblePlanet: CelestialBody?
)
