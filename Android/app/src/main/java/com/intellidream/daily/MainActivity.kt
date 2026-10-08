package com.intellidream.daily

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.WaterDrop
import com.intellidream.daily.presentation.foldable.DailyFoldableCompanionPane
import com.intellidream.daily.presentation.foldable.FoldableDetailHeader
import com.intellidream.daily.presentation.foldable.SmartBriefingFoldablePane
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import com.intellidream.daily.designsystem.FloatingGlassCapsule
import com.intellidream.daily.designsystem.GlassButton
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.NavigationTab
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.AuthSessionState
import com.intellidream.daily.model.DailyForecastSummary
import com.intellidream.daily.model.LocationSource
import com.intellidream.daily.model.ForecastItem
import com.intellidream.daily.model.ForecastResponse
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.model.WeatherResponse
import androidx.compose.ui.platform.LocalConfiguration
import com.intellidream.daily.location.AndroidLocationManager
import com.intellidream.daily.network.WeatherRepository
import com.intellidream.daily.network.WeatherRepository.CoordinatesResult
import com.intellidream.daily.presentation.LoginScreen
import com.intellidream.daily.presentation.SettingsScreen
import com.intellidream.daily.presentation.dashboard.CustomizeDashboardScreen
import com.intellidream.daily.presentation.dashboard.DashboardView
import com.intellidream.daily.presentation.weather.WeatherDetailView
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val authRepository by lazy { DailyApp.instance.authRepository }
    private val settingsRepository by lazy { DailyApp.instance.settingsRepository }
    private val weatherRepository by lazy { DailyApp.instance.weatherRepository }
    private val weatherCacheRepository by lazy { DailyApp.instance.weatherCacheRepository }
    private val habitsRepository by lazy { DailyApp.instance.habitsRepository }
    private val healthRepository by lazy { DailyApp.instance.healthRepository }
    private val smartLedgerRepository by lazy { DailyApp.instance.smartLedgerRepository }
    private val financeDataRepository by lazy { DailyApp.instance.financeDataRepository }
    private val tagdosRepository by lazy { DailyApp.instance.tagdosRepository }
    private val newsRepository by lazy { DailyApp.instance.newsRepository }
    private val smartBriefingRepository by lazy { DailyApp.instance.smartBriefingRepository }

    private var selectedTab by mutableStateOf(NavigationTab.Dashboard)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Wire resilient hardware GPS location provider
        weatherRepository.gpsLocationProvider = {
            if (AndroidLocationManager.hasLocationPermission(this@MainActivity)) {
                val coords = AndroidLocationManager.getCurrentCoordinates(this@MainActivity)
                if (coords != null) {
                    val municipality = AndroidLocationManager.reverseGeocode(this@MainActivity, coords.first, coords.second)
                    CoordinatesResult(
                        lat = coords.first,
                        lon = coords.second,
                        cityName = municipality ?: "Current Location",
                        source = LocationSource.GPS
                    )
                } else null
            } else null
        }

        // Wire cross-module hydration logging to Health Connect
        habitsRepository.onWaterLogged = { amountMl, timestamp ->
            lifecycleScope.launch {
                try {
                    healthRepository.healthConnectManager.writeHydrationRecord(amountMl, timestamp)
                } catch (_: Exception) {}
            }
        }

        handleIntentData(intent)
        processNavigationIntent(intent)

        setContent {
            val authState by authRepository.sessionState.collectAsState()
            val settings by settingsRepository.settings.collectAsState()
            val weather by weatherRepository.currentWeather.collectAsState()
            val forecast by weatherRepository.forecast.collectAsState()
            val hourlyForecasts by weatherRepository.hourlyForecasts.collectAsState()
            val dailySummaries by weatherRepository.dailySummaries.collectAsState()
            val locationName by weatherRepository.currentLocationName.collectAsState()
            val locationSource by weatherRepository.locationSource.collectAsState()
            val isAutoLocation by weatherRepository.isAutoLocation.collectAsState()
            val isWeatherLoading by weatherRepository.isLoading.collectAsState()
            val weatherError by weatherRepository.errorMessage.collectAsState()

            val scope = rememberCoroutineScope()
            var showSettings by remember { mutableStateOf(false) }
            var showCustomize by remember { mutableStateOf(false) }

            LaunchedEffect(settings.isGuestMode, authState) {
                if (settings.isGuestMode && authState is AuthSessionState.Unauthenticated) {
                    authRepository.signInAsGuest()
                }
            }

            // Re-fetch weather when unit system changes
            LaunchedEffect(settings.weatherUnitSystem) {
                weatherRepository.refreshWeather(
                    force = true,
                    unitSystem = settings.weatherUnitSystem,
                    onSuccess = { w, f, city, lat, lon ->
                        scope.launch { weatherCacheRepository.saveCache(w, f, city, lat, lon) }
                    }
                )
            }

            LaunchedEffect(authState.profile, weather) {
                if (authState.isAuthenticatedOrGuest && weather != null) {
                    val firstName = authState.profile?.firstName ?: "Friend"
                    val uid = authState.profile?.id ?: "guest"
                    smartBriefingRepository.checkAutomaticMorningPresentation(
                        settings = settings,
                        userName = firstName,
                        userId = uid,
                        weather = weather,
                        locationName = locationName,
                        healthRepository = healthRepository,
                        habitsRepository = habitsRepository,
                        smartLedgerRepository = smartLedgerRepository,
                        tagdosRepository = tagdosRepository,
                        newsRepository = newsRepository
                    )
                }
            }

            Crossfade(targetState = authState.isAuthenticatedOrGuest, label = "AuthCrossfade") { isAuthenticated ->
                if (!isAuthenticated) {
                    LoginScreen(
                        onGoogleSignInClick = { authRepository.launchGoogleSignIn(this@MainActivity) },
                        onGuestSignInClick = {
                            scope.launch {
                                settingsRepository.updateSettings { it.copy(isGuestMode = true) }
                                authRepository.signInAsGuest()
                            }
                        }
                    )
                } else {
                    val configuration = LocalConfiguration.current
                    val isFoldable = configuration.screenWidthDp >= 600

                    if (isFoldable) {
                        DailyRootScreen(
                            userProfile = authState.profile,
                            settings = settings,
                            weather = weather,
                            forecast = forecast,
                            hourlyForecasts = hourlyForecasts,
                            dailySummaries = dailySummaries,
                            locationName = locationName,
                            locationSource = locationSource,
                            isAutoLocation = isAutoLocation,
                            weatherError = weatherError,
                            isWeatherLoading = isWeatherLoading,
                            habitsRepository = habitsRepository,
                            healthRepository = healthRepository,
                            smartLedgerRepository = smartLedgerRepository,
                            financeDataRepository = financeDataRepository,
                            tagdosRepository = tagdosRepository,
                            newsRepository = newsRepository,
                            smartBriefingRepository = smartBriefingRepository,
                            weatherRepository = weatherRepository,
                            onRefreshWeather = {
                                scope.launch {
                                    weatherRepository.refreshWeather(
                                        force = true,
                                        unitSystem = settings.weatherUnitSystem,
                                        onSuccess = { w, f, city, lat, lon ->
                                            scope.launch { weatherCacheRepository.saveCache(w, f, city, lat, lon) }
                                        }
                                    )
                                }
                            },
                            onSelectManualLocation = { lat, lon, name ->
                                scope.launch {
                                    weatherRepository.setManualLocation(lat, lon, name, settings.weatherUnitSystem) { w, f, city, lLat, lLon ->
                                        scope.launch { weatherCacheRepository.saveCache(w, f, city, lLat, lLon) }
                                    }
                                }
                            },
                            onResetToAutoLocation = {
                                scope.launch {
                                    weatherRepository.resetToAutoLocation(settings.weatherUnitSystem) { w, f, city, lLat, lLon ->
                                        scope.launch { weatherCacheRepository.saveCache(w, f, city, lLat, lLon) }
                                    }
                                }
                            },
                            selectedTab = selectedTab,
                            onSelectTab = { selectedTab = it },
                            showSettings = showSettings,
                            onSetShowSettings = { showSettings = it },
                            showCustomize = showCustomize,
                            onSetShowCustomize = { showCustomize = it },
                            onSignOutClick = {
                                scope.launch {
                                    settingsRepository.updateSettings { it.copy(isGuestMode = false) }
                                    authRepository.signOut()
                                    showSettings = false
                                }
                            },
                            onOpenCustomize = { showCustomize = true },
                            onOpenSettings = { showSettings = true },
                            onUpdateSettings = { transform ->
                                scope.launch { settingsRepository.updateSettings(transform) }
                            }
                        )
                    } else {
                        Crossfade(targetState = if (showCustomize) "customize" else if (showSettings) "settings" else "root", label = "ScreenCrossfade") { screen ->
                            when (screen) {
                                "customize" -> {
                                    BackHandler { showCustomize = false }
                                    CustomizeDashboardScreen(
                                        settings = settings,
                                        onUpdateSettings = { transform: (AppSettings) -> AppSettings ->
                                            scope.launch { settingsRepository.updateSettings(transform) }
                                        },
                                        onBackClick = { showCustomize = false }
                                    )
                                }
                                "settings" -> {
                                    BackHandler { showSettings = false }
                                    SettingsScreen(
                                        settings = settings,
                                        userProfile = authState.profile,
                                        onUpdateSettings = { transform ->
                                            scope.launch { settingsRepository.updateSettings(transform) }
                                        },
                                        onSignOutClick = {
                                            scope.launch {
                                                settingsRepository.updateSettings { it.copy(isGuestMode = false) }
                                                authRepository.signOut()
                                                showSettings = false
                                            }
                                        },
                                        onBackClick = { showSettings = false }
                                    )
                                }
                                else -> {
                                    DailyRootScreen(
                                        userProfile = authState.profile,
                                        settings = settings,
                                        weather = weather,
                                        forecast = forecast,
                                        hourlyForecasts = hourlyForecasts,
                                        dailySummaries = dailySummaries,
                                        locationName = locationName,
                                        locationSource = locationSource,
                                        isAutoLocation = isAutoLocation,
                                        weatherError = weatherError,
                                        isWeatherLoading = isWeatherLoading,
                                        habitsRepository = habitsRepository,
                                        healthRepository = healthRepository,
                                        smartLedgerRepository = smartLedgerRepository,
                                        financeDataRepository = financeDataRepository,
                                        tagdosRepository = tagdosRepository,
                                        newsRepository = newsRepository,
                                        smartBriefingRepository = smartBriefingRepository,
                                        weatherRepository = weatherRepository,
                                        onRefreshWeather = {
                                            scope.launch {
                                                weatherRepository.refreshWeather(
                                                    force = true,
                                                    unitSystem = settings.weatherUnitSystem,
                                                    onSuccess = { w, f, city, lat, lon ->
                                                        scope.launch { weatherCacheRepository.saveCache(w, f, city, lat, lon) }
                                                    }
                                                )
                                            }
                                        },
                                        onSelectManualLocation = { lat, lon, name ->
                                            scope.launch {
                                                weatherRepository.setManualLocation(lat, lon, name, settings.weatherUnitSystem) { w, f, city, lLat, lLon ->
                                                    scope.launch { weatherCacheRepository.saveCache(w, f, city, lLat, lLon) }
                                                }
                                            }
                                        },
                                        onResetToAutoLocation = {
                                            scope.launch {
                                                weatherRepository.resetToAutoLocation(settings.weatherUnitSystem) { w, f, city, lLat, lLon ->
                                                    scope.launch { weatherCacheRepository.saveCache(w, f, city, lLat, lLon) }
                                                }
                                            }
                                        },
                                        selectedTab = selectedTab,
                                        onSelectTab = { selectedTab = it },
                                        onOpenCustomize = { showCustomize = true },
                                        onOpenSettings = { showSettings = true },
                                        onUpdateSettings = { transform ->
                                            scope.launch { settingsRepository.updateSettings(transform) }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        healthRepository.refreshIfStale()
        lifecycleScope.launch {
            com.intellidream.daily.glance.WidgetUpdateHelper.updateAllWidgets(this@MainActivity)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntentData(intent)
        processNavigationIntent(intent)
    }

    private fun processNavigationIntent(intent: Intent?) {
        if (intent == null) return

        intent.getStringExtra(EXTRA_PIN_WIDGET)?.let { widgetType ->
            val appWidgetManager = getSystemService(android.appwidget.AppWidgetManager::class.java)
            if (appWidgetManager?.isRequestPinAppWidgetSupported == true) {
                val receiverClass = when (widgetType.lowercase()) {
                    "smokes" -> com.intellidream.daily.glance.DailySmokesGlanceReceiver::class.java
                    "bubbles" -> com.intellidream.daily.glance.DailyBubblesGlanceReceiver::class.java
                    "sleep" -> com.intellidream.daily.glance.DailySleepGlanceReceiver::class.java
                    "stress" -> com.intellidream.daily.glance.DailyStressGlanceReceiver::class.java
                    "money" -> com.intellidream.daily.glance.DailyMoneyGlanceReceiver::class.java
                    "tagdos" -> com.intellidream.daily.glance.DailyTagdosGlanceReceiver::class.java
                    else -> com.intellidream.daily.glance.DailyCombinedGlanceReceiver::class.java
                }
                val provider = android.content.ComponentName(this, receiverClass)
                appWidgetManager.requestPinAppWidget(provider, null, null)
            }
        }

        // 1. Deep Link URI Handling (e.g. daily://habits/water, daily://health/sleep, daily://health/stress)
        intent.data?.let { uri ->
            if (uri.scheme == "daily") {
                val host = uri.host?.lowercase(java.util.Locale.ROOT) ?: ""
                val path = uri.path?.lowercase(java.util.Locale.ROOT) ?: ""
                when {
                    host.contains("habit") || path.contains("water") || path.contains("bubble") || path.contains("smoke") -> {
                        selectedTab = NavigationTab.Habits
                        if (path.contains("smoke") || host.contains("smoke")) {
                            habitsRepository.switchHabit(com.intellidream.daily.model.HabitType.SMOKES)
                        } else {
                            habitsRepository.switchHabit(com.intellidream.daily.model.HabitType.WATER)
                        }
                    }
                    host.contains("health") || path.contains("sleep") || path.contains("stress") -> {
                        selectedTab = NavigationTab.Health
                        if (path.contains("sleep")) {
                            healthRepository.setActiveSubTab(com.intellidream.daily.model.HealthSubTab.SLEEP)
                        } else if (path.contains("stress")) {
                            healthRepository.setActiveSubTab(com.intellidream.daily.model.HealthSubTab.STRESS)
                        }
                    }
                    host.contains("finance") || host.contains("money") || path.contains("money") -> {
                        selectedTab = NavigationTab.Finances
                    }
                    host.contains("tagdos") || path.contains("tagdos") -> {
                        selectedTab = NavigationTab.Tagdos
                    }
                    host.contains("weather") -> {
                        selectedTab = NavigationTab.Weather
                    }
                    host.contains("news") -> {
                        selectedTab = NavigationTab.News
                    }
                    else -> {
                        selectedTab = NavigationTab.Dashboard
                    }
                }
            }
        }

        // 2. Extra Keys Handling
        val tabKey = intent.getStringExtra(EXTRA_TARGET_TAB)
        if (tabKey != null) {
            val target = when (tabKey) {
                TAB_HEALTH -> NavigationTab.Health
                TAB_HABITS -> NavigationTab.Habits
                TAB_FINANCES -> NavigationTab.Finances
                TAB_TAGDOS -> NavigationTab.Tagdos
                TAB_WEATHER -> NavigationTab.Weather
                TAB_NEWS -> NavigationTab.News
                else -> NavigationTab.Dashboard
            }
            selectedTab = target

            intent.getStringExtra(EXTRA_HEALTH_SUBTAB)?.let { sub ->
                when (sub) {
                    "stress" -> healthRepository.setActiveSubTab(com.intellidream.daily.model.HealthSubTab.STRESS)
                    "sleep" -> healthRepository.setActiveSubTab(com.intellidream.daily.model.HealthSubTab.SLEEP)
                    "vitals" -> healthRepository.setActiveSubTab(com.intellidream.daily.model.HealthSubTab.VITALS)
                    "trends" -> healthRepository.setActiveSubTab(com.intellidream.daily.model.HealthSubTab.TRENDS)
                    else -> healthRepository.setActiveSubTab(com.intellidream.daily.model.HealthSubTab.OVERVIEW)
                }
            }

            intent.getStringExtra(EXTRA_HABIT_SUBTAB)?.let { sub ->
                when (sub) {
                    "smokes" -> habitsRepository.switchHabit(com.intellidream.daily.model.HabitType.SMOKES)
                    else -> habitsRepository.switchHabit(com.intellidream.daily.model.HabitType.WATER)
                }
            }
        }
    }

    private fun handleIntentData(intent: Intent?) {
        if (intent == null) return
        authRepository.handleIntent(intent)
        intent.data?.let { uri ->
            if (uri.scheme == "com.intellidream.daily" && uri.host == "login-callback") {
                lifecycleScope.launch {
                    authRepository.handleAuthCallback(uri)
                }
            }
        }
    }

    companion object {
        const val EXTRA_TARGET_TAB = "extra_target_tab"
        const val EXTRA_HEALTH_SUBTAB = "extra_health_subtab"
        const val EXTRA_HABIT_SUBTAB = "extra_habit_subtab"
        const val EXTRA_PIN_WIDGET = "extra_pin_widget"

        const val TAB_DASHBOARD = "dashboard"
        const val TAB_HEALTH = "health"
        const val TAB_HABITS = "habits"
        const val TAB_FINANCES = "finances"
        const val TAB_TAGDOS = "tagdos"
        const val TAB_WEATHER = "weather"
        const val TAB_NEWS = "news"
    }
}

@Composable
fun DailyRootScreen(
    userProfile: UserProfile?,
    settings: AppSettings,
    weather: WeatherResponse?,
    forecast: ForecastResponse?,
    hourlyForecasts: List<ForecastItem>,
    dailySummaries: List<DailyForecastSummary>,
    locationName: String,
    locationSource: LocationSource,
    isAutoLocation: Boolean,
    weatherError: String?,
    isWeatherLoading: Boolean,
    habitsRepository: com.intellidream.daily.database.HabitsRepository,
    healthRepository: com.intellidream.daily.health.HealthDataRepository,
    smartLedgerRepository: com.intellidream.daily.database.SmartLedgerRepository,
    financeDataRepository: com.intellidream.daily.database.FinanceDataRepository,
    tagdosRepository: com.intellidream.daily.database.TagdosRepository,
    newsRepository: com.intellidream.daily.database.NewsRepository,
    smartBriefingRepository: com.intellidream.daily.briefing.SmartBriefingRepository,
    weatherRepository: WeatherRepository,
    onRefreshWeather: () -> Unit,
    onSelectManualLocation: (Double, Double, String) -> Unit,
    onResetToAutoLocation: () -> Unit,
    selectedTab: NavigationTab = NavigationTab.Dashboard,
    onSelectTab: (NavigationTab) -> Unit = {},
    showSettings: Boolean = false,
    onSetShowSettings: ((Boolean) -> Unit)? = null,
    showCustomize: Boolean = false,
    onSetShowCustomize: ((Boolean) -> Unit)? = null,
    onSignOutClick: (() -> Unit)? = null,
    onOpenCustomize: () -> Unit,
    onOpenSettings: () -> Unit,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit = {}
) {
    val configuration = LocalConfiguration.current
    val isFoldable = configuration.screenWidthDp >= 600

    var showFoldableBriefing by remember { mutableStateOf(false) }

    // Intercept back gestures: on foldable, collapse the right pane back to Companion/Dashboard
    BackHandler(enabled = isFoldable && (selectedTab != NavigationTab.Dashboard || showSettings || showCustomize || showFoldableBriefing)) {
        if (showCustomize) onSetShowCustomize?.invoke(false)
        else if (showSettings) onSetShowSettings?.invoke(false)
        else if (showFoldableBriefing) showFoldableBriefing = false
        else onSelectTab(NavigationTab.Dashboard)
    }

    // On standard phone mode, back returns to Dashboard
    BackHandler(enabled = !isFoldable && selectedTab != NavigationTab.Dashboard) {
        onSelectTab(NavigationTab.Dashboard)
    }

    LaunchedEffect(userProfile) {
        val uid = userProfile?.id ?: "guest"
        newsRepository.currentUserId = uid
        habitsRepository.currentUserId = uid
        healthRepository.currentUserId = uid
        if (uid.isNotEmpty() && uid != "guest") {
            habitsRepository.syncLogs(uid)
            newsRepository.syncWithSupabase(uid)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(brush = ThemeColors.backgroundGradient)
    ) {
        if (isFoldable) {
            // =========================================================================
            // ADAPTIVE DUAL-PANE FOLDABLE / TABLET ARCHITECTURE (Galaxy Z Fold 8 & Foldables)
            // =========================================================================
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding(),
                verticalAlignment = Alignment.Top
            ) {
                // --- 1. Master Pane (Left): Dashboard & Anchored Capsule ---
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .padding(start = 16.dp, end = 12.dp, top = 4.dp)
                ) {
                    DashboardView(
                        userProfile = userProfile,
                        settings = settings,
                        weather = weather,
                        forecast = forecast,
                        hourlyForecasts = hourlyForecasts,
                        locationName = locationName,
                        isWeatherLoading = isWeatherLoading,
                        habitsRepository = habitsRepository,
                        healthRepository = healthRepository,
                        smartLedgerRepository = smartLedgerRepository,
                        financeDataRepository = financeDataRepository,
                        tagdosRepository = tagdosRepository,
                        newsRepository = newsRepository,
                        smartBriefingRepository = smartBriefingRepository,
                        onRefreshWeather = onRefreshWeather,
                        onOpenCustomize = {
                            showFoldableBriefing = false
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(true)
                        },
                        onOpenSettings = {
                            showFoldableBriefing = false
                            onSetShowCustomize?.invoke(false)
                            onSetShowSettings?.invoke(true)
                        },
                        onUpdateSettings = onUpdateSettings,
                        onNavigateToHabits = {
                            showFoldableBriefing = false
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(false)
                            onSelectTab(NavigationTab.Habits)
                        },
                        onNavigateToHealth = {
                            showFoldableBriefing = false
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(false)
                            onSelectTab(NavigationTab.Health)
                        },
                        onNavigateToFinances = {
                            showFoldableBriefing = false
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(false)
                            onSelectTab(NavigationTab.Finances)
                        },
                        onNavigateToTagdos = {
                            showFoldableBriefing = false
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(false)
                            onSelectTab(NavigationTab.Tagdos)
                        },
                        onNavigateToNews = {
                            showFoldableBriefing = false
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(false)
                            onSelectTab(NavigationTab.News)
                        },
                        onNavigateToWeather = {
                            showFoldableBriefing = false
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(false)
                            onSelectTab(NavigationTab.Weather)
                        },
                        forceSingleColumn = true,
                        onBriefingClick = {
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(false)
                            showFoldableBriefing = true
                        },
                        modifier = Modifier.fillMaxSize()
                    )

                    // Option A: Floating Glass Capsule anchored at bottom of Master pane
                    FloatingGlassCapsule(
                        selectedTab = selectedTab,
                        onTabSelected = { tab ->
                            showFoldableBriefing = false
                            onSetShowSettings?.invoke(false)
                            onSetShowCustomize?.invoke(false)
                            onSelectTab(tab)
                        },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .navigationBarsPadding()
                            .padding(bottom = 16.dp)
                    )
                }

                // --- 2. Subtle Crease / Hinge Divider ---
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .width(1.dp)
                        .background(Color.White.copy(alpha = 0.08f))
                )

                // --- 3. Detail Pane (Right): Companion or Hub or Settings or Briefing ---
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .padding(start = 12.dp, end = 16.dp, top = 4.dp)
                ) {
                    when {
                        showCustomize -> {
                            Column(modifier = Modifier.fillMaxSize()) {
                                FoldableDetailHeader(
                                    title = "Customize Dashboard",
                                    icon = Icons.Rounded.Tune,
                                    iconTint = ThemeColors.accentPurple,
                                    subtitle = "Reorder & Toggle Widgets",
                                    onCloseClick = { onSetShowCustomize?.invoke(false) }
                                )
                                CustomizeDashboardScreen(
                                    settings = settings,
                                    onUpdateSettings = onUpdateSettings,
                                    onBackClick = { onSetShowCustomize?.invoke(false) }
                                )
                            }
                        }
                        showSettings -> {
                            Column(modifier = Modifier.fillMaxSize()) {
                                FoldableDetailHeader(
                                    title = "Settings & Profile",
                                    icon = Icons.Rounded.Settings,
                                    iconTint = ThemeColors.accentBlue,
                                    subtitle = userProfile?.email ?: "Account & Preferences",
                                    onCloseClick = { onSetShowSettings?.invoke(false) }
                                )
                                SettingsScreen(
                                    settings = settings,
                                    userProfile = userProfile,
                                    onUpdateSettings = onUpdateSettings,
                                    onSignOutClick = { onSignOutClick?.invoke() },
                                    onBackClick = { onSetShowSettings?.invoke(false) }
                                )
                            }
                        }
                        showFoldableBriefing -> {
                            SmartBriefingFoldablePane(
                                repository = smartBriefingRepository,
                                userProfile = userProfile,
                                settings = settings,
                                weather = weather,
                                locationName = locationName,
                                healthRepository = healthRepository,
                                habitsRepository = habitsRepository,
                                smartLedgerRepository = smartLedgerRepository,
                                tagdosRepository = tagdosRepository,
                                newsRepository = newsRepository,
                                onDismiss = { showFoldableBriefing = false },
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                        selectedTab == NavigationTab.Dashboard -> {
                            // Option B: Persistent Companion View
                            DailyFoldableCompanionPane(
                                userProfile = userProfile,
                                settings = settings,
                                weather = weather,
                                healthRepository = healthRepository,
                                habitsRepository = habitsRepository,
                                smartLedgerRepository = smartLedgerRepository,
                                financeDataRepository = financeDataRepository,
                                tagdosRepository = tagdosRepository,
                                newsRepository = newsRepository,
                                smartBriefingRepository = smartBriefingRepository,
                                onOpenHub = { tab ->
                                    showFoldableBriefing = false
                                    onSetShowSettings?.invoke(false)
                                    onSetShowCustomize?.invoke(false)
                                    onSelectTab(tab)
                                },
                                onOpenBriefing = {
                                    onSetShowSettings?.invoke(false)
                                    onSetShowCustomize?.invoke(false)
                                    showFoldableBriefing = true
                                },
                                onOpenNewsArticle = { _ ->
                                    onSelectTab(NavigationTab.News)
                                }
                            )
                        }
                        selectedTab == NavigationTab.Health -> {
                            Column(modifier = Modifier.fillMaxSize()) {
                                FoldableDetailHeader(
                                    title = "Health Studio",
                                    icon = Icons.Rounded.Favorite,
                                    iconTint = ThemeColors.accentPink,
                                    subtitle = "Biometrics & Sleep",
                                    onCloseClick = { onSelectTab(NavigationTab.Dashboard) }
                                )
                                com.intellidream.daily.presentation.health.HealthMainView(
                                    repository = healthRepository,
                                    onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                                )
                            }
                        }
                        selectedTab == NavigationTab.Habits -> {
                            Column(modifier = Modifier.fillMaxSize()) {
                                FoldableDetailHeader(
                                    title = "Habits & Routines",
                                    icon = Icons.Rounded.WaterDrop,
                                    iconTint = ThemeColors.accentCyan,
                                    subtitle = "Hydration & Smoke Quitting",
                                    onCloseClick = { onSelectTab(NavigationTab.Dashboard) }
                                )
                                com.intellidream.daily.presentation.habits.HabitsMainView(
                                    repository = habitsRepository,
                                    onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                                )
                            }
                        }
                        selectedTab == NavigationTab.Finances -> {
                            Column(modifier = Modifier.fillMaxSize()) {
                                FoldableDetailHeader(
                                    title = "Smart Ledger",
                                    icon = Icons.Rounded.AccountBalanceWallet,
                                    iconTint = ThemeColors.accentGreen,
                                    subtitle = "Personal Finances & Wealth",
                                    onCloseClick = { onSelectTab(NavigationTab.Dashboard) }
                                )
                                com.intellidream.daily.presentation.finances.FinancesMainView(
                                    smartLedgerRepository = smartLedgerRepository,
                                    financeDataRepository = financeDataRepository,
                                    onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                                )
                            }
                        }
                        selectedTab == NavigationTab.Tagdos -> {
                            Column(modifier = Modifier.fillMaxSize()) {
                                FoldableDetailHeader(
                                    title = "Tagdos & Notes",
                                    icon = Icons.Rounded.Checklist,
                                    iconTint = ThemeColors.accentYellow,
                                    subtitle = "Mental Stream & Quick Notes",
                                    onCloseClick = { onSelectTab(NavigationTab.Dashboard) }
                                )
                                com.intellidream.daily.presentation.tagdos.TagdosNotesHubView(
                                    repository = tagdosRepository,
                                    onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                                )
                            }
                        }
                        selectedTab == NavigationTab.News -> {
                            Column(modifier = Modifier.fillMaxSize()) {
                                FoldableDetailHeader(
                                    title = "Curated News",
                                    icon = Icons.Rounded.Newspaper,
                                    iconTint = ThemeColors.accentBlue,
                                    subtitle = "Feeds & Deep Read",
                                    onCloseClick = { onSelectTab(NavigationTab.Dashboard) }
                                )
                                com.intellidream.daily.presentation.news.NewsFeedView(
                                    repository = newsRepository,
                                    settings = settings,
                                    onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                                )
                            }
                        }
                        selectedTab == NavigationTab.Weather -> {
                            Column(modifier = Modifier.fillMaxSize()) {
                                FoldableDetailHeader(
                                    title = "Weather Radar",
                                    icon = Icons.Rounded.Cloud,
                                    iconTint = ThemeColors.accentYellow,
                                    subtitle = locationName,
                                    onCloseClick = { onSelectTab(NavigationTab.Dashboard) }
                                )
                                WeatherDetailView(
                                    weather = weather,
                                    hourlyForecasts = hourlyForecasts,
                                    dailySummaries = dailySummaries,
                                    locationName = locationName,
                                    locationSource = locationSource,
                                    isAutoLocation = isAutoLocation,
                                    isLoading = isWeatherLoading,
                                    errorMessage = weatherError,
                                    settings = settings,
                                    weatherRepository = weatherRepository,
                                    onNavigateBack = { onSelectTab(NavigationTab.Dashboard) },
                                    onRefreshWeather = onRefreshWeather,
                                    onSelectManualLocation = onSelectManualLocation,
                                    onResetToAutoLocation = onResetToAutoLocation
                                )
                            }
                        }
                    }
                }
            }
        } else {
            // =========================================================================
            // STANDARD COMPACT PHONE ARCHITECTURE (< 600dp, e.g. Pixel 9 Pro or Folded Cover Screen)
            // =========================================================================
            val maxContentWidth = 760.dp
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding(),
                contentAlignment = Alignment.TopCenter
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .widthIn(max = maxContentWidth)
                ) {
                    when (selectedTab) {
                        NavigationTab.Dashboard -> {
                            DashboardView(
                                userProfile = userProfile,
                                settings = settings,
                                weather = weather,
                                forecast = forecast,
                                hourlyForecasts = hourlyForecasts,
                                locationName = locationName,
                                isWeatherLoading = isWeatherLoading,
                                habitsRepository = habitsRepository,
                                healthRepository = healthRepository,
                                smartLedgerRepository = smartLedgerRepository,
                                financeDataRepository = financeDataRepository,
                                tagdosRepository = tagdosRepository,
                                newsRepository = newsRepository,
                                smartBriefingRepository = smartBriefingRepository,
                                onRefreshWeather = onRefreshWeather,
                                onOpenCustomize = onOpenCustomize,
                                onOpenSettings = onOpenSettings,
                                onUpdateSettings = onUpdateSettings,
                                onNavigateToHabits = { onSelectTab(NavigationTab.Habits) },
                                onNavigateToHealth = { onSelectTab(NavigationTab.Health) },
                                onNavigateToFinances = { onSelectTab(NavigationTab.Finances) },
                                onNavigateToTagdos = { onSelectTab(NavigationTab.Tagdos) },
                                onNavigateToNews = { onSelectTab(NavigationTab.News) },
                                onNavigateToWeather = { onSelectTab(NavigationTab.Weather) },
                                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                            )
                        }
                        NavigationTab.Weather -> {
                            WeatherDetailView(
                                weather = weather,
                                hourlyForecasts = hourlyForecasts,
                                dailySummaries = dailySummaries,
                                locationName = locationName,
                                locationSource = locationSource,
                                isAutoLocation = isAutoLocation,
                                isLoading = isWeatherLoading,
                                errorMessage = weatherError,
                                settings = settings,
                                weatherRepository = weatherRepository,
                                onNavigateBack = { onSelectTab(NavigationTab.Dashboard) },
                                onRefreshWeather = onRefreshWeather,
                                onSelectManualLocation = onSelectManualLocation,
                                onResetToAutoLocation = onResetToAutoLocation
                            )
                        }
                        NavigationTab.Finances -> {
                            com.intellidream.daily.presentation.finances.FinancesMainView(
                                smartLedgerRepository = smartLedgerRepository,
                                financeDataRepository = financeDataRepository,
                                onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                            )
                        }
                        NavigationTab.Habits -> {
                            com.intellidream.daily.presentation.habits.HabitsMainView(
                                repository = habitsRepository,
                                onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                            )
                        }
                        NavigationTab.Health -> {
                            com.intellidream.daily.presentation.health.HealthMainView(
                                repository = healthRepository,
                                onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                            )
                        }
                        NavigationTab.Tagdos -> {
                            com.intellidream.daily.presentation.tagdos.TagdosNotesHubView(
                                repository = tagdosRepository,
                                onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                            )
                        }
                        NavigationTab.News -> {
                            com.intellidream.daily.presentation.news.NewsFeedView(
                                repository = newsRepository,
                                settings = settings,
                                onNavigateBack = { onSelectTab(NavigationTab.Dashboard) }
                            )
                        }
                        else -> {
                            Column(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(horizontal = 20.dp, vertical = 8.dp),
                                verticalArrangement = Arrangement.Top,
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = selectedTab.displayName,
                                        color = Color.White,
                                        fontSize = 24.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                    GlassButton(
                                        onClick = onOpenSettings,
                                        cornerRadius = 12.dp,
                                        paddingHorizontal = 10.dp,
                                        paddingVertical = 10.dp
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.Settings,
                                            contentDescription = "Settings",
                                            tint = Color.White,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    }
                                }

                                Spacer(modifier = Modifier.height(24.dp))

                                GlassCard(
                                    modifier = Modifier.fillMaxWidth(),
                                    cornerRadius = 20.dp,
                                    padding = 24.dp,
                                    intensity = GlassIntensity.Medium
                                ) {
                                    Column {
                                        Text(
                                            text = "${selectedTab.displayName} Hub",
                                            color = ThemeColors.accentBlue,
                                            fontSize = 18.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                        Spacer(modifier = Modifier.height(8.dp))
                                        Text(
                                            text = "Full parity feature for ${selectedTab.displayName} is scheduled in upcoming phases with Room offline cache and Supabase realtime synchronization.",
                                            color = ThemeColors.textSecondary,
                                            fontSize = 14.sp,
                                            lineHeight = 20.sp
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Floating Glass Capsule Navigation at the bottom (Centered on phone mode)
            FloatingGlassCapsule(
                selectedTab = selectedTab,
                onTabSelected = onSelectTab,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(bottom = 16.dp)
            )
        }
    }
}
