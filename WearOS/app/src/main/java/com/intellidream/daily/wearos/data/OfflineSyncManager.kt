package com.intellidream.daily.wearos.data

import com.intellidream.daily.wearos.domain.model.HabitLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.decodeFromString
import io.github.jan.supabase.postgrest.postgrest

class OfflineSyncManager private constructor() {
    private val _queue = MutableStateFlow<List<HabitLog>>(emptyList())
    val queue: StateFlow<List<HabitLog>> = _queue
    
    // In a real app we'd save this to SharedPreferences or Room. 
    // Keeping it simple and analogous to the Swift prototype.

    fun enqueue(log: HabitLog) {
        val current = _queue.value.toMutableList()
        current.add(log)
        _queue.value = current
    }

    fun removeFirst() {
        val current = _queue.value.toMutableList()
        if (current.isNotEmpty()) {
            current.removeAt(0)
            _queue.value = current
        }
    }

    suspend fun syncPendingLogs(supabaseClient: io.github.jan.supabase.SupabaseClient) {
        val logs = _queue.value.toList()
        for (log in logs) {
            try {
                supabaseClient.postgrest["habits_logs"].insert(log)
                removeFirst()
            } catch (e: Exception) {
                // Network error likely, stop and wait
                break
            }
        }
    }

    companion object {
        val shared = OfflineSyncManager()
    }
}
