package com.intellidream.daily.network

import android.util.Log
import com.intellidream.daily.model.RemoteTagdoQuickNoteRecord
import com.intellidream.daily.model.RemoteTagdoStreamRecord
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray

class TagdosRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    /**
     * Explicit upsert payload without `id` and without default property values so:
     * 1) `onConflict = "user_id,stream_number"` never hits a PK collision on `id` after stream reorder.
     * 2) Nullable `reminder_time` is always serialized as `"reminder_time": null` when cleared.
     */
    @Serializable
    private data class TagdosStreamUpsertPayload(
        @SerialName("user_id") val userId: String,
        @SerialName("stream_number") val streamNumber: Int,
        val title: String,
        @SerialName("raw_syntax") val rawSyntax: String,
        @SerialName("reminder_time") val reminderTime: String?,
        @SerialName("active_memos") val activeMemos: String,
        val attachments: JsonArray,
        @SerialName("updated_at") val updatedAt: String
    )

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    suspend fun pullStreams(userId: String): List<RemoteTagdoStreamRecord>? = withContext(Dispatchers.IO) {
        if (userId.isBlank() || userId == "guest") return@withContext null
        try {
            clientManager.client.postgrest["tagdos_streams"]
                .select {
                    filter {
                        eq("user_id", userId)
                    }
                    order("stream_number", Order.ASCENDING)
                }
                .decodeList<RemoteTagdoStreamRecord>()
        } catch (e: Exception) {
            Log.w(TAG, "pullStreams failed: ${e.message}")
            null
        }
    }

    suspend fun upsertStream(
        userId: String,
        streamNumber: Int,
        title: String,
        rawSyntax: String,
        reminderTime: String?,
        activeMemos: String,
        attachmentsJson: String = "[]",
        updatedAtIso: String
    ): Boolean = withContext(Dispatchers.IO) {
        if (userId.isBlank() || userId == "guest") return@withContext false
        try {
            val attachmentsArray = runCatching {
                val trimmed = attachmentsJson.trim()
                if (trimmed.startsWith("[")) json.parseToJsonElement(trimmed).jsonArray else JsonArray(emptyList())
            }.getOrElse { JsonArray(emptyList()) }

            val payload = TagdosStreamUpsertPayload(
                userId = userId,
                streamNumber = streamNumber,
                title = title,
                rawSyntax = rawSyntax,
                reminderTime = reminderTime,
                activeMemos = activeMemos,
                attachments = attachmentsArray,
                updatedAt = updatedAtIso
            )
            clientManager.client.postgrest["tagdos_streams"].upsert(payload) {
                onConflict = "user_id,stream_number"
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "upsertStream($streamNumber) failed: ${e.message}")
            false
        }
    }

    suspend fun deleteStreamsOverflow(userId: String, maxStreamNumber: Int): Boolean = withContext(Dispatchers.IO) {
        if (userId.isBlank() || userId == "guest") return@withContext false
        try {
            clientManager.client.postgrest["tagdos_streams"].delete {
                filter {
                    eq("user_id", userId)
                    gt("stream_number", maxStreamNumber)
                }
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "deleteStreamsOverflow($maxStreamNumber) failed: ${e.message}")
            false
        }
    }

    suspend fun pullQuickNotes(userId: String): List<RemoteTagdoQuickNoteRecord>? = withContext(Dispatchers.IO) {
        if (userId.isBlank() || userId == "guest") return@withContext null
        try {
            clientManager.client.postgrest["tagdos_quick_notes"]
                .select {
                    filter {
                        eq("user_id", userId)
                    }
                    order("updated_at", Order.DESCENDING)
                }
                .decodeList<RemoteTagdoQuickNoteRecord>()
        } catch (e: Exception) {
            Log.w(TAG, "pullQuickNotes failed: ${e.message}")
            null
        }
    }

    suspend fun upsertQuickNote(record: RemoteTagdoQuickNoteRecord): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["tagdos_quick_notes"].upsert(record) {
                onConflict = "id"
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "upsertQuickNote(${record.id}) failed: ${e.message}")
            false
        }
    }

    suspend fun deleteQuickNote(userId: String, noteId: String): Boolean = withContext(Dispatchers.IO) {
        if (userId.isBlank() || userId == "guest") return@withContext false
        try {
            clientManager.client.postgrest["tagdos_quick_notes"].delete {
                filter {
                    eq("id", noteId)
                    eq("user_id", userId)
                }
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "deleteQuickNote($noteId) failed: ${e.message}")
            false
        }
    }

    companion object {
        private const val TAG = "TagdosRemoteService"
    }
}
