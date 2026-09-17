package com.intellidream.daily.network

import com.intellidream.daily.model.DailyForecastSummary
import com.intellidream.daily.model.ForecastItem
import com.intellidream.daily.model.ForecastResponse
import com.intellidream.daily.model.IpLocationResponse
import com.intellidream.daily.model.LocationSource
import com.intellidream.daily.model.WeatherResponse
import com.intellidream.daily.model.WeatherUnitSystem
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs

class WeatherRepository(
    private val coroutineScope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {
    private val apiKey = "eebcefca9dbf33a96cb6d583481235d2"
    private val baseUrl = "https://api.openweathermap.org/data/2.5"
    private val ipUrl = "https://freeipapi.com/api/json"

    private val httpClient = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
                encodeDefaults = true
            })
        }
    }

    private val cacheDurationMs = 15 * 60 * 1000L // 15 minutes
    private var lastFetchTime = 0L
    private var lastCoordinates: Pair<Double, Double>? = null

    private val _currentWeather = MutableStateFlow<WeatherResponse?>(null)
    val currentWeather: StateFlow<WeatherResponse?> = _currentWeather.asStateFlow()

    private val _forecast = MutableStateFlow<ForecastResponse?>(null)
    val forecast: StateFlow<ForecastResponse?> = _forecast.asStateFlow()

    private val _dailySummaries = MutableStateFlow<List<DailyForecastSummary>>(emptyList())
    val dailySummaries: StateFlow<List<DailyForecastSummary>> = _dailySummaries.asStateFlow()

    private val _hourlyForecasts = MutableStateFlow<List<ForecastItem>>(emptyList())
    val hourlyForecasts: StateFlow<List<ForecastItem>> = _hourlyForecasts.asStateFlow()

    private val _currentLocationName = MutableStateFlow("Detecting...")
    val currentLocationName: StateFlow<String> = _currentLocationName.asStateFlow()

    private val _locationSource = MutableStateFlow(LocationSource.Unknown)
    val locationSource: StateFlow<LocationSource> = _locationSource.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    fun initializeWithCache(
        cachedWeather: WeatherResponse?,
        cachedForecast: ForecastResponse?,
        cityName: String?,
        timestamp: Long,
        lat: Double?,
        lon: Double?
    ) {
        if (cachedWeather != null) {
            _currentWeather.value = cachedWeather
            if (!cityName.isNullOrEmpty()) _currentLocationName.value = cityName
            if (lat != null && lon != null) lastCoordinates = Pair(lat, lon)
            lastFetchTime = timestamp
        }
        if (cachedForecast != null) {
            _forecast.value = cachedForecast
            _hourlyForecasts.value = cachedForecast.list.take(8)
            _dailySummaries.value = aggregateDailyForecasts(cachedForecast.list)
        }
    }

    suspend fun refreshWeather(
        force: Boolean = false,
        unitSystem: WeatherUnitSystem = WeatherUnitSystem.Metric,
        onSuccess: ((WeatherResponse, ForecastResponse, String, Double, Double) -> Unit)? = null
    ) {
        if (_isLoading.value) return
        _isLoading.value = true
        _errorMessage.value = null

        try {
            val (lat, lon, cityName, source) = getResilientCoordinates()
            val units = if (unitSystem == WeatherUnitSystem.Metric) "metric" else "imperial"

            val weather = fetchCurrentWeather(lat, lon, units, force)
            val forecastData = fetchForecast(lat, lon, units, force)

            _currentWeather.value = weather
            _forecast.value = forecastData
            lastCoordinates = Pair(lat, lon)
            lastFetchTime = System.currentTimeMillis()
            _locationSource.value = source

            val resolvedName = when {
                weather.name.isNotEmpty() -> weather.name
                !cityName.isNullOrEmpty() -> cityName
                else -> "Local Area"
            }
            _currentLocationName.value = resolvedName
            _hourlyForecasts.value = forecastData.list.take(8)
            _dailySummaries.value = aggregateDailyForecasts(forecastData.list)

            onSuccess?.invoke(weather, forecastData, resolvedName, lat, lon)
        } catch (e: Exception) {
            _errorMessage.value = e.message ?: "Failed to fetch atmospheric telemetry"
        } finally {
            _isLoading.value = false
        }
    }

    private suspend fun getResilientCoordinates(): CoordinatesResult {
        // 1. Check in-memory coordinates if within cache TTL
        val cached = lastCoordinates
        if (cached != null && (System.currentTimeMillis() - lastFetchTime) < cacheDurationMs) {
            return CoordinatesResult(cached.first, cached.second, _currentLocationName.value, _locationSource.value)
        }

        // 2. IP Geolocation fallback (freeipapi.com)
        try {
            val ipInfo: IpLocationResponse = httpClient.get(ipUrl).body()
            val lat = ipInfo.latitude
            val lon = ipInfo.longitude
            if (lat != null && lon != null) {
                return CoordinatesResult(lat, lon, ipInfo.cityName, LocationSource.IP)
            }
        } catch (e: Exception) {
            // Ignore IP failure and fall back
        }

        // 3. Fallback coordinates (Bucharest / New York default)
        return CoordinatesResult(44.4268, 26.1025, "Bucharest", LocationSource.Unknown)
    }

    private suspend fun fetchCurrentWeather(lat: Double, lon: Double, units: String, force: Boolean): WeatherResponse {
        val url = "$baseUrl/weather?lat=$lat&lon=$lon&appid=$apiKey&units=$units"
        return httpClient.get(url).body()
    }

    private suspend fun fetchForecast(lat: Double, lon: Double, units: String, force: Boolean): ForecastResponse {
        val url = "$baseUrl/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=$units"
        return httpClient.get(url).body()
    }

    private fun aggregateDailyForecasts(items: List<ForecastItem>): List<DailyForecastSummary> {
        val dayFormat = SimpleDateFormat("EEE", Locale.getDefault())
        val dateFormat = SimpleDateFormat("MMM d", Locale.getDefault())
        val dateKeyFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())

        val grouped = items.groupBy { item ->
            dateKeyFormat.format(Date(item.dt * 1000L))
        }

        return grouped.map { (dateKey, dayItems) ->
            val first = dayItems.first()
            val date = Date(first.dt * 1000L)
            val minTemp = dayItems.minOf { it.main.tempMin }
            val maxTemp = dayItems.maxOf { it.main.tempMax }
            val icon = dayItems.firstOrNull { it.weather.isNotEmpty() }?.weather?.first()?.icon ?: "01d"
            val desc = dayItems.firstOrNull { it.weather.isNotEmpty() }?.weather?.first()?.description?.replaceFirstChar { it.uppercase() } ?: "Clear"
            val maxPop = dayItems.mapNotNull { it.pop }.maxOrNull() ?: 0.0

            DailyForecastSummary(
                id = dateKey,
                timestamp = first.dt,
                dayName = dayFormat.format(date),
                dateFormatted = dateFormat.format(date),
                tempMin = minTemp,
                tempMax = maxTemp,
                iconCode = icon,
                conditionText = desc,
                popMax = maxPop
            )
        }.take(5)
    }

    data class CoordinatesResult(
        val lat: Double,
        val lon: Double,
        val cityName: String?,
        val source: LocationSource
    )
}
