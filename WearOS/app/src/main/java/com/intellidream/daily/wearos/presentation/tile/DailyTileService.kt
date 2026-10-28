package com.intellidream.daily.wearos.presentation.tile

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.action.actionStartActivity
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.glance.wear.tiles.GlanceTileService
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.presentation.MainActivity

class DailyTileService : GlanceTileService() {
    @androidx.compose.runtime.Composable
    override fun Content() {
        val context = LocalContext.current
        var waterStr = "0"
        var smokesStr = "0"
        var waterGoal = 2500
        var smokesGoal = 15

        try {
            val prefs = context.getSharedPreferences(WatchSessionManager.PREFS_NAME, Context.MODE_PRIVATE)
            waterStr = prefs.getString(WatchSessionManager.KEY_WATER_TOTAL, "0") ?: "0"
            smokesStr = prefs.getString(WatchSessionManager.KEY_SMOKES_TOTAL, "0") ?: "0"
            waterGoal = prefs.getString(WatchSessionManager.KEY_WATER_GOAL, null)?.toIntOrNull() ?: 2000
            smokesGoal = prefs.getString(WatchSessionManager.KEY_SMOKES_GOAL, null)?.toIntOrNull() ?: 40
        } catch (ignored: Exception) {}

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .clickable(actionStartActivity<MainActivity>()),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "DAYONE ORBIT",
                style = TextStyle(
                    color = ColorProvider(Color(0xFF9E9E9E)),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
            )
            Spacer(modifier = GlanceModifier.height(8.dp))

            // Hydration Metric
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "💧 $waterStr",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF38BDF8)),
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                Text(
                    text = " / ${waterGoal}ml",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF9CA3AF)),
                        fontSize = 12.sp
                    )
                )
            }

            Spacer(modifier = GlanceModifier.height(6.dp))

            // Smokes Metric
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "🔥 $smokesStr",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFFEF4444)),
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                Text(
                    text = " / $smokesGoal max",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF9CA3AF)),
                        fontSize = 12.sp
                    )
                )
            }
        }
    }
}
