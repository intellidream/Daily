package com.intellidream.daily.model

import kotlinx.serialization.Serializable

@Serializable
enum class CelestialBody(
    val code: String,
    val displayNameRo: String,
    val symbol: String,
    val colorHex: String
) {
    SUN("Sun", "Sun", "☉", "#FFD700"),
    MOON("Moon", "Moon", "☽", "#F0F3F4"),
    MERCURY("Mercury", "Mercury", "☿", "#B0BEC5"),
    VENUS("Venus", "Venus", "♀", "#FFE082"),
    MARS("Mars", "Mars", "♂", "#FF7043"),
    JUPITER("Jupiter", "Jupiter", "♃", "#FFA726"),
    SATURN("Saturn", "Saturn", "♄", "#FFE082"),
    URANUS("Uranus", "Uranus", "♅", "#80DEEA"),
    NEPTUNE("Neptune", "Neptune", "♆", "#42A5F5"),
    PLUTO("Pluto", "Pluto", "♇", "#BCAAA4");

    val displayName: String get() = displayNameRo

    companion object {
        val majorPlanets = listOf(MERCURY, VENUS, MARS, JUPITER, SATURN, URANUS, NEPTUNE)
        val allBodies = values().toList()
    }
}

@Serializable
data class CelestialCoordinates(
    val azimuthDegrees: Double,
    val altitudeDegrees: Double,
    val rightAscensionHours: Double,
    val declinationDegrees: Double,
    val distanceAU: Double,
    val visualMagnitude: Double
) {
    val isVisible: Boolean get() = altitudeDegrees > 0.0
}

@Serializable
enum class MoonPhaseQuarter(val displayNameRo: String, val symbol: String) {
    NEW_MOON("New Moon", "🌑"),
    WAXING_CRESCENT("Waxing Crescent", "🌒"),
    FIRST_QUARTER("First Quarter", "🌓"),
    WAXING_GIBBOUS("Waxing Gibbous", "🌔"),
    FULL_MOON("Full Moon", "🌕"),
    WANING_GIBBOUS("Waning Gibbous", "🌖"),
    THIRD_QUARTER("Third Quarter", "🌗"),
    WANING_CRESCENT("Waning Crescent", "🌘");

    val displayName: String get() = displayNameRo
}

@Serializable
data class MoonPhaseInfo(
    val phaseAngleDegrees: Double,
    val illuminatedFraction: Double,
    val quarter: MoonPhaseQuarter,
    val ageDays: Double,
    val isWaxing: Boolean,
    val distanceKm: Double
) {
    val illuminationPercent: Int get() = (illuminatedFraction * 100.0).coerceIn(0.0, 100.0).toInt()
}

@Serializable
data class SunTimes(
    val dawnAstronomicalIso: String?,
    val dawnNauticalIso: String?,
    val dawnCivilIso: String?,
    val sunriseIso: String?,
    val solarNoonIso: String?,
    val sunsetIso: String?,
    val duskCivilIso: String?,
    val duskNauticalIso: String?,
    val duskAstronomicalIso: String?
)

@Serializable
enum class StargazingQuality(val displayNameRo: String, val colorHex: String) {
    PRISTINE("Pristine", "#00E676"),
    GOOD("Good", "#00E5FF"),
    FAIR("Fair", "#FFD600"),
    POOR("Poor", "#FF5252");

    val displayName: String get() = displayNameRo
}

@Serializable
data class StargazingConditions(
    val score: Int,
    val quality: StargazingQuality,
    val bortleClass: Int,
    val limitingMagnitude: Double,
    val cloudCoverTotalPercent: Int,
    val cloudCoverLowPercent: Int,
    val cloudCoverMidPercent: Int,
    val cloudCoverHighPercent: Int,
    val moonIlluminationPercent: Int,
    val isMoonAboveHorizon: Boolean,
    val seeingArcseconds: Double? = null,
    val dewPointDepressionCelsius: Double? = null,
    val bestWindowDescription: String? = null,
    val narrativeAdvice: String
)

@Serializable
data class CosmosStar(
    val name: String,
    val bayer: String? = null,
    val constellation: String,
    val raHours: Double,
    val decDegrees: Double,
    val mag: Double,
    val colorIndexBV: Double = 0.0,
    val colorHex: String = "#FFFFFF"
) {
    val visualMag: Double get() = mag
    val decDeg: Double get() = decDegrees
    val nameRo: String get() = name
    val nameEn: String get() = name
    val constellationCode: String get() = constellation
    val bvColorIndex: Double get() = colorIndexBV
    val hip: Int? get() = null
}

@Serializable
data class CosmosConstellation(
    val id: String,
    val nameLa: String,
    val nameEn: String,
    val nameRo: String,
    val centerRa: Double,
    val centerDec: Double,
    val stars: List<String> = emptyList()
) {
    val code: String get() = id
    val latinName: String get() = nameLa
    val romanianName: String get() = nameRo
    val raCenterHours: Double get() = centerRa
    val decCenterDeg: Double get() = centerDec
}

@Serializable
data class CosmosDeepSkyObject(
    val id: String,
    val name: String,
    val constellation: String,
    val raHours: Double,
    val decDegrees: Double,
    val type: String,
    val visualMag: Double,
    val optics: String = "",
    val descRo: String = ""
) {
    val catalogNumber: String get() = id
    val commonNameRo: String get() = name
    val commonNameEn: String get() = name
    val objectType: String get() = type
    val constellationCode: String get() = constellation
    val decDeg: Double get() = decDegrees
}

@Serializable
data class MeteorShower(
    val id: String,
    val nameRo: String,
    val peakDateIso: String,
    val zhrRate: Int,
    val velocityKmS: Double,
    val radiantConstellation: String,
    val parentBody: String
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
