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

class SmokesComplicationService : SuspendingComplicationDataSourceService() {
    private fun createTapAction(): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("page", 1)
        }
        return PendingIntent.getActivity(
            applicationContext,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val tapAction = createTapAction()
        return when (type) {
            ComplicationType.SHORT_TEXT -> {
                ShortTextComplicationData.Builder(
                    text = PlainComplicationText.Builder("🔥3").build(),
                    contentDescription = PlainComplicationText.Builder("Smokes Total").build()
                )
                    .setTapAction(tapAction)
                    .build()
            }
            ComplicationType.RANGED_VALUE -> {
                RangedValueComplicationData.Builder(
                    value = 3f,
                    min = 0f,
                    max = 12f,
                    contentDescription = PlainComplicationText.Builder("Smokes Progress").build()
                )
                    .setText(PlainComplicationText.Builder("3").build())
                    .setTitle(PlainComplicationText.Builder("🔥").build())
                    .setTapAction(tapAction)
                    .build()
            }
            else -> null
        }
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        var smokes = 0
        var goal = 15
        try {
            val prefs = applicationContext.getSharedPreferences(WatchSessionManager.PREFS_NAME, Context.MODE_PRIVATE)
            smokes = (prefs.getString(WatchSessionManager.KEY_SMOKES_TOTAL, "0") ?: "0").toIntOrNull() ?: 0
            goal = prefs.getString(WatchSessionManager.KEY_SMOKES_GOAL, null)?.toIntOrNull() ?: 15
        } catch (ignored: Exception) {}

        val tapAction = createTapAction()
        return when (request.complicationType) {
            ComplicationType.SHORT_TEXT -> {
                ShortTextComplicationData.Builder(
                    text = PlainComplicationText.Builder("🔥$smokes").build(),
                    contentDescription = PlainComplicationText.Builder("Smokes Total").build()
                )
                    .setTapAction(tapAction)
                    .build()
            }
            ComplicationType.RANGED_VALUE -> {
                val safeGoal = maxOf(goal, 1).toFloat()
                RangedValueComplicationData.Builder(
                    value = smokes.toFloat().coerceAtLeast(0f),
                    min = 0f,
                    max = safeGoal,
                    contentDescription = PlainComplicationText.Builder("Smokes: $smokes / $goal max").build()
                )
                    .setText(PlainComplicationText.Builder("$smokes").build())
                    .setTitle(PlainComplicationText.Builder("🔥").build())
                    .setTapAction(tapAction)
                    .build()
            }
            else -> null
        }
    }
}
