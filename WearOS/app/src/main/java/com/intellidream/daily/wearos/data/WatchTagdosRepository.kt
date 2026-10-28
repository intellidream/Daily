package com.intellidream.daily.wearos.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.ui.graphics.Color
import com.intellidream.daily.wearos.presentation.theme.DailyWearColors
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

@Serializable
enum class TagDoPillType {
    STANDARD,
    FINANCIAL,
    URGENT,
    TEMPORAL_OR_METRIC,
    COMPLETED
}

val TagDoPillType.badgeColor: Color
    get() = when (this) {
        TagDoPillType.STANDARD -> Color(0xFF00E5FF)          // Neon Cyan
        TagDoPillType.FINANCIAL -> Color(0xFF00E676)         // Neon Emerald Green
        TagDoPillType.URGENT -> Color(0xFFFF2D55)            // Glowing Ruby Coral
        TagDoPillType.TEMPORAL_OR_METRIC -> Color(0xFFFFD600)// Neon Amber Yellow
        TagDoPillType.COMPLETED -> Color(0xFF8E8E93)         // Dimmed Slate
    }

@Serializable
data class TagDoPill(
    val id: String = UUID.randomUUID().toString(),
    val rawText: String,
    val type: TagDoPillType = detectType(rawText),
    val isCompleted: Boolean = false
) {
    companion object {
        fun detectType(text: String): TagDoPillType {
            return when {
                text.contains("$") || text.contains("€") -> TagDoPillType.FINANCIAL
                text.contains("!") -> TagDoPillType.URGENT
                text.any { it.isDigit() } -> TagDoPillType.TEMPORAL_OR_METRIC
                else -> TagDoPillType.STANDARD
            }
        }
    }
}

@Serializable
data class TagDoCluster(
    val id: String = UUID.randomUUID().toString(),
    val pills: List<TagDoPill> = emptyList(),
    val rawText: String = ""
) {
    val activePills: List<TagDoPill> get() = pills.filter { !it.isCompleted }
}

