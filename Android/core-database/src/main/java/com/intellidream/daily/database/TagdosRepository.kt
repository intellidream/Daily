package com.intellidream.daily.database

import com.intellidream.daily.database.dao.TagdosDao
import com.intellidream.daily.database.entity.TagdoQuickNoteEntity
import com.intellidream.daily.database.entity.TagdoStreamEntity
import com.intellidream.daily.model.TagDoPill
import com.intellidream.daily.model.TagDoQuickNote
import com.intellidream.daily.model.TagDoStream
import com.intellidream.daily.model.TagdosParser
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

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
                        val existing = currentStreams.firstOrNull { it.id == entity.id }
                        val stream = TagdosParser.parseStream(
                            rawText = entity.rawText,
                            title = entity.title,
                            id = entity.id,
                            streamReminder = entity.streamReminder,
                            orderIndex = entity.orderIndex,
                            existingStream = existing
                        )
                        stream.copy(
                            customTitle = entity.customTitle,
                            activeMemos = entity.activeMemos,
                            updatedAt = entity.updatedAt
                        )
                    }
                    _streams.value = parsed
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
                        TagDoQuickNote(
                            id = entity.id,
                            userId = entity.userId,
                            title = entity.title,
                            content = entity.content,
                            isPinned = entity.isPinned,
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
                updatedAt = s.updatedAt,
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
                createdAt = n.createdAt,
                updatedAt = n.updatedAt,
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
            activeMemos = activeMemos,
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
        scope.launch(ioDispatcher) {
            tagdosDao.upsertStream(updated.toEntity(syncedAt = null))
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

        scope.launch(ioDispatcher) {
            tagdosDao.upsertStream(stream.toEntity(syncedAt = null))
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
        scope.launch(ioDispatcher) {
            tagdosDao.upsertStreams(reindexed.map { it.toEntity(syncedAt = null) })
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

        scope.launch(ioDispatcher) {
            tagdosDao.deleteStreamById(streamId)
            tagdosDao.upsertStreams(reindexedDomain.map { it.toEntity(syncedAt = null) })
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
            val toSave = touchedEntities.values.toList()
            scope.launch(ioDispatcher) {
                tagdosDao.upsertStreams(toSave)
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
        }
    }

    fun deleteQuickNote(id: String) {
        scope.launch(ioDispatcher) {
            tagdosDao.deleteNoteById(id)
        }
    }

    fun syncWithSupabase() {
        // Trigger manual sync pass (will integrate with Supabase / WorkManager)
    }
}
