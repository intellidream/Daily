package com.intellidream.daily.database

import com.intellidream.daily.database.dao.TagdosDao
import com.intellidream.daily.database.entity.TagdoQuickNoteEntity
import com.intellidream.daily.database.entity.TagdoStreamEntity
import com.intellidream.daily.model.RemoteTagdoQuickNoteRecord
import com.intellidream.daily.model.RemoteTagdoStreamRecord
import com.intellidream.daily.model.TagDoCluster
import com.intellidream.daily.model.TagDoPill
import com.intellidream.daily.model.TagDoQuickNote
import com.intellidream.daily.model.TagDoStream
import com.intellidream.daily.model.TagdosNavigationTarget
import com.intellidream.daily.model.TagdosParser
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

interface TagdosSyncHandler {
    suspend fun pullStreams(userId: String): List<RemoteTagdoStreamRecord>?
    suspend fun upsertStream(
        userId: String,
        streamNumber: Int,
        title: String,
        rawSyntax: String,
        reminderTime: String?,
        activeMemos: String,
        attachmentsJson: String,
        updatedAtIso: String
    ): Boolean
    suspend fun deleteStreamsOverflow(userId: String, maxStreamNumber: Int): Boolean
    suspend fun pullQuickNotes(userId: String): List<RemoteTagdoQuickNoteRecord>?
    suspend fun upsertQuickNote(record: RemoteTagdoQuickNoteRecord): Boolean
    suspend fun deleteQuickNote(userId: String, noteId: String): Boolean
}

/**
 * Centralized repository managing TagDoS streams, mental tags, per-stream active memos, and quick notes.
 * Backed by Room SQLite database with synced_at dirty tracking.
 * Matches iOS [TagdosStore.swift].
 */
