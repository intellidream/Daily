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
                        eq("is_deleted", false)
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
}
