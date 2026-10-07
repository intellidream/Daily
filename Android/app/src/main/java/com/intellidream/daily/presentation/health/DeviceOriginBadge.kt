package com.intellidream.daily.presentation.health

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Adjust
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Sensors
import androidx.compose.material.icons.rounded.Smartphone
import androidx.compose.material.icons.rounded.Watch
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
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.DeviceIconType
import com.intellidream.daily.model.DeviceSource

fun getDeviceIcon(iconType: DeviceIconType): ImageVector {
    return when (iconType) {
        DeviceIconType.WATCH -> Icons.Rounded.Watch
        DeviceIconType.RING -> Icons.Rounded.Adjust
        DeviceIconType.HEALTH -> Icons.Rounded.Favorite
        DeviceIconType.PHONE -> Icons.Rounded.Smartphone
        DeviceIconType.MANUAL -> Icons.Rounded.Edit
        DeviceIconType.SENSOR -> Icons.Rounded.Sensors
    }
}

/**
 * Prominent, high-contrast badge attributing a health metric to its originating physical device.
 * Renders a solid color-coded dot, official hardware icon (Oura Ring, Apple Watch, Pixel Watch, Health Connect, etc.),
 * and the device display name.
 */
@Composable
fun DeviceOriginBadge(
    device: String?,
    compact: Boolean = false,
    modifier: Modifier = Modifier
) {
    val clean = device?.trim()
    if (clean.isNullOrEmpty()) return

    val source = DeviceSource.from(clean)
    if (source.isVirtualEngine) return

    val color = runCatching { Color(android.graphics.Color.parseColor(source.colorHex)) }
        .getOrDefault(ThemeColors.accentCyan)
    val icon = getDeviceIcon(source.iconType)

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(color.copy(alpha = 0.14f))
            .border(0.8.dp, color.copy(alpha = 0.35f), RoundedCornerShape(percent = 50))
            .padding(
                horizontal = if (compact) 7.dp else 9.dp,
                vertical = if (compact) 3.dp else 4.dp
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 5.dp)
    ) {
        // 1. Solid color circle
        Box(
            modifier = Modifier
                .size(if (compact) 6.dp else 7.dp)
                .clip(CircleShape)
                .background(color)
        )

        // 2. Hardware icon in color
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(if (compact) 10.dp else 12.dp)
        )

        // 3. Device Display Name
        Text(
            text = source.displayName,
            fontSize = if (compact) 10.sp else 11.sp,
            fontWeight = FontWeight.Bold,
            color = color,
            maxLines = 1
        )
    }
}
