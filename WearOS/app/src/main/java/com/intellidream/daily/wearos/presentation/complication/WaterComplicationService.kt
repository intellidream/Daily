package com.intellidream.daily.wearos.presentation.complication

import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.intellidream.daily.wearos.data.dataStore
import kotlinx.coroutines.flow.first

class WaterComplicationService : SuspendingComplicationDataSourceService() {
    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        if (type == ComplicationType.SHORT_TEXT) {
            return ShortTextComplicationData.Builder(
                text = PlainComplicationText.Builder("💧0").build(),
                contentDescription = PlainComplicationText.Builder("Water Total").build()
            ).build()
        }
        return null
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) return null
        
        var water = "0"
        try {
            val prefs = applicationContext.dataStore.data.first()
            water = prefs[stringPreferencesKey("daily_water_total")] ?: "0"
        } catch (ignored: Exception) {}

        return ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder("💧$water").build(),
            contentDescription = PlainComplicationText.Builder("Water Total").build()
        ).build()
    }
}
