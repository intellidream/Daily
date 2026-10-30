package com.intellidream.daily.wearos.presentation.orbit

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Grain
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.TrendingDown
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.data.WatchSmartLedgerRepository
import com.intellidream.daily.wearos.data.WatchTagdosRepository
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.google.android.horologist.annotations.ExperimentalHorologistApi
import com.google.android.horologist.compose.layout.ScalingLazyColumn
import com.google.android.horologist.compose.layout.ScalingLazyColumnState
import com.google.android.horologist.compose.layout.ScreenScaffold
import com.google.android.horologist.compose.layout.rememberResponsiveColumnState
import com.intellidream.daily.wearos.presentation.theme.SurfaceCard
import com.intellidream.daily.wearos.presentation.theme.SurfaceCardBorder
import com.intellidream.daily.wearos.presentation.theme.WaterCyan
import androidx.compose.runtime.Immutable
import java.util.Calendar

@Immutable
data class MacroPillar(val name: String, val value: String, val color: Color)
@Immutable
data class StockTicker(val symbol: String, val price: String, val change: String, val isPositive: Boolean)

@OptIn(ExperimentalHorologistApi::class)
@Composable
fun OrbitHubScreen(
    isPageActive: Boolean = true
) {
    val columnState = rememberResponsiveColumnState(
        rotaryMode = ScalingLazyColumnState.RotaryMode.Scroll
    )

    val context = LocalContext.current
    val sessionManager = remember { WatchSessionManager.getInstance(context) }
    val ledgerRepository = remember { WatchSmartLedgerRepository.getInstance(context) }
    val tagdosRepository = remember { WatchTagdosRepository.getInstance(context) }

    LaunchedEffect(isPageActive) {
        if (isPageActive) {
            ledgerRepository.syncWithSupabase(force = false)
        }
    }

    val hour = remember { Calendar.getInstance().get(Calendar.HOUR_OF_DAY) }
    val greeting = remember(hour) {
        when {
            hour < 12 -> "Good morning"
            hour < 18 -> "Good afternoon"
            else -> "Good evening"
        }
    }

    // Dynamic Briefing
    val streams by tagdosRepository.streams.collectAsState()
    val activeStreamsCount = streams.size
    val activePillsCount = streams.flatMap { it.activePills }.size

    val bubblesLogs = sessionManager.cachedBubblesLogs ?: emptyList()
    val todayWater = bubblesLogs.filter { it.metadata?.contains("Coffee") != true }.sumOf { it.value.toInt() }
    val todayCoffee = bubblesLogs.filter { it.metadata?.contains("Coffee") == true }.sumOf { it.value.toInt() }
    val waterGoal = sessionManager.bubblesGoal.collectAsState().value
    val hydrPct = if (waterGoal > 0) minOf(100, ((todayWater + todayCoffee) * 100 / waterGoal)) else 45
    val smokesLogs = sessionManager.cachedSmokesLogs ?: emptyList()
    val todaySmokes = smokesLogs.sumOf { maxOf(1, it.value.toInt()) }
    val smokePart = if (todaySmokes == 0) "Smoke-free day in progress." else "$todaySmokes smokes logged."
    val taskPart = if (activeStreamsCount > 0) "$activeStreamsCount active streams in TagDoS" else "All TagDoS streams clear"
    val briefingText = "Steady energy and optimal pace. $taskPart, hydration at $hydrPct%. $smokePart"

    // Dynamic Weather state (Bucharest diurnal curve)
    val highTemp = 21
    val lowTemp = 11
    val radians = ((hour - 6) / 24.0) * 2.0 * Math.PI
    val tempFraction = (kotlin.math.sin(radians - Math.PI / 2.0) + 1.0) / 2.0
    val currentTemp = lowTemp + kotlin.math.round((highTemp - lowTemp) * tempFraction).toInt()

    val conditionText = when {
        hour in 6..10 -> "Crisp & clear"
        hour in 11..15 -> "Partly sunny"
        hour in 16..19 -> "Golden dusk"
        else -> "Clear & calm"
    }
    val popPercent = when {
        hour in 11..15 -> 10
        hour in 16..19 -> 8
        else -> 5
    }
    val humidityVal = when {
        hour in 11..15 -> 52
        hour in 16..19 -> 60
        hour in 6..10 -> 68
        else -> 72
    }
    val uvIndexVal = when {
        hour in 11..15 -> 4
        hour in 6..10 -> 2
        hour in 16..19 -> 1
        else -> 0
    }

    // Exact Synodic Cosmos Calculations (Bucharest 44.4°N)
    val now = remember { System.currentTimeMillis() }
    val cal = remember { Calendar.getInstance() }
    val dayOfYear = remember { cal.get(Calendar.DAY_OF_YEAR) }
    val currentMinute = remember { cal.get(Calendar.MINUTE) }
    val currentDecimal = hour + currentMinute / 60.0

    val solarDeclination = -23.44 * kotlin.math.cos((dayOfYear + 10.0) / 365.25 * 2.0 * Math.PI)
    val latRad = 44.43 * (Math.PI / 180.0)
    val decRad = solarDeclination * (Math.PI / 180.0)
    val cosHourAngle = -kotlin.math.tan(latRad) * kotlin.math.tan(decRad)
    val hourAngle = kotlin.math.acos(cosHourAngle.coerceIn(-1.0, 1.0)) * (180.0 / Math.PI) / 15.0

    val solarNoon = 12.0
    val sunriseHours = solarNoon - hourAngle + 0.9
    val sunsetHours = solarNoon + hourAngle + 0.9

    val srHour = sunriseHours.toInt()
    val srMin = ((sunriseHours - srHour) * 60.0).toInt()
    val ssHour = sunsetHours.toInt()
    val ssMin = ((sunsetHours - ssHour) * 60.0).toInt()

    val sunriseTime = String.format("%02d:%02d", srHour, srMin)
    val sunsetTime = String.format("%02d:%02d", ssHour, ssMin)

    val daylightProgress = when {
        currentDecimal < sunriseHours -> 0f
        currentDecimal > sunsetHours -> 1f
        else -> ((currentDecimal - sunriseHours) / maxOf(0.1, sunsetHours - sunriseHours)).toFloat()
    }

    // Synodic Moon Phase (Epoch New Moon: Jan 11, 2024 at 11:57 UTC = 1704974220000L)
    val refNewMoonEpoch = 1704974220000L
    val synodicMonthMs = 29.53058867 * 86400000.0
    val elapsedMs = (now - refNewMoonEpoch).toDouble()
    val cyclePos = elapsedMs % synodicMonthMs
    val moonAgeDays = (if (cyclePos >= 0) cyclePos else cyclePos + synodicMonthMs) / 86400000.0
    val moonIllumination = kotlin.math.round((1.0 - kotlin.math.cos((moonAgeDays / 29.53058867) * 2.0 * Math.PI)) / 2.0 * 100.0).toInt()

    val moonPhaseName = when {
        moonAgeDays < 1.8 -> "New Moon"
        moonAgeDays < 7.4 -> "Waxing Crescent"
        moonAgeDays < 9.2 -> "First Quarter"
        moonAgeDays < 14.8 -> "Waxing Gibbous"
        moonAgeDays < 16.6 -> "Full Moon"
        moonAgeDays < 22.1 -> "Waning Gibbous"
        moonAgeDays < 23.9 -> "Last Quarter"
        else -> "Waning Crescent"
    }

    val allPills = streams.flatMap { it.clusters.flatMap { c -> c.pills } }
    val completedPillsCount = allPills.count { it.isCompleted }
    val totalPillsCount = allPills.size
    val craftVal = if (totalPillsCount > 0) "${(completedPillsCount * 100 / totalPillsCount)}%" else "85%"
    val bodyVal = if (todaySmokes == 0) "100%" else "${maxOf(50, 100 - todaySmokes * 5)}%"
    val pillars = listOf(
        MacroPillar("Energy", "92%", Color(0xFF00E5FF)),
        MacroPillar("Mind", "86%", Color(0xFFA855F7)),
        MacroPillar("Body", bodyVal, Color(0xFF10B981)),
        MacroPillar("Craft", craftVal, Color(0xFFF59E0B)),
        MacroPillar("Wealth", "+2.4%", Color(0xFF34D399)),
        MacroPillar("Tribe", "85%", Color(0xFFEC4899))
    )

    val tickers = remember {
        listOf(
            StockTicker("AAPL", "$234.10", "+1.4%", true),
            StockTicker("NVDA", "$142.80", "+2.6%", true),
            StockTicker("TSLA", "$219.50", "-0.5%", false),
            StockTicker("BTC", "$68,120", "+3.2%", true)
        )
    }

    ScreenScaffold(scrollState = columnState) {
        ScalingLazyColumn(
            columnState = columnState,
            modifier = Modifier.fillMaxSize()
        ) {
            // Header
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.padding(bottom = 6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Public,
                        contentDescription = "Orbit",
                        tint = WaterCyan,
                        modifier = Modifier.size(15.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Orbit Context",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }

            // 1. Diurnal Briefing Card
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF0D1B2A))
                        .border(1.dp, Color(0x3300E5FF), RoundedCornerShape(14.dp))
                        .padding(10.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Default.AutoAwesome,
                            contentDescription = null,
                            tint = WaterCyan,
                            modifier = Modifier.size(11.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "DIURNAL BRIEFING",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = WaterCyan
                        )
                    }

                    Spacer(modifier = Modifier.height(4.dp))

                    Text(
                        text = "$greeting, Mihai",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )

                    Spacer(modifier = Modifier.height(2.dp))

                    Text(
                        text = briefingText,
                        fontSize = 10.sp,
                        color = Color(0xFFC0CAD8),
                        lineHeight = 13.sp
                    )
                }
            }

            // 2. Hyper-Local Weather Card
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF101D2D))
                        .border(1.dp, SurfaceCardBorder, RoundedCornerShape(14.dp))
                        .padding(10.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "WEATHER & ATMOSPHERE",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF38BDF8)
                        )
                        Text(
                            text = "Bucharest",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color(0xFF94A3B8)
                        )
                    }

                    Spacer(modifier = Modifier.height(6.dp))

                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Default.WbSunny,
                            contentDescription = null,
                            tint = Color(0xFFFBBF24),
                            modifier = Modifier.size(26.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Column {
                            Row(verticalAlignment = Alignment.Bottom) {
                                Text(
                                    text = "$currentTemp°",
                                    fontSize = 22.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    text = "H:$highTemp° L:$lowTemp°",
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Color(0xFF94A3B8)
                                )
                            }
                            Text(
                                text = conditionText,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color(0xFFCBD5E1)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(6.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Default.Grain,
                                contentDescription = null,
                                tint = Color(0xFF38BDF8),
                                modifier = Modifier.size(10.dp)
                            )
                            Spacer(modifier = Modifier.width(3.dp))
                            Text(
                                text = "POP $popPercent%",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFFCBD5E1)
                            )
                        }
                        Text(
                            text = "Humidity $humidityVal%",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color(0xFF94A3B8)
                        )
                        Text(
                            text = "UV $uvIndexVal",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color(0xFFFBBF24)
                        )
                    }
                }
            }

            // 3. Cosmos Sun & Moon Arc Card
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF1A1528))
                        .border(1.dp, SurfaceCardBorder, RoundedCornerShape(14.dp))
                        .padding(10.dp)
                ) {
                    Text(
                        text = "COSMOS & CIRCADIAN RHYTHM",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFFF59E0B)
                    )

                    Spacer(modifier = Modifier.height(6.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Default.WbSunny,
                                contentDescription = null,
                                tint = Color(0xFFF59E0B),
                                modifier = Modifier.size(12.dp)
                            )
                            Spacer(modifier = Modifier.width(3.dp))
                            Text(
                                text = sunriseTime,
                                fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace,
                                color = Color(0xFFE2E8F0)
                            )
                        }

                        // Daylight progress track
                        Box(
                            modifier = Modifier
                                .width(40.dp)
                                .height(4.dp)
                                .clip(RoundedCornerShape(2.dp))
                                .background(Color(0x33FFFFFF))
                        ) {
                            Box(
                                modifier = Modifier
                                    .width((40.dp * daylightProgress).coerceAtLeast(4.dp))
                                    .height(4.dp)
                                    .background(Color(0xFFF59E0B))
                            )
                        }

                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = sunsetTime,
                                fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace,
                                color = Color(0xFFE2E8F0)
                            )
                            Spacer(modifier = Modifier.width(3.dp))
                            Icon(
                                imageVector = Icons.Default.WbSunny,
                                contentDescription = null,
                                tint = Color(0xFFEF4444),
                                modifier = Modifier.size(12.dp)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(6.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Default.NightsStay,
                                contentDescription = null,
                                tint = Color(0xFFC084FC),
                                modifier = Modifier.size(12.dp)
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(
                                text = moonPhaseName,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White
                            )
                        }
                        Text(
                            text = "$moonIllumination%",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                            color = Color(0xFFC084FC)
                        )
                    }
                }
            }

            // 4. Macro Pillars Card
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF111C18))
                        .border(1.dp, SurfaceCardBorder, RoundedCornerShape(14.dp))
                        .padding(10.dp)
                ) {
                    Text(
                        text = "MACRO PILLARS",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF10B981)
                    )

                    Spacer(modifier = Modifier.height(6.dp))

                    // 3 rows x 2 columns
                    for (i in 0 until pillars.size step 2) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 2.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            PillarBadge(pillar = pillars[i], modifier = Modifier.weight(1f))
                            if (i + 1 < pillars.size) {
                                PillarBadge(pillar = pillars[i + 1], modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            }

            // 5. Smart Ledger Quick Glance & Adjust
            item {
                SmartLedgerCard(isPageActive = isPageActive)
            }

            // 6. Market Watchlist Card
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF141E18))
                        .border(1.dp, SurfaceCardBorder, RoundedCornerShape(14.dp))
                        .padding(10.dp)
                ) {
                    Text(
                        text = "MARKETS & ASSETS",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF34D399)
                    )

                    Spacer(modifier = Modifier.height(6.dp))

                    tickers.forEach { item ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 3.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = item.symbol,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Monospace,
                                color = Color.White
                            )

                            Text(
                                text = item.price,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                fontFamily = FontFamily.Monospace,
                                color = Color(0xFFCBD5E1)
                            )

                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(4.dp))
                                    .background(
                                        if (item.isPositive) Color(0x2610B981) else Color(0x26EF4444)
                                    )
                                    .padding(horizontal = 4.dp, vertical = 1.dp)
                            ) {
                                Text(
                                    text = item.change,
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold,
                                    fontFamily = FontFamily.Monospace,
                                    color = if (item.isPositive) Color(0xFF10B981) else Color(0xFFEF4444)
                                )
                            }
                        }
                    }
                }
            }

            // Bottom Spacer
            item {
                Spacer(modifier = Modifier.height(18.dp))
            }
        }
    }
}

@Composable
private fun PillarBadge(
    pillar: MacroPillar,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Color(0x1AFFFFFF))
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(5.dp)
                    .clip(CircleShape)
                    .background(pillar.color)
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = pillar.name,
                fontSize = 9.sp,
                fontWeight = FontWeight.Medium,
                color = Color(0xFFE2E8F0)
            )
        }
        Text(
            text = pillar.value,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            color = Color.White
        )
    }
}
