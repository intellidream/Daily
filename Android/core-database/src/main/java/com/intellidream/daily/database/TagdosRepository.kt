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
                title = "DUBaFest bilete",
                content = "DUBaFest bilete: ia pt CiSTiu si asigura buget 2x",
                isPinned = true
            ),
            TagDoQuickNote(
                id = UUID.randomUUID().toString(),
                title = "Benzina 98",
                content = "Urmeaza benzina 98 la urmatorul plin, apoi curatat interior",
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

    // MARK: - Quick Notes Mutations

    fun createQuickNote(title: String = "", content: String = "") {
        scope.launch(ioDispatcher) {
            val note = TagDoQuickNote(
                id = UUID.randomUUID().toString(),
                title = title,
                content = content,
                isPinned = false,
                createdAt = System.currentTimeMillis(),
                updatedAt = System.currentTimeMillis()
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
