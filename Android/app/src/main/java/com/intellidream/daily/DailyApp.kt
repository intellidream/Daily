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
    lateinit var dailyDatabase: com.intellidream.daily.database.DailyDatabase
        private set
    lateinit var habitsRepository: com.intellidream.daily.database.HabitsRepository
        private set
    lateinit var habitRemoteService: com.intellidream.daily.network.HabitRemoteService
        private set
    lateinit var healthRepository: com.intellidream.daily.health.HealthDataRepository
        private set
    lateinit var smartLedgerRepository: com.intellidream.daily.database.SmartLedgerRepository
        private set
    lateinit var financeDataRepository: com.intellidream.daily.database.FinanceDataRepository
        private set
    lateinit var financeRemoteService: com.intellidream.daily.network.FinanceRemoteService
        private set
    lateinit var tagdosRepository: com.intellidream.daily.database.TagdosRepository
        private set
    lateinit var newsRemoteService: com.intellidream.daily.network.NewsRemoteService
        private set
    lateinit var newsRepository: com.intellidream.daily.database.NewsRepository
        private set
    lateinit var smartBriefingRepository: com.intellidream.daily.briefing.SmartBriefingRepository
        private set

    private val appScope = CoroutineScope(Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        instance = this
        com.intellidream.daily.network.SupabaseClientManager.initialize(this)
        settingsRepository = SettingsRepository(this)
        authRepository = AuthRepository(context = this)
        weatherCacheRepository = WeatherCacheRepository(this)
        weatherRepository = WeatherRepository()
        dailyDatabase = com.intellidream.daily.database.DailyDatabase.getDatabase(this)
        habitsRepository = com.intellidream.daily.database.HabitsRepository(dailyDatabase.habitLogDao())
        habitRemoteService = com.intellidream.daily.network.HabitRemoteService()
        healthRepository = com.intellidream.daily.health.HealthDataRepository(
            context = this,
            telemetryDao = dailyDatabase.healthTelemetryDao(),
            vitalsDao = dailyDatabase.vitalMetricDao()
        )
        smartLedgerRepository = com.intellidream.daily.database.SmartLedgerRepository(dailyDatabase.smartLedgerDao())
        financeDataRepository = com.intellidream.daily.database.FinanceDataRepository()
        financeRemoteService = com.intellidream.daily.network.FinanceRemoteService()
        tagdosRepository = com.intellidream.daily.database.TagdosRepository(dailyDatabase.tagdosDao())
        newsRemoteService = com.intellidream.daily.network.NewsRemoteService()
        newsRepository = com.intellidream.daily.database.NewsRepository(dailyDatabase.newsDao())
        smartBriefingRepository = com.intellidream.daily.briefing.SmartBriefingRepository(this)

        habitsRepository.syncHandler = object : com.intellidream.daily.database.HabitSyncHandler {
            override suspend fun pushLog(log: com.intellidream.daily.model.HabitLogRecord): Boolean {
                return habitRemoteService.pushLog(log)
            }
            override suspend fun pullLogsForDate(userId: String, startIso: String, endIso: String): List<com.intellidream.daily.model.HabitLogRecord> {
                return habitRemoteService.pullLogsForDate(userId, startIso, endIso)
            }
            override suspend fun pullUserPreferences(userId: String): com.intellidream.daily.model.UserPreferencesRecord? {
                return habitRemoteService.pullUserPreferences(userId)
            }
            override suspend fun pullGoals(userId: String): List<com.intellidream.daily.model.HabitGoalRecord> {
                return habitRemoteService.pullGoals(userId)
            }
            override suspend fun deleteLog(logId: String): Boolean {
                return habitRemoteService.deleteLog(logId)
            }
        }

        newsRepository.syncHandler = object : com.intellidream.daily.database.NewsSyncHandler {
            override suspend fun fetchUrl(url: String): String? = newsRemoteService.fetchUrl(url)
            override suspend fun searchFeedly(query: String): List<com.intellidream.daily.model.FeedSearchResult> = newsRemoteService.searchFeedly(query)
            override suspend fun pullSubscriptions(userId: String): List<com.intellidream.daily.model.RssSubscription> = newsRemoteService.pullSubscriptions(userId)
            override suspend fun pushSubscription(subscription: com.intellidream.daily.model.RssSubscription): Boolean = newsRemoteService.pushSubscription(subscription)
            override suspend fun pullSavedArticles(userId: String): List<com.intellidream.daily.model.SavedArticle> = newsRemoteService.pullSavedArticles(userId)
            override suspend fun pushSavedArticle(article: com.intellidream.daily.model.SavedArticle): Boolean = newsRemoteService.pushSavedArticle(article)
        }

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
            if (currentSettings != null) {
                habitsRepository.setWaterGoal(currentSettings.habitsWaterTargetLiters * 1000.0)
            }
            val state = authRepository.sessionState.firstOrNull()
            val uid = (state as? com.intellidream.daily.model.AuthSessionState.Authenticated)?.profile?.id
            if (!uid.isNullOrEmpty() && uid != "guest") {
                habitsRepository.currentUserId = uid
                habitsRepository.syncLogs(uid)
                newsRepository.currentUserId = uid
                newsRepository.syncWithSupabase(uid)
            }
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
