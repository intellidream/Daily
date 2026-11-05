package com.intellidream.daily.wearos.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.Immutable
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.contentType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.OffsetDateTime
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToInt

@Immutable
@Serializable
data class PulseSnapshot(
    val localDate: String,
    val syncedAtEpochMs: Long = 0L,

    // Sleep & Recovery
    val hasSleepData: Boolean = false,
    val sleepScore: Int = 0,
    val sleepDurationFormatted: String = "--",
    val readinessHeadline: String = "Awaiting Sleep Sync",
    val readinessStatus: String = "Pending",
    val sleepNarrative: String = "Tap Pulse Studio or open Daily on phone to sync recovery.",
    val sleepSourceDevice: String? = null,
    val restingHrText: String = "RHR: -- bpm",
    val hrvText: String = "HRV: -- ms",
    val deepWeight: Float = 0.22f,
    val remWeight: Float = 0.23f,
    val lightWeight: Float = 0.47f,
    val awakeWeight: Float = 0.08f,
    val readinessScore: Int? = null,

    // Autonomic Stress (Engine v2.0)
    val hasStressData: Boolean = false,
    val stressScore: Int = 0,
    val stressBadgeText: String = "--/100",
    val stressLevel: String = "Calm",
    val stressHeadline: String = "Calibrating Tone",
    val monkeyMoodText: String = "Zen Monkey",
    val stepsText: String = "-- steps",
    val parasympatheticPercent: Int = 0,
    val parasympatheticText: String = "Parasym: --%",
    val adviceQuote: String = "Syncing autonomic balance from your wearables.",
    val recommendedBreathing: String = "Physiological Sigh"
) {
    companion object {
        fun empty(dateStr: String): PulseSnapshot = PulseSnapshot(localDate = dateStr)
    }
}

