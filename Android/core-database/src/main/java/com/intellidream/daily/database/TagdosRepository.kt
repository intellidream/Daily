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

    fun updateStreamRawText(streamId: String, newRawText: String) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
            var updated = TagdosParser.parseStream(
                rawText = newRawText,
                title = stream.customTitle ?: stream.title,
                id = stream.id,
                streamReminder = stream.streamReminder,
                orderIndex = stream.orderIndex,
                existingStream = stream
            )
            val customTitle = stream.customTitle
            if (customTitle.isNullOrBlank()) {
                updated = updated.copy(title = updated.autoDetectedTitle, customTitle = null)
            } else {
                updated = updated.copy(customTitle = customTitle, title = customTitle)
            }
            updated = updated.copy(
                activeMemos = stream.activeMemos,
                attachments = stream.attachments,
                updatedAt = System.currentTimeMillis()
            )

            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun updateStreamTitle(streamId: String, newTitle: String?) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
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

            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun setStreamReminder(streamId: String, date: Long?) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
            val updated = stream.copy(
                streamReminder = date,
                updatedAt = System.currentTimeMillis()
            )
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun updateStreamMemos(streamId: String, memos: String) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
            val updated = stream.copy(
                activeMemos = memos,
                updatedAt = System.currentTimeMillis()
            )
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun recyclePillToBack(streamId: String, pillId: String) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
            val updated = TagdosParser.recyclePillToBack(stream, pillId)
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun togglePillCompletion(streamId: String, pillId: String) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
            val updated = TagdosParser.togglePillCompletion(stream, pillId)
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun removePill(streamId: String, pillId: String) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
            val updated = TagdosParser.removePill(stream, pillId)
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun movePillToFront(streamId: String, pillId: String) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
            val updated = TagdosParser.movePillToFront(stream, pillId)
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun addPill(streamId: String, clusterIndex: Int, text: String) {
        scope.launch(ioDispatcher) {
            val stream = _streams.value.firstOrNull { it.id == streamId } ?: return@launch
            val updated = TagdosParser.addPill(stream, clusterIndex, text)
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun updatePillText(streamId: String, pillId: String, newText: String) {
        val current = _streams.value.toMutableList()
        val idx = current.indexOfFirst { it.id == streamId }
        if (idx < 0) return
        val updated = TagdosParser.updatePillText(current[idx], pillId, newText)
        current[idx] = updated
        _streams.value = current

        scope.launch(ioDispatcher) {
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
    }

    fun createStream(
        title: String? = null,
        rawText: String = "",
        activeMemos: String = ""
    ): String {
        val current = _streams.value.toMutableList()
        val nextOrderIndex = (current.maxOfOrNull { it.orderIndex } ?: -1) + 1
        val cleanTitle = title?.trim()?.takeIf { it.isNotEmpty() }
        val newId = UUID.randomUUID().toString()
        var stream = TagdosParser.parseStream(
            rawText = rawText,
            title = cleanTitle ?: "Stream ${nextOrderIndex + 1}",
            id = newId,
            orderIndex = nextOrderIndex
        )
        stream = if (cleanTitle != null) {
            stream.copy(customTitle = cleanTitle, title = cleanTitle, activeMemos = activeMemos)
        } else {
            stream.copy(customTitle = null, title = stream.autoDetectedTitle, activeMemos = activeMemos)
        }
        current.add(stream)
        _streams.value = current

        scope.launch(ioDispatcher) {
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = stream.id,
                    orderIndex = stream.orderIndex,
                    title = stream.title,
                    customTitle = stream.customTitle,
                    rawText = stream.rawText,
                    streamReminder = stream.streamReminder,
                    activeMemos = stream.activeMemos,
                    updatedAt = System.currentTimeMillis(),
                    syncedAt = null
                )
            )
        }
        return newId
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
            val reindexed = reindexedDomain.map { stream ->
                TagdoStreamEntity(
                    id = stream.id,
                    orderIndex = stream.orderIndex,
                    title = stream.title,
                    customTitle = stream.customTitle,
                    rawText = stream.rawText,
                    streamReminder = stream.streamReminder,
                    activeMemos = stream.activeMemos,
                    updatedAt = stream.updatedAt,
                    syncedAt = null
                )
            }
            tagdosDao.upsertStreams(reindexed)
        }
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

        if (mode == "new") {
            return createStream(title = newStreamTitle, rawText = combinedDsl, activeMemos = combinedMemos)
        }

        val current = _streams.value.toMutableList()
        val idx = current.indexOfFirst { it.id == targetStreamId }
        if (idx < 0) {
            return createStream(title = newStreamTitle, rawText = combinedDsl, activeMemos = combinedMemos)
        }
        val existing = current[idx]

        val newRaw: String
        val mergedMemos: String
        val preserveExisting: TagDoStream?

        if (mode == "replace") {
            newRaw = combinedDsl
            mergedMemos = combinedMemos
            preserveExisting = null
        } else {
            val existingRaw = existing.rawText.trim()
            newRaw = when {
                existingRaw.isEmpty() -> combinedDsl
                combinedDsl.isEmpty() -> existingRaw
                else -> "$existingRaw & $combinedDsl"
            }
            val existingMemos = existing.activeMemos.trim()
            mergedMemos = when {
                existingMemos.isEmpty() -> combinedMemos
                combinedMemos.isEmpty() -> existingMemos
                else -> "$existingMemos\n$combinedMemos"
            }
            preserveExisting = existing
        }

        var updated = TagdosParser.parseStream(
            rawText = newRaw,
            title = existing.customTitle ?: existing.title,
            id = existing.id,
            streamReminder = existing.streamReminder,
            orderIndex = existing.orderIndex,
            existingStream = preserveExisting
        )
        val existingCustomTitle = existing.customTitle
        updated = if (existingCustomTitle.isNullOrBlank()) {
            updated.copy(title = updated.autoDetectedTitle, customTitle = null, activeMemos = mergedMemos, updatedAt = System.currentTimeMillis())
        } else {
            updated.copy(customTitle = existingCustomTitle, title = existingCustomTitle, activeMemos = mergedMemos, updatedAt = System.currentTimeMillis())
        }
        current[idx] = updated
        _streams.value = current

        scope.launch(ioDispatcher) {
            tagdosDao.upsertStream(
                TagdoStreamEntity(
                    id = updated.id,
                    orderIndex = updated.orderIndex,
                    title = updated.title,
                    customTitle = updated.customTitle,
                    rawText = updated.rawText,
                    streamReminder = updated.streamReminder,
                    activeMemos = updated.activeMemos,
                    updatedAt = updated.updatedAt,
                    syncedAt = null
                )
            )
        }
        return existing.id
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
