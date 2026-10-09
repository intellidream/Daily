package com.intellidream.daily.network

import com.intellidream.daily.model.HabitGoalRecord
import com.intellidream.daily.model.HabitLogRecord
import com.intellidream.daily.model.UserPreferencesRecord
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class HabitRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    suspend fun pushLog(log: HabitLogRecord): Boolean = withContext(Dispatchers.IO) {
        if (log.userId.isNullOrEmpty() || log.userId == "guest") return@withContext false
        try {
            clientManager.client.postgrest["habits_logs"].insert(log)
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun pullLogsForDate(userId: String, startIso: String, endIso: String): List<HabitLogRecord> = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["habits_logs"]
                .select {
                    filter {
                        if (userId.isNotEmpty() && userId != "guest") {
                            eq("user_id", userId)
                        }
                        gte("logged_at", startIso)
                        lt("logged_at", endIso)
                    }
                }
                .decodeList<HabitLogRecord>()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun pullUserPreferences(userId: String): UserPreferencesRecord? = withContext(Dispatchers.IO) {
        if (userId.isEmpty() || userId == "guest") return@withContext null
        try {
            val list = clientManager.client.postgrest["user_preferences"]
                .select {
                    filter {
                        eq("id", userId)
                    }
                    limit(1)
                }
                .decodeList<UserPreferencesRecord>()
            list.firstOrNull()
        } catch (_: Exception) {
            null
        }
    }

    suspend fun pullGoals(userId: String): List<HabitGoalRecord> = withContext(Dispatchers.IO) {
        if (userId.isEmpty() || userId == "guest") return@withContext emptyList()
        try {
            clientManager.client.postgrest["habits_goals"]
                .select {
                    filter {
                        eq("user_id", userId)
                        eq("is_deleted", false)
                    }
                }
                .decodeList<HabitGoalRecord>()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun deleteLog(logId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["habits_logs"]
                .update(buildJsonObject { put("is_deleted", true) }) {
                    filter {
                        eq("id", logId)
                    }
                }
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun fetchLogsSince(sinceEpochMs: Long, habitType: String): List<HabitLogRecord> = withContext(Dispatchers.IO) {
        try {
            val sinceIso = java.time.Instant.ofEpochMilli(sinceEpochMs).toString()
            clientManager.client.postgrest["habits_logs"]
                .select {
                    filter {
                        eq("habit_type", habitType)
                        gte("logged_at", sinceIso)
                        eq("is_deleted", false)
                    }
                }
                .decodeList<HabitLogRecord>()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun fetchHabitsConsistency(
        userId: String,
        startDateStr: String,
        endDateStr: String,
        startIso112: String
    ): com.intellidream.daily.model.HabitsConsistencyResult = withContext(Dispatchers.IO) {
        val waterTotals = mutableMapOf<String, Double>()
        val smokesTotals = mutableMapOf<String, Int>()
        var fetchedViaRpc = false
        var rawLogsList: List<HabitLogRecord> = emptyList()

        // 4A. Primary: Call Supabase RPC get_habits_consistency for Water & Smokes
        try {
            val waterParams = buildJsonObject {
                put("p_habit_type", "water")
                put("p_start_date", startDateStr)
                put("p_end_date", endDateStr)
            }
            val waterRows = clientManager.client.postgrest.rpc(
                function = "get_habits_consistency",
                parameters = waterParams
            ).decodeList<com.intellidream.daily.model.HabitsConsistencyRow>()

            val smokesParams = buildJsonObject {
                put("p_habit_type", "smokes")
                put("p_start_date", startDateStr)
                put("p_end_date", endDateStr)
            }
            val smokesRows = clientManager.client.postgrest.rpc(
                function = "get_habits_consistency",
                parameters = smokesParams
            ).decodeList<com.intellidream.daily.model.HabitsConsistencyRow>()

            for (r in waterRows) {
                waterTotals[r.normalizedDayKey] = r.total_value
            }
            for (r in smokesRows) {
                smokesTotals[r.normalizedDayKey] = r.total_value.toInt()
            }
            if (waterRows.isNotEmpty() || smokesRows.isNotEmpty()) {
                fetchedViaRpc = true
            }
        } catch (_: Exception) {
            // Fallback to direct tables below
        }

        // 4B. Fallback: Dual-Table Ingestion (habits_daily_summaries + habits_logs) ONLY if !fetchedViaRpc (matching iOS)
        if (!fetchedViaRpc) {
            try {
                val summaries = clientManager.client.postgrest["habits_daily_summaries"]
                    .select {
                        filter {
                            gte("date", startDateStr)
                            if (userId.isNotEmpty() && userId != "guest") {
                                eq("user_id", userId)
                            }
                        }
                    }
                    .decodeList<com.intellidream.daily.model.HabitsDailySummaryRow>()

                for (s in summaries) {
                    val k = s.normalizedDayKey
                    if (s.habit_type == "water") {
                        waterTotals[k] = s.total_value
                    } else if (s.habit_type == "smokes") {
                        smokesTotals[k] = s.total_value.toInt()
                    }
                }
            } catch (_: Exception) {}

            // Fetch raw habits_logs for 112 days (overrides summaries)
            try {
                val rawLogs = clientManager.client.postgrest["habits_logs"]
                    .select {
                        filter {
                            gte("logged_at", startIso112)
                            eq("is_deleted", false)
                            if (userId.isNotEmpty() && userId != "guest") {
                                eq("user_id", userId)
                            }
                        }
                        order("logged_at", io.github.jan.supabase.postgrest.query.Order.ASCENDING)
                        limit(5000)
                    }
                    .decodeList<HabitLogRecord>()

                rawLogsList = rawLogs

                val sdf = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).apply {
                    timeZone = java.util.TimeZone.getTimeZone("UTC")
                }
                val rawWater = mutableMapOf<String, Double>()
                val rawSmokes = mutableMapOf<String, Int>()
                for (l in rawLogs) {
                    val k = sdf.format(java.util.Date(l.loggedAt))
                    if (l.habitType == "water") {
                        rawWater[k] = (rawWater[k] ?: 0.0) + l.value
                    } else if (l.habitType == "smokes") {
                        rawSmokes[k] = (rawSmokes[k] ?: 0) + l.value.toInt()
                    }
                }
                for ((k, v) in rawWater) {
                    waterTotals[k] = v
                }
                for ((k, v) in rawSmokes) {
                    smokesTotals[k] = v
                }
            } catch (_: Exception) {}
        }

        com.intellidream.daily.model.HabitsConsistencyResult(
            waterTotals = waterTotals,
            smokesTotals = smokesTotals,
            recentRawLogs = rawLogsList
        )
    }

    suspend fun fetchSmokesFinancials(sinceIso: String): com.intellidream.daily.model.SmokesFinancialsRpcResult? = withContext(Dispatchers.IO) {
        try {
            val params = buildJsonObject {
                put("p_since_date", sinceIso)
            }
            clientManager.client.postgrest.rpc(
                function = "get_smokes_financials",
                parameters = params
            ).decodeAs<com.intellidream.daily.model.SmokesFinancialsRpcResult>()
        } catch (_: Exception) {
            null
        }
    }
}