class TagdosRepository(
    private val tagdosDao: TagdosDao,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
) {
    private val _streams = MutableStateFlow<List<TagDoStream>>(emptyList())
    val streams: StateFlow<List<TagDoStream>> = _streams.asStateFlow()

    private val _quickNotes = MutableStateFlow<List<TagDoQuickNote>>(emptyList())
    val quickNotes: StateFlow<List<TagDoQuickNote>> = _quickNotes.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _pendingNavigation = MutableStateFlow<TagdosNavigationTarget?>(null)
    val pendingNavigation: StateFlow<TagdosNavigationTarget?> = _pendingNavigation.asStateFlow()

    var onStreamsChanged: (() -> Unit)? = null
    var syncHandler: TagdosSyncHandler? = null

    @Volatile
    var currentUserId: String = "guest"

    private val syncMutex = Mutex()
    private val attachmentsJsonByStreamId = ConcurrentHashMap<String, String>()
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private var pushDebounceJob: Job? = null

    @Volatile
    private var lastSyncMs: Long = 0L

    fun requestNavigation(
        streamId: String? = null,
        clusterIndex: Int? = null,
        pillId: String? = null,
        openPillEditor: Boolean = false
    ) {
        if (streamId != null || clusterIndex != null || pillId != null) {
            _pendingNavigation.value = TagdosNavigationTarget(
                streamId = streamId,
                clusterIndex = clusterIndex,
                pillId = pillId,
                openPillEditor = openPillEditor
            )
        }
    }

    fun handleDeepLink(uriString: String) {
        val qIdx = uriString.indexOf('?')
        if (qIdx < 0 || qIdx >= uriString.length - 1) return
        val query = uriString.substring(qIdx + 1).substringBefore('#')
        val params = linkedMapOf<String, String>()
        for (part in query.split('&')) {
            val kv = part.split('=', limit = 2)
            if (kv.size == 2) {
                val key = runCatching { java.net.URLDecoder.decode(kv[0], "UTF-8") }.getOrDefault(kv[0])
                val value = runCatching { java.net.URLDecoder.decode(kv[1], "UTF-8") }.getOrDefault(kv[1])
                params[key] = value
            }
        }
        val streamId = params["streamId"]?.takeIf { it.isNotBlank() }
        val clusterIndex = params["clusterIndex"]?.toIntOrNull()
        val pillId = params["pillId"]?.takeIf { it.isNotBlank() }
        val openEdit = params["edit"] == "1" || pillId != null
        requestNavigation(
            streamId = streamId,
            clusterIndex = clusterIndex,
            pillId = pillId,
            openPillEditor = openEdit
        )
    }

    fun consumePendingNavigation() {
        _pendingNavigation.value = null
    }

    private fun encodeClusterReminders(clusters: List<TagDoCluster>): String {
        val parts = clusters.mapIndexedNotNull { idx, c ->
            c.reminderTime?.let { "$idx=$it" }
        }
        return if (parts.isEmpty()) "{}" else parts.joinToString(",")
    }

    private fun decodeClusterReminders(raw: String?): Map<Int, Long> {
        val clean = raw?.trim().orEmpty()
        if (clean.isEmpty() || clean == "{}") return emptyMap()
        val map = linkedMapOf<Int, Long>()
        for (pair in clean.split(',')) {
            val kv = pair.split('=', limit = 2)
            if (kv.size == 2) {
                val idx = kv[0].trim().toIntOrNull()
                val ts = kv[1].trim().toLongOrNull()
                if (idx != null && ts != null) {
                    map[idx] = ts
                }
            }
        }
        return map
    }

    companion object {
        const val DEFAULT_STREAM_1 = "MG/GM/TG & FSH/LDL & C\$T/DUB/14 & PL98/PBZ/SPL/CLN/ROT\$ & BP/ACTE & VER/CLD/DIV\$/CNTR/!MP\$/FCT\$/STK/BON\$ & BIA/€CO & SSD/ELVS/MEIZ & GORN/PICI/CRNA/IOA & CDO/SRN/NLU/NIN/SVS & ITP/CRRvg/Park/Ghis"
        const val DEFAULT_STREAM_2 = "WRK/PRJ/REV & MET/ZOOM/CALL & TKT/BUG/PR & DEPL/REL"
        const val DEFAULT_STREAM_3 = "FIT/GYM/RUN & PROT/CREAT & SLP/REC/HRV"
        const val DEFAULT_STREAM_4 = "FIN/CARD/CASH & INV/STK/CRYP & SUB/UTL/CHL"
        const val DEFAULT_STREAM_5 = "HOM/ORD/CLN & BUY/MKT/GROC & FAM/CALL/VIS"
    }

    init {
        // 1. Observe Streams Flow
        scope.launch {
            tagdosDao.getAllStreamsFlow().collectLatest { entities ->
                if (entities.isEmpty()) {
                    seedDefaultStreams()
                } else {
                    val currentStreams = _streams.value
                    val parsed = entities.map { entity ->
                        attachmentsJsonByStreamId[entity.id] = entity.attachmentsJson
                        val existing = currentStreams.firstOrNull { it.id == entity.id }
                        val savedClusterRems = decodeClusterReminders(entity.clusterRemindersJson)
                        val stream = TagdosParser.parseStream(
                            rawText = entity.rawText,
                            title = entity.title,
                            id = entity.id,
                            streamReminder = entity.streamReminder,
                            orderIndex = entity.orderIndex,
                            existingStream = existing
                        )
                        val hydratedClusters = stream.clusters.mapIndexed { idx, cluster ->
                            cluster.copy(reminderTime = savedClusterRems[idx])
                        }
                        stream.copy(
                            clusters = hydratedClusters,
                            customTitle = entity.customTitle,
                            activeMemos = entity.activeMemos,
                            updatedAt = entity.updatedAt
                        )
                    }
                    _streams.value = parsed
                    onStreamsChanged?.invoke()
                }
            }
        }

        // 2. Observe Quick Notes Flow
        scope.launch {
            tagdosDao.getAllNotesFlow().collectLatest { entities ->
                if (entities.isEmpty()) {
                    seedDefaultNotes()
                } else {
                    val notes = entities.map { entity ->
                        val decodedTags = runCatching {
                            if (entity.tagsJson.isBlank()) emptyList()
                            else json.decodeFromString(ListSerializer(String.serializer()), entity.tagsJson)
                        }.getOrDefault(emptyList())
                        TagDoQuickNote(
                            id = entity.id,
                            userId = entity.userId,
                            title = entity.title,
                            content = entity.content,
                            isPinned = entity.isPinned,
                            tags = decodedTags,
                            createdAt = entity.createdAt,
                            updatedAt = entity.updatedAt
                        )
                    }
                    _quickNotes.value = notes
                }
            }
        }
    }

    private suspend fun seedDefaultStreams() = withContext(ioDispatcher) {
        val defaultStreams = listOf(
            TagdosParser.parseStream(rawText = DEFAULT_STREAM_1, title = "Stream 1: Daily Ops", orderIndex = 0),
            TagdosParser.parseStream(rawText = DEFAULT_STREAM_2, title = "Stream 2: Work & Code", orderIndex = 1),
            TagdosParser.parseStream(rawText = DEFAULT_STREAM_3, title = "Stream 3: Health & Fitness", orderIndex = 2),
            TagdosParser.parseStream(rawText = DEFAULT_STREAM_4, title = "Stream 4: Finances & Bills", orderIndex = 3),
            TagdosParser.parseStream(rawText = DEFAULT_STREAM_5, title = "Stream 5: Home & Life", orderIndex = 4)
        )

        val entities = defaultStreams.map { s ->
            TagdoStreamEntity(
                id = s.id,
                orderIndex = s.orderIndex,
                title = s.title,
                customTitle = s.customTitle,
                rawText = s.rawText,
                streamReminder = s.streamReminder,
                activeMemos = s.activeMemos,
                updatedAt = 0L, // Untouched starter seed so Supabase cloud rows always win
                syncedAt = null
            )
        }
        tagdosDao.upsertStreams(entities)
    }

    private suspend fun seedDefaultNotes() = withContext(ioDispatcher) {
        val defaultNotes = listOf(
            TagDoQuickNote(
                id = UUID.randomUUID().toString(),
                title = "Concert Tickets",
                content = "Concert Tickets: book 2x passes and confirm budget",
                isPinned = true
            ),
            TagDoQuickNote(
                id = UUID.randomUUID().toString(),
                title = "Car Maintenance",
                content = "Car Maintenance: refuel 98 octane and schedule interior clean",
                isPinned = false
            )
        )

        val entities = defaultNotes.map { n ->
            TagdoQuickNoteEntity(
                id = n.id,
                userId = n.userId,
                title = n.title,
                content = n.content,
                isPinned = n.isPinned,
                createdAt = 0L,
                updatedAt = 0L, // Untouched starter seed so Supabase cloud notes always win
                syncedAt = null
            )
        }
        tagdosDao.upsertNotes(entities)
    }

    // MARK: - Stream Mutations

    private fun TagDoStream.toEntity(syncedAt: Long? = null): TagdoStreamEntity =
        TagdoStreamEntity(
            id = id,
            orderIndex = orderIndex,
            title = title,
            customTitle = customTitle,
            rawText = rawText,
            streamReminder = streamReminder,
            clusterRemindersJson = encodeClusterReminders(clusters),
            activeMemos = activeMemos,
            attachmentsJson = attachmentsJsonByStreamId[id] ?: "[]",
            updatedAt = updatedAt,
            syncedAt = syncedAt
        )

    private fun persistStreamUpdate(updated: TagDoStream) {
        val current = _streams.value.toMutableList()
        val idx = current.indexOfFirst { it.id == updated.id }
        if (idx >= 0) {
            current[idx] = updated
        } else {
            current.add(updated)
            current.sortBy { it.orderIndex }
        }
        _streams.value = current
        onStreamsChanged?.invoke()
        scope.launch(ioDispatcher) {
            tagdosDao.upsertStream(updated.toEntity(syncedAt = null))
            scheduleCloudPush()
        }
    }

    fun updateStreamRawText(streamId: String, newRawText: String) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        var updated = TagdosParser.parseStream(
            rawText = newRawText,
            title = stream.customTitle ?: stream.title,
            id = stream.id,
            streamReminder = stream.streamReminder,
            orderIndex = stream.orderIndex,
            existingStream = stream
        )
        val customTitle = stream.customTitle?.trim()?.takeIf { it.isNotEmpty() }
        updated = if (customTitle == null) {
            updated.copy(title = updated.autoDetectedTitle, customTitle = null)
        } else {
            updated.copy(customTitle = customTitle, title = customTitle)
        }
        updated = updated.copy(
            activeMemos = stream.activeMemos,
            attachments = stream.attachments,
            updatedAt = System.currentTimeMillis()
        )
        persistStreamUpdate(updated)
    }

    fun updateStreamTitle(streamId: String, newTitle: String?) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        val clean = newTitle?.trim()
        val (finalTitle, finalCustom) = if (!clean.isNullOrEmpty()) {
            clean to clean
        } else {
            stream.autoDetectedTitle to null
        }

        val updated = stream.copy(
            title = finalTitle,
            customTitle = finalCustom,
            updatedAt = System.currentTimeMillis()
        )
        persistStreamUpdate(updated)
    }

    fun setStreamReminder(streamId: String, date: Long?) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        persistStreamUpdate(stream.copy(streamReminder = date, updatedAt = System.currentTimeMillis()))
    }

    fun setClusterReminder(streamId: String, clusterIndex: Int, date: Long?) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        if (clusterIndex !in stream.clusters.indices) return
        val updatedClusters = stream.clusters.mapIndexed { idx, c ->
            if (idx == clusterIndex) c.copy(reminderTime = date) else c
        }
        persistStreamUpdate(stream.copy(clusters = updatedClusters, updatedAt = System.currentTimeMillis()))
    }

    fun updateStreamMemos(streamId: String, memos: String) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        persistStreamUpdate(stream.copy(activeMemos = memos, updatedAt = System.currentTimeMillis()))
    }

    fun recyclePillToBack(streamId: String, pillId: String) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        persistStreamUpdate(TagdosParser.recyclePillToBack(stream, pillId))
    }

    fun togglePillCompletion(streamId: String, pillId: String) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        persistStreamUpdate(TagdosParser.togglePillCompletion(stream, pillId))
    }

    fun removePill(streamId: String, pillId: String) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        persistStreamUpdate(TagdosParser.removePill(stream, pillId))
    }

    fun movePillToFront(streamId: String, pillId: String) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        persistStreamUpdate(TagdosParser.movePillToFront(stream, pillId))
    }

    fun addPill(streamId: String, clusterIndex: Int, text: String) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        persistStreamUpdate(TagdosParser.addPill(stream, clusterIndex, text))
    }

    fun updatePillText(streamId: String, pillId: String, newText: String) {
        val stream = _streams.value.firstOrNull { it.id == streamId } ?: return
        persistStreamUpdate(TagdosParser.updatePillText(stream, pillId, newText))
    }

    fun createStream(
        title: String? = null,
        rawText: String = "",
        activeMemos: String = ""
    ): String {
        val current = _streams.value.toMutableList()
        val nextOrderIndex = (current.maxOfOrNull { it.orderIndex } ?: -1) + 1
        val stream = buildNewStream(title, rawText, activeMemos, nextOrderIndex)
        current.add(stream)
        _streams.value = current
        onStreamsChanged?.invoke()

        scope.launch(ioDispatcher) {
            tagdosDao.upsertStream(stream.toEntity(syncedAt = null))
            scheduleCloudPush()
        }
        return stream.id
    }

    private fun buildNewStream(
        title: String?,
        rawText: String,
        activeMemos: String,
        orderIndex: Int
    ): TagDoStream {
        val cleanTitle = title?.trim()?.takeIf { it.isNotEmpty() }
        val newId = UUID.randomUUID().toString()
        var stream = TagdosParser.parseStream(
            rawText = rawText,
            title = cleanTitle ?: "Stream ${orderIndex + 1}",
            id = newId,
            orderIndex = orderIndex
        )
        stream = if (cleanTitle != null) {
            stream.copy(customTitle = cleanTitle, title = cleanTitle, activeMemos = activeMemos, updatedAt = System.currentTimeMillis())
        } else {
            stream.copy(customTitle = null, title = stream.autoDetectedTitle, activeMemos = activeMemos, updatedAt = System.currentTimeMillis())
        }
        return stream
    }

    fun moveStream(fromIndex: Int, toIndex: Int) {
        val current = _streams.value
        if (fromIndex !in current.indices || toIndex !in current.indices || fromIndex == toIndex) return
        val reordered = current.toMutableList()
        val item = reordered.removeAt(fromIndex)
        reordered.add(toIndex, item)
        applyReorderedStreams(reordered)
    }

    fun reorderStreams(orderedIds: List<String>) {
        val current = _streams.value
        val byId = current.associateBy { it.id }.toMutableMap()
        val reordered = mutableListOf<TagDoStream>()
        for (id in orderedIds) {
            byId.remove(id)?.let { reordered.add(it) }
        }
        for (s in current) {
            if (byId.containsKey(s.id)) reordered.add(s)
        }
        if (reordered.map { it.id } == current.map { it.id }) return
        applyReorderedStreams(reordered)
    }

    private fun applyReorderedStreams(reordered: List<TagDoStream>) {
        val now = System.currentTimeMillis()
        val reindexed = reordered.mapIndexed { idx, stream ->
            val shifted = stream.copy(orderIndex = idx, updatedAt = now)
            val custom = shifted.customTitle?.trim()?.takeIf { it.isNotEmpty() }
            if (custom == null) shifted.copy(title = shifted.autoDetectedTitle, customTitle = null)
            else shifted.copy(title = custom, customTitle = custom)
        }
        _streams.value = reindexed
        onStreamsChanged?.invoke()
        scope.launch(ioDispatcher) {
            tagdosDao.upsertStreams(reindexed.map { it.toEntity(syncedAt = null) })
            scheduleCloudPush()
        }
    }

    fun deleteStream(streamId: String) {
        val current = _streams.value
        if (current.size <= 1) return
        val remaining = current.filter { it.id != streamId }
        if (remaining.size == current.size) return

        val reindexedDomain = remaining.mapIndexed { idx, stream ->
            val shifted = stream.copy(orderIndex = idx, updatedAt = System.currentTimeMillis())
            if (shifted.customTitle.isNullOrBlank()) {
                shifted.copy(title = shifted.autoDetectedTitle)
            } else {
                shifted
            }
        }
        _streams.value = reindexedDomain
        onStreamsChanged?.invoke()

        scope.launch(ioDispatcher) {
            tagdosDao.deleteStreamById(streamId)
            tagdosDao.upsertStreams(reindexedDomain.map { it.toEntity(syncedAt = null) })
            val uid = currentUserId
            val handler = syncHandler
            if (handler != null && uid.isNotBlank() && uid != "guest") {
                handler.deleteStreamsOverflow(uid, reindexedDomain.size)
            }
            scheduleCloudPush()
        }
    }

    sealed class TagdosTaskImportTarget {
        data class ReplaceStream(val streamId: String) : TagdosTaskImportTarget()
        data class AppendToStream(val streamId: String) : TagdosTaskImportTarget()
        data class NewStream(val title: String) : TagdosTaskImportTarget()
    }

    data class TagdosTaskImportItem(
        val dslOrTag: String,
        val memoLine: String?,
        val target: TagdosTaskImportTarget
    )

    fun importExternalTaskBatch(items: List<TagdosTaskImportItem>): String? {
        if (items.isEmpty()) return null
        val current = _streams.value.toMutableList()
        val touchedEntities = linkedMapOf<String, TagdoStreamEntity>()
        var firstAffectedId: String? = null
        val now = System.currentTimeMillis()

        // 1. Replace targets
        val replaceOrder = mutableListOf<String>()
        val replaceGroups = linkedMapOf<String, MutableList<TagdosTaskImportItem>>()
        for (item in items) {
            val target = item.target
            if (target is TagdosTaskImportTarget.ReplaceStream) {
                if (!replaceGroups.containsKey(target.streamId)) replaceOrder.add(target.streamId)
                replaceGroups.getOrPut(target.streamId) { mutableListOf() }.add(item)
            }
        }

        for (streamId in replaceOrder) {
            val group = replaceGroups[streamId] ?: continue
            val idx = current.indexOfFirst { it.id == streamId }
            if (idx < 0) continue
            val existing = current[idx]
            val combinedDsl = combineImportedDslChunks(group.map { it.dslOrTag })
            val combinedMemos = group.mapNotNull { it.memoLine?.trim() }.filter { it.isNotEmpty() }.joinToString("\n")

            var updated = TagdosParser.parseStream(
                rawText = combinedDsl,
                title = existing.customTitle ?: existing.title,
                id = existing.id,
                streamReminder = existing.streamReminder,
                orderIndex = existing.orderIndex,
                existingStream = null
            )
            val custom = existing.customTitle?.trim()?.takeIf { it.isNotEmpty() }
            updated = if (custom == null) {
                updated.copy(title = updated.autoDetectedTitle, customTitle = null, activeMemos = combinedMemos, attachments = existing.attachments, updatedAt = now)
            } else {
                updated.copy(customTitle = custom, title = custom, activeMemos = combinedMemos, attachments = existing.attachments, updatedAt = now)
            }
            current[idx] = updated
            touchedEntities[updated.id] = updated.toEntity(syncedAt = null)
            if (firstAffectedId == null) firstAffectedId = updated.id
        }

        // 2. Append targets
        val appendOrder = mutableListOf<String>()
        val appendGroups = linkedMapOf<String, MutableList<TagdosTaskImportItem>>()
        for (item in items) {
            val target = item.target
            if (target is TagdosTaskImportTarget.AppendToStream) {
                if (!appendGroups.containsKey(target.streamId)) appendOrder.add(target.streamId)
                appendGroups.getOrPut(target.streamId) { mutableListOf() }.add(item)
            }
        }

        for (streamId in appendOrder) {
            val group = appendGroups[streamId] ?: continue
            val idx = current.indexOfFirst { it.id == streamId }
            if (idx < 0) continue
            val existing = current[idx]
            val combinedDsl = combineImportedDslChunks(group.map { it.dslOrTag })
            val combinedMemos = group.mapNotNull { it.memoLine?.trim() }.filter { it.isNotEmpty() }.joinToString("\n")
            val existingRaw = existing.rawText.trim()
            val newRaw = when {
                existingRaw.isEmpty() -> combinedDsl
                combinedDsl.isEmpty() -> existingRaw
                else -> "$existingRaw & $combinedDsl"
            }
            val existingMemos = existing.activeMemos.trim()
            val mergedMemos = when {
                existingMemos.isEmpty() -> combinedMemos
                combinedMemos.isEmpty() -> existingMemos
                else -> "$existingMemos\n$combinedMemos"
            }

            var updated = TagdosParser.parseStream(
                rawText = newRaw,
                title = existing.customTitle ?: existing.title,
                id = existing.id,
                streamReminder = existing.streamReminder,
                orderIndex = existing.orderIndex,
                existingStream = existing
            )
            val custom = existing.customTitle?.trim()?.takeIf { it.isNotEmpty() }
            updated = if (custom == null) {
                updated.copy(title = updated.autoDetectedTitle, customTitle = null, activeMemos = mergedMemos, attachments = existing.attachments, updatedAt = now)
            } else {
                updated.copy(customTitle = custom, title = custom, activeMemos = mergedMemos, attachments = existing.attachments, updatedAt = now)
            }
            current[idx] = updated
            touchedEntities[updated.id] = updated.toEntity(syncedAt = null)
            if (firstAffectedId == null) firstAffectedId = updated.id
        }

        // 3. New Stream targets
        val namedOrder = mutableListOf<String>()
        val namedGroups = linkedMapOf<String, MutableList<TagdosTaskImportItem>>()
        val unnamedItems = mutableListOf<TagdosTaskImportItem>()

        for (item in items) {
            val target = item.target
            if (target is TagdosTaskImportTarget.NewStream) {
                val cleanTitle = target.title.trim()
                if (cleanTitle.isEmpty()) {
                    unnamedItems.add(item)
                } else {
                    if (!namedGroups.containsKey(cleanTitle)) namedOrder.add(cleanTitle)
                    namedGroups.getOrPut(cleanTitle) { mutableListOf() }.add(item)
                }
            }
        }

        for (titleKey in namedOrder) {
            val group = namedGroups[titleKey] ?: continue
            val combinedDsl = combineImportedDslChunks(group.map { it.dslOrTag })
            val combinedMemos = group.mapNotNull { it.memoLine?.trim() }.filter { it.isNotEmpty() }.joinToString("\n")
            val nextIdx = (current.maxOfOrNull { it.orderIndex } ?: -1) + 1
            val created = buildNewStream(titleKey, combinedDsl, combinedMemos, nextIdx)
            current.add(created)
            touchedEntities[created.id] = created.toEntity(syncedAt = null)
            if (firstAffectedId == null) firstAffectedId = created.id
        }

        for (item in unnamedItems) {
            val combinedDsl = combineImportedDslChunks(listOf(item.dslOrTag))
            val memo = item.memoLine?.trim().orEmpty()
            val nextIdx = (current.maxOfOrNull { it.orderIndex } ?: -1) + 1
            val created = buildNewStream(null, combinedDsl, memo, nextIdx)
            current.add(created)
            touchedEntities[created.id] = created.toEntity(syncedAt = null)
            if (firstAffectedId == null) firstAffectedId = created.id
        }

        if (touchedEntities.isNotEmpty()) {
            _streams.value = current
            onStreamsChanged?.invoke()
            val toSave = touchedEntities.values.toList()
            scope.launch(ioDispatcher) {
                tagdosDao.upsertStreams(toSave)
                scheduleCloudPush()
            }
        }
        return firstAffectedId
    }

    fun importExternalTasks(
        mode: String,
        targetStreamId: String?,
        newStreamTitle: String?,
        rawDslChunks: List<String>,
        memoLines: List<String>
    ): String {
        val combinedDsl = combineImportedDslChunks(rawDslChunks)
        val combinedMemos = memoLines.map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n")
        val target: TagdosTaskImportTarget = when {
            mode == "new" -> TagdosTaskImportTarget.NewStream(newStreamTitle.orEmpty())
            mode == "replace" && targetStreamId != null && _streams.value.any { it.id == targetStreamId } ->
                TagdosTaskImportTarget.ReplaceStream(targetStreamId)
            targetStreamId != null && _streams.value.any { it.id == targetStreamId } ->
                TagdosTaskImportTarget.AppendToStream(targetStreamId)
            else -> TagdosTaskImportTarget.NewStream(newStreamTitle.orEmpty())
        }
        return importExternalTaskBatch(
            listOf(TagdosTaskImportItem(combinedDsl, combinedMemos.ifEmpty { null }, target))
        ) ?: createStream(title = newStreamTitle, rawText = combinedDsl, activeMemos = combinedMemos)
    }

    private fun combineImportedDslChunks(chunks: List<String>): String {
        val cleaned = chunks.map { it.trim() }.filter { it.isNotEmpty() }
        if (cleaned.isEmpty()) return ""

        val singleTags = mutableListOf<String>()
        val complexClusters = mutableListOf<String>()

        for (chunk in cleaned) {
            if (chunk.contains("&") || chunk.contains("/")) {
                complexClusters.add(chunk)
            } else {
                singleTags.add(chunk)
            }
        }

        val parts = mutableListOf<String>()
        if (singleTags.isNotEmpty()) {
            parts.add(singleTags.joinToString("/"))
        }
        parts.addAll(complexClusters)
        return parts.joinToString(" & ")
    }

    // MARK: - Quick Notes Mutations

    fun createQuickNote(title: String = "", content: String = "") {
        createQuickNoteReturningId(title, content)
    }

    fun createQuickNoteReturningId(title: String = "", content: String = ""): String {
        val noteId = UUID.randomUUID().toString()
        scope.launch(ioDispatcher) {
            val now = System.currentTimeMillis()
            val note = TagDoQuickNote(
                id = noteId,
                userId = currentUserId.takeIf { it.isNotBlank() && it != "guest" },
                title = title,
                content = content,
                isPinned = false,
                createdAt = now,
                updatedAt = now
            )
            tagdosDao.upsertNote(
                TagdoQuickNoteEntity(
                    id = note.id,
                    userId = note.userId,
                    title = note.title,
                    content = note.content,
                    isPinned = note.isPinned,
                    createdAt = note.createdAt,
                    updatedAt = note.updatedAt,
                    syncedAt = null
                )
            )
            scheduleCloudPush()
        }
        return noteId
    }

    fun updateQuickNote(id: String, title: String, content: String) {
        scope.launch(ioDispatcher) {
            val existing = tagdosDao.getNoteById(id) ?: return@launch
            val updated = existing.copy(
                title = title,
                content = content,
                updatedAt = System.currentTimeMillis(),
                syncedAt = null
            )
            tagdosDao.upsertNote(updated)
            scheduleCloudPush()
        }
    }

    fun togglePinQuickNote(id: String) {
        scope.launch(ioDispatcher) {
            val existing = tagdosDao.getNoteById(id) ?: return@launch
            val updated = existing.copy(
                isPinned = !existing.isPinned,
                updatedAt = System.currentTimeMillis(),
                syncedAt = null
            )
            tagdosDao.upsertNote(updated)
            scheduleCloudPush()
        }
    }

    fun deleteQuickNote(id: String) {
        scope.launch(ioDispatcher) {
            tagdosDao.deleteNoteById(id)
            val uid = currentUserId
            val handler = syncHandler
            if (handler != null && uid.isNotBlank() && uid != "guest") {
                handler.deleteQuickNote(uid, id)
            }
        }
    }

    // MARK: - Supabase Cloud Synchronization

    private fun isUntouchedSeedStream(entity: TagdoStreamEntity): Boolean {
        if (entity.updatedAt <= 0L) return true
        if (entity.syncedAt == null &&
            entity.customTitle.isNullOrBlank() &&
            entity.activeMemos.isBlank() &&
            entity.streamReminder == null &&
            (entity.clusterRemindersJson.isBlank() || entity.clusterRemindersJson == "{}")
        ) {
            return when (entity.orderIndex) {
                0 -> entity.rawText == DEFAULT_STREAM_1
                1 -> entity.rawText == DEFAULT_STREAM_2
                2 -> entity.rawText == DEFAULT_STREAM_3
                3 -> entity.rawText == DEFAULT_STREAM_4
                4 -> entity.rawText == DEFAULT_STREAM_5
                else -> false
            }
        }
        return false
    }

    private fun isUntouchedSeedNote(entity: TagdoQuickNoteEntity): Boolean {
        if (entity.updatedAt <= 0L) return true
        if (entity.syncedAt == null) {
            if (entity.title == "Concert Tickets" && entity.content.startsWith("Concert Tickets:")) return true
            if (entity.title == "Car Maintenance" && entity.content.startsWith("Car Maintenance:")) return true
        }
        return false
    }

    private fun parseIsoToEpochMs(iso: String?): Long {
        val clean = iso?.trim().orEmpty()
        if (clean.isEmpty()) return System.currentTimeMillis()
        return runCatching { Instant.parse(clean).toEpochMilli() }
            .recoverCatching { OffsetDateTime.parse(clean).toInstant().toEpochMilli() }
            .getOrElse { System.currentTimeMillis() }
    }

    private fun encodeReminderSpecForEntity(entity: TagdoStreamEntity): String? {
        val parsed = TagdosParser.parseStream(
            rawText = entity.rawText,
            title = entity.customTitle ?: entity.title,
            id = entity.id,
            streamReminder = entity.streamReminder,
            orderIndex = entity.orderIndex
        )
        val savedMap = decodeClusterReminders(entity.clusterRemindersJson)
        val hydrated = parsed.copy(
            clusters = parsed.clusters.mapIndexed { idx, c -> c.copy(reminderTime = savedMap[idx]) }
        )
        return TagdosParser.encodeReminderSpec(hydrated)
    }

    private fun scheduleCloudPush() {
        val uid = currentUserId
        if (uid.isBlank() || uid == "guest" || syncHandler == null) return
        pushDebounceJob?.cancel()
        pushDebounceJob = scope.launch(ioDispatcher) {
            delay(500L)
            val activeUid = currentUserId
            val handler = syncHandler ?: return@launch
            if (activeUid.isBlank() || activeUid == "guest") return@launch
            syncMutex.withLock {
                pushPendingLocalChanges(handler, activeUid)
            }
        }
    }

    private suspend fun pushPendingLocalChanges(
        handler: TagdosSyncHandler,
        uid: String,
        forceMissingNumbers: Set<Int> = emptySet(),
        forceAllStreams: Boolean = false
    ) {
        val localStreams = tagdosDao.getAllStreamsOnce()
        for (ls in localStreams) {
            val streamNum = ls.orderIndex + 1
            val isDirty = ls.syncedAt == null && !isUntouchedSeedStream(ls)
            val isMissingRemote = forceMissingNumbers.contains(streamNum)
            if (!forceAllStreams && !isDirty && !isMissingRemote) continue

            val effectiveTitle = ls.customTitle?.takeIf { it.isNotBlank() } ?: ls.title
            val reminderSpec = encodeReminderSpecForEntity(ls)
            val updatedIso = if (ls.updatedAt > 0L) Instant.ofEpochMilli(ls.updatedAt).toString() else Instant.now().toString()
            val ok = handler.upsertStream(
                userId = uid,
                streamNumber = streamNum,
                title = effectiveTitle,
                rawSyntax = ls.rawText,
                reminderTime = reminderSpec,
                activeMemos = ls.activeMemos,
                attachmentsJson = ls.attachmentsJson,
                updatedAtIso = updatedIso
            )
            if (ok) {
                tagdosDao.upsertStream(ls.copy(syncedAt = System.currentTimeMillis()))
            }
        }

        val localNotes = tagdosDao.getAllNotesOnce()
        for (ln in localNotes) {
            if (ln.syncedAt != null || isUntouchedSeedNote(ln)) continue
            val tagsList = runCatching {
                if (ln.tagsJson.isBlank()) emptyList()
                else json.decodeFromString(ListSerializer(String.serializer()), ln.tagsJson)
            }.getOrDefault(emptyList())
            val createdIso = if (ln.createdAt > 0L) Instant.ofEpochMilli(ln.createdAt).toString() else Instant.now().toString()
            val updatedIso = if (ln.updatedAt > 0L) Instant.ofEpochMilli(ln.updatedAt).toString() else Instant.now().toString()
            val record = RemoteTagdoQuickNoteRecord(
                id = ln.id,
                userId = uid,
                title = ln.title,
                content = ln.content,
                isPinned = ln.isPinned,
                tags = tagsList,
                createdAt = createdIso,
                updatedAt = updatedIso
            )
            if (handler.upsertQuickNote(record)) {
                tagdosDao.upsertNote(ln.copy(userId = uid, syncedAt = System.currentTimeMillis()))
            }
        }
    }

    suspend fun syncWithSupabase(
        userId: String = currentUserId,
        force: Boolean = false
    ) = withContext(ioDispatcher) {
        val uid = userId.trim()
        if (uid.isEmpty() || uid == "guest") return@withContext
        currentUserId = uid
        val handler = syncHandler ?: return@withContext

        syncMutex.withLock {
            val nowStart = System.currentTimeMillis()
            if (!force && nowStart - lastSyncMs < 15_000L) return@withLock

            _isSyncing.value = true
            try {
                // 1. Pull & Merge Streams
                val remoteStreams = handler.pullStreams(uid)
                if (remoteStreams != null) {
                    var localStreams = tagdosDao.getAllStreamsOnce().toMutableList()
                    if (localStreams.isEmpty() && remoteStreams.isEmpty()) {
                        seedDefaultStreams()
                        localStreams = tagdosDao.getAllStreamsOnce().toMutableList()
                    }

                    val remoteNumbers = remoteStreams.map { it.streamNumber }.toSet()
                    if (remoteStreams.isNotEmpty()) {
                        val maxRemoteNum = remoteStreams.maxOf { it.streamNumber }
                        val orphans = localStreams.filter {
                            it.syncedAt != null && (it.orderIndex + 1) > maxRemoteNum && !isUntouchedSeedStream(it)
                        }
                        for (orphan in orphans) {
                            tagdosDao.deleteStreamById(orphan.id)
                            localStreams.removeAll { it.id == orphan.id }
                        }

                        val syncStamp = System.currentTimeMillis()
                        for (remote in remoteStreams) {
                            val orderIdx = (remote.streamNumber - 1).coerceAtLeast(0)
                            val existing = localStreams.firstOrNull { it.orderIndex == orderIdx }
                            val remoteUpdatedMs = parseIsoToEpochMs(remote.updatedAt)
                            val localIsSeed = existing == null || isUntouchedSeedStream(existing)
                            val localIsDirty = existing != null && existing.syncedAt == null && !localIsSeed

                            val remoteMemos = remote.activeMemos.orEmpty()
                            val localEffectiveTitle = existing?.customTitle?.takeIf { it.isNotBlank() } ?: existing?.title.orEmpty()
                            val existingSpec = existing?.let { encodeReminderSpecForEntity(it) }
                            val remoteDiffers = existing == null ||
                                existing.rawText != remote.rawSyntax ||
                                localEffectiveTitle != remote.title ||
                                existing.activeMemos != remoteMemos ||
                                existingSpec != remote.reminderTime

                            val adoptRemote = localIsSeed ||
                                (!localIsDirty && (remoteUpdatedMs > existing!!.updatedAt || remoteDiffers)) ||
                                (localIsDirty && remoteUpdatedMs > existing!!.updatedAt)

                            if (adoptRemote) {
                                val remoteId = remote.id?.takeIf { it.isNotBlank() } ?: existing?.id ?: UUID.randomUUID().toString()
                                if (existing != null && !existing.id.equals(remoteId, ignoreCase = true)) {
                                    tagdosDao.deleteStreamById(existing.id)
                                    localStreams.removeAll { it.id == existing.id }
                                }

                                val (streamRemTs, clusterMap) = TagdosParser.decodeReminderSpec(remote.reminderTime)
                                val clusterJson = if (clusterMap.isEmpty()) "{}" else clusterMap.entries.joinToString(",") { "${it.key}=${it.value}" }
                                val attachmentsJson = remote.attachments?.let {
                                    json.encodeToString(JsonArray.serializer(), it)
                                } ?: "[]"
                                val previewParsed = TagdosParser.parseStream(
                                    rawText = remote.rawSyntax,
                                    title = remote.title,
                                    id = remoteId,
                                    streamReminder = streamRemTs,
                                    orderIndex = orderIdx
                                )
                                val autoTitle = previewParsed.autoDetectedTitle
                                val trimmedRemoteTitle = remote.title.trim()
                                val customTitle = if (trimmedRemoteTitle.isNotEmpty() && trimmedRemoteTitle != autoTitle) trimmedRemoteTitle else null
                                val resolvedTitle = customTitle ?: autoTitle

                                val updatedEntity = TagdoStreamEntity(
                                    id = remoteId,
                                    orderIndex = orderIdx,
                                    title = resolvedTitle,
                                    customTitle = customTitle,
                                    rawText = remote.rawSyntax,
                                    streamReminder = streamRemTs,
                                    clusterRemindersJson = clusterJson,
                                    activeMemos = remoteMemos,
                                    attachmentsJson = attachmentsJson,
                                    updatedAt = remoteUpdatedMs,
                                    syncedAt = syncStamp
                                )
                                attachmentsJsonByStreamId[remoteId] = attachmentsJson
                                tagdosDao.upsertStream(updatedEntity)
                                localStreams.removeAll { it.id == remoteId }
                                localStreams.add(updatedEntity)
                            }
                        }

                        val missingNumbers = localStreams.map { it.orderIndex + 1 }.toSet().minus(remoteNumbers)
                        pushPendingLocalChanges(handler, uid, forceMissingNumbers = missingNumbers, forceAllStreams = false)
                    } else {
                        pushPendingLocalChanges(handler, uid, forceAllStreams = true)
                    }
                }

                // 2. Pull & Merge Quick Notes
                val remoteNotes = handler.pullQuickNotes(uid)
                if (remoteNotes != null) {
                    val localNotes = tagdosDao.getAllNotesOnce().toMutableList()
                    if (remoteNotes.isNotEmpty()) {
                        for (seedNote in localNotes.filter { isUntouchedSeedNote(it) }) {
                            tagdosDao.deleteNoteById(seedNote.id)
                            localNotes.removeAll { it.id == seedNote.id }
                        }

                        val remoteIds = remoteNotes.map { it.id.lowercase() }.toSet()
                        for (orphan in localNotes.filter { it.syncedAt != null && !remoteIds.contains(it.id.lowercase()) }) {
                            tagdosDao.deleteNoteById(orphan.id)
                            localNotes.removeAll { it.id == orphan.id }
                        }

                        val syncStamp = System.currentTimeMillis()
                        for (rNote in remoteNotes) {
                            val existing = localNotes.firstOrNull { it.id.equals(rNote.id, ignoreCase = true) }
                            val rUpdatedMs = parseIsoToEpochMs(rNote.updatedAt)
                            val rCreatedMs = parseIsoToEpochMs(rNote.createdAt)
                            val localDirty = existing != null && existing.syncedAt == null && !isUntouchedSeedNote(existing)

                            val adoptNote = existing == null ||
                                (!localDirty && (rUpdatedMs > existing.updatedAt ||
                                    existing.title != rNote.title ||
                                    existing.content != rNote.content ||
                                    existing.isPinned != rNote.isPinned)) ||
                                (localDirty && rUpdatedMs > existing.updatedAt)

                            if (adoptNote) {
                                val tagsJson = json.encodeToString(ListSerializer(String.serializer()), rNote.tags.orEmpty())
                                tagdosDao.upsertNote(
                                    TagdoQuickNoteEntity(
                                        id = rNote.id,
                                        userId = rNote.userId ?: uid,
                                        title = rNote.title,
                                        content = rNote.content,
                                        isPinned = rNote.isPinned,
                                        tagsJson = tagsJson,
                                        createdAt = rCreatedMs,
                                        updatedAt = rUpdatedMs,
                                        syncedAt = syncStamp
                                    )
                                )
                            }
                        }
                    }
                    pushPendingLocalChanges(handler, uid, forceMissingNumbers = emptySet(), forceAllStreams = false)
                }

                lastSyncMs = System.currentTimeMillis()
            } finally {
                _isSyncing.value = false
            }
        }
    }
}
