package com.intellidream.daily.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.intellidream.daily.DailyApp
import com.intellidream.daily.MainActivity
import com.intellidream.daily.R
import com.intellidream.daily.cosmos.CosmosCatalogRepository
import com.intellidream.daily.model.AstronomyService
import com.intellidream.daily.model.CelestialBody
import java.util.Locale

class DailyCosmosGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyCosmosGlanceWidget()
}

class DailyCosmosGlanceWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val app = runCatching { DailyApp.instance }.getOrNull()
        val weather = app?.weatherRepository?.currentWeather?.value
        val lat = weather?.coord?.lat ?: 44.4268
        val lon = weather?.coord?.lon ?: 26.1025
        val cloudPct = weather?.clouds?.all

        val nowMs = System.currentTimeMillis()
        val time = AstronomyService.makeTime(nowMs)
        val moon = AstronomyService.moonPhase(time, lat, lon)
        val bortle = runCatching { CosmosCatalogRepository(context).bortleClass(lat, lon) }.getOrDefault(5)
        val conditions = AstronomyService.evaluateStargazingConditions(
            latitude = lat,
            longitude = lon,
            millis = nowMs,
            cloudCoverTotal = cloudPct,
            cloudCoverLow = null,
            cloudCoverMid = null,
            cloudCoverHigh = null,
            bortleClass = bortle
        )

        val visiblePlanets = CelestialBody.majorPlanets.filter { body ->
            AstronomyService.coordinates(body, lat, lon, 0.0, time).altitudeDegrees > 0.0
        }
        val planetsSummary = if (visiblePlanets.isEmpty()) {
            "Solar planets below horizon"
        } else {
            visiblePlanets.take(3).joinToString(" · ") { it.displayName }
        }

        val verdictColor = Color(android.graphics.Color.parseColor(conditions.quality.colorHex))
        val cyanColor = Color(0xFF00E5FF)
        val mutedColor = Color(0xFF94A3B8)

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.intellidream.daily.ACTION_OPEN_COSMOS"
            data = Uri.parse("daily://cosmos")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_TARGET_TAB, MainActivity.TAB_COSMOS)
        }

        provideContent {
            val size = LocalSize.current
            GlanceTheme {
                Box(
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .appWidgetBackground()
                        .background(ImageProvider(R.drawable.widget_background))
                        .cornerRadius(22.dp)
                        .clickable(actionStartActivity(launchIntent))
                        .padding(14.dp)
                ) {
                    if (size.width >= 210.dp) {
                        Row(
                            modifier = GlanceModifier.fillMaxSize(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = GlanceModifier.defaultWeight()) {
                                Text(
                                    text = "COSMOS OBSERVATORY",
                                    style = TextStyle(
                                        color = ColorProvider(cyanColor),
                                        fontSize = 9.5.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                                Spacer(GlanceModifier.height(4.dp))
                                Row(verticalAlignment = Alignment.Bottom) {
                                    Text(
                                        text = "${conditions.score}",
                                        style = TextStyle(
                                            color = ColorProvider(Color.White),
                                            fontSize = 30.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    )
                                    Spacer(GlanceModifier.width(4.dp))
                                    Text(
                                        text = "${conditions.quality.displayName.uppercase(Locale.US)} · B${conditions.bortleClass}",
                                        style = TextStyle(
                                            color = ColorProvider(verdictColor),
                                            fontSize = 10.5.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    )
                                }
                                Spacer(GlanceModifier.height(4.dp))
                                Text(
                                    text = "${moon.quarter.symbol} ${moon.quarter.displayName} (${moon.illuminationPercent}%)",
                                    style = TextStyle(
                                        color = ColorProvider(Color(0xFFFDE68A)),
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Medium
                                    ),
                                    maxLines = 1
                                )
                            }

                            Spacer(GlanceModifier.width(10.dp))

                            Column(modifier = GlanceModifier.defaultWeight()) {
                                Text(
                                    text = "BEST WINDOW",
                                    style = TextStyle(
                                        color = ColorProvider(mutedColor),
                                        fontSize = 9.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                                Text(
                                    text = conditions.bestWindowDescription ?: "Calculated at dusk",
                                    style = TextStyle(
                                        color = ColorProvider(Color.White),
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Medium
                                    ),
                                    maxLines = 1
                                )
                                Spacer(GlanceModifier.height(6.dp))
                                Text(
                                    text = "VISIBLE PLANETS (${visiblePlanets.size})",
                                    style = TextStyle(
                                        color = ColorProvider(mutedColor),
                                        fontSize = 9.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                                Text(
                                    text = planetsSummary,
                                    style = TextStyle(
                                        color = ColorProvider(Color.White),
                                        fontSize = 10.5.sp
                                    ),
                                    maxLines = 1
                                )
                            }
                        }
                    } else {
                        Column(modifier = GlanceModifier.fillMaxSize()) {
                            Row(
                                modifier = GlanceModifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "COSMOS",
                                    style = TextStyle(
                                        color = ColorProvider(cyanColor),
                                        fontSize = 9.5.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                                Spacer(GlanceModifier.defaultWeight())
                                Text(
                                    text = moon.quarter.symbol,
                                    style = TextStyle(fontSize = 14.sp)
                                )
                            }
                            Spacer(GlanceModifier.defaultWeight())
                            Row(verticalAlignment = Alignment.Bottom) {
                                Text(
                                    text = "${conditions.score}",
                                    style = TextStyle(
                                        color = ColorProvider(Color.White),
                                        fontSize = 28.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                                Spacer(GlanceModifier.width(4.dp))
                                Text(
                                    text = conditions.quality.displayName,
                                    style = TextStyle(
                                        color = ColorProvider(verdictColor),
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                )
                            }
                            Text(
                                text = "${moon.quarter.displayName} · ${moon.illuminationPercent}%",
                                style = TextStyle(
                                    color = ColorProvider(Color(0xFFE2E8F0)),
                                    fontSize = 10.sp
                                ),
                                maxLines = 1
                            )
                            Text(
                                text = "${visiblePlanets.size} planets up · B${conditions.bortleClass}",
                                style = TextStyle(
                                    color = ColorProvider(mutedColor),
                                    fontSize = 9.5.sp
                                ),
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
    }
}
