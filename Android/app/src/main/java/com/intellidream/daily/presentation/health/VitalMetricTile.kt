package com.intellidream.daily.presentation.health

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.MonitorHeart
import androidx.compose.material.icons.rounded.Nightlight
import androidx.compose.material.icons.rounded.Scale
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.ShowChart
import androidx.compose.material.icons.rounded.Spa
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.designsystem.GlassCard
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DeviceSource
import com.intellidream.daily.model.HealthMetricType
import com.intellidream.daily.model.VitalMetricRecord
import java.util.Locale
import kotlin.math.roundToInt

@Composable
fun VitalMetricTile(
    metricType: HealthMetricType,
    record: VitalMetricRecord?,
    tint: Color = ThemeColors.accentCyan,
    modifier: Modifier = Modifier
) {
    GlassCard(
        modifier = modifier.fillMaxWidth(),
        cornerRadius = 18.dp,
        padding = 14.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            // Header: Icon + Metric Name + Source Device Badge
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(tint.copy(alpha = 0.16f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = getMetricIcon(metricType),
                        contentDescription = null,
                        tint = tint,
                        modifier = Modifier.size(15.dp)
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(
                        text = metricType.displayName,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1
                    )

                    val device = record?.sourceDevice
                    if (!device.isNullOrEmpty()) {
                        Text(
                            text = DeviceSource.from(device).displayName,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                            color = ThemeColors.fgMutedDark,
                            maxLines = 1
                        )
                    }
                }

                Spacer(modifier = Modifier.weight(1f))
            }

            // Value + Unit
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = formatValue(metricType, record?.value),
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )

                Text(
                    text = record?.unit ?: metricType.defaultUnit,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = ThemeColors.fgMutedDark,
                    modifier = Modifier.padding(bottom = 2.dp)
                )
            }
        }
    }
}

private fun formatValue(metricType: HealthMetricType, value: Double?): String {
    if (value == null) return "--"
    return when (metricType) {
        HealthMetricType.STEPS,
        HealthMetricType.ACTIVE_ENERGY,
        HealthMetricType.BASAL_ENERGY,
        HealthMetricType.FLOORS_CLIMBED,
        HealthMetricType.HEART_RATE,
        HealthMetricType.RESTING_HEART_RATE,
        HealthMetricType.HRV_SDNN,
        HealthMetricType.HRV_RMSSD,
        HealthMetricType.OXYGEN_SATURATION,
        HealthMetricType.BLOOD_PRESSURE_SYSTOLIC,
        HealthMetricType.BLOOD_PRESSURE_DIASTOLIC,
        HealthMetricType.HYDRATION,
        HealthMetricType.STRESS,
        HealthMetricType.PAI,
        HealthMetricType.MINDFUL_SESSION -> "${value.roundToInt()}"

        HealthMetricType.DISTANCE,
        HealthMetricType.WEIGHT,
        HealthMetricType.LEAN_BODY_MASS,
        HealthMetricType.HEIGHT,
        HealthMetricType.BMI,
        HealthMetricType.RESPIRATORY_RATE,
        HealthMetricType.BODY_TEMPERATURE,
        HealthMetricType.BODY_FAT_PERCENTAGE -> String.format(Locale.getDefault(), "%.1f", value)

        HealthMetricType.SLEEP_DURATION,
        HealthMetricType.SLEEP_DEEP,
        HealthMetricType.SLEEP_REM,
        HealthMetricType.SLEEP_LIGHT,
        HealthMetricType.SLEEP_AWAKE,
        HealthMetricType.NAP_DURATION -> {
            val hours = value.toInt() / 60
            val mins = value.toInt() % 60
            if (hours > 0) "${hours}h ${mins}m" else "${mins}m"
        }
        else -> String.format(Locale.getDefault(), "%.1f", value)
    }
}

private fun getMetricIcon(type: HealthMetricType): ImageVector = when (type) {
    HealthMetricType.STEPS -> Icons.Rounded.DirectionsWalk
    HealthMetricType.ACTIVE_ENERGY, HealthMetricType.BASAL_ENERGY -> Icons.Rounded.LocalFireDepartment
    HealthMetricType.HEART_RATE, HealthMetricType.RESTING_HEART_RATE -> Icons.Rounded.Favorite
    HealthMetricType.HRV_SDNN, HealthMetricType.HRV_RMSSD -> Icons.Rounded.ShowChart
    HealthMetricType.OXYGEN_SATURATION, HealthMetricType.RESPIRATORY_RATE -> Icons.Rounded.SelfImprovement
    HealthMetricType.BLOOD_PRESSURE_SYSTOLIC, HealthMetricType.BLOOD_PRESSURE_DIASTOLIC -> Icons.Rounded.MonitorHeart
    HealthMetricType.SLEEP_DURATION, HealthMetricType.SLEEP_DEEP,
    HealthMetricType.SLEEP_REM, HealthMetricType.SLEEP_LIGHT,
    HealthMetricType.SLEEP_AWAKE, HealthMetricType.NAP_DURATION -> Icons.Rounded.Nightlight
    HealthMetricType.HYDRATION -> Icons.Rounded.WaterDrop
    HealthMetricType.STRESS -> Icons.Rounded.Spa
    HealthMetricType.WEIGHT, HealthMetricType.BODY_FAT_PERCENTAGE, HealthMetricType.BMI, HealthMetricType.LEAN_BODY_MASS -> Icons.Rounded.Scale
    HealthMetricType.WALKING_SPEED, HealthMetricType.RUNNING_SPEED -> Icons.Rounded.Speed
    else -> Icons.Rounded.ShowChart
}
