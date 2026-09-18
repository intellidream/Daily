package com.intellidream.daily

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Settings
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
import com.intellidream.daily.network.WeatherRepository
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        handleIntentData(intent)

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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntentData(intent)
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
    onOpenCustomize: () -> Unit,
    onOpenSettings: () -> Unit,
    onUpdateSettings: ((AppSettings) -> AppSettings) -> Unit = {}
) {
    var selectedTab by remember { mutableStateOf(NavigationTab.Dashboard) }

    BackHandler(enabled = selectedTab != NavigationTab.Dashboard) {
        selectedTab = NavigationTab.Dashboard
    }

    LaunchedEffect(userProfile) {
        val uid = userProfile?.id ?: "guest"
        if (newsRepository.currentUserId != uid) {
            newsRepository.currentUserId = uid
        }
        if (habitsRepository.currentUserId != uid) {
            habitsRepository.currentUserId = uid
        }
        if (healthRepository.currentUserId != uid) {
            healthRepository.currentUserId = uid
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(brush = ThemeColors.backgroundGradient)
    ) {
        // Main Tab Content
        Box(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
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
                        onNavigateToHabits = { selectedTab = NavigationTab.Habits },
                        onNavigateToHealth = { selectedTab = NavigationTab.Health },
                        onNavigateToFinances = { selectedTab = NavigationTab.Finances },
                        onNavigateToTagdos = { selectedTab = NavigationTab.Tagdos },
                        onNavigateToNews = { selectedTab = NavigationTab.News },
                        onNavigateToWeather = { selectedTab = NavigationTab.Weather },
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
                        onNavigateBack = { selectedTab = NavigationTab.Dashboard },
                        onRefreshWeather = onRefreshWeather,
                        onSelectManualLocation = onSelectManualLocation,
                        onResetToAutoLocation = onResetToAutoLocation
                    )
                }
                NavigationTab.Finances -> {
                    com.intellidream.daily.presentation.finances.FinancesMainView(
                        smartLedgerRepository = smartLedgerRepository,
                        financeDataRepository = financeDataRepository,
                        onNavigateBack = { selectedTab = NavigationTab.Dashboard }
                    )
                }
                NavigationTab.Habits -> {
                    com.intellidream.daily.presentation.habits.HabitsMainView(
                        repository = habitsRepository,
                        onNavigateBack = { selectedTab = NavigationTab.Dashboard }
                    )
                }
                NavigationTab.Health -> {
                    com.intellidream.daily.presentation.health.HealthMainView(
                        repository = healthRepository,
                        onNavigateBack = { selectedTab = NavigationTab.Dashboard }
                    )
                }
                NavigationTab.Tagdos -> {
                    com.intellidream.daily.presentation.tagdos.TagdosNotesHubView(
                        repository = tagdosRepository,
                        onNavigateBack = { selectedTab = NavigationTab.Dashboard }
                    )
                }
                NavigationTab.News -> {
                    com.intellidream.daily.presentation.news.NewsFeedView(
                        repository = newsRepository,
                        settings = settings,
                        onNavigateBack = { selectedTab = NavigationTab.Dashboard }
                    )
                }
                else -> {
                    // Secondary Tab placeholder screen
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

        // Floating Glass Capsule Navigation at the bottom
        FloatingGlassCapsule(
            selectedTab = selectedTab,
            onTabSelected = { selectedTab = it },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 16.dp)
        )
    }
}
