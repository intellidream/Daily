package com.intellidream.daily.presentation.dashboard

import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.AstronomyService
import com.intellidream.daily.model.CelestialBody
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.MoonPhaseInfo
import com.intellidream.daily.model.SGP4Propagator
import com.intellidream.daily.model.StargazingConditions
import com.intellidream.daily.model.StargazingQuality
import java.util.Locale
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.tan

private data class MiniBrightStar(val raHours: Double, val decDeg: Double, val mag: Float)

private val MiniReferenceStars = listOf(
    MiniBrightStar(6.7525, -16.7161, -1.46f), // Sirius
    MiniBrightStar(14.2610, 19.1825, -0.05f), // Arcturus
    MiniBrightStar(18.6156, 38.7837, 0.03f),  // Vega
    MiniBrightStar(5.2782, 45.9980, 0.08f),   // Capella
    MiniBrightStar(5.2423, -8.2016, 0.13f),   // Rigel
    MiniBrightStar(7.6550, 5.2250, 0.34f),    // Procyon
    MiniBrightStar(5.9195, 7.4071, 0.42f),    // Betelgeuse
    MiniBrightStar(19.8464, 8.8683, 0.76f),   // Altair
    MiniBrightStar(4.5987, 16.5093, 0.86f),   // Aldebaran
    MiniBrightStar(16.4901, -26.4320, 0.96f), // Antares
    MiniBrightStar(13.4199, -11.1613, 0.97f), // Spica
    MiniBrightStar(7.7553, 28.0262, 1.14f),   // Pollux
    MiniBrightStar(22.9608, -29.6222, 1.16f), // Fomalhaut
    MiniBrightStar(20.6905, 45.2803, 1.25f),  // Deneb
    MiniBrightStar(10.1395, 11.9672, 1.36f),  // Regulus
    MiniBrightStar(2.5303, 89.2641, 1.98f)    // Polaris
)

@Composable
fun CosmosDashboardCard(
    size: DashboardWidgetSize,
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>,
    settings: AppSettings,
    latitude: Double = 44.4323,
    longitude: Double = 26.1063,
    onTap: () -> Unit,
    onLongClick: (() -> Unit)? = null
) {
    val cardHeight = when (size) {
        DashboardWidgetSize.Small -> 155.dp
        DashboardWidgetSize.Wide -> 160.dp
        DashboardWidgetSize.Tall, DashboardWidgetSize.Large -> 324.dp
    }

    val glassIntensity = when (settings.glassIntensity) {
        com.intellidream.daily.model.GlassIntensity.Subtle -> GlassIntensity.Subtle
        com.intellidream.daily.model.GlassIntensity.Medium -> GlassIntensity.Medium
        com.intellidream.daily.model.GlassIntensity.Prominent -> GlassIntensity.Prominent
    }

    val lat = latitude
    val lon = longitude

    GlassCard(
        modifier = Modifier
            .fillMaxWidth()
            .height(cardHeight),
        cornerRadius = 20.dp,
        padding = if (size == DashboardWidgetSize.Small) 14.dp else 18.dp,
        intensity = glassIntensity,
        onClick = onTap,
        onLongClick = onLongClick
    ) {
        when (size) {
            DashboardWidgetSize.Small -> SmallCosmosContent(conditions, moon, visiblePlanets, lat, lon)
            DashboardWidgetSize.Wide -> WideCosmosContent(conditions, moon, visiblePlanets, lat, lon)
            DashboardWidgetSize.Tall -> TallCosmosContent(conditions, moon, visiblePlanets, lat, lon)
            DashboardWidgetSize.Large -> LargeCosmosContent(conditions, moon, visiblePlanets, lat, lon)
        }
    }
}

