package com.intellidream.daily.database

import com.intellidream.daily.database.dao.SmartLedgerDao
import com.intellidream.daily.database.entity.SmartLedgerEntity
import com.intellidream.daily.model.DEFAULT_LEDGER_TEXT
import com.intellidream.daily.model.ParsedSmartLedger
import com.intellidream.daily.model.SmartLedgerParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

interface SmartLedgerSyncHandler {
    suspend fun fetchRemoteLedger(userId: String): Pair<String, Long>? // (ledger_text, updated_at_epoch)
    suspend fun pushLedger(userId: String, text: String): Boolean
}

/**
 * Manages local Room persistence, reactive publishing, live re-calculation,
 * and Supabase cloud synchronization of the user's Smart Ledger text document.
 */
class SmartLedgerRepository(
    private val smartLedgerDao: SmartLedgerDao,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {
    private val _rawText = MutableStateFlow(DEFAULT_LEDGER_TEXT)
    val rawText: StateFlow<String> = _rawText.asStateFlow()

    private val _parsedLedger = MutableStateFlow(SmartLedgerParser.parse(DEFAULT_LEDGER_TEXT))
    val parsedLedger: StateFlow<ParsedSmartLedger> = _parsedLedger.asStateFlow()

    var syncHandler: SmartLedgerSyncHandler? = null
    var onLedgerChanged: (() -> Unit)? = null
    private var activeUserId: String? = null
    private var pushJob: Job? = null

    init {
        scope.launch {
            smartLedgerDao.getLedger().collect { entity ->
                if (entity != null && entity.rawText.isNotBlank()) {
                    if (entity.rawText != _rawText.value) {
                        _rawText.value = entity.rawText
                        _parsedLedger.value = SmartLedgerParser.parse(entity.rawText)
                        onLedgerChanged?.invoke()
                    }
                } else {
                    // Seed database with default ledger text
                    smartLedgerDao.upsert(
                        SmartLedgerEntity(
                            id = "primary_ledger",
                            rawText = DEFAULT_LEDGER_TEXT,
                            updatedAt = System.currentTimeMillis(),
                            syncedAt = null
                        )
                    )
                }
            }
        }
    }

    fun setUserId(userId: String?) {
        activeUserId = userId
        if (userId != null) {
            scope.launch {
                syncWithCloud()
            }
        }
    }

    suspend fun syncWithCloud() {
        val uid = activeUserId ?: return
        val handler = syncHandler ?: return
        try {
            val remote = handler.fetchRemoteLedger(uid)
            val local = smartLedgerDao.getLedgerSync("primary_ledger")
            val localUpdated = local?.updatedAt ?: 0L
            if (remote != null) {
                val (remoteText, remoteUpdated) = remote
                if (remoteUpdated > localUpdated) {
                    _rawText.value = remoteText
                    _parsedLedger.value = SmartLedgerParser.parse(remoteText)
                    onLedgerChanged?.invoke()
                    smartLedgerDao.upsert(
                        SmartLedgerEntity(
                            id = "primary_ledger",
                            rawText = remoteText,
                            updatedAt = remoteUpdated,
                            syncedAt = System.currentTimeMillis()
                        )
                    )
                } else if (localUpdated > remoteUpdated && local?.syncedAt == null) {
                    if (handler.pushLedger(uid, _rawText.value)) {
                        smartLedgerDao.markSynced("primary_ledger")
                    }
                }
            } else {
                if (handler.pushLedger(uid, _rawText.value)) {
                    smartLedgerDao.markSynced("primary_ledger")
                }
            }
        } catch (_: Exception) {}
    }

    fun saveLedgerText(newText: String, triggerCloudPush: Boolean = true) {
        val trimmed = newText.trim()
        val textToUse = if (trimmed.isEmpty()) DEFAULT_LEDGER_TEXT else newText
        _rawText.value = textToUse
        _parsedLedger.value = SmartLedgerParser.parse(textToUse)
        onLedgerChanged?.invoke()

        val now = System.currentTimeMillis()
        scope.launch {
            smartLedgerDao.upsert(
                SmartLedgerEntity(
                    id = "primary_ledger",
                    rawText = textToUse,
                    updatedAt = now,
                    syncedAt = null
                )
            )
        }

        if (triggerCloudPush && activeUserId != null) {
            pushJob?.cancel()
            pushJob = scope.launch {
                delay(500L) // 500ms debounce
                val uid = activeUserId ?: return@launch
                val handler = syncHandler ?: return@launch
                if (handler.pushLedger(uid, textToUse)) {
                    smartLedgerDao.markSynced("primary_ledger")
                }
            }
        }
    }

    fun adjustItem(lineIndex: Int, deltaRaw: Double) {
        val updatedText = SmartLedgerParser.adjustItemAmount(_rawText.value, lineIndex, deltaRaw)
        saveLedgerText(updatedText)
    }

    fun setItemAmount(lineIndex: Int, newRaw: Double) {
        val updatedText = SmartLedgerParser.setItemAmount(_rawText.value, lineIndex, newRaw)
        saveLedgerText(updatedText)
    }

    fun addItem(sectionName: String, key: String, amount: Double, note: String?) {
        val updatedText = SmartLedgerParser.addItem(_rawText.value, sectionName, key, amount, note)
        saveLedgerText(updatedText)
    }

    fun deleteItem(lineIndex: Int) {
        val updatedText = SmartLedgerParser.deleteItem(_rawText.value, lineIndex)
        saveLedgerText(updatedText)
    }

    fun resetToDefault() {
        saveLedgerText(DEFAULT_LEDGER_TEXT)
    }
}
