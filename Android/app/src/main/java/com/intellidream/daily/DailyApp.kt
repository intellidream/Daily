package com.intellidream.daily

import android.app.Application
import com.intellidream.daily.database.SettingsRepository
import com.intellidream.daily.database.WeatherCacheRepository
import com.intellidream.daily.network.AuthRepository
import com.intellidream.daily.network.WeatherRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

class DailyApp : Application() {
    lateinit var settingsRepository: SettingsRepository
        private set
    lateinit var authRepository: AuthRepository
        private set
    lateinit var weatherCacheRepository: WeatherCacheRepository
        private set
    lateinit var weatherRepository: WeatherRepository
        private set

    private val appScope = CoroutineScope(Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        instance = this
        settingsRepository = SettingsRepository(this)
        authRepository = AuthRepository()
        weatherCacheRepository = WeatherCacheRepository(this)
        weatherRepository = WeatherRepository()

        // Bootstrap cached weather & refresh
        appScope.launch {
            val cached = weatherCacheRepository.cachedWeather.firstOrNull()
            if (cached != null) {
                weatherRepository.initializeWithCache(
                    cachedWeather = cached.weather,
                    cachedForecast = cached.forecast,
                    cityName = cached.cityName,
                    timestamp = cached.timestamp,
                    lat = cached.lat,
                    lon = cached.lon
                )
            }

            val currentSettings = settingsRepository.settings.firstOrNull()
            weatherRepository.refreshWeather(
                force = false,
                unitSystem = currentSettings?.weatherUnitSystem ?: com.intellidream.daily.model.WeatherUnitSystem.Metric,
                onSuccess = { w, f, city, lat, lon ->
                    appScope.launch {
                        weatherCacheRepository.saveCache(w, f, city, lat, lon)
                    }
                }
            )
        }
    }

    companion object {
        lateinit var instance: DailyApp
            private set
    }
}
