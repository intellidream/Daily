package com.intellidream.daily.wearos.presentation.tile

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.glance.wear.tiles.GlanceTileService
import com.intellidream.daily.wearos.data.dataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

class DailyTileService : GlanceTileService() {
    @androidx.compose.runtime.Composable
    override fun Content() {
        val context = LocalContext.current
        var waterStr = "0"
        var smokesStr = "0"

        // Tile layout generation happens on a background worker thread, so runBlocking is safe here
        runBlocking {
            try {
                val prefs = context.dataStore.data.first()
                waterStr = prefs[stringPreferencesKey("daily_water_total")] ?: "0"
                smokesStr = prefs[stringPreferencesKey("daily_smokes_total")] ?: "0"
            } catch (ignored: Exception) {}
        }

        Column(
            modifier = GlanceModifier.fillMaxSize(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "💧 ${waterStr}ml",
                style = TextStyle(color = ColorProvider(Color.Cyan), fontSize = 24.sp)
            )
            Spacer(modifier = GlanceModifier.height(12.dp))
            Text(
                text = "🚬 $smokesStr",
                style = TextStyle(color = ColorProvider(Color(0xFFFFA500)), fontSize = 24.sp)
            )
        }
    }
}
