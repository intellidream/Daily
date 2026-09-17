package com.intellidream.daily.database

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.intellidream.daily.model.ForecastResponse
import com.intellidream.daily.model.WeatherResponse
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

private val Context.weatherDataStore: DataStore<Preferences> by preferencesDataStore(name = "daily_weather_cache")

data class CachedWeatherData(
    val weather: WeatherResponse?,
    val forecast: ForecastResponse?,
    val cityName: String?,
    val timestamp: Long,
    val lat: Double?,
    val lon: Double?
)

class WeatherCacheRepository(private val context: Context) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    private object Keys {
        val WEATHER_JSON = stringPreferencesKey("cached_weather_json")
        val FORECAST_JSON = stringPreferencesKey("cached_forecast_json")
        val CITY_NAME = stringPreferencesKey("cached_city_name")
        val TIMESTAMP = longPreferencesKey("cached_timestamp")
        val LAT = doublePreferencesKey("cached_lat")
        val LON = doublePreferencesKey("cached_lon")
    }

    val cachedWeather: Flow<CachedWeatherData> = context.weatherDataStore.data.map { prefs ->
        val weatherJson = prefs[Keys.WEATHER_JSON]
        val forecastJson = prefs[Keys.FORECAST_JSON]
        val cityName = prefs[Keys.CITY_NAME]
        val timestamp = prefs[Keys.TIMESTAMP] ?: 0L
        val lat = prefs[Keys.LAT]
        val lon = prefs[Keys.LON]

        val weather = weatherJson?.let {
            try {
                json.decodeFromString<WeatherResponse>(it)
            } catch (e: Exception) {
                null
            }
        }

        val forecast = forecastJson?.let {
            try {
                json.decodeFromString<ForecastResponse>(it)
            } catch (e: Exception) {
                null
            }
        }

        CachedWeatherData(
            weather = weather,
            forecast = forecast,
            cityName = cityName,
            timestamp = timestamp,
            lat = lat,
            lon = lon
        )
    }

    suspend fun saveCache(
        weather: WeatherResponse,
        forecast: ForecastResponse,
        cityName: String,
        lat: Double,
        lon: Double
    ) {
        context.weatherDataStore.edit { prefs ->
            try {
                prefs[Keys.WEATHER_JSON] = json.encodeToString(WeatherResponse.serializer(), weather)
                prefs[Keys.FORECAST_JSON] = json.encodeToString(ForecastResponse.serializer(), forecast)
                prefs[Keys.CITY_NAME] = cityName
                prefs[Keys.TIMESTAMP] = System.currentTimeMillis()
                prefs[Keys.LAT] = lat
                prefs[Keys.LON] = lon
            } catch (e: Exception) {
                // Log or ignore encoding failures
            }
        }
    }
}