@Composable
private fun MiniZenithSkyDomeCanvas(
    latitude: Double,
    longitude: Double,
    diameter: Dp,
    modifier: Modifier = Modifier
) {
    val nowMs = remember { System.currentTimeMillis() }
    val bodies: List<Pair<CelestialBody, com.intellidream.daily.model.CelestialCoordinates>> = remember(latitude, longitude, nowMs / 60_000L) {
        val t = AstronomyService.makeTime(nowMs)
        listOf(
            CelestialBody.MOON,
            CelestialBody.MERCURY,
            CelestialBody.VENUS,
            CelestialBody.MARS,
            CelestialBody.JUPITER,
            CelestialBody.SATURN
        ).map { body ->
            body to AstronomyService.coordinates(body, latitude, longitude, 0.0, t)
        }.filter { it.second.isVisible }
    }

    Canvas(modifier = modifier.size(diameter)) {
        val cx = size.width * 0.5f
        val cy = size.height * 0.5f
        val r = min(cx, cy) - 2.dp.toPx()

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(Color(0xFF0A142B), Color(0xFF03060F)),
                center = Offset(cx, cy),
                radius = r
            ),
            radius = r,
            center = Offset(cx, cy)
        )
        drawCircle(
            color = Color(0xFF00E5FF).copy(alpha = 0.35f),
            radius = r,
            center = Offset(cx, cy),
            style = Stroke(width = 1.1.dp.toPx())
        )
        drawCircle(
            color = Color.White.copy(alpha = 0.10f),
            radius = r * 0.5f,
            center = Offset(cx, cy),
            style = Stroke(width = 0.7.dp.toPx())
        )

        val astroTime = AstronomyService.makeTime(nowMs)
        // Bright Reference Stars (Stereographic Zenith Planisphere: N up, E left / W right sky dome)
        for (star in MiniReferenceStars) {
            val hor = AstronomyService.starHorizontalCoordinates(star.raHours, star.decDeg, latitude, longitude, 0.0, astroTime)
            if (hor.altitudeDegrees <= 0.0) continue
            val zRad = (90.0 - hor.altitudeDegrees) * (PI / 180.0)
            val rho = (r * tan(zRad * 0.5)).toFloat()
            val azRad = hor.azimuthDegrees * (PI / 180.0)
            val sx = cx - (rho * sin(azRad)).toFloat()
            val sy = cy - (rho * cos(azRad)).toFloat()
            val sr = if (star.mag < 0.2f) 2.0f else 1.35f
            drawCircle(Color.White.copy(alpha = 0.85f), radius = sr, center = Offset(sx, sy))
        }

        // Live Solar System Bodies Above Horizon
        for ((body, coords) in bodies) {
            val zRad = (90.0 - coords.altitudeDegrees) * (PI / 180.0)
            val rho = (r * tan(zRad * 0.5)).toFloat()
            val azRad = coords.azimuthDegrees * (PI / 180.0)
            val sx = cx - (rho * sin(azRad)).toFloat()
            val sy = cy - (rho * cos(azRad)).toFloat()
            val col = if (body == CelestialBody.MOON) Color(0xFFFFE599) else Color(0xFF00E5FF)
            val br = if (body == CelestialBody.MOON) 3.4f else 2.5f
            drawCircle(col, radius = br, center = Offset(sx, sy))
        }
    }
}

