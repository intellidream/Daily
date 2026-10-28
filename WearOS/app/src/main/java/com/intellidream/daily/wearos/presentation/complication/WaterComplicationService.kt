package com.intellidream.daily.wearos.presentation.complication

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.intellidream.daily.wearos.data.WatchSessionManager
import com.intellidream.daily.wearos.presentation.MainActivity

class WaterComplicationService : SuspendingComplicationDataSourceService() {
    private fun createTapAction(): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("page", 0)
        }
        return PendingIntent.getActivity(
            applicationContext,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val tapAction = createTapAction()
        return when (type) {
            ComplicationType.SHORT_TEXT -> {
                ShortTextComplicationData.Builder(
                    text = PlainComplicationText.Builder("💧1250").build(),
                    contentDescription = PlainComplicationText.Builder("Water Total").build()
                )
                    .setTapAction(tapAction)
                    .build()
            }
            ComplicationType.RANGED_VALUE -> {
                RangedValueComplicationData.Builder(
                    value = 1250f,
                    min = 0f,
                    max = 2500f,
                    contentDescription = PlainComplicationText.Builder("Water Progress").build()
                )
                    .setText(PlainComplicationText.Builder("1250").build())
                    .setTitle(PlainComplicationText.Builder("💧").build())
                    .setTapAction(tapAction)
                    .build()
            }
            else -> null
        }
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        var water = 0
        var goal = 2500
        try {
            val prefs = applicationContext.getSharedPreferences(WatchSessionManager.PREFS_NAME, Context.MODE_PRIVATE)
            water = (prefs.getString(WatchSessionManager.KEY_WATER_TOTAL, "0") ?: "0").toIntOrNull() ?: 0
            goal = prefs.getString(WatchSessionManager.KEY_WATER_GOAL, null)?.toIntOrNull() ?: 2000
        } catch (ignored: Exception) {}

        val tapAction = createTapAction()
        return when (request.complicationType) {
            ComplicationType.SHORT_TEXT -> {
                ShortTextComplicationData.Builder(
                    text = PlainComplicationText.Builder("💧$water").build(),
                    contentDescription = PlainComplicationText.Builder("Water Total").build()
                )
                    .setTapAction(tapAction)
                    .build()
            }
            ComplicationType.RANGED_VALUE -> {
                val safeGoal = maxOf(goal, 1).toFloat()
                RangedValueComplicationData.Builder(
                    value = water.toFloat().coerceAtLeast(0f),
                    min = 0f,
                    max = safeGoal,
                    contentDescription = PlainComplicationText.Builder("Water: $water / $goal ml").build()
                )
                    .setText(PlainComplicationText.Builder("$water").build())
                    .setTitle(PlainComplicationText.Builder("💧").build())
                    .setTapAction(tapAction)
                    .build()
            }
            else -> null
        }
    }
}
