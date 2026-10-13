package com.intellidream.daily.wearos.data

import android.content.Context
import com.intellidream.daily.wearos.domain.model.PairedWatch
import com.intellidream.daily.wearos.domain.model.WatchPairing
import com.intellidream.daily.wearos.domain.model.WatchPairingInsert
import com.intellidream.daily.wearos.domain.model.HabitLog
import com.intellidream.daily.wearos.domain.model.WaterDayBucket
import com.intellidream.daily.wearos.domain.model.SmokeDayBucket
import java.util.concurrent.ConcurrentHashMap
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.user.UserSession
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.http.contentType
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Calendar
import kotlinx.coroutines.async
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import com.intellidream.daily.wearos.domain.util.HabitDateParser
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

class WatchSessionManager private constructor(private val context: Context) {

    companion object {
        const val PREFS_NAME = "daily_prefs"
        const val KEY_ACCESS_TOKEN = "supabase_access_token"
        const val KEY_REFRESH_TOKEN = "supabase_refresh_token"
        const val KEY_USER_ID = "supabase_user_id"
        const val KEY_PAIRED_WATCH_ID = "paired_watch_id"
        const val KEY_WATER_TOTAL = "daily_water_total"
        const val KEY_SMOKES_TOTAL = "daily_smokes_total"
        const val KEY_WATER_GOAL = "water_goal"
        const val KEY_SMOKES_GOAL = "smokes_goal"
        const val KEY_LAST_HEALTH_SYNC = "last_health_sync_time"
        const val KEY_LAST_HEALTH_SYNC_STATUS = "last_health_sync_status"
        const val KEY_BUBBLES_DAY_CACHE = "bubbles_day_cache"
        const val KEY_SMOKES_DAY_CACHE = "smokes_day_cache"
        const val KEY_BUBBLES_WEEK_CACHE = "bubbles_week_cache"
        const val KEY_SMOKES_WEEK_CACHE = "smokes_week_cache"
        const val KEY_LAST_HABITS_SYNC = "last_habits_sync_time"

        @Volatile
        private var instance: WatchSessionManager? = null

        fun getInstance(context: Context): WatchSessionManager {
            return instance ?: synchronized(this) {
                instance ?: WatchSessionManager(context.applicationContext).also {
                    instance = it
                    it.initCachesFromDisk()
                    it.initBackgroundServices()
                }
            }
        }
    }

    private val prefs by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val supabaseUrl = "https://akkfouifxztnfwwiclwg.supabase.co"
    private val supabaseAnonKey = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"

    val supabaseClient: SupabaseClient by lazy {
        createSupabaseClient(supabaseUrl, supabaseAnonKey) {
            install(Auth) {
                alwaysAutoRefresh = false
            }
            install(Postgrest)
        }
    }

    private val _isAuthenticated = MutableStateFlow(
        !prefs.getString(KEY_ACCESS_TOKEN, null).isNullOrEmpty() &&
        !prefs.getString(KEY_USER_ID, null).isNullOrEmpty()
    )
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated

    private val _pairingCode = MutableStateFlow("")
    val pairingCode: StateFlow<String> = _pairingCode

    private val _isPairing = MutableStateFlow(false)
    val isPairing: StateFlow<Boolean> = _isPairing

    private val _errorMessage = MutableStateFlow("")
    val errorMessage: StateFlow<String> = _errorMessage
    
    private val _currentUserId = MutableStateFlow<String?>(
        prefs.getString(KEY_USER_ID, null)
    )
    val currentUserId: StateFlow<String?> = _currentUserId

    // Reactive persistent goals (backed by SharedPreferences with immediate 0ms availability)
    private val _bubblesGoal = MutableStateFlow(
        prefs.getString(KEY_WATER_GOAL, null)?.toIntOrNull() ?: 2000
    )
    val bubblesGoal: StateFlow<Int> = _bubblesGoal

    private val _smokesGoal = MutableStateFlow(
        prefs.getString(KEY_SMOKES_GOAL, null)?.toIntOrNull() ?: 40
    )
    val smokesGoal: StateFlow<Int> = _smokesGoal

    fun setBubblesGoal(goal: Int) {
        if (goal > 0 && _bubblesGoal.value != goal) {
            _bubblesGoal.value = goal
            prefs.edit().putString(KEY_WATER_GOAL, goal.toString()).apply()
        }
    }

    fun setSmokesGoal(goal: Int) {
        if (goal > 0 && _smokesGoal.value != goal) {
            _smokesGoal.value = goal
            prefs.edit().putString(KEY_SMOKES_GOAL, goal.toString()).apply()
        }
    }

    var cachedBubblesGoal: Int?
        get() = _bubblesGoal.value
        set(value) { if (value != null) setBubblesGoal(value) }

    var cachedSmokesGoal: Int?
        get() = _smokesGoal.value
        set(value) { if (value != null) setSmokesGoal(value) }

    var cachedBubblesLogs: List<HabitLog>? = null
    var cachedSmokesLogs: List<HabitLog>? = null

    // Multi-day in-memory caching keyed by date string (e.g. "2026-09-09")
    val bubblesDayCache = ConcurrentHashMap<String, List<HabitLog>>()
    val smokesDayCache = ConcurrentHashMap<String, List<HabitLog>>()

