package com.intellidream.daily.database

import com.intellidream.daily.database.dao.HabitLogDao
import com.intellidream.daily.database.entity.HabitLogEntity
import com.intellidream.daily.model.HabitConsistencyCell
import com.intellidream.daily.model.HabitDrinkBreakdown
import com.intellidream.daily.model.HabitLogRecord
import com.intellidream.daily.model.HabitTrendDay
import com.intellidream.daily.model.HabitType
import com.intellidream.daily.model.SmokePreset
import com.intellidream.daily.model.SmokesFinancialMetrics
import com.intellidream.daily.model.SmokesSettings
import com.intellidream.daily.model.WaterPreset
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID

interface HabitSyncHandler {
    suspend fun pushLog(log: HabitLogRecord): Boolean
    suspend fun pullLogsForDate(userId: String, startIso: String, endIso: String): List<HabitLogRecord>
    suspend fun pullUserPreferences(userId: String): com.intellidream.daily.model.UserPreferencesRecord?
    suspend fun pullGoals(userId: String): List<com.intellidream.daily.model.HabitGoalRecord>
    suspend fun deleteLog(logId: String): Boolean
}

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class HabitsRepository(
    private val dao: HabitLogDao,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) {
    var syncHandler: HabitSyncHandler? = null
    var currentUserId: String = "guest"

    // State
    private val _selectedDate = MutableStateFlow(getStartOfDay(System.currentTimeMillis()))
    val selectedDate: StateFlow<Long> = _selectedDate.asStateFlow()

    private val _activeHabit = MutableStateFlow(HabitType.WATER)
    val activeHabit: StateFlow<HabitType> = _activeHabit.asStateFlow()

    private val _waterGoal = MutableStateFlow(2000.0)
    val waterGoal: StateFlow<Double> = _waterGoal.asStateFlow()

    private val _smokesSettings = MutableStateFlow(SmokesSettings())
    val smokesSettings: StateFlow<SmokesSettings> = _smokesSettings.asStateFlow()

    // Logs for selected date (Bubbles)
    val selectedDateWaterLogs: StateFlow<List<HabitLogRecord>> = _selectedDate
        .flatMapLatest { dateMillis ->
            val start = getStartOfDay(dateMillis)
            val end = getEndOfDay(dateMillis)
            dao.getLogsForDate("water", start, end)
        }
        .combine(_selectedDate) { entities, _ ->
            entities.map { it.toRecord() }
        }
        .flowOn(Dispatchers.Default)
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    // Logs for selected date (Smokes)
    val selectedDateSmokesLogs: StateFlow<List<HabitLogRecord>> = _selectedDate
        .flatMapLatest { dateMillis ->
            val start = getStartOfDay(dateMillis)
            val end = getEndOfDay(dateMillis)
            dao.getLogsForDate("smokes", start, end)
        }
        .combine(_selectedDate) { entities, _ ->
            entities.map { it.toRecord() }
        }
        .flowOn(Dispatchers.Default)
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    // Today's total water (ml)
    val waterTotalToday: StateFlow<Double> = selectedDateWaterLogs
        .combine(_selectedDate) { logs, _ ->
            logs.sumOf { it.value }
        }
        .stateIn(scope, SharingStarted.Eagerly, 0.0)

    // Today's total smokes (count)
    val smokesTotalToday: StateFlow<Int> = selectedDateSmokesLogs
        .combine(_selectedDate) { logs, _ ->
            logs.sumOf { it.value.toInt() }
        }
        .stateIn(scope, SharingStarted.Eagerly, 0)

    // Water drink breakdown
    val waterDrinkBreakdown: StateFlow<List<HabitDrinkBreakdown>> = selectedDateWaterLogs
        .combine(waterTotalToday) { logs, total ->
            if (total <= 0.0 || logs.isEmpty()) {
                emptyList()
            } else {
                val groupMap = mutableMapOf<String, Double>()
                for (log in logs) {
                    val drink = log.drinkType
                    groupMap[drink] = (groupMap[drink] ?: 0.0) + log.value
                }
                groupMap.map { (drink, amt) ->
                    val pct = (amt / total) * 100.0
                    val lower = drink.lowercase(Locale.US)
                    val (hex, icon) = when {
                        lower.contains("coffee") || lower.contains("espresso") -> "#F59E0B" to "coffee"
                        lower.contains("tea") -> "#84CC16" to "emoji_food_beverage"
                        lower.contains("bottle") -> "#06B6D4" to "science"
                        else -> "#00E5FF" to "water_drop"
                    }
                    HabitDrinkBreakdown(
                        drink = drink,
                        amount = amt,
                        unit = "ml",
                        percentage = pct,
                        hexColor = hex,
                        iconName = icon
                    )
                }.sortedByDescending { it.amount }
            }
        }
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    // Smokes type breakdown
    val smokesTypeBreakdown: StateFlow<List<HabitDrinkBreakdown>> = selectedDateSmokesLogs
        .combine(smokesTotalToday) { logs, total ->
            if (total <= 0 || logs.isEmpty()) {
                emptyList()
            } else {
                val groupMap = mutableMapOf<String, Double>()
                for (log in logs) {
                    val type = log.smokeType
                    groupMap[type] = (groupMap[type] ?: 0.0) + log.value
                }
                groupMap.map { (type, count) ->
                    val pct = (count / total.toDouble()) * 100.0
                    val lower = type.lowercase(Locale.US)
                    val (hex, icon) = when {
                        lower.contains("heat") || lower.contains("vape") -> "#3B82F6" to "bolt"
                        lower.contains("roll") -> "#F97316" to "eco"
                        lower.contains("cigarillo") || (lower.contains("cigar") && !lower.contains("cigarette")) -> "#A855F7" to "local_fire_department"
                        else -> "#EF4444" to "local_fire_department"
                    }
                    HabitDrinkBreakdown(
                        drink = type,
                        amount = count,
                        unit = "cigs",
                        percentage = pct,
                        hexColor = hex,
                        iconName = icon
                    )
                }.sortedByDescending { it.amount }
            }
        }
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    // All active water logs (for 112-day heatmap and 7-day trend)
    private val allWaterLogs = dao.getAllActiveLogs("water")
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    // All active smokes logs (for 112-day heatmap, 7-day trend, and financials)
    private val allSmokesLogs = dao.getAllActiveLogs("smokes")
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    // 7-day trend history
    val waterSevenDayHistory: StateFlow<List<HabitTrendDay>> = combine(allWaterLogs, _waterGoal) { logs, goal ->
        calculateSevenDayHistory(logs, goal)
    }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    val smokesSevenDayHistory: StateFlow<List<HabitTrendDay>> = combine(allSmokesLogs, _smokesSettings) { logs, settings ->
        calculateSevenDayHistory(logs, settings.baselineDailyCount.toDouble(), isSmokes = true)
    }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    // 112-day consistency heatmap
    val waterConsistencyHeatmap: StateFlow<List<HabitConsistencyCell>> = combine(allWaterLogs, _waterGoal) { logs, goal ->
        calculateConsistencyHeatmap(logs, goal, isSmokes = false)
    }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    val smokesConsistencyHeatmap: StateFlow<List<HabitConsistencyCell>> = combine(allSmokesLogs, _smokesSettings) { logs, settings ->
        calculateConsistencyHeatmap(logs, settings.baselineDailyCount.toDouble(), isSmokes = true)
    }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    // Smokes financial metrics
    val smokesFinancials: StateFlow<SmokesFinancialMetrics> = combine(allSmokesLogs, _smokesSettings) { logs, settings ->
        calculateSmokesFinancials(logs, settings)
    }.stateIn(scope, SharingStarted.Eagerly, SmokesFinancialMetrics())

    // Convenience Navigation Getters
    fun isSelectedDateToday(): Boolean {
        val cal = Calendar.getInstance()
        val currentStart = getStartOfDay(System.currentTimeMillis())
        return _selectedDate.value == currentStart
    }

    fun getFormattedDateTitle(): String {
        val dateMillis = _selectedDate.value
        val todayStart = getStartOfDay(System.currentTimeMillis())
        val cal = Calendar.getInstance().apply { timeInMillis = todayStart; add(Calendar.DAY_OF_YEAR, -1) }
        val yesterdayStart = cal.timeInMillis

        return when (dateMillis) {
            todayStart -> "Today"
            yesterdayStart -> "Yesterday"
            else -> {
                val sdf = SimpleDateFormat("EEE, MMM d", Locale.US)
                sdf.format(Date(dateMillis))
            }
        }
    }

    fun syncLogs(userId: String = currentUserId, dateMillis: Long = _selectedDate.value) {
        scope.launch {
            val handler = syncHandler ?: return@launch
            val startIso = java.time.Instant.ofEpochMilli(getStartOfDay(dateMillis)).toString()
            val endIso = java.time.Instant.ofEpochMilli(getEndOfDay(dateMillis)).toString()

            // 1. Fetch user preferences if user is authenticated
            if (userId.isNotEmpty() && userId != "guest") {
                try {
                    val prefs = handler.pullUserPreferences(userId)
                    if (prefs != null) {
                        val wg = prefs.water_goal
                        if (wg != null && wg > 0) {
                            _waterGoal.value = wg
                        }
                        var newSettings = _smokesSettings.value
                        val baseline = prefs.smokes_baseline
                        if (baseline != null && baseline > 0) {
                            newSettings = newSettings.copy(baselineCigsPerDay = baseline)
                        }
                        val packSize = prefs.smokes_pack_size
                        if (packSize != null && packSize > 0) {
                            newSettings = newSettings.copy(cigsPerPack = packSize)
                        }
                        val packCost = prefs.smokes_pack_cost
                        if (packCost != null && packCost >= 0) {
                            newSettings = newSettings.copy(costPerPack = packCost)
                        }
                        val currency = prefs.smokes_currency
                        if (!currency.isNullOrEmpty()) {
                            newSettings = newSettings.copy(currency = currency)
                        }
                        val quitDate = prefs.smokes_quit_date
                        if (!quitDate.isNullOrEmpty()) {
                            val parsedQuit = try {
                                java.time.Instant.parse(quitDate).toEpochMilli()
                            } catch (_: Exception) {
                                try {
                                    java.time.LocalDate.parse(quitDate).atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
                                } catch (_: Exception) {
                                    null
                                }
                            }
                            if (parsedQuit != null) {
                                newSettings = newSettings.copy(quitStartDate = parsedQuit)
                            }
                        }
                        _smokesSettings.value = newSettings
                    }

                    val goals = handler.pullGoals(userId)
                    for (g in goals) {
                        if (g.habitType == "water" && g.targetValue > 0) {
                            _waterGoal.value = g.targetValue
                        }
                    }
                } catch (_: Exception) {}
            }

            // 2. Fetch logs for this date window
            try {
                val remoteLogs = handler.pullLogsForDate(userId, startIso, endIso)
                if (remoteLogs.isNotEmpty()) {
                    val locallyDeletedIds = dao.getDeletedLogIds().toSet()
                    val remoteDeletedLogs = remoteLogs.filter { it.isDeleted }
                    
                    // Synchronize remote tombstones to local database
                    for (del in remoteDeletedLogs) {
                        dao.softDelete(del.id)
                    }

                    // Insert active entities that are not locally deleted
                    val allDeletedIds = locallyDeletedIds + remoteDeletedLogs.map { it.id }.toSet()
                    val activeEntities = remoteLogs
                        .filter { !it.isDeleted && !allDeletedIds.contains(it.id) }
                        .map { HabitLogEntity.fromRecord(it, syncedAt = System.currentTimeMillis()) }
                    
                    if (activeEntities.isNotEmpty()) {
                        dao.insertAll(activeEntities)
                    }
                }
            } catch (_: Exception) {}
        }
    }

    // Navigation Actions
    fun switchHabit(type: HabitType) {
        _activeHabit.value = type
    }

    fun selectDate(timestampMillis: Long) {
        _selectedDate.value = getStartOfDay(timestampMillis)
        syncLogs(currentUserId, _selectedDate.value)
    }

    fun goToPreviousDay() {
        val cal = Calendar.getInstance().apply {
            timeInMillis = _selectedDate.value
            add(Calendar.DAY_OF_YEAR, -1)
        }
        _selectedDate.value = getStartOfDay(cal.timeInMillis)
        syncLogs(currentUserId, _selectedDate.value)
    }

    fun goToNextDay() {
        val cal = Calendar.getInstance().apply {
            timeInMillis = _selectedDate.value
            add(Calendar.DAY_OF_YEAR, 1)
        }
        _selectedDate.value = getStartOfDay(cal.timeInMillis)
        syncLogs(currentUserId, _selectedDate.value)
    }

    fun goToToday() {
        _selectedDate.value = getStartOfDay(System.currentTimeMillis())
        syncLogs(currentUserId, _selectedDate.value)
    }

    fun setWaterGoal(goal: Double) {
        _waterGoal.value = goal
    }

    fun updateSmokesSettings(settings: SmokesSettings) {
        _smokesSettings.value = settings
    }

    // Logging Actions
    fun logWater(preset: WaterPreset, multiplier: Int = 1, customAmount: Double? = null) {
        val safeMultiplier = multiplier.coerceAtLeast(1)
        val baseAmount = customAmount ?: preset.amountMl
        val totalAmount = baseAmount * safeMultiplier

        val metaJson = buildJsonObject {
            put("drink", preset.displayName)
            if (safeMultiplier > 1) {
                put("multiplier", safeMultiplier.toString())
                put("base_value", baseAmount.toString())
            }
        }.toString()

        val logTime = computeLogTimestamp()
        val record = HabitLogRecord(
            id = UUID.randomUUID().toString(),
            userId = if (currentUserId != "guest") currentUserId else null,
            habitType = "water",
            value = totalAmount,
            unit = "ml",
            loggedAt = logTime,
            metadata = metaJson
        )

        scope.launch {
            dao.insert(HabitLogEntity.fromRecord(record))
            syncHandler?.pushLog(record)
        }
    }

    fun logSmoke(preset: SmokePreset, multiplier: Int = 1, customCount: Int? = null) {
        val safeMultiplier = multiplier.coerceAtLeast(1)
        val baseCount = customCount ?: preset.count
        val totalCount = baseCount * safeMultiplier

        val metaJson = buildJsonObject {
            put("type", preset.displayName)
            if (safeMultiplier > 1) {
                put("multiplier", safeMultiplier.toString())
                put("base_value", baseCount.toString())
            }
        }.toString()

        val logTime = computeLogTimestamp()
        val record = HabitLogRecord(
            id = UUID.randomUUID().toString(),
            userId = if (currentUserId != "guest") currentUserId else null,
            habitType = "smokes",
            value = totalCount.toDouble(),
            unit = "cigs",
            loggedAt = logTime,
            metadata = metaJson
        )

        scope.launch {
            dao.insert(HabitLogEntity.fromRecord(record))
            syncHandler?.pushLog(record)
        }
    }

    fun deleteLog(id: String) {
        scope.launch {
            dao.softDelete(id)
            syncHandler?.deleteLog(id)
        }
    }

    // Computes the timestamp for the log, preserving past date if navigated to past
    private fun computeLogTimestamp(): Long {
        val isToday = isSelectedDateToday()
        return if (isToday) {
            System.currentTimeMillis()
        } else {
            val nowCal = Calendar.getInstance()
            val targetCal = Calendar.getInstance().apply {
                timeInMillis = _selectedDate.value
                set(Calendar.HOUR_OF_DAY, nowCal.get(Calendar.HOUR_OF_DAY))
                set(Calendar.MINUTE, nowCal.get(Calendar.MINUTE))
                set(Calendar.SECOND, nowCal.get(Calendar.SECOND))
            }
            targetCal.timeInMillis
        }
    }

    // MARK: - Calculation Helpers

    private fun calculateSevenDayHistory(
        entities: List<HabitLogEntity>,
        goal: Double,
        isSmokes: Boolean = false
    ): List<HabitTrendDay> {
        val sdfKey = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val sdfLabel = SimpleDateFormat("EEE", Locale.US)
        val map = mutableMapOf<String, Double>()

        for (e in entities) {
            val key = sdfKey.format(Date(e.loggedAt))
            map[key] = (map[key] ?: 0.0) + e.value
        }

        val result = mutableListOf<HabitTrendDay>()
        val cal = Calendar.getInstance()

        // 7 days ending today
        for (i in 6 downTo 0) {
            val loopCal = Calendar.getInstance().apply {
                timeInMillis = cal.timeInMillis
                add(Calendar.DAY_OF_YEAR, -i)
            }
            val key = sdfKey.format(loopCal.time)
            val label = sdfLabel.format(loopCal.time)
            val value = map[key] ?: 0.0
            val met = if (isSmokes) value <= goal else value >= goal

            result.add(
                HabitTrendDay(
                    date = loopCal.timeInMillis,
                    dayLabel = label,
                    value = value,
                    goal = goal,
                    isGoalMet = met
                )
            )
        }
        return result
    }

    private fun calculateConsistencyHeatmap(
        entities: List<HabitLogEntity>,
        goal: Double,
        isSmokes: Boolean = false
    ): List<HabitConsistencyCell> {
        val sdfKey = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val sdfTooltip = SimpleDateFormat("MMM d, yyyy", Locale.US)
        val map = mutableMapOf<String, Double>()

        for (e in entities) {
            val key = sdfKey.format(Date(e.loggedAt))
            map[key] = (map[key] ?: 0.0) + e.value
        }

        val cells = mutableListOf<HabitConsistencyCell>()
        val totalDays = 112 // 16 weeks

        for (i in (totalDays - 1) downTo 0) {
            val loopCal = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -i)
            }
            val dateKey = sdfKey.format(loopCal.time)
            val tooltipDate = sdfTooltip.format(loopCal.time)
            val value = map[dateKey] ?: 0.0

            val intensity = if (isSmokes) {
                when {
                    value == 0.0 -> 4 // Smoke-free max positive intensity
                    value <= goal * 0.5 -> 3
                    value <= goal -> 2
                    value <= goal * 1.5 -> 1
                    else -> 0
                }
            } else {
                when {
                    value <= 0.0 -> 0
                    value < goal * 0.4 -> 1
                    value < goal * 0.75 -> 2
                    value < goal -> 3
                    else -> 4
                }
            }

            val isGoalMet = if (isSmokes) value <= goal else value >= goal
            val tooltip = "$tooltipDate: ${value.toInt()} ${if (isSmokes) "cigs" else "ml"}"

            cells.add(
                HabitConsistencyCell(
                    date = loopCal.timeInMillis,
                    dateKey = dateKey,
                    value = value,
                    intensityLevel = intensity,
                    tooltip = tooltip,
                    isGoalMet = isGoalMet
                )
            )
        }
        return cells
    }

    private fun calculateSmokesFinancials(
        entities: List<HabitLogEntity>,
        settings: SmokesSettings
    ): SmokesFinancialMetrics {
        val now = System.currentTimeMillis()
        val startDate = settings.quitStartDate.coerceAtMost(now)
        val daysTracked = ((now - startDate) / (1000L * 60 * 60 * 24)).toInt().coerceAtLeast(1)

        val totalExpectedCigs = daysTracked * settings.baselineDailyCount
        val totalSmoked = entities.sumOf { it.value }.toInt()
        val cigsAvoided = (totalExpectedCigs - totalSmoked).coerceAtLeast(0)
        val costPerCig = settings.costPerCig
        val moneySaved = cigsAvoided * costPerCig

        val latestSmoke = entities.maxByOrNull { it.loggedAt }
        val lastSmokeTime = latestSmoke?.loggedAt
        val timeSince = lastSmokeTime?.let { (now - it).coerceAtLeast(0L) }
        val lastSmokeType = latestSmoke?.metadata?.let { meta ->
            try {
                if (meta.startsWith("{")) {
                    org.json.JSONObject(meta).optString("preset", meta)
                } else meta
            } catch (_: Exception) {
                meta
            }
        }

        return SmokesFinancialMetrics(
            moneySaved = moneySaved,
            cigsAvoided = cigsAvoided,
            daysTracked = daysTracked,
            costPerCig = costPerCig,
            currency = settings.currency,
            lastSmokeDate = lastSmokeTime,
            timeSinceLastSmokeMillis = timeSince,
            lastSmokeType = lastSmokeType
        )
    }

    companion object {
        fun getStartOfDay(timeMillis: Long): Long {
            return Calendar.getInstance().apply {
                timeInMillis = timeMillis
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
        }

        fun getEndOfDay(timeMillis: Long): Long {
            return Calendar.getInstance().apply {
                timeInMillis = timeMillis
                set(Calendar.HOUR_OF_DAY, 23)
                set(Calendar.MINUTE, 59)
                set(Calendar.SECOND, 59)
                set(Calendar.MILLISECOND, 999)
            }.timeInMillis
        }
    }
}
