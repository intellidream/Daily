package com.intellidream.daily.presentation.dashboard

import androidx.compose.animation.animateColorAsState
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
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.GlassIntensity
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.AppSettings
import com.intellidream.daily.model.CelestialBody
import com.intellidream.daily.model.DashboardWidgetSize
import com.intellidream.daily.model.MoonPhaseInfo
import com.intellidream.daily.model.StargazingConditions
import com.intellidream.daily.model.StargazingQuality

@Composable
fun CosmosDashboardCard(
    size: DashboardWidgetSize,
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>,
    settings: AppSettings,
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
            DashboardWidgetSize.Small -> SmallCosmosContent(conditions, moon, visiblePlanets)
            DashboardWidgetSize.Wide -> WideCosmosContent(conditions, moon, visiblePlanets)
            DashboardWidgetSize.Tall -> TallCosmosContent(conditions, moon, visiblePlanets)
            DashboardWidgetSize.Large -> LargeCosmosContent(conditions, moon, visiblePlanets)
        }
    }
}

@Composable
private fun SmallCosmosContent(
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>
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
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF7C4DFF).copy(alpha = 0.22f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.NightsStay,
                    contentDescription = null,
                    tint = Color(0xFFB388FF),
                    modifier = Modifier.size(18.dp)
                )
            }

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
                text = "Cosmos",
                color = Color.White.copy(alpha = 0.70f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = "${moon?.quarter?.symbol ?: "🌓"} ${moon?.illuminationPercent ?: 50}%",
                color = Color.White,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = if (visiblePlanets.isNotEmpty()) "${visiblePlanets.size} planete pe cer" else quality.displayNameRo,
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
    visiblePlanets: List<CelestialBody>
) {
    val score = conditions?.score ?: 80
    val quality = conditions?.quality ?: StargazingQuality.PRISTINE
    val qualityColor = parseHexColor(quality.colorHex)

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Header Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF7C4DFF).copy(alpha = 0.22f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Rounded.NightsStay,
                        contentDescription = null,
                        tint = Color(0xFFB388FF),
                        modifier = Modifier.size(19.dp)
                    )
                }
                Column {
                    Text(
                        text = "Observator & Cerul Nopții",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Bortle ${conditions?.bortleClass ?: 4} • NELM ${String.format("%.1f", conditions?.limitingMagnitude ?: 6.2)}m",
                        color = Color.White.copy(alpha = 0.60f),
                        fontSize = 11.sp
                    )
                }
            }

            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(qualityColor.copy(alpha = 0.18f))
                    .border(1.dp, qualityColor.copy(alpha = 0.35f), CircleShape)
                    .padding(horizontal = 9.dp, vertical = 4.dp)
            ) {
                Text(
                    text = "$score • ${quality.displayNameRo.uppercase()}",
                    color = qualityColor,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        // Center Info Cards
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            // Moon Status Box
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.White.copy(alpha = 0.05f))
                    .padding(8.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = moon?.quarter?.symbol ?: "🌖",
                        fontSize = 24.sp
                    )
                    Column {
                        Text(
                            text = moon?.quarter?.displayNameRo ?: "Lună",
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "${moon?.illuminationPercent ?: 0}% iluminat",
                            color = Color.White.copy(alpha = 0.60f),
                            fontSize = 10.sp
                        )
                    }
                }
            }

            // Visible Planets Box
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.White.copy(alpha = 0.05f))
                    .padding(8.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF00E5FF).copy(alpha = 0.18f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Visibility,
                            contentDescription = null,
                            tint = Color(0xFF00E5FF),
                            modifier = Modifier.size(15.dp)
                        )
                    }
                    Column {
                        Text(
                            text = if (visiblePlanets.isNotEmpty()) visiblePlanets.take(3).joinToString(" ") { it.symbol } else "Planete",
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1
                        )
                        Text(
                            text = if (visiblePlanets.isNotEmpty()) "${visiblePlanets.size} vizibile acum" else "Nicio planetă",
                            color = Color.White.copy(alpha = 0.60f),
                            fontSize = 10.sp
                        )
                    }
                }
            }
        }

        // Bottom Narrative Advice
        Text(
            text = conditions?.narrativeAdvice ?: "Condiții bune pentru observarea cerului profund.",
            color = Color.White.copy(alpha = 0.65f),
            fontSize = 11.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun TallCosmosContent(
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        WideCosmosContent(conditions, moon, visiblePlanets)

        Spacer(modifier = Modifier.height(8.dp))

        // Extra Tall Section
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
                        text = "Corpuri Vizibile în Seara Asta",
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
                    CelestialRowItem("Luna", "${moon?.quarter?.symbol} ${moon?.illuminationPercent}%", "În urcare")
                    CelestialRowItem("Jupiter", "♃ mag -2.4", "Vizibil SE")
                    CelestialRowItem("Saturn", "♄ mag +0.7", "Inele înclinate")
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Fereastră ideală: ${conditions?.bestWindowDescription ?: "22:00 – 02:00"}",
                        color = Color(0xFF00E5FF),
                        fontSize = 10.sp,
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
    }
}

@Composable
private fun LargeCosmosContent(
    conditions: StargazingConditions?,
    moon: MoonPhaseInfo?,
    visiblePlanets: List<CelestialBody>
) {
    TallCosmosContent(conditions, moon, visiblePlanets)
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
            color = Color.White.copy(alpha = 0.50f),
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