@Serializable
data class TagDoStream(
    val id: String = UUID.randomUUID().toString(),
    val streamNumber: Int,
    val title: String,
    val rawText: String,
    val clusters: List<TagDoCluster> = emptyList(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    val activePills: List<TagDoPill> get() = clusters.flatMap { it.activePills }
    val drivingPill: TagDoPill? get() = activePills.firstOrNull()

    val streamShortCode: String
        get() = when (streamNumber) {
            1 -> "S1"
            2 -> "S2"
            3 -> "S3"
            4 -> "S4"
            5 -> "S5"
            else -> "S$streamNumber"
        }

    val streamColor: Color
        get() = when (streamNumber) {
            1 -> Color(0xFF00E5FF)
            2 -> Color(0xFF38BDF8)
            3 -> Color(0xFF10B981)
            4 -> Color(0xFFF59E0B)
            5 -> Color(0xFFEC4899)
            else -> Color(0xFFA855F7)
        }
}

@Serializable
data class TagDoQuickNote(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val content: String,
    val isPinned: Boolean = true,
    val updatedAt: Long = System.currentTimeMillis()
)

@Serializable
internal data class RemoteStreamDTO(
    val id: String,
    val user_id: String,
    val stream_number: Int,
    val title: String,
    val raw_syntax: String,
    val updated_at: String? = null
)

@Serializable
internal data class RemoteNoteDTO(
    val id: String,
    val title: String,
    val content: String,
    val is_pinned: Boolean = true,
    val updated_at: String? = null
)

class WatchTagdosRepository private constructor(private val context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private val _streams = MutableStateFlow<List<TagDoStream>>(loadCachedStreams())
    val streams: StateFlow<List<TagDoStream>> = _streams.asStateFlow()

    private val _quickNotes = MutableStateFlow<List<TagDoQuickNote>>(loadCachedNotes())
    val quickNotes: StateFlow<List<TagDoQuickNote>> = _quickNotes.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    companion object {
        private const val PREFS_NAME = "watch_tagdos_prefs"
        private const val KEY_STREAMS_CACHE = "tagdos_streams_cache_v1"
        private const val KEY_NOTES_CACHE = "tagdos_quick_notes_cache_v1"

        @Volatile
        private var instance: WatchTagdosRepository? = null

        fun getInstance(context: Context): WatchTagdosRepository {
            return instance ?: synchronized(this) {
                instance ?: WatchTagdosRepository(context.applicationContext).also { instance = it }
            }
        }

        fun parseStream(
            rawText: String,
            title: String,
            streamNumber: Int,
            id: String = UUID.randomUUID().toString(),
            existingStream: TagDoStream? = null
        ): TagDoStream {
            val trimmed = rawText.trim()
            if (trimmed.isEmpty()) {
                return TagDoStream(id = id, streamNumber = streamNumber, title = title, rawText = "")
            }

            val rawClusters = trimmed.split("&").map { it.trim() }.filter { it.isNotEmpty() }
            val parsedClusters = mutableListOf<TagDoCluster>()

            for (rawCluster in rawClusters) {
                val rawTokens = rawCluster.split("/").map { it.trim() }.filter { it.isNotEmpty() }
                val pills = mutableListOf<TagDoPill>()
                for (token in rawTokens) {
                    val existing = existingStream?.clusters?.flatMap { it.pills }?.firstOrNull { it.rawText == token }
                    if (existing != null) {
                        pills.add(existing.copy())
                    } else {
                        pills.add(TagDoPill(rawText = token))
                    }
                }
                if (pills.isNotEmpty()) {
                    parsedClusters.add(TagDoCluster(pills = pills, rawText = rawCluster))
                }
            }

            return TagDoStream(
                id = id,
                streamNumber = streamNumber,
                title = title,
                rawText = trimmed,
                clusters = parsedClusters
            )
        }
    }

    private fun loadCachedStreams(): List<TagDoStream> {
        val rawJson = prefs.getString(KEY_STREAMS_CACHE, null)
        if (!rawJson.isNullOrEmpty()) {
            try {
                return json.decodeFromString<List<TagDoStream>>(rawJson)
            } catch (ignored: Exception) {}
        }
        return listOf(
            parseStream("MG/GM/TG & FSH/LDL & C\$T/DUB/14 & PL98/PBZ/SPL/CLN", "Daily Ops", 1),
            parseStream("WRK/PRJ/REV & MET/ZOOM/CALL & TKT/BUG/PR", "Work & Code", 2),
            parseStream("FIT/GYM/RUN & PROT/CREAT & SLP/REC/HRV", "Health & Fitness", 3),
            parseStream("FIN/CARD/CASH & INV/STK/CRYP & SUB/UTL/CHL", "Finances & Bills", 4),
            parseStream("HOM/ORD/CLN & BUY/MKT/GROC & FAM/CALL/VIS", "Home & Life", 5)
        )
    }

    private fun loadCachedNotes(): List<TagDoQuickNote> {
        val rawJson = prefs.getString(KEY_NOTES_CACHE, null)
        if (!rawJson.isNullOrEmpty()) {
            try {
                return json.decodeFromString<List<TagDoQuickNote>>(rawJson)
            } catch (ignored: Exception) {}
        }
        return listOf(
            TagDoQuickNote(title = "Groceries", content = "Lapte de migdale, Cafea Columbia, Fructe de padure"),
            TagDoQuickNote(title = "Passcode Parking", content = "#5829 intrare subteran")
        )
    }

    private fun persistData() {
        try {
            prefs.edit()
                .putString(KEY_STREAMS_CACHE, json.encodeToString(_streams.value))
                .putString(KEY_NOTES_CACHE, json.encodeToString(_quickNotes.value))
                .apply()
        } catch (ignored: Exception) {}
    }

    suspend fun syncWithSupabase() = withContext(Dispatchers.IO) {
        val sessionManager = WatchSessionManager.getInstance(context)
        val client = sessionManager.supabaseClient ?: return@withContext
        val userId = sessionManager.currentUserId.value ?: return@withContext

        _isSyncing.value = true
        try {
            // 1. Fetch Streams
            val resStreams = client.postgrest["tagdos_streams"]
                .select {
                    filter { eq("user_id", userId) }
                    order("stream_number", order = Order.ASCENDING)
                }
                .decodeList<RemoteStreamDTO>()

            if (resStreams.isNotEmpty()) {
                val updatedStreams = resStreams.map { remote ->
                    val existing = _streams.value.firstOrNull { it.streamNumber == remote.stream_number }
                    parseStream(
                        rawText = remote.raw_syntax,
                        title = remote.title,
                        streamNumber = remote.stream_number,
                        id = remote.id,
                        existingStream = existing
                    )
                }.sortedBy { it.streamNumber }

                _streams.value = updatedStreams
                persistData()
            }

            // 2. Fetch Pinned Quick Notes
            val resNotes = client.postgrest["tagdos_quick_notes"]
                .select {
                    filter {
                        eq("user_id", userId)
                        eq("is_pinned", true)
                    }
                    order("updated_at", order = Order.DESCENDING)
                    limit(10)
                }
                .decodeList<RemoteNoteDTO>()

            if (resNotes.isNotEmpty()) {
                val updatedNotes = resNotes.map { r ->
                    TagDoQuickNote(
                        id = r.id,
                        title = r.title,
                        content = r.content,
                        isPinned = r.is_pinned
                    )
                }
                _quickNotes.value = updatedNotes
                persistData()
            }
        } catch (e: Exception) {
            android.util.Log.e("WatchTagdosRepository", "Sync failed: ${e.message}")
        } finally {
            _isSyncing.value = false
        }
    }

    fun completePill(streamNumber: Int, pillId: String) {
        val currentList = _streams.value.toMutableList()
        val sIdx = currentList.indexOfFirst { it.streamNumber == streamNumber }
        if (sIdx == -1) return

        val stream = currentList[sIdx]
        var pillFound = false
        val updatedClusters = stream.clusters.map { cluster ->
            val updatedPills = cluster.pills.map { pill ->
                if (pill.id == pillId) {
                    pillFound = true
                    pill.copy(isCompleted = true)
                } else pill
            }
            cluster.copy(pills = updatedPills)
        }

        if (!pillFound) return

        val activeClusterStrings = updatedClusters.mapNotNull { cluster ->
            val activeTokens = cluster.pills.filter { !it.isCompleted }.map { it.rawText }
            if (activeTokens.isEmpty()) null else activeTokens.joinToString("/")
        }
        val newRawSyntax = activeClusterStrings.joinToString(" & ")

        currentList[sIdx] = stream.copy(
            clusters = updatedClusters,
            rawText = newRawSyntax,
            updatedAt = System.currentTimeMillis()
        )
        _streams.value = currentList
        persistData()

        pushStreamUpdate(streamNumber, newRawSyntax)
    }

    fun recycleDrivingPill(streamNumber: Int) {
        val currentList = _streams.value.toMutableList()
        val sIdx = currentList.indexOfFirst { it.streamNumber == streamNumber }
        if (sIdx == -1) return

        val stream = currentList[sIdx]
        val driving = stream.drivingPill ?: return
        val clusters = stream.clusters.toMutableList()
        if (clusters.isEmpty()) return

        val firstClusterPills = clusters[0].pills.filter { it.id != driving.id }.toMutableList()
        if (firstClusterPills.isEmpty() && clusters.size > 1) {
            val lastClusterPills = clusters[clusters.size - 1].pills.toMutableList()
            lastClusterPills.add(driving)
            clusters[clusters.size - 1] = clusters[clusters.size - 1].copy(pills = lastClusterPills)
            clusters.removeAt(0)
        } else {
            firstClusterPills.add(driving)
            clusters[0] = clusters[0].copy(pills = firstClusterPills)
        }

        val newRawSyntax = clusters.joinToString(" & ") { c -> c.pills.joinToString("/") { it.rawText } }
        currentList[sIdx] = stream.copy(
            clusters = clusters,
            rawText = newRawSyntax,
            updatedAt = System.currentTimeMillis()
        )
        _streams.value = currentList
        persistData()

        pushStreamUpdate(streamNumber, newRawSyntax)
    }

    fun addQuickTask(streamNumber: Int, text: String) {
        val clean = text.trim().replace("/", "-").replace("&", "+")
        if (clean.isEmpty()) return

        val currentList = _streams.value.toMutableList()
        val sIdx = currentList.indexOfFirst { it.streamNumber == streamNumber }
        if (sIdx == -1) return

        val stream = currentList[sIdx]
        val newRaw = if (stream.rawText.isEmpty()) clean else "${stream.rawText}/$clean"
        currentList[sIdx] = parseStream(newRaw, stream.title, streamNumber, stream.id, stream)
        _streams.value = currentList
        persistData()

        pushStreamUpdate(streamNumber, newRaw)
    }

    fun addQuickNote(title: String, content: String) {
        val cleanTitle = title.trim()
        val cleanContent = content.trim()
        if (cleanTitle.isEmpty() && cleanContent.isEmpty()) return

        val finalTitle = if (cleanTitle.isEmpty()) cleanContent.lines().firstOrNull() ?: "Note" else cleanTitle
        val newNote = TagDoQuickNote(
            title = finalTitle,
            content = if (cleanContent.isEmpty()) finalTitle else cleanContent,
            isPinned = true
        )

        val currentNotes = _quickNotes.value.toMutableList()
        currentNotes.add(0, newNote)
        _quickNotes.value = currentNotes
        persistData()

        CoroutineScope(Dispatchers.IO).launch {
            val sessionManager = WatchSessionManager.getInstance(context)
            val client = sessionManager.supabaseClient ?: return@launch
            val userId = sessionManager.currentUserId.value ?: return@launch
            try {
                val obj = buildJsonObject {
                    put("id", newNote.id)
                    put("user_id", userId)
                    put("title", newNote.title)
                    put("content", newNote.content)
                    put("is_pinned", true)
                }
                client.postgrest["tagdos_quick_notes"].insert(obj)
            } catch (e: Exception) {
                android.util.Log.e("WatchTagdosRepository", "Failed to push note: ${e.message}")
            }
        }
    }

    private fun pushStreamUpdate(streamNumber: Int, newRawSyntax: String) {
        CoroutineScope(Dispatchers.IO).launch {
            val sessionManager = WatchSessionManager.getInstance(context)
            val client = sessionManager.supabaseClient ?: return@launch
            val userId = sessionManager.currentUserId.value ?: return@launch

            try {
                val updateObj = buildJsonObject {
                    put("raw_syntax", newRawSyntax)
                    put("updated_at", java.time.Instant.now().toString())
                }
                client.postgrest["tagdos_streams"].update(updateObj) {
                    filter {
                        eq("user_id", userId)
                        eq("stream_number", streamNumber)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("WatchTagdosRepository", "Failed to push stream: ${e.message}")
            }
        }
    }
}
