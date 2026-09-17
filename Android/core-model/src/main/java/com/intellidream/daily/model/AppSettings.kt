package com.intellidream.daily.model

import kotlinx.serialization.Serializable

@Serializable
enum class AppTheme(val value: String, val displayName: String) {
    System("system", "System"),
    Dark("dark", "Dark"),
    Light("light", "Light")
}

@Serializable
enum class GlassIntensity(val value: String, val displayName: String, val blurOpacity: Float) {
    Subtle("subtle", "Subtle", 0.12f),
    Medium("medium", "Medium", 0.20f),
    Prominent("high", "Prominent", 0.32f)
}

@Serializable
enum class WeatherUnitSystem(val value: String, val displayName: String, val tempSymbol: String) {
    Metric("metric", "Metric (°C, m/s)", "°C"),
    Imperial("imperial", "Imperial (°F, mph)", "°F")
}

@Serializable
enum class DashboardWidgetSize(val value: String, val displayName: String, val columnSpan: Int, val rowSpan: Int) {
    Small("1x1", "Small", 1, 1),
    Wide("2x1", "Wide", 2, 1),
    Tall("1x2", "Tall", 1, 2),
    Large("2x2", "Large", 2, 2)
}

@Serializable
enum class DashboardWidgetType(val id: String, val title: String) {
    Weather("weather", "Weather & Atmosphere"),
    News("news", "News & Briefings"),
    Health("health", "Health & Vitals"),
    Habits("habits", "Habits & Cravings"),
    Finances("finances", "Finances & Markets"),
    TagdosNotes("tagdos_notes", "Tagdos & Notes")
}

@Serializable
data class DashboardWidgetConfig(
    val id: String,
    val size: DashboardWidgetSize = DashboardWidgetSize.Wide,
    val isVisible: Boolean = true
) {
    companion object {
        val defaultLayout: List<DashboardWidgetConfig> = listOf(
            DashboardWidgetConfig(DashboardWidgetType.Weather.id, DashboardWidgetSize.Wide, true),
            DashboardWidgetConfig(DashboardWidgetType.News.id, DashboardWidgetSize.Wide, true),
            DashboardWidgetConfig(DashboardWidgetType.Health.id, DashboardWidgetSize.Wide, true),
            DashboardWidgetConfig(DashboardWidgetType.Habits.id, DashboardWidgetSize.Wide, true),
            DashboardWidgetConfig(DashboardWidgetType.Finances.id, DashboardWidgetSize.Wide, true),
            DashboardWidgetConfig(DashboardWidgetType.TagdosNotes.id, DashboardWidgetSize.Wide, true)
        )
    }
}

@Serializable
data class AppSettings(
    // Appearance & Glass
    val isGuestMode: Boolean = false,
    val theme: AppTheme = AppTheme.Dark,
    val glassIntensity: GlassIntensity = GlassIntensity.Medium,
    val hapticsEnabled: Boolean = true,

    // Weather Preferences
    val weatherAlwaysAutoLocation: Boolean = false,
    val weatherUnitSystem: WeatherUnitSystem = WeatherUnitSystem.Metric,
    val weatherWindUnit: String = "m/s",
    val weatherPressureUnit: String = "hpa",
    val weatherShowSunrise: Boolean = true,
    val weatherShowHumidity: Boolean = true,

    // Health & Vitals
    val healthMockDataEnabled: Boolean = false,
    val healthSleepTargetHours: Double = 8.0,

    // Habits Tracking
    val habitsWaterTargetLiters: Double = 2.0,
    val habitsRemindersEnabled: Boolean = true,

    // News Configuration
    val newsAutoRefreshOnStartup: Boolean = true,
    val newsShowImages: Boolean = true,
    val newsMediumUsername: String? = null,
    val newsMediumReadingListUrl: String? = null,

    // Cloud & Sync
    val cloudSyncEnabled: Boolean = true,
    val lastSyncTimestamp: Long? = null,
    val watchSyncFrequency: Int = 15,

    // Smart Periodic Briefing
    val smartBriefingEnabled: Boolean = true,
    val smartBriefingAutoMorning: Boolean = true,
    val geminiApiKey: String? = null,

    // Dashboard Layout
    val dashboardWidgets: List<DashboardWidgetConfig> = DashboardWidgetConfig.defaultLayout
)
