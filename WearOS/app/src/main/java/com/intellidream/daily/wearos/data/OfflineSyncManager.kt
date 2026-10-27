package com.intellidream.daily.wearos.data

import android.content.Context
import android.content.SharedPreferences
import com.intellidream.daily.wearos.domain.model.HabitLog
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
enum class SyncActionType {
    INSERT,
    DELETE
}

@Serializable
data class PendingSyncItem(
    val actionType: SyncActionType,
    val log: HabitLog,
    val queuedAt: Long = System.currentTimeMillis()
)

class OfflineSyncManager private constructor(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val syncMutex = Mutex()

    private val _pendingItems = MutableStateFlow<List<PendingSyncItem>>(emptyList())
    val pendingItems: StateFlow<List<PendingSyncItem>> = _pendingItems

    init {
        loadQueueFromDisk()
    }

    @Synchronized
    private fun loadQueueFromDisk() {
        try {
            val rawJson = prefs.getString(KEY_OUTBOX_QUEUE, null)
            if (!rawJson.isNullOrEmpty()) {
                val list = json.decodeFromString<List<PendingSyncItem>>(rawJson)
                _pendingItems.value = list
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to load outbox from disk: ${e.message}")
        }
    }

    @Synchronized
    private fun persistQueueToDisk() {
        try {
            val list = _pendingItems.value
            val rawJson = json.encodeToString(list)
            prefs.edit().putString(KEY_OUTBOX_QUEUE, rawJson).apply()
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to persist outbox to disk: ${e.message}")
        }
    }

    @Synchronized
    fun enqueueInsert(log: HabitLog) {
        val current = _pendingItems.value.toMutableList()
        current.add(PendingSyncItem(actionType = SyncActionType.INSERT, log = log))
        _pendingItems.value = current
        persistQueueToDisk()
    }

    fun enqueue(log: HabitLog) = enqueueInsert(log)

    @Synchronized
    fun enqueueDelete(log: HabitLog) {
        val current = _pendingItems.value.toMutableList()
        current.add(PendingSyncItem(actionType = SyncActionType.DELETE, log = log))
        _pendingItems.value = current
        persistQueueToDisk()
    }

    suspend fun syncPendingLogs(supabaseClient: SupabaseClient): Boolean = withContext(Dispatchers.IO) {
        if (!syncMutex.tryLock()) {
            return@withContext false
        }
        try {
            val snapshot = synchronized(this@OfflineSyncManager) { _pendingItems.value.toList() }
            if (snapshot.isEmpty()) return@withContext true

            val processedIds = mutableSetOf<String>()

            // 1. Process inserts in batch
            val inserts = snapshot.filter { it.actionType == SyncActionType.INSERT }
            if (inserts.isNotEmpty()) {
                try {
                    val logsToInsert = inserts.map { it.log }
                    supabaseClient.postgrest["habits_logs"].upsert(logsToInsert)
                    inserts.forEach { processedIds.add("${it.actionType}_${it.log.id}") }
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    android.util.Log.w(TAG, "Batch insert failed: ${e.message}")
                    // Stop on network failure to preserve order and retry later
                    return@withContext false
                }
            }

            // 2. Process deletes
            val deletes = snapshot.filter { it.actionType == SyncActionType.DELETE }
            if (deletes.isNotEmpty()) {
                try {
                    for (del in deletes) {
                        supabaseClient.postgrest["habits_logs"]
                            .update({
                                set("is_deleted", true)
                            }) {
                                filter { eq("id", del.log.id) }
                            }
                        processedIds.add("${del.actionType}_${del.log.id}")
                    }
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    android.util.Log.w(TAG, "Delete sync failed: ${e.message}")
                    return@withContext false
                }
            }

            // Remove processed items from queue
            synchronized(this@OfflineSyncManager) {
                val remaining = _pendingItems.value.filter {
                    !processedIds.contains("${it.actionType}_${it.log.id}")
                }
                _pendingItems.value = remaining
                persistQueueToDisk()
            }
            return@withContext true
        } finally {
            syncMutex.unlock()
        }
    }

    companion object {
        private const val TAG = "OfflineSyncManager"
        private const val PREFS_NAME = "daily_offline_sync"
        private const val KEY_OUTBOX_QUEUE = "pending_outbox_queue"

        @Volatile
        private var instance: OfflineSyncManager? = null

        fun getInstance(context: Context): OfflineSyncManager {
            return instance ?: synchronized(this) {
                instance ?: OfflineSyncManager(context.applicationContext).also {
                    instance = it
                }
            }
        }

        val shared: OfflineSyncManager
            get() = instance ?: error("OfflineSyncManager must be initialized via getInstance(context) first")
    }
}
