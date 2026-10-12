package com.intellidream.daily.wearos.presentation.components

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Text

@Composable
fun TemporalNavHeader(
    title: String,
    canGoForward: Boolean,
    accentColor: Color,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    modifier: Modifier = Modifier
) {
    val view = LocalView.current

    Row(
        modifier = modifier
            .fillMaxWidth(0.92f)
            .height(34.dp)
            .clip(RoundedCornerShape(17.dp))
            .background(Color(0xFF161A22))
            .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(17.dp))
            .padding(horizontal = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Previous Button (‹)
        Box(
            modifier = Modifier
                .size(width = 34.dp, height = 28.dp)
                .clip(RoundedCornerShape(14.dp))
                .clickable {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    onPrevious()
                },
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "‹",
                color = accentColor,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold
            )
        }

        // Centered Date / Week Label
        Text(
            text = title,
            color = Color.White,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f)
        )

        // Next Button (›) - hidden when on current date/week
        if (canGoForward) {
            Box(
                modifier = Modifier
                    .size(width = 34.dp, height = 28.dp)
                .clip(RoundedCornerShape(14.dp))
                .clickable {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    onNext()
                },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "›",
                    color = accentColor,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        } else {
            // Invisible placeholder for balanced layout centering
            Box(modifier = Modifier.size(width = 34.dp, height = 28.dp))
        }
    }
}
