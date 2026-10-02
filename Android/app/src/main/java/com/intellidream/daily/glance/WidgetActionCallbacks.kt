package com.intellidream.daily.glance

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.updateAll
import com.intellidream.daily.DailyApp
import com.intellidream.daily.model.SmokePreset
import com.intellidream.daily.model.WaterPreset

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

        app.habitsRepository.logWater(preset = preset, customAmount = amount)

        runCatching { DailyBubblesGlanceWidget().updateAll(context) }
        runCatching { DailyCombinedGlanceWidget().updateAll(context) }
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

        app.habitsRepository.logSmoke(preset = preset)

        runCatching { DailySmokesGlanceWidget().updateAll(context) }
        runCatching { DailyCombinedGlanceWidget().updateAll(context) }
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
            app.smartLedgerRepository.adjustItem(item.lineIndex, delta)
            runCatching { DailyMoneyGlanceWidget().updateAll(context) }
            runCatching { DailyCombinedGlanceWidget().updateAll(context) }
        }
    }

    companion object {
        val AccountKey = ActionParameters.Key<String>("account")
        val DeltaKey = ActionParameters.Key<Double>("delta")
    }
}