class WatchPulseRepository private constructor(private val context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(WatchSessionManager.PREFS_NAME, Context.MODE_PRIVATE)

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    private val httpClient: HttpClient by lazy {
        HttpClient(CIO) {
            engine {
                requestTimeout = 15_000L
            }
        }
    }

    private val _snapshot = MutableStateFlow(loadCachedSnapshot())
    val snapshot: StateFlow<PulseSnapshot> = _snapshot.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    companion object {
        private const val SUPABASE_URL = "https://akkfouifxztnfwwiclwg.supabase.co"
        private const val SUPABASE_ANON_KEY = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"

        private const val KEY_PULSE_SNAPSHOT_CACHE = "watch_pulse_studio_cache_v2"
        private const val KEY_PULSE_LAST_SYNC_TS = "watch_pulse_last_sync_ts_v2"

        // 10-minute smartwatch battery & network TTL policy
        private const val CACHE_TTL_MS = 10 * 60 * 1000L
        // 2-minute early retry if sleep hasn't synced yet in the morning
        private const val MISSING_SLEEP_RETRY_MS = 2 * 60 * 1000L
        // Recompute server summary via health-engine if summary is > 15m old
        private const val SERVER_SUMMARY_MAX_AGE_MS = 15 * 60 * 1000L

        @Volatile
        private var instance: WatchPulseRepository? = null

        fun getInstance(context: Context): WatchPulseRepository {
            return instance ?: synchronized(this) {
                instance ?: WatchPulseRepository(context.applicationContext).also { instance = it }
            }
        }

        private fun currentLocalDateString(): String {
            val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            fmt.timeZone = TimeZone.getDefault()
            return fmt.format(Date())
        }
    }

    private fun loadCachedSnapshot(): PulseSnapshot {
        val todayStr = currentLocalDateString()
        val raw = prefs.getString(KEY_PULSE_SNAPSHOT_CACHE, null)
        if (!raw.isNullOrBlank()) {
            try {
                val decoded = json.decodeFromString<PulseSnapshot>(raw)
                return decoded.copy(
                    deepWeight = decoded.deepWeight.coerceAtLeast(0.02f),
                    remWeight = decoded.remWeight.coerceAtLeast(0.02f),
                    lightWeight = decoded.lightWeight.coerceAtLeast(0.02f),
                    awakeWeight = decoded.awakeWeight.coerceAtLeast(0.02f)
                )
            } catch (_: Exception) {}
        }
        return PulseSnapshot.empty(todayStr)
    }

    private fun persistSnapshot(snap: PulseSnapshot, syncedAtMs: Long) {
        try {
            prefs.edit()
                .putString(KEY_PULSE_SNAPSHOT_CACHE, json.encodeToString(snap))
                .putLong(KEY_PULSE_LAST_SYNC_TS, syncedAtMs)
                .apply()
        } catch (_: Exception) {}
    }

    /**
     * Synchronizes Pulse Studio (Sleep & Recovery + Autonomic Stress v2.0) from canonical
     * `public.health_daily_summary` and triggers `health-engine` recomputation when stale or forced.
     * Strictly throttled to 10-minute TTL unless `force == true` or date rolled over.
     */
    suspend fun syncWithSupabase(force: Boolean = false) = withContext(Dispatchers.IO) {
        if (_isSyncing.value) return@withContext

        val nowMs = System.currentTimeMillis()
        val todayStr = currentLocalDateString()
        val lastSyncMs = prefs.getLong(KEY_PULSE_LAST_SYNC_TS, 0L)
        val currentSnap = _snapshot.value

        val isNewDay = currentSnap.localDate != todayStr
        val neverSynced = lastSyncMs <= 0L || (!currentSnap.hasSleepData && !currentSnap.hasStressData)
        val ttlExpired = (nowMs - lastSyncMs) >= CACHE_TTL_MS
        val missingSleepRetry = !currentSnap.hasSleepData && (nowMs - lastSyncMs) >= MISSING_SLEEP_RETRY_MS

        if (!force && !isNewDay && !neverSynced && !ttlExpired && !missingSleepRetry) {
            return@withContext
        }

        val sessionManager = WatchSessionManager.getInstance(context)
        val accessToken = prefs.getString(WatchSessionManager.KEY_ACCESS_TOKEN, null)
        val userId = sessionManager.currentUserId.value
            ?: prefs.getString(WatchSessionManager.KEY_USER_ID, null)

        if (accessToken.isNullOrBlank() || userId.isNullOrBlank()) {
            return@withContext
        }

        _isSyncing.value = true
        try {
            var summaryRow = fetchSummaryRowFromRest(accessToken, userId, todayStr)

            if (shouldInvokeHealthEngine(summaryRow, force, nowMs)) {
                val recomputed = invokeHealthEngine(accessToken, userId, todayStr, nowMs)
                if (recomputed != null) {
                    summaryRow = recomputed
                } else if (summaryRow == null) {
                    summaryRow = fetchSummaryRowFromRest(accessToken, userId, todayStr)
                }
            }

            if (summaryRow != null) {
                val built = buildSnapshot(summaryRow, todayStr, nowMs)
                _snapshot.value = built
                persistSnapshot(built, nowMs)
                sessionManager.recordHealthSync("synced")
            } else if (currentSnap.localDate != todayStr) {
                val emptyToday = PulseSnapshot.empty(todayStr)
                _snapshot.value = emptyToday
                prefs.edit().putLong(KEY_PULSE_LAST_SYNC_TS, nowMs).apply()
            }
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            android.util.Log.w("WatchPulseRepository", "Pulse sync warning: ${e.message}")
        } finally {
            _isSyncing.value = false
        }
    }

    private suspend fun fetchSummaryRowFromRest(
        accessToken: String,
        userId: String,
        dateStr: String
    ): JsonObject? {
        return try {
            val selectCols = listOf(
                "local_date",
                "computed_at",
                "engine_version",
                "steps",
                "active_kcal",
                "sleep_asleep_s",
                "sleep_score",
                "stress_avg",
                "rhr",
                "hrv_sdnn",
                "hrv_rmssd",
                "spo2",
                "sleep_verdict:summary->sleep->guidance->verdict",
                "sleep_source:summary->sleep->primary_session->>source_device",
                "sleep_eff:summary->sleep->primary_session->efficiency_percent",
                "sleep_rest:summary->sleep->primary_session->restorative_percent",
                "sleep_rating:summary->sleep->primary_session->>quality_rating",
                "deep_s:summary->sleep->primary_session->deep_seconds",
                "rem_s:summary->sleep->primary_session->rem_seconds",
                "light_s:summary->sleep->primary_session->light_seconds",
                "awake_s:summary->sleep->primary_session->awake_seconds",
                "stress_score:summary->stress->current_score",
                "stress_level:summary->stress->>current_level",
                "stress_daily_avg:summary->stress->daily_average",
                "monkey_mood:summary->stress->>monkey_mood",
                "parasym_pct:summary->stress->parasympathetic_percent",
                "advice_quote:summary->stress->>advice_quote",
                "rec_breathing:summary->stress->>recommended_breathing",
                "stress_hrv:summary->stress->current_hrv_ms",
                "stress_rhr:summary->stress->resting_heart_rate_bpm"
            ).joinToString(",")
            val url = "$SUPABASE_URL/rest/v1/health_daily_summary"
            val response = httpClient.request(url) {
                method = HttpMethod.Get
                parameter("user_id", "eq.$userId")
                parameter("local_date", "eq.$dateStr")
                parameter("select", selectCols)
                parameter("limit", "1")
                header("Authorization", "Bearer $accessToken")
                header("apikey", SUPABASE_ANON_KEY)
                header("Accept", "application/json")
            }
            if (response.status.value !in 200..299) return null
            val arr = json.parseToJsonElement(response.bodyAsText()) as? JsonArray
            arr?.firstOrNull() as? JsonObject
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun invokeHealthEngine(
        accessToken: String,
        userId: String,
        dateStr: String,
        nowMs: Long
    ): JsonObject? {
        return try {
            val rawTzMin = TimeZone.getDefault().getOffset(nowMs) / 60_000
            val tzOffsetMin = if (rawTzMin == 0) 120 else rawTzMin
            val bodyJson = buildJsonObject {
                put("user_id", userId)
                put("date", dateStr)
                put("tz_offset_min", tzOffsetMin)
                put("slim_watch", true)
            }.toString()

            val response = httpClient.request("$SUPABASE_URL/functions/v1/health-engine") {
                method = HttpMethod.Post
                header("Authorization", "Bearer $accessToken")
                header("apikey", SUPABASE_ANON_KEY)
                contentType(ContentType.Application.Json)
                setBody(bodyJson)
            }
            if (response.status.value !in 200..299) return null
            val root = json.parseToJsonElement(response.bodyAsText()) as? JsonObject
            root?.get("summary") as? JsonObject
        } catch (_: Exception) {
            null
        }
    }

    private fun shouldInvokeHealthEngine(
        row: JsonObject?,
        force: Boolean,
        nowMs: Long
    ): Boolean {
        if (force) return true
        if (row == null) return true

        val version = row.str("engine_version") ?: ""
        if (!(version.startsWith("v2") || version.startsWith("2."))) return true

        // Consumer-only smartwatch mode: only invoke health-engine when server summary is missing
        // or user explicitly tapped Refresh (`force == true`).
        return false
    }

    private fun parseIsoToEpochMs(raw: String): Long? {
        try {
            return Instant.parse(raw).toEpochMilli()
        } catch (_: Exception) {}
        try {
            val normalized = raw.trim().replace(" ", "T")
            return OffsetDateTime.parse(normalized).toInstant().toEpochMilli()
        } catch (_: Exception) {}
        return null
    }

    private fun buildSnapshot(
        row: JsonObject,
        fallbackDate: String,
        syncedAtMs: Long
    ): PulseSnapshot {
        val localDate = row.str("local_date") ?: fallbackDate
        val summaryObj = row.obj("summary")

        // --- Sleep & Recovery (supports both slim flat PostgREST aliases and summary JSON) ---
        val sleepContainer = summaryObj?.obj("sleep")
        val primarySession = sleepContainer?.obj("primary_session")
        val verdictObj = row.obj("sleep_verdict") ?: sleepContainer?.obj("guidance")?.obj("verdict")

        val asleepSeconds = primarySession?.int("asleep_seconds")
            ?: row.int("sleep_asleep_s")
            ?: 0
        val sleepScore = primarySession?.int("sleep_score")
            ?: row.int("sleep_score")
            ?: 0
        val hasSleepData = asleepSeconds > 0 && sleepScore > 0

        val sleepDurationFormatted = if (asleepSeconds > 0) {
            val h = asleepSeconds / 3600
            val m = (asleepSeconds % 3600) / 60
            if (h > 0) "${h}h ${m}m" else "${m}m"
        } else {
            "--"
        }

        val readinessScore = verdictObj?.int("readiness_score")
        val verdictStatus = verdictObj?.str("status")
            ?: row.str("sleep_rating")
            ?: primarySession?.str("quality_rating")
            ?: if (hasSleepData) {
                when {
                    sleepScore >= 85 -> "Optimal"
                    sleepScore >= 75 -> "Good"
                    else -> "Fair"
                }
            } else {
                "Pending"
            }

        val readinessHeadline = when {
            !hasSleepData -> "Awaiting Sleep Sync"
            readinessScore != null && readinessScore > 0 -> "Readiness $readinessScore • $verdictStatus"
            else -> "$verdictStatus Recovery"
        }

        val rawNarrative = verdictObj?.str("narrative")?.trim()
        val sleepNarrative = when {
            !rawNarrative.isNullOrEmpty() && hasSleepData -> rawNarrative
            hasSleepData -> {
                val eff = row.int("sleep_eff") ?: primarySession?.int("efficiency_percent") ?: 90
                val restPct = row.int("sleep_rest") ?: primarySession?.int("restorative_percent") ?: 25
                "Efficiency $eff% • $restPct% restorative stages."
            }
            else -> "Wear watch or ring overnight to populate recovery."
        }

        val sleepSourceDevice = row.str("sleep_source") ?: primarySession?.str("source_device")

        val deepS = (row.int("deep_s") ?: primarySession?.int("deep_seconds") ?: 0).toFloat()
        val remS = (row.int("rem_s") ?: primarySession?.int("rem_seconds") ?: 0).toFloat()
        val lightS = (row.int("light_s") ?: primarySession?.int("light_seconds") ?: 0).toFloat()
        val awakeS = (row.int("awake_s") ?: primarySession?.int("awake_seconds") ?: 0).toFloat()
        val stageTotal = deepS + remS + lightS + awakeS

        val deepWeight: Float
        val remWeight: Float
        val lightWeight: Float
        val awakeWeight: Float
        if (stageTotal > 0f) {
            val rDeep = (deepS / stageTotal).coerceAtLeast(0.03f)
            val rRem = (remS / stageTotal).coerceAtLeast(0.03f)
            val rLight = (lightS / stageTotal).coerceAtLeast(0.03f)
            val rAwake = (awakeS / stageTotal).coerceAtLeast(0.02f)
            val sum = rDeep + rRem + rLight + rAwake
            deepWeight = (rDeep / sum).coerceAtLeast(0.02f)
            remWeight = (rRem / sum).coerceAtLeast(0.02f)
            lightWeight = (rLight / sum).coerceAtLeast(0.02f)
            awakeWeight = (rAwake / sum).coerceAtLeast(0.02f)
        } else {
            deepWeight = 0.22f
            remWeight = 0.23f
            lightWeight = 0.47f
            awakeWeight = 0.08f
        }

        // --- Cardiovascular & Vitals ---
        val cardioObj = summaryObj?.obj("cardiovascular")
        val stressObj = summaryObj?.obj("stress")

        val rhrVal = row.dbl("rhr")
            ?: cardioObj?.dbl("resting_bpm")
            ?: row.dbl("stress_rhr")
            ?: stressObj?.dbl("resting_heart_rate_bpm")
        val restingHrText = if (rhrVal != null && rhrVal > 0.0) {
            "RHR: ${rhrVal.roundToInt()} bpm"
        } else {
            "RHR: -- bpm"
        }

        val hrvVal = row.dbl("stress_hrv")
            ?: stressObj?.dbl("current_hrv_ms")
            ?: row.dbl("hrv_rmssd")
            ?: row.dbl("hrv_sdnn")
        val hrvText = if (hrvVal != null && hrvVal > 0.0) {
            "HRV: ${hrvVal.roundToInt()} ms"
        } else {
            "HRV: -- ms"
        }

        // --- Autonomic Stress (Engine v2.0) ---
        val currentStressScore = row.int("stress_score")
            ?: stressObj?.int("current_score")
            ?: row.int("stress_avg")
        val hasStressData = (currentStressScore != null)
        val finalStressScore = (currentStressScore ?: 0).coerceIn(0, 100)
        val stressBadgeText = if (hasStressData) "$finalStressScore/100" else "--/100"

        val rawLevel = row.str("stress_level")
            ?: stressObj?.str("current_level")
            ?: levelFromScore(finalStressScore)
        val dailyAvg = row.int("stress_daily_avg")
            ?: stressObj?.int("daily_average")
            ?: row.int("stress_avg")
            ?: finalStressScore

        val stressHeadline = when {
            !hasStressData -> "Calibrating Tone"
            dailyAvg > 0 && dailyAvg != finalStressScore -> "$rawLevel • Avg $dailyAvg"
            else -> "$rawLevel Tone"
        }

        val monkeyMoodText = row.str("monkey_mood")
            ?: stressObj?.str("monkey_mood")
            ?: moodFromScore(finalStressScore)

        val activityObj = summaryObj?.obj("activity")
        val totalSteps = row.int("steps")
            ?: activityObj?.int("total_steps")
            ?: 0
        val formattedSteps = NumberFormat.getIntegerInstance(Locale.US).format(totalSteps)
        val stepsText = "$formattedSteps steps"

        val parasym = row.int("parasym_pct")
            ?: stressObj?.int("parasympathetic_percent")
            ?: if (hasStressData) (100 - finalStressScore).coerceIn(0, 100) else 0
        val parasympatheticText = if (hasStressData) "Parasym: $parasym%" else "Parasym: --%"

        val adviceQuote = (row.str("advice_quote") ?: stressObj?.str("advice_quote"))?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "Autonomic tone is steady. Stay hydrated and pace calmly."
        val recommendedBreathing = row.str("rec_breathing")
            ?: stressObj?.str("recommended_breathing")
            ?: "Physiological Sigh"

        return PulseSnapshot(
            localDate = localDate,
            syncedAtEpochMs = syncedAtMs,
            hasSleepData = hasSleepData,
            sleepScore = sleepScore,
            sleepDurationFormatted = sleepDurationFormatted,
            readinessHeadline = readinessHeadline,
            readinessStatus = verdictStatus,
            sleepNarrative = sleepNarrative,
            sleepSourceDevice = sleepSourceDevice,
            restingHrText = restingHrText,
            hrvText = hrvText,
            deepWeight = deepWeight,
            remWeight = remWeight,
            lightWeight = lightWeight,
            awakeWeight = awakeWeight,
            readinessScore = readinessScore,
            hasStressData = hasStressData,
            stressScore = finalStressScore,
            stressBadgeText = stressBadgeText,
            stressLevel = rawLevel,
            stressHeadline = stressHeadline,
            monkeyMoodText = monkeyMoodText,
            stepsText = stepsText,
            parasympatheticPercent = parasym,
            parasympatheticText = parasympatheticText,
            adviceQuote = adviceQuote,
            recommendedBreathing = recommendedBreathing
        )
    }

    private fun levelFromScore(score: Int): String = when {
        score <= 25 -> "Restful"
        score <= 50 -> "Calm"
        score <= 75 -> "Moderate"
        else -> "High"
    }

    private fun moodFromScore(score: Int): String = when {
        score <= 25 -> "Zen Monkey"
        score <= 50 -> "Curious Monkey"
        score <= 75 -> "Busy Monkey"
        else -> "Overheated Monkey"
    }

    // Safe JsonObject traversal helpers
    private fun JsonObject.obj(key: String): JsonObject? {
        val el: JsonElement = this[key] ?: return null
        return if (el is JsonNull) null else el as? JsonObject
    }

    private fun JsonObject.str(key: String): String? {
        val el: JsonElement = this[key] ?: return null
        if (el is JsonNull) return null
        return (el as? JsonPrimitive)?.contentOrNull
    }

    private fun JsonObject.int(key: String): Int? {
        val el: JsonElement = this[key] ?: return null
        if (el is JsonNull) return null
        val prim = el as? JsonPrimitive ?: return null
        return prim.intOrNull ?: prim.doubleOrNull?.roundToInt()
    }

    private fun JsonObject.dbl(key: String): Double? {
        val el: JsonElement = this[key] ?: return null
        if (el is JsonNull) return null
        return (el as? JsonPrimitive)?.doubleOrNull
    }
}
