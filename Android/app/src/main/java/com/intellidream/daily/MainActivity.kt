package com.intellidream.daily

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.FloatingGlassCapsule
import com.intellidream.daily.designsystem.GlassButton
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.NavigationTab
import com.intellidream.daily.designsystem.ThemeColors

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            DailyRootScreen()
        }
    }
}

@Composable
fun DailyRootScreen() {
    var selectedTab by remember { mutableStateOf(NavigationTab.Dashboard) }
    var tapCounter by remember { mutableStateOf(0) }

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
            // Header
            RowHeader()

            Spacer(modifier = Modifier.height(24.dp))

            // Hero Glass Card
            GlassCard(
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 20.dp,
                padding = 20.dp,
                intensity = GlassIntensity.Medium
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
                    Spacer(modifier = Modifier.height(16.dp))
                    GlassButton(
                        onClick = { tapCounter++ },
                        paddingHorizontal = 16.dp,
                        paddingVertical = 10.dp
                    ) {
                        Text(
                            text = if (tapCounter == 0) "Explore Features" else "Tapped $tapCounter times",
                            color = ThemeColors.accentCyan,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Active Tab preview card
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

@Composable
private fun RowHeader() {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Welcome to DayOne",
            color = ThemeColors.textSecondary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium
        )
        Text(
            text = "Your Life, Synchronized",
            color = Color.White,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold
        )
    }
}
