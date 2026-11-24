package com.intellidream.daily.glance

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.updateAll
import com.intellidream.daily.DailyApp
import com.intellidream.daily.model.SmokePreset
import com.intellidream.daily.model.WaterPreset
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

class LogWaterActionCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val amount = parameters[AmountKey] ?: 150.0
        val drink = parameters[DrinkKey] ?: "Water"

        val app = runCatching { DailyApp.instance }.getOrNull() ?: return
        val preset = when (drink.lowercase()) {
            "coffee" -> WaterPreset.COFFEE
            "tea" -> WaterPreset.TEA
            else -> if (amount >= 300.0) WaterPreset.LARGE_WATER else WaterPreset.SMALL_WATER
        }

        app.habitsRepository.logWaterAndPersist(
            preset = preset,
            customAmount = amount,
            notifyWidgets = false
        )

        WidgetUpdateHelper.updateHabitsWidgets(context, "water")
    }

    companion object {
        val AmountKey = ActionParameters.Key<Double>("amountMl")
        val DrinkKey = ActionParameters.Key<String>("drinkType")
    }
}

class LogSmokeActionCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val smokeType = parameters[SmokeTypeKey] ?: "Cig"

        val app = runCatching { DailyApp.instance }.getOrNull() ?: return
        val preset = when (smokeType.lowercase()) {
            "cgr", "cigarillo" -> SmokePreset.CIGARILLO
            "rol", "rolled" -> SmokePreset.ROLLED
            "heat", "heated" -> SmokePreset.HEATED
            else -> SmokePreset.CIGARETTE
        }

        app.habitsRepository.logSmokeAndPersist(
            preset = preset,
            notifyWidgets = false
        )

        WidgetUpdateHelper.updateHabitsWidgets(context, "smokes")
    }

    companion object {
        val SmokeTypeKey = ActionParameters.Key<String>("smokeType")
    }
}

class AdjustLedgerActionCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val account = parameters[AccountKey] ?: "Card"
        val delta = parameters[DeltaKey] ?: 100.0

        val app = runCatching { DailyApp.instance }.getOrNull() ?: return
        val parsed = app.smartLedgerRepository.parsedLedger.value

        // Look for liquid item matching name (Card or Cash)
        val allItems = parsed.sections.flatMap { it.items }
        val item = allItems.firstOrNull {
            it.displayName.contains(account, ignoreCase = true) || it.key.contains(account, ignoreCase = true)
        }

        if (item != null && item.lineIndex >= 0) {
            app.smartLedgerRepository.adjustItem(item.lineIndex, delta, notifyWidgets = false)
            WidgetUpdateHelper.updateFinanceWidgets(context)
        }
    }

    companion object {
        val AccountKey = ActionParameters.Key<String>("account")
        val DeltaKey = ActionParameters.Key<Double>("delta")
    }
}

class TagdosPillActionCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val streamId = parameters[StreamIdKey].orEmpty()
        val pillId = parameters[PillIdKey].orEmpty()
        val action = parameters[ActionKey] ?: "done"
        if (streamId.isBlank() || pillId.isBlank()) return

        val app = runCatching { DailyApp.instance }.getOrNull() ?: return
        if (action == "recycle") {
            app.tagdosRepository.recyclePillToBack(streamId, pillId, notifyWidgets = false)
        } else {
            app.tagdosRepository.togglePillCompletion(streamId, pillId, notifyWidgets = false)
        }
        WidgetUpdateHelper.updateTagdosWidgets(context)
    }

    companion object {
        val StreamIdKey = ActionParameters.Key<String>("streamId")
        val PillIdKey = ActionParameters.Key<String>("pillId")
        val ActionKey = ActionParameters.Key<String>("action")
    }
}

object WidgetUpdateHelper {
    suspend fun updateTagdosWidgets(context: Context) = coroutineScope {
        launch { runCatching { DailyTagdosGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyCombinedGlanceWidget().updateAll(context) } }
    }

    suspend fun updateHabitsWidgets(context: Context, habitType: String? = null) = coroutineScope {
        when (habitType) {
            "water" -> {
                launch { runCatching { DailyBubblesGlanceWidget().updateAll(context) } }
                launch { runCatching { DailyCombinedGlanceWidget().updateAll(context) } }
            }
            "smokes" -> {
                launch { runCatching { DailySmokesGlanceWidget().updateAll(context) } }
                launch { runCatching { DailyCombinedGlanceWidget().updateAll(context) } }
            }
            else -> {
                launch { runCatching { DailyBubblesGlanceWidget().updateAll(context) } }
                launch { runCatching { DailySmokesGlanceWidget().updateAll(context) } }
                launch { runCatching { DailyCombinedGlanceWidget().updateAll(context) } }
            }
        }
    }

    suspend fun updateHealthWidgets(context: Context) = coroutineScope {
        launch { runCatching { DailySleepGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyStressGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyCombinedGlanceWidget().updateAll(context) } }
    }

    suspend fun updateFinanceWidgets(context: Context) = coroutineScope {
        launch { runCatching { DailyMoneyGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyCombinedGlanceWidget().updateAll(context) } }
    }

    suspend fun updateCosmosWidgets(context: Context) = coroutineScope {
        launch { runCatching { DailyCosmosGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyCombinedGlanceWidget().updateAll(context) } }
    }

    suspend fun updateAllWidgets(context: Context) = coroutineScope {
        launch { runCatching { DailyBubblesGlanceWidget().updateAll(context) } }
        launch { runCatching { DailySmokesGlanceWidget().updateAll(context) } }
        launch { runCatching { DailySleepGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyStressGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyMoneyGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyTagdosGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyCosmosGlanceWidget().updateAll(context) } }
        launch { runCatching { DailyCombinedGlanceWidget().updateAll(context) } }
    }
}