    // Weekly bucket in-memory caching keyed by weekOffset (0 = This Week, -1 = Last Week)
    val bubblesWeekCache = ConcurrentHashMap<Int, List<WaterDayBucket>>()
    val smokesWeekCache = ConcurrentHashMap<Int, List<SmokeDayBucket>>()

    private val json = Json { ignoreUnknownKeys = true }

    fun initCachesFromDisk() {
        try {
            val bDayJson = prefs.getString(KEY_BUBBLES_DAY_CACHE, null)
            if (!bDayJson.isNullOrEmpty()) {
                val map = json.decodeFromString<Map<String, List<HabitLog>>>(bDayJson)
                bubblesDayCache.putAll(map)
            }
        } catch (e: Exception) {
            android.util.Log.w("WatchSessionManager", "Failed to load bubblesDayCache from disk: ${e.message}")
        }

        try {
            val sDayJson = prefs.getString(KEY_SMOKES_DAY_CACHE, null)
            if (!sDayJson.isNullOrEmpty()) {
                val map = json.decodeFromString<Map<String, List<HabitLog>>>(sDayJson)
                smokesDayCache.putAll(map)
            }
        } catch (e: Exception) {
            android.util.Log.w("WatchSessionManager", "Failed to load smokesDayCache from disk: ${e.message}")
        }

        try {
            val bWeekJson = prefs.getString(KEY_BUBBLES_WEEK_CACHE, null)
            if (!bWeekJson.isNullOrEmpty()) {
                val map = json.decodeFromString<Map<String, List<WaterDayBucket>>>(bWeekJson)
                for ((k, v) in map) {
                    k.toIntOrNull()?.let { bubblesWeekCache[it] = v }
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("WatchSessionManager", "Failed to load bubblesWeekCache from disk: ${e.message}")
        }

        try {
            val sWeekJson = prefs.getString(KEY_SMOKES_WEEK_CACHE, null)
            if (!sWeekJson.isNullOrEmpty()) {
                val map = json.decodeFromString<Map<String, List<SmokeDayBucket>>>(sWeekJson)
                for ((k, v) in map) {
                    k.toIntOrNull()?.let { smokesWeekCache[it] = v }
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("WatchSessionManager", "Failed to load smokesWeekCache from disk: ${e.message}")
        }

        val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        cachedBubblesLogs = bubblesDayCache[todayStr]
        cachedSmokesLogs = smokesDayCache[todayStr]
    }

    fun saveCachesToDisk() {
        scope.launch {
            try {
                val bDayJson = json.encodeToString(bubblesDayCache.toMap())
                val sDayJson = json.encodeToString(smokesDayCache.toMap())
                val bWeekMap = bubblesWeekCache.mapKeys { it.key.toString() }
                val sWeekMap = smokesWeekCache.mapKeys { it.key.toString() }
                val bWeekJson = json.encodeToString(bWeekMap)
                val sWeekJson = json.encodeToString(sWeekMap)

                prefs.edit()
                    .putString(KEY_BUBBLES_DAY_CACHE, bDayJson)
                    .putString(KEY_SMOKES_DAY_CACHE, sDayJson)
                    .putString(KEY_BUBBLES_WEEK_CACHE, bWeekJson)
                    .putString(KEY_SMOKES_WEEK_CACHE, sWeekJson)
                    .apply()
            } catch (e: Exception) {
                android.util.Log.w("WatchSessionManager", "Failed to save caches to disk: ${e.message}")
            }
        }
    }

    fun getBubblesLogs(dateStr: String): List<HabitLog>? = bubblesDayCache[dateStr]

    fun setBubblesLogs(dateStr: String, logs: List<HabitLog>) {
        bubblesDayCache[dateStr] = logs
        val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        if (dateStr == todayStr) {
            cachedBubblesLogs = logs
        }
        saveCachesToDisk()
    }

    fun getSmokesLogs(dateStr: String): List<HabitLog>? = smokesDayCache[dateStr]

    fun setSmokesLogs(dateStr: String, logs: List<HabitLog>) {
        smokesDayCache[dateStr] = logs
        val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        if (dateStr == todayStr) {
            cachedSmokesLogs = logs
        }
        saveCachesToDisk()
    }

    fun getBubblesWeek(weekOffset: Int): List<WaterDayBucket>? = bubblesWeekCache[weekOffset]

    fun setBubblesWeek(weekOffset: Int, buckets: List<WaterDayBucket>) {
        bubblesWeekCache[weekOffset] = buckets
        saveCachesToDisk()
    }

    fun getSmokesWeek(weekOffset: Int): List<SmokeDayBucket>? = smokesWeekCache[weekOffset]

    fun setSmokesWeek(weekOffset: Int, buckets: List<SmokeDayBucket>) {
        smokesWeekCache[weekOffset] = buckets
        saveCachesToDisk()
    }

    fun updateBubblesWeekToday(isCoffee: Boolean, delta: Double) {
        bubblesWeekCache[0]?.find { it.isToday }?.let { bucket ->
            if (isCoffee) bucket.coffee = maxOf(0.0, bucket.coffee + delta)
            else bucket.water = maxOf(0.0, bucket.water + delta)
        }
        saveCachesToDisk()
    }

    fun updateSmokesWeekToday(isHeated: Boolean, delta: Double) {
        smokesWeekCache[0]?.find { it.isToday }?.let { bucket ->
            if (isHeated) bucket.heat = maxOf(0.0, bucket.heat + delta)
            else bucket.cig = maxOf(0.0, bucket.cig + delta)
        }
        saveCachesToDisk()
    }

    fun getWeekWindow(offset: Int): Pair<Calendar, Calendar> {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)

        val dayOfWeek = cal.get(Calendar.DAY_OF_WEEK)
        val daysFromMonday = if (dayOfWeek == Calendar.SUNDAY) 6 else dayOfWeek - Calendar.MONDAY
        cal.add(Calendar.DAY_OF_YEAR, -daysFromMonday + offset * 7)

        val monday = cal.clone() as Calendar
        val nextMonday = cal.clone() as Calendar
        nextMonday.add(Calendar.DAY_OF_YEAR, 7)
        return Pair(monday, nextMonday)
    }

    @Volatile private var isSyncingHabits = false

    fun triggerHabitsSync(force: Boolean = false) {
        scope.launch {
            syncAllHabits(force)
        }
    }

    suspend fun syncAllHabits(force: Boolean = false) {
        val uid = _currentUserId.value ?: return
        val lastSync = prefs.getLong(KEY_LAST_HABITS_SYNC, 0L)
        val now = System.currentTimeMillis()
        if (!force && now - lastSync < 60_000L) {
            return
        }
        if (isSyncingHabits) return
        isSyncingHabits = true

        withContext(Dispatchers.IO) {
            try {
                val cal = Calendar.getInstance()
                cal.set(Calendar.HOUR_OF_DAY, 0)
                cal.set(Calendar.MINUTE, 0)
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)

                val startCal = cal.clone() as Calendar
                startCal.add(Calendar.DAY_OF_YEAR, -15)
                val startStr = Instant.ofEpochMilli(startCal.timeInMillis).toString()

                val endCal = cal.clone() as Calendar
                endCal.add(Calendar.DAY_OF_YEAR, 2)
                val endStr = Instant.ofEpochMilli(endCal.timeInMillis).toString()

                val waterDeferred = async {
                    try {
                        supabaseClient.postgrest["habits_logs"]
                            .select {
                                filter {
                                    eq("habit_type", "water")
                                    eq("is_deleted", false)
                                    and {
                                        gte("logged_at", startStr)
                                        lt("logged_at", endStr)
                                    }
                                }
                            }.decodeList<HabitLog>().sortedByDescending { it.logged_at }
                    } catch (e: Exception) {
                        if (e is kotlinx.coroutines.CancellationException) throw e
                        android.util.Log.w("WatchSessionManager", "Water sync fetch failed: ${e.message}")
                        null
                    }
                }

                val smokesDeferred = async {
                    try {
                        supabaseClient.postgrest["habits_logs"]
                            .select {
                                filter {
                                    or {
                                        eq("habit_type", "smokes")
                                        eq("habit_type", "smoke")
                                    }
                                    eq("is_deleted", false)
                                    and {
                                        gte("logged_at", startStr)
                                        lt("logged_at", endStr)
                                    }
                                }
                            }.decodeList<HabitLog>().sortedByDescending { it.logged_at }
                    } catch (e: Exception) {
                        if (e is kotlinx.coroutines.CancellationException) throw e
                        android.util.Log.w("WatchSessionManager", "Smokes sync fetch failed: ${e.message}")
                        null
                    }
                }

                val waterLogs = waterDeferred.await()
                val smokesLogs = smokesDeferred.await()

                val localDateFmt = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
                val dayLabelFmt = SimpleDateFormat("EEE", Locale.getDefault())
                val todayDateStr = localDateFmt.format(Date())

                if (waterLogs != null) {
                    val waterGrouped = mutableMapOf<String, MutableList<HabitLog>>()
                    for (log in waterLogs) {
                        val dStr = HabitDateParser.parseToLocalDate(log.logged_at)?.toString()
                        if (dStr != null) {
                            waterGrouped.getOrPut(dStr) { mutableListOf() }.add(log)
                        }
                    }
                    for ((dStr, list) in waterGrouped) {
                        bubblesDayCache[dStr] = list
                    }
                    val todayWaterLogs = waterGrouped[todayDateStr] ?: emptyList()
                    cachedBubblesLogs = todayWaterLogs
                    var tW = 0
                    var tC = 0
                    for (log in todayWaterLogs) {
                        if (log.metadata?.contains("Coffee") == true) tC += log.value.toInt() else tW += log.value.toInt()
                    }
                    persistWaterTotal(tW + tC)

                    for (offset in listOf(0, -1)) {
                        val (monCal, _) = getWeekWindow(offset)
                        val buckets = mutableListOf<WaterDayBucket>()
                        for (i in 0 until 7) {
                            val dCal = monCal.clone() as Calendar
                            dCal.add(Calendar.DAY_OF_YEAR, i)
                            val dStr = localDateFmt.format(dCal.time)
                            val lbl = dayLabelFmt.format(dCal.time).take(1)
                            val bucket = WaterDayBucket(dStr, lbl, dStr == todayDateStr)
                            val dayLogsForDate = waterGrouped[dStr] ?: emptyList()
                            for (log in dayLogsForDate) {
                                val isCoffee = log.metadata?.contains("Coffee", ignoreCase = true) == true
                                if (isCoffee) bucket.coffee += log.value else bucket.water += log.value
                            }
                            buckets.add(bucket)
                        }
                        bubblesWeekCache[offset] = buckets
                    }
                }

                if (smokesLogs != null) {
                    val smokesGrouped = mutableMapOf<String, MutableList<HabitLog>>()
                    for (log in smokesLogs) {
                        val dStr = HabitDateParser.parseToLocalDate(log.logged_at)?.toString()
                        if (dStr != null) {
                            smokesGrouped.getOrPut(dStr) { mutableListOf() }.add(log)
                        }
                    }
                    for ((dStr, list) in smokesGrouped) {
                        smokesDayCache[dStr] = list
                    }
                    val todaySmokesLogs = smokesGrouped[todayDateStr] ?: emptyList()
                    cachedSmokesLogs = todaySmokesLogs
                    var tCig = 0
                    var tHeat = 0
                    for (log in todaySmokesLogs) {
                        val count = maxOf(1, log.value.toInt())
                        if (log.metadata?.contains("Heated") == true) tHeat += count else tCig += count
                    }
                    persistSmokesTotal(tCig + tHeat)

                    for (offset in listOf(0, -1)) {
                        val (monCal, _) = getWeekWindow(offset)
                        val buckets = mutableListOf<SmokeDayBucket>()
                        for (i in 0 until 7) {
                            val dCal = monCal.clone() as Calendar
                            dCal.add(Calendar.DAY_OF_YEAR, i)
                            val dStr = localDateFmt.format(dCal.time)
                            val lbl = dayLabelFmt.format(dCal.time).take(1)
                            val bucket = SmokeDayBucket(dStr, lbl, dStr == todayDateStr)
                            val dayLogsForDate = smokesGrouped[dStr] ?: emptyList()
                            for (log in dayLogsForDate) {
                                val isHeated = log.metadata?.contains("Heated", ignoreCase = true) == true
                                val count = maxOf(1.0, log.value)
                                if (isHeated) bucket.heat += count else bucket.cig += count
                            }
                            buckets.add(bucket)
                        }
                        smokesWeekCache[offset] = buckets
                    }
                }

                saveCachesToDisk()
                prefs.edit().putLong(KEY_LAST_HABITS_SYNC, System.currentTimeMillis()).apply()

                _dataRefreshTrigger.value++
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e("WatchSessionManager", "syncAllHabits error: ${e.message}", e)
            } finally {
                isSyncingHabits = false
            }
        }
    }

    // Bumped on every resume to tell screens to re-fetch data
    private val _dataRefreshTrigger = MutableStateFlow(0)
    val dataRefreshTrigger: StateFlow<Int> = _dataRefreshTrigger

    fun recordHealthSync(status: String = "synced") {
        val now = System.currentTimeMillis()
        prefs.edit()
            .putString(KEY_LAST_HEALTH_SYNC, now.toString())
            .putString(KEY_LAST_HEALTH_SYNC_STATUS, status)
            .apply()
    }

    fun recordHealthSyncNoNewData() {
        prefs.edit().putString(KEY_LAST_HEALTH_SYNC_STATUS, "no_new_data").apply()
    }

    fun persistWaterTotal(water: Int) {
        prefs.edit().putString(KEY_WATER_TOTAL, water.toString()).apply()
    }

    fun persistSmokesTotal(smokes: Int) {
        prefs.edit().putString(KEY_SMOKES_TOTAL, smokes.toString()).apply()
    }

    @Volatile private var pollJob: Job? = null
    @Volatile private var isPolling = false
    @Volatile private var isPairingCompleted = false
    private val scope = CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.IO)
    @Volatile private var isRecovering = false
    @Volatile private var isCheckingSession = false

    /**
     * Imports a 10-year Orbit watch JWT session into the Supabase Auth client.
     * We set expiresIn to 10 years (315360000L seconds) so supabase-kt never considers
     * the token expired and PostgREST always attaches the Bearer token to requests.
     */
    suspend fun importOrbitSession(accessToken: String, refreshToken: String = "") {
        try {
            val session = UserSession(
                accessToken = accessToken,
                refreshToken = refreshToken,
                expiresIn = 315360000L,
                tokenType = "bearer",
                user = null
            )
            supabaseClient.auth.importSession(session, autoRefresh = false)
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            android.util.Log.w("WatchSessionManager", "importOrbitSession non-fatal: ${e.localizedMessage}")
        }
    }

    fun initBackgroundServices() {
        startSessionListener()
        checkExistingSession()
    }

    /**
     * Listens to the Supabase Auth plugin's session status. When the plugin auto-refreshes
     * tokens (e.g. before access-token expiry), the NEW tokens are persisted to DataStore
     * so we never have stale credentials on disk.
     */
    private fun startSessionListener() {
        scope.launch {
            supabaseClient.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        val session = status.session
                        val uid = session.user?.id ?: extractUserId(session.accessToken)
                        prefs.edit()
                            .putString(KEY_ACCESS_TOKEN, session.accessToken)
                            .putString(KEY_REFRESH_TOKEN, session.refreshToken)
                            .apply()
                        if (uid != null) {
                            prefs.edit().putString(KEY_USER_ID, uid).apply()
                            _currentUserId.value = uid
                            fetchGoalsAndPreferences(uid)
                        }
                        _isAuthenticated.value = true
                        _isPairing.value = false
                    }
                    is SessionStatus.NotAuthenticated -> {
                        // Attempt recovery from SharedPreferences tokens regardless of current auth state.
                        if (!isRecovering) {
                            val savedUserId = prefs.getString(KEY_USER_ID, null)
                            if (!savedUserId.isNullOrEmpty()) {
                                val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null)
                                val refreshToken = prefs.getString(KEY_REFRESH_TOKEN, "") ?: ""
                                if (!accessToken.isNullOrEmpty()) {
                                    isRecovering = true
                                    try {
                                        importOrbitSession(accessToken, refreshToken)
                                    } catch (e: Exception) {
                                        if (e is kotlinx.coroutines.CancellationException) throw e
                                    } finally {
                                        isRecovering = false
                                    }
                                    _currentUserId.value = savedUserId
                                    _isAuthenticated.value = true
                                    _isPairing.value = false
                                    fetchGoalsAndPreferences(savedUserId)
                                }
                            } else if (_isAuthenticated.value) {
                                // No stored user — truly logged out
                                _isAuthenticated.value = false
                                _currentUserId.value = null
                            }
                        }
                    }
                    else -> { /* LoadingFromStorage, NetworkError — no action */ }
                }
            }
        }
    }

    private var lastGoalsSyncTime = 0L
    private val GOALS_SYNC_COOLDOWN_MS = 60_000L

    fun fetchGoalsAndPreferences(userId: String, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastGoalsSyncTime < GOALS_SYNC_COOLDOWN_MS) {
            return
        }
        lastGoalsSyncTime = now
        scope.launch {
            withContext(Dispatchers.IO) {
                try {
                    // 1. Fetch user_preferences for smokes_baseline
                    val prefsList = supabaseClient.postgrest["user_preferences"]
                        .select {
                            filter { eq("id", userId) }
                        }.decodeList<com.intellidream.daily.wearos.domain.model.UserPreference>()

                    if (prefsList.isNotEmpty()) {
                        val base = prefsList.first().smokes_baseline
                        if (base != null && base > 0) {
                            setSmokesGoal(base)
                        }
                    }
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    android.util.Log.w("WatchSessionManager", "fetchGoalsAndPreferences prefs: ${e.message}")
                }

                try {
                    // 2. Fetch habits_goals for water
                    val goals = supabaseClient.postgrest["habits_goals"]
                        .select {
                            filter {
                                eq("user_id", userId)
                                eq("is_deleted", false)
                            }
                        }.decodeList<com.intellidream.daily.wearos.domain.model.HabitGoal>()

                    for (g in goals) {
                        if (g.habit_type == "water" && (g.target_value ?: 0.0) > 0) {
                            setBubblesGoal(g.target_value!!.toInt())
                        }
                    }
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    android.util.Log.w("WatchSessionManager", "fetchGoalsAndPreferences goals: ${e.message}")
                }
            }
        }
    }

    fun checkExistingSession() {
        android.util.Log.d("WatchSessionManager", "checkExistingSession called: isChecking=$isCheckingSession, auth=${_isAuthenticated.value}")
        if (isCheckingSession) return
        isCheckingSession = true
        scope.launch {
            try {
                // 1. Check if the Auth plugin already has a cached session.
                val existingSession = supabaseClient.auth.currentSessionOrNull()
                android.util.Log.d("WatchSessionManager", "checkExistingSession: in-memory session = ${existingSession != null}")
                if (existingSession != null) {
                    val uid = existingSession.user?.id ?: extractUserId(existingSession.accessToken)
                    if (uid != null) {
                        // Show authenticated UI immediately using cached data
                        _currentUserId.value = uid
                        _isAuthenticated.value = true
                        _isPairing.value = false
                        prefs.edit()
                            .putString(KEY_ACCESS_TOKEN, existingSession.accessToken)
                            .putString(KEY_REFRESH_TOKEN, existingSession.refreshToken)
                            .putString(KEY_USER_ID, uid)
                            .apply()
                        fetchGoalsAndPreferences(uid)
                        syncAllHabits(force = false)
                        return@launch
                    }
                }

                // 2. Fall back to SharedPreferences tokens
                val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null)
                val refreshToken = prefs.getString(KEY_REFRESH_TOKEN, "") ?: ""
                var savedUserId = prefs.getString(KEY_USER_ID, null)
                android.util.Log.d("WatchSessionManager", "checkExistingSession SharedPreferences: hasToken=${!accessToken.isNullOrEmpty()}, uid=$savedUserId")
                
                if (savedUserId.isNullOrEmpty() && !accessToken.isNullOrEmpty()) {
                    savedUserId = extractUserId(accessToken)
                    if (savedUserId != null) {
                        prefs.edit().putString(KEY_USER_ID, savedUserId).apply()
                    }
                }

                // Note: 10-year Orbit watch JWTs have empty refresh tokens, so only require accessToken & savedUserId
                if (!accessToken.isNullOrEmpty() && !savedUserId.isNullOrEmpty()) {
                    importOrbitSession(accessToken, refreshToken)
                    _currentUserId.value = savedUserId
                    _isAuthenticated.value = true
                    _isPairing.value = false
                    fetchGoalsAndPreferences(savedUserId)
                    syncAllHabits(force = false)
                    android.util.Log.d("WatchSessionManager", "checkExistingSession: restored session for user $savedUserId")
                } else {
                    _isAuthenticated.value = false
                    _currentUserId.value = null
                    android.util.Log.d("WatchSessionManager", "checkExistingSession: no valid session found, isPairing=${_isPairing.value}, pin=${_pairingCode.value}")
                    if (!_isPairing.value || _pairingCode.value.isEmpty()) {
                        generatePairingCode()
                    }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e("WatchSessionManager", "checkExistingSession exception", e)
            } finally {
                isCheckingSession = false
            }
        }
    }

    fun generatePairingCode() {
        if (_isAuthenticated.value) {
            android.util.Log.d("WatchSessionManager", "generatePairingCode: already authenticated, skipping")
            return
        }
        stopPolling()
        isPairingCompleted = false
        _isPairing.value = true
        _errorMessage.value = ""
        val code = String.format("%06d", (0..999999).random())
        _pairingCode.value = code
        android.util.Log.d("WatchSessionManager", "generatePairingCode: generated code=$code")

        scope.launch {
            try {
                val pairing = WatchPairingInsert(pin_code = code)
                supabaseClient.postgrest["watch_pairing_codes"].insert(pairing)
                android.util.Log.d("WatchSessionManager", "generatePairingCode: insert OK in Supabase, starting polling")
                startPolling()
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e("WatchSessionManager", "Pairing insert failed", e)
                val msg = e.localizedMessage ?: e.cause?.localizedMessage ?: e::class.java.simpleName
                _errorMessage.value = "Insert Err: $msg"
            }
        }
    }

    fun stopPolling() {
        android.util.Log.d("WatchSessionManager", "stopPolling called")
        isPolling = false
        pollJob?.cancel()
        pollJob = null
    }

    private fun startPolling() {
        stopPolling()
        isPolling = true
        isPairingCompleted = false
        android.util.Log.d("WatchSessionManager", "startPolling launched for pin=${_pairingCode.value}")
        pollJob = scope.launch {
            while (isActive && isPolling) {
                delay(2500)
                if (!isActive || !isPolling) break
                android.util.Log.d("WatchSessionManager", "Polling tick: checking pin=${_pairingCode.value}")
                checkPairingStatus()
            }
        }
    }

    private suspend fun checkPairingStatus() {
        if (!isPolling || isPairingCompleted || _pairingCode.value.isEmpty()) {
            android.util.Log.d("WatchSessionManager", "checkPairingStatus skipped: isPolling=$isPolling, isPairingCompleted=$isPairingCompleted, pin=${_pairingCode.value}")
            return
        }
        val currentPin = _pairingCode.value

        try {
            android.util.Log.d("WatchSessionManager", "checkPairingStatus querying watch_pairing_codes for pin=$currentPin")
            val pairings = supabaseClient.postgrest["watch_pairing_codes"]
                .select { filter { eq("pin_code", currentPin) } }
                .decodeList<WatchPairing>()

            android.util.Log.d("WatchSessionManager", "checkPairingStatus result count: ${pairings.size}")
            val pairing = pairings.firstOrNull()
            if (pairing != null) {
                val token = pairing.access_token
                android.util.Log.d("WatchSessionManager", "checkPairingStatus record: claimed=${pairing.claimed}, hasToken=${!token.isNullOrEmpty()}")
                if (!token.isNullOrEmpty()) {
                    // 1. IMMEDIATELY stop polling so no subsequent poll can ever trigger
                    if (isPairingCompleted) return
                    isPairingCompleted = true
                    stopPolling()

                    val refresh = pairing.refresh_token.orEmpty()
                    val uid = extractUserId(token) ?: pairing.user_id
                    android.util.Log.d("WatchSessionManager", "checkPairingStatus: extracted uid=$uid")

                    if (uid != null) {
                        // 2. Persistent storage in SharedPreferences (instant synchronous in-memory write + async disk flush)
                        prefs.edit()
                            .putString(KEY_ACCESS_TOKEN, token)
                            .putString(KEY_REFRESH_TOKEN, refresh)
                            .putString(KEY_USER_ID, uid)
                            .apply()
                        android.util.Log.d("WatchSessionManager", "checkPairingStatus: saved to SharedPreferences")

                        // 3. Update UI states IMMEDIATELY so the watch immediately switches to the 5-page dashboard!
                        _currentUserId.value = uid
                        _isAuthenticated.value = true
                        _isPairing.value = false
                        _pairingCode.value = ""
                        _errorMessage.value = ""
                        android.util.Log.d("WatchSessionManager", "checkPairingStatus: SUCCESS! Set isAuthenticated=true")

                        // 4. Import session into client so PostgREST has valid Bearer token
                        scope.launch {
                            importOrbitSession(token, refresh)
                        }

                        // 5. Clean up pairing code row (best-effort)
                        scope.launch {
                            try {
                                supabaseClient.postgrest["watch_pairing_codes"]
                                    .delete { filter { eq("pin_code", currentPin) } }
                            } catch (e: Exception) {
                                if (e is kotlinx.coroutines.CancellationException) throw e
                            }
                        }

                        // 6. Register device in paired_watches table (guarded for idempotency)
                        scope.launch {
                            registerPairing(token, uid)
                        }

                        _dataRefreshTrigger.value++
                    } else {
                        // In the rare event user ID cannot be determined yet, resume polling
                        android.util.Log.w("WatchSessionManager", "checkPairingStatus: uid is null, resuming polling")
                        isPairingCompleted = false
                        startPolling()
                    }
                }
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            android.util.Log.e("WatchSessionManager", "checkPairingStatus poll exception", e)
            _errorMessage.value = "Poll Err: ${e.localizedMessage}"
        }
    }

    fun onAppResumed() {
        // Always attempt a full session refresh on resume. WearOS Doze mode kills the
        // Auth plugin's auto-refresh coroutine, so the access token is almost certainly
        // expired after any meaningful sleep period. We must proactively refresh here.
        scope.launch {
            // Step 0: Check if the main app pushed repair tokens (fresh credentials)
            checkForRepairTokens()

            // Step 1: Try importing the in-memory session
            val session = supabaseClient.auth.currentSessionOrNull()
            if (session != null) {
                _isAuthenticated.value = true
                val uid = session.user?.id ?: extractUserId(session.accessToken)
                _currentUserId.value = uid
                if (uid != null) {
                    fetchGoalsAndPreferences(uid)
                }
            } else {
                // Auth plugin has no session at all — full recovery from SharedPreferences
                recoverFromPreferences()
                val uid = _currentUserId.value
                if (uid != null) {
                    fetchGoalsAndPreferences(uid)
                }
            }

            // Tell screens to re-fetch their data now that auth is fresh
            _dataRefreshTrigger.value++

            // Flush any logs that were queued while offline
            if (_isAuthenticated.value) {
                OfflineSyncManager.shared.syncPendingLogs(supabaseClient)
                recordHealthSync()
                syncAllHabits(force = false)
            }
        }
    }

    /**
     * Recovers a Supabase session from SharedPreferences-persisted tokens. Called when the Auth
     * plugin's in-memory session is gone or its refresh attempt failed.
     */
    private suspend fun recoverFromPreferences() {
        val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null)
        val refreshToken = prefs.getString(KEY_REFRESH_TOKEN, "") ?: ""
        val savedUserId = prefs.getString(KEY_USER_ID, null)

        if (!accessToken.isNullOrEmpty() && !savedUserId.isNullOrEmpty()) {
            isRecovering = true
            try {
                importOrbitSession(accessToken, refreshToken)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
            } finally {
                isRecovering = false
            }
            _currentUserId.value = savedUserId
            _isAuthenticated.value = true
        }
    }

    /**
     * Registers this device in the persistent paired_watches table after a successful
     * pairing. Checks for an existing desktop-created placeholder (device_name == "Wear OS" or "Watch")
     * and adopts/updates it instead of blindly inserting a duplicate.
     * Never deactivates or modifies other paired devices, allowing multiple simultaneous watches.
     */
    private suspend fun registerPairing(accessToken: String, userId: String) {
        try {
            // Idempotency check: if we already have an active paired_watch_id stored, do not register again
            val existingWatchId = prefs.getString(KEY_PAIRED_WATCH_ID, null)
            if (!existingWatchId.isNullOrEmpty()) {
                android.util.Log.i("WatchSessionManager", "Device already registered with id: $existingWatchId")
                return
            }

            val deviceName = android.os.Build.MODEL ?: "Wear OS"
            val nowStr = java.time.Instant.now().toString()

            val client = HttpClient(CIO) {
                install(io.ktor.client.plugins.contentnegotiation.ContentNegotiation) {
                    kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                }
            }

            var adoptedId: String? = null

            // Step 1: Check if desktop created an active placeholder row ("Wear OS" or "Watch")
            try {
                val queryUrl = "$supabaseUrl/rest/v1/paired_watches?user_id=eq.$userId&platform=eq.wearos&or=(device_name.eq.Wear%20OS,device_name.eq.Watch)&is_active=eq.true&order=paired_at.desc&limit=1"
                val checkResp = client.request(queryUrl) {
                    method = io.ktor.http.HttpMethod.Get
                    header("Authorization", "Bearer $accessToken")
                    header("apikey", supabaseAnonKey)
                    header("Accept", "application/json")
                }

                if (checkResp.status.value in 200..299) {
                    val respText = checkResp.bodyAsText()
                    val jsonArray = kotlinx.serialization.json.Json.parseToJsonElement(respText) as? kotlinx.serialization.json.JsonArray
                    val placeholderObj = jsonArray?.firstOrNull() as? kotlinx.serialization.json.JsonObject
                    val id = placeholderObj?.get("id")?.jsonPrimitive?.content
                    if (!id.isNullOrEmpty()) {
                        adoptedId = id
                        android.util.Log.i("WatchSessionManager", "Adopting desktop placeholder paired_watch: $id")

                        // Update this placeholder with actual device model name and timestamp
                        val patchUrl = "$supabaseUrl/rest/v1/paired_watches?id=eq.$id"
                        val patchBody = """
                            {
                                "device_name": "$deviceName",
                                "last_token_push": "$nowStr"
                            }
                        """.trimIndent()

                        client.request(patchUrl) {
                            method = io.ktor.http.HttpMethod.Patch
                            header("Authorization", "Bearer $accessToken")
                            header("apikey", supabaseAnonKey)
                            contentType(io.ktor.http.ContentType.Application.Json)
                            setBody(patchBody)
                        }

                        prefs.edit().putString(KEY_PAIRED_WATCH_ID, id).apply()
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("WatchSessionManager", "Error checking for existing paired_watch placeholder: ${e.message}")
            }

            // Step 2: If no desktop placeholder was found, insert a new record for this device
            if (adoptedId == null) {
                val jsonBody = """
                    {
                        "user_id": "$userId",
                        "platform": "wearos",
                        "device_name": "$deviceName",
                        "is_active": true,
                        "last_token_push": "$nowStr"
                    }
                """.trimIndent()

                val response = client.request("$supabaseUrl/rest/v1/paired_watches") {
                    method = io.ktor.http.HttpMethod.Post
                    header("Authorization", "Bearer $accessToken")
                    header("apikey", supabaseAnonKey)
                    header("Prefer", "return=representation")
                    contentType(io.ktor.http.ContentType.Application.Json)
                    setBody(jsonBody)
                }

                if (response.status.value in 200..299) {
                    val responseText = response.bodyAsText()
                    val jsonArray = kotlinx.serialization.json.Json.parseToJsonElement(responseText) as? kotlinx.serialization.json.JsonArray
                    val firstObj = jsonArray?.firstOrNull() as? kotlinx.serialization.json.JsonObject
                    val id = firstObj?.get("id")?.jsonPrimitive?.content

                    if (!id.isNullOrEmpty()) {
                        prefs.edit().putString(KEY_PAIRED_WATCH_ID, id).apply()
                        android.util.Log.i("WatchSessionManager", "Inserted new paired_watch record: $id")
                    }
                }
            }

            // Note: Never deactivate other devices. Multiple watches can be paired simultaneously.

            client.close()
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            // Non-critical — pairing still works without the persistent record
        }
    }

    /**
     * Checks the paired_watches table for repair tokens pushed by the main app,
     * or for remote unpair status (row deleted or is_active == false).
     */
    private suspend fun checkForRepairTokens() {
        try {
            val pairedWatchId = prefs.getString(KEY_PAIRED_WATCH_ID, null) ?: return

            val records = supabaseClient.postgrest["paired_watches"]
                .select { filter { eq("id", pairedWatchId) } }
                .decodeList<PairedWatch>()

            val record = records.firstOrNull() ?: return
            if (record.is_active == false) {
                android.util.Log.i("WatchSessionManager", "Remote unpair detected from paired_watches. Logging out.")
                logout()
                return
            }

            val pendingAccess = record.pending_access_token
            val pendingRefresh = record.pending_refresh_token

            if (!pendingAccess.isNullOrEmpty()) {
                // Apply the fresh tokens
                importOrbitSession(pendingAccess, pendingRefresh ?: "")

                // Clear the pending tokens so we don't re-apply on next resume
                supabaseClient.postgrest["paired_watches"]
                    .update({
                        set("pending_access_token", null as String?)
                        set("pending_refresh_token", null as String?)
                    }) { filter { eq("id", pairedWatchId) } }
            }
        } catch (e: Exception) {
            // Non-critical — normal session refresh will still run
        }
    }

    fun logout() {
        stopPolling()
        scope.launch {
            // Deactivate the paired_watches record
            try {
                val pairedWatchId = prefs.getString(KEY_PAIRED_WATCH_ID, null)
                if (pairedWatchId != null) {
                    supabaseClient.postgrest["paired_watches"]
                        .update({ set("is_active", false) }) {
                            filter { eq("id", pairedWatchId) }
                        }
                }
            } catch (_: Exception) {}

            prefs.edit()
                .remove(KEY_ACCESS_TOKEN)
                .remove(KEY_REFRESH_TOKEN)
                .remove(KEY_USER_ID)
                .remove(KEY_PAIRED_WATCH_ID)
                .apply()

            try { supabaseClient.auth.signOut() } catch (e: Exception) {}
            _isAuthenticated.value = false
            _currentUserId.value = null
            generatePairingCode()
        }
    }

    private fun extractUserId(jwt: String): String? {
        try {
            val parts = jwt.split(".")
            if (parts.size != 3) return null
            var base64 = parts[1].replace("-", "+").replace("_", "/")
            val pad = base64.length % 4
            if (pad > 0) {
                base64 += "=".repeat(4 - pad)
            }
            val jsonBytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
            val jsonString = String(jsonBytes, Charsets.UTF_8)
            val jsonObject = kotlinx.serialization.json.Json.parseToJsonElement(jsonString) as kotlinx.serialization.json.JsonObject
            return jsonObject["sub"]?.jsonPrimitive?.content
        } catch (e: Exception) {
            return null
        }
    }
}
