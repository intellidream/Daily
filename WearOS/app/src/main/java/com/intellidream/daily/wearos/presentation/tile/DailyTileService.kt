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
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
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

        try {
            val prefs = context.getSharedPreferences(WatchSessionManager.PREFS_NAME, Context.MODE_PRIVATE)
            waterStr = prefs.getString(WatchSessionManager.KEY_WATER_TOTAL, "0") ?: "0"
            smokesStr = prefs.getString(WatchSessionManager.KEY_SMOKES_TOTAL, "0") ?: "0"
        } catch (ignored: Exception) {}

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .clickable(actionStartActivity<MainActivity>()),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "💧 ${waterStr}ml",
                style = TextStyle(color = ColorProvider(Color.Cyan), fontSize = 24.sp)
            )
            Spacer(modifier = GlanceModifier.height(12.dp))
            Text(
                text = "🔥 $smokesStr",
                style = TextStyle(color = ColorProvider(Color(0xFFFFA500)), fontSize = 24.sp)
            )
        }
    }
}
