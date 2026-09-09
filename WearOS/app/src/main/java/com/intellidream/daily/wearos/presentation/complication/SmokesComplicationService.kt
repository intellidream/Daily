package com.intellidream.daily.wearos.presentation.complication

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.presentation.MainActivity

class SmokesComplicationService : SuspendingComplicationDataSourceService() {
    private fun createTapAction(): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("page", 2)
        }
        return PendingIntent.getActivity(
            applicationContext,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        if (type == ComplicationType.SHORT_TEXT) {
            return ShortTextComplicationData.Builder(
                text = PlainComplicationText.Builder("🔥0").build(),
                contentDescription = PlainComplicationText.Builder("Smokes Total").build()
            )
                .setTapAction(createTapAction())
                .build()
        }
        return null
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) return null
        
        var smokes = "0"
        try {
            val prefs = applicationContext.getSharedPreferences(WatchSessionManager.PREFS_NAME, Context.MODE_PRIVATE)
            smokes = prefs.getString(WatchSessionManager.KEY_SMOKES_TOTAL, "0") ?: "0"
        } catch (ignored: Exception) {}

        return ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder("🔥$smokes").build(),
            contentDescription = PlainComplicationText.Builder("Smokes Total").build()
        )
            .setTapAction(createTapAction())
            .build()
    }
}
