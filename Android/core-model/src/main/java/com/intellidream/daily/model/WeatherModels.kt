package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class WeatherResponse(
    val coord: Coord? = null,
    val weather: List<WeatherDescription> = emptyList(),
    val main: MainWeather,
    val visibility: Int? = null,
    val wind: Wind? = null,
    val clouds: Clouds? = null,
    val dt: Long = System.currentTimeMillis() / 1000,
    val sys: Sys? = null,
    val timezone: Int? = null,
    val id: Long? = null,
    val name: String = "",
    val cod: Int? = null
)

@Serializable
data class ForecastResponse(
    val cod: String? = null,
    val message: Int? = null,
    val cnt: Int? = null,
    val list: List<ForecastItem> = emptyList(),
    val city: City? = null
)

@Serializable
data class ForecastItem(
    val dt: Long,
    val main: MainWeather,
    val weather: List<WeatherDescription> = emptyList(),
    val clouds: Clouds? = null,
    val wind: Wind? = null,
    val visibility: Int? = null,
    val pop: Double? = null, // Probability of precipitation (0.0 to 1.0)
    @SerialName("dt_txt") val dtTxt: String? = null
)

@Serializable
data class Coord(
    val lon: Double,
    val lat: Double
)

@Serializable
data class WeatherDescription(
    val id: Int,
    val main: String,
    val description: String,
    val icon: String
)

@Serializable
data class MainWeather(
    val temp: Double,
    @SerialName("feels_like") val feelsLike: Double? = null,
    @SerialName("temp_min") val tempMin: Double,
    @SerialName("temp_max") val tempMax: Double,
    val pressure: Int = 1013,
    val humidity: Int = 50
)

@Serializable
data class Wind(
    val speed: Double,
    val deg: Int? = null
) {
    val cardinalDirection: String
        get() {
            val d = deg ?: return "N/A"
            val directions = listOf(
                "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
            )
            val index = (((d + 11.25) / 22.5).toInt()) % 16
            return directions[index]
        }
}

@Serializable
data class Clouds(
    val all: Int? = null
)

@Serializable
data class Sys(
    val country: String? = null,
    val sunrise: Long? = null,
    val sunset: Long? = null
)

@Serializable
data class City(
    val id: Long? = null,
    val name: String? = null,
    val coord: Coord? = null,
    val country: String? = null,
    val timezone: Int? = null,
    val sunrise: Long? = null,
    val sunset: Long? = null
)

@Serializable
data class LocationSuggestion(
    val name: String,
    val state: String? = null,
    val country: String? = null,
    val lat: Double,
    val lon: Double
) {
    val id: String get() = "${lat}_${lon}_${name}"
    val displayName: String
        get() {
            val parts = mutableListOf(name)
            if (!state.isNullOrEmpty()) parts.add(state)
            if (!country.isNullOrEmpty()) parts.add(country)
            return parts.joinToString(", ")
        }
}

@Serializable
data class IpLocationResponse(
    val latitude: Double? = null,
    val longitude: Double? = null,
    val cityName: String? = null,
    val countryName: String? = null
)

data class DailyForecastSummary(
    val id: String,
    val timestamp: Long,
    val dayName: String,
    val dateFormatted: String,
    val tempMin: Double,
    val tempMax: Double,
    val iconCode: String,
    val conditionText: String,
    val popMax: Double
)

enum class LocationSource(val displayName: String) {
    Unknown("Locating"),
    GPS("GPS"),
    IP("Network"),
    Manual("Custom")
}

object WeatherConditionHelper {
    fun iconName(iconCode: String): String {
        return when (iconCode) {
            "01d" -> "sunny"
            "01n" -> "clear_night"
            "02d" -> "partly_cloudy_day"
            "02n" -> "partly_cloudy_night"
            "03d", "03n" -> "cloud"
            "04d", "04n" -> "cloudy"
            "09d", "09n" -> "rainy_heavy"
            "10d" -> "rainy"
            "10n" -> "rainy"
            "11d", "11n" -> "thunderstorm"
            "13d", "13n" -> "weather_snowy"
            "50d", "50n" -> "foggy"
            else -> "cloud"
        }
    }

    fun conditionColorHex(iconCode: String): Long {
        return when (iconCode) {
            "01d" -> 0xFFFFD166 // Warm Sun
            "01n" -> 0xFFA0B2C6 // Moon silver
            "02d" -> 0xFFFFE082 // Sun with cloud
            "02n" -> 0xFF78909C
            "03d", "03n", "04d", "04n" -> 0xFF90A4AE // Cloud gray
            "09d", "09n", "10d", "10n" -> 0xFF4A9EFF // Rain blue
            "11d", "11n" -> 0xFFFFB74D // Lightning amber
            "13d", "13n" -> 0xFF80DEEA // Snow cyan
            "50d", "50n" -> 0xFFB0BEC5 // Fog
            else -> 0xFF00E5FF
        }
    }
}
