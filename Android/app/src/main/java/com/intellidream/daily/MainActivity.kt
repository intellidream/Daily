package com.intellidream.daily

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
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
import androidx.compose.material.icons.filled.Settings
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
import com.intellidream.daily.model.UserProfile
import com.intellidream.daily.presentation.LoginScreen
import com.intellidream.daily.presentation.SettingsScreen
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val authRepository by lazy { DailyApp.instance.authRepository }
    private val settingsRepository by lazy { DailyApp.instance.settingsRepository }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        handleIntentData(intent)

        setContent {
            val authState by authRepository.sessionState.collectAsState()
            val settings by settingsRepository.settings.collectAsState()
            val scope = rememberCoroutineScope()
            var showSettings by remember { mutableStateOf(false) }

            LaunchedEffect(settings.isGuestMode, authState) {
                if (settings.isGuestMode && authState is AuthSessionState.Unauthenticated) {
                    authRepository.signInAsGuest()
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
                    Crossfade(targetState = showSettings, label = "SettingsCrossfade") { inSettings ->
                        if (inSettings) {
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
                        } else {
                            DailyRootScreen(
                                userProfile = authState.profile,
                                settings = settings,
                                onOpenSettings = { showSettings = true }
                            )
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
        intent?.data?.let { uri ->
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
    onOpenSettings: () -> Unit
) {
    var selectedTab by remember { mutableStateOf(NavigationTab.Dashboard) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(brush = ThemeColors.backgroundGradient)
    ) {
        // Main content
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.Top,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header with User Greeting and Settings Button
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Welcome, ${userProfile?.firstName ?: "Friend"}",
                        color = ThemeColors.textSecondary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "Your Life, Synchronized",
                        color = Color.White,
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                GlassButton(
                    onClick = onOpenSettings,
                    cornerRadius = 12.dp,
                    paddingHorizontal = 10.dp,
                    paddingVertical = 10.dp
                ) {
                    Icon(
                        imageVector = Icons.Filled.Settings,
                        contentDescription = "Settings",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Hero Glass Card
            GlassCard(
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 20.dp,
                padding = 20.dp,
                intensity = when (settings.glassIntensity) {
                    com.intellidream.daily.model.GlassIntensity.Subtle -> GlassIntensity.Subtle
                    com.intellidream.daily.model.GlassIntensity.Medium -> GlassIntensity.Medium
                    com.intellidream.daily.model.GlassIntensity.Prominent -> GlassIntensity.Prominent
                }
            ) {
                Column {
                    Text(
                        text = "DayOne Android",
                        color = Color.White,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = "Tactile Liquid Glass design system with 120Hz smooth scrolling, offline-first Room cache, and Supabase cloud sync.",
                        color = ThemeColors.textSecondary,
                        fontSize = 14.sp,
                        lineHeight = 20.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Active Tab card
            GlassCard(
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 16.dp,
                padding = 16.dp,
                intensity = GlassIntensity.Subtle
            ) {
                Column {
                    Text(
                        text = "Active Tab: ${selectedTab.displayName}",
                        color = ThemeColors.accentBlue,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "100% parity with iOS & DailyCore architecture.",
                        color = ThemeColors.textMuted,
                        fontSize = 13.sp
                    )
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
