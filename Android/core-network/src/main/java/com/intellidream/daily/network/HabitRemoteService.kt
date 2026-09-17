package com.intellidream.daily.network

import com.intellidream.daily.model.HabitLogRecord
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class HabitRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    suspend fun pushLog(log: HabitLogRecord): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["habits_logs"].insert(log)
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun fetchLogsSince(sinceEpochMs: Long, habitType: String): List<HabitLogRecord> = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["habits_logs"]
                .select {
                    filter {
                        eq("habit_type", habitType)
                        gte("logged_at", sinceEpochMs)
                        eq("is_deleted", false)
                    }
                }
                .decodeList<HabitLogRecord>()
        } catch (_: Exception) {
            emptyList()
        }
    }
}