@Composable
private fun SmallCosmosContent(
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>,
    lat: Double,
    lon: Double
) {
    val score = conditions?.score ?: 75
    val quality = conditions?.quality ?: StargazingQuality.GOOD
    val qualityColor = parseHexColor(quality.colorHex)

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            MiniZenithSkyDomeCanvas(latitude = lat, longitude = lon, diameter = 40.dp)

            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(qualityColor.copy(alpha = 0.20f))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(
                    text = "$score/100",
                    color = qualityColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = "Cosmos Observatory",
                color = Color.White.copy(alpha = 0.72f),
                fontSize = 11.5.sp,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = "${moon?.quarter?.symbol ?: "🌓"} ${moon?.illuminationPercent ?: 50}%",
                color = Color.White,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = if (visiblePlanets.isNotEmpty()) "${visiblePlanets.size} planets above horizon" else quality.displayName,
                color = qualityColor,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun WideCosmosContent(
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>,
    lat: Double,
    lon: Double
) {
    val score = conditions?.score ?: 80
    val quality = conditions?.quality ?: StargazingQuality.GOOD
    val qualityColor = parseHexColor(quality.colorHex)

    Row(
        modifier = Modifier.fillMaxSize(),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        MiniZenithSkyDomeCanvas(latitude = lat, longitude = lon, diameter = 92.dp)

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Night Sky Observatory",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Bortle ${conditions?.bortleClass ?: 5} • NELM ${String.format(Locale.US, "%.1f", conditions?.limitingMagnitude ?: 5.8)} • ${conditions?.provenance?.badgeLabel ?: "EPHEMERIS"}",
                        color = Color.White.copy(alpha = 0.62f),
                        fontSize = 10.5.sp
                    )
                }

                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(qualityColor.copy(alpha = 0.18f))
                        .border(1.dp, qualityColor.copy(alpha = 0.35f), CircleShape)
                        .padding(horizontal = 9.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = "$score • ${quality.displayName.uppercase(Locale.US)}",
                        color = qualityColor,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            Spacer(modifier = Modifier.height(6.dp))

            Text(
                text = "${moon?.quarter?.symbol ?: "🌓"} ${moon?.quarter?.displayName ?: "Moon"} (${moon?.illuminationPercent ?: 0}%) • " +
                    if (visiblePlanets.isNotEmpty()) visiblePlanets.take(3).joinToString(", ") { it.displayName } else "Deep-sky window",
                color = Color.White.copy(alpha = 0.88f),
                fontSize = 11.5.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            Text(
                text = conditions?.bestWindowDescription ?: conditions?.narrativeAdvice ?: "Tap to open interactive 120Hz sky chart",
                color = Color(0xFF00E5FF),
                fontSize = 10.5.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun TallCosmosContent(
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>,
    lat: Double,
    lon: Double
) {
    val nowMs = remember { System.currentTimeMillis() }
    val liveRows: List<Pair<CelestialBody, com.intellidream.daily.model.CelestialCoordinates>> = remember(lat, lon, nowMs / 60_000L) {
        val t = AstronomyService.makeTime(nowMs)
        listOf(
            CelestialBody.MOON,
            CelestialBody.MERCURY,
            CelestialBody.VENUS,
            CelestialBody.MARS,
            CelestialBody.JUPITER,
            CelestialBody.SATURN
        ).map { body ->
            body to AstronomyService.coordinates(body, lat, lon, 0.0, t)
        }.filter { it.second.isVisible }
            .sortedByDescending { it.second.altitudeDegrees }
            .take(3)
    }

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Box(modifier = Modifier.height(118.dp)) {
            WideCosmosContent(conditions, moon, visiblePlanets, lat, lon)
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(14.dp))
                .background(Color(0xFF0B1426))
                .padding(12.dp)
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Currently Above Local Horizon",
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Icon(
                        imageVector = Icons.Rounded.AutoAwesome,
                        contentDescription = null,
                        tint = Color(0xFFFFD54F),
                        modifier = Modifier.size(14.dp)
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (liveRows.isEmpty()) {
                        Text(
                            text = "No bright planets above the horizon right now — explore 15,544 stars & 219 deep-sky objects.",
                            color = Color.White.copy(alpha = 0.72f),
                            fontSize = 11.sp
                        )
                    } else {
                        for ((body, coords) in liveRows) {
                            val detail = if (body == CelestialBody.MOON) {
                                "${moon?.quarter?.symbol ?: "☽"} ${moon?.illuminationPercent ?: 0}% lit"
                            } else {
                                "${body.symbol} mag ${String.format(Locale.US, "%.1f", coords.visualMagnitude)}"
                            }
                            val dir = coords.compassDirection
                            CelestialRowItem(
                                name = body.displayName,
                                detail = detail,
                                status = "Alt ${String.format(Locale.US, "%+.0f°", coords.altitudeDegrees)} $dir"
                            )
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = conditions?.bestWindowDescription ?: "Open Observatory for SGP4 ISS passes & telescope zoom",
                        color = Color(0xFF00E5FF),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.5f),
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun LargeCosmosContent(
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>,
    lat: Double,
    lon: Double
) {
    val score = conditions?.score ?: 80
    val quality = conditions?.quality ?: StargazingQuality.GOOD
    val qualityColor = parseHexColor(quality.colorHex)

    val nowMs = remember { System.currentTimeMillis() }
    val liveBodies: List<Pair<CelestialBody, com.intellidream.daily.model.CelestialCoordinates>> = remember(lat, lon, nowMs / 60_000L) {
        val t = AstronomyService.makeTime(nowMs)
        listOf(
            CelestialBody.MOON,
            CelestialBody.MERCURY,
            CelestialBody.VENUS,
            CelestialBody.MARS,
            CelestialBody.JUPITER,
            CelestialBody.SATURN
        ).map { body ->
            body to AstronomyService.coordinates(body, lat, lon, 0.0, t)
        }.filter { it.second.isVisible }
            .sortedByDescending { it.second.altitudeDegrees }
    }

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Top row: Header with score badge + Mini Sky Dome + Moon & Sky context
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            MiniZenithSkyDomeCanvas(latitude = lat, longitude = lon, diameter = 96.dp)

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Cosmos Observatory",
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(qualityColor.copy(alpha = 0.18f))
                            .border(1.dp, qualityColor.copy(alpha = 0.35f), CircleShape)
                            .padding(horizontal = 9.dp, vertical = 3.dp)
                    ) {
                        Text(
                            text = "$score • ${quality.displayName.uppercase(Locale.US)}",
                            color = qualityColor,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                Text(
                    text = "Bortle ${conditions?.bortleClass ?: 5} • NELM ${String.format(Locale.US, "%.1f", conditions?.limitingMagnitude ?: 5.8)} • ${conditions?.provenance?.badgeLabel ?: "EPHEMERIS"}",
                    color = Color.White.copy(alpha = 0.62f),
                    fontSize = 11.sp
                )

                Text(
                    text = "${moon?.quarter?.symbol ?: "🌓"} ${moon?.quarter?.displayName ?: "Moon"} • ${moon?.illuminationPercent ?: 0}% lit",
                    color = Color.White.copy(alpha = 0.90f),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium
                )

                Text(
                    text = conditions?.bestWindowDescription ?: conditions?.narrativeAdvice ?: "Ideal dark window calculation active",
                    color = Color(0xFF00E5FF),
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        // Middle container: Active Sky Bodies & Planetary Positions
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(14.dp))
                .background(Color(0xFF0B1426))
                .padding(horizontal = 12.dp, vertical = 10.dp)
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Visible in Night Sky Dome",
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "${liveBodies.size} bodies above horizon",
                        color = Color.White.copy(alpha = 0.55f),
                        fontSize = 10.5.sp
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    if (liveBodies.isEmpty()) {
                        Text(
                            text = "No major planets above the horizon right now. 15,544 Hipparcos stars & 219 DSOs available in sky chart.",
                            color = Color.White.copy(alpha = 0.70f),
                            fontSize = 11.sp
                        )
                    } else {
                        for ((body, coords) in liveBodies.take(4)) {
                            val detail = if (body == CelestialBody.MOON) {
                                "${moon?.quarter?.symbol ?: "☽"} ${moon?.illuminationPercent ?: 0}% illuminated"
                            } else {
                                "${body.symbol} mag ${String.format(Locale.US, "%.1f", coords.visualMagnitude)}"
                            }
                            val dir = coords.compassDirection
                            CelestialRowItem(
                                name = body.displayName,
                                detail = detail,
                                status = "Alt ${String.format(Locale.US, "%+.0f°", coords.altitudeDegrees)} $dir"
                            )
                        }
                    }
                }

                // Cloud & Seeing Telemetry strip
                val cLow = conditions?.cloudCoverLowPercent ?: 0
                val cMid = conditions?.cloudCoverMidPercent ?: 0
                val cHigh = conditions?.cloudCoverHighPercent ?: 0
                val seeing = conditions?.seeingArcseconds?.let { String.format(Locale.US, "%.1f\" FWHM", it) } ?: "1.1\" FWHM"
                Text(
                    text = "Clouds: L $cLow% · M $cMid% · H $cHigh% • Seeing: $seeing",
                    color = Color.White.copy(alpha = 0.50f),
                    fontSize = 10.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        // Bottom CTA
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Tap to launch interactive 120Hz Sky Dome & SGP4 ISS passes",
                color = Color(0xFF00E5FF),
                fontSize = 10.5.sp,
                fontWeight = FontWeight.Medium
            )
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.5f),
                modifier = Modifier.size(14.dp)
            )
        }
    }
}

@Composable
private fun CelestialRowItem(name: String, detail: String, status: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF00E676))
            )
            Text(
                text = name,
                color = Color.White,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium
            )
        }
        Text(
            text = detail,
            color = Color.White.copy(alpha = 0.70f),
            fontSize = 11.sp
        )
        Text(
            text = status,
            color = Color.White.copy(alpha = 0.58f),
            fontSize = 10.sp
        )
    }
}

private fun parseHexColor(hex: String): Color {
    return try {
        val clean = hex.removePrefix("#")
        val colorInt = clean.toLong(16)
        if (clean.length == 6) {
            Color(0xFF000000 or colorInt)
        } else {
            Color(colorInt)
        }
    } catch (_: Exception) {
        Color(0xFF00E5FF)
    }
}
