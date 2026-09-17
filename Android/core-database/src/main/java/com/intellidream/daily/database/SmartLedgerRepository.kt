package com.intellidream.daily.database

import com.intellidream.daily.database.dao.SmartLedgerDao
import com.intellidream.daily.database.entity.SmartLedgerEntity
import com.intellidream.daily.model.DEFAULT_LEDGER_TEXT
import com.intellidream.daily.model.ParsedSmartLedger
import com.intellidream.daily.model.SmartLedgerParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Manages local Room persistence, reactive publishing, and live re-calculation
 * of the user's Smart Ledger text document.
 */
class SmartLedgerRepository(
    private val smartLedgerDao: SmartLedgerDao,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {
    private val _rawText = MutableStateFlow(DEFAULT_LEDGER_TEXT)
    val rawText: StateFlow<String> = _rawText.asStateFlow()

    private val _parsedLedger = MutableStateFlow(SmartLedgerParser.parse(DEFAULT_LEDGER_TEXT))
    val parsedLedger: StateFlow<ParsedSmartLedger> = _parsedLedger.asStateFlow()

    init {
        scope.launch {
            smartLedgerDao.getLedger().collect { entity ->
                if (entity != null && entity.rawText.isNotBlank()) {
                    if (entity.rawText != _rawText.value) {
                        _rawText.value = entity.rawText
                        _parsedLedger.value = SmartLedgerParser.parse(entity.rawText)
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

    fun saveLedgerText(newText: String) {
        val trimmed = newText.trim()
        val textToUse = if (trimmed.isEmpty()) DEFAULT_LEDGER_TEXT else newText
        _rawText.value = textToUse
        _parsedLedger.value = SmartLedgerParser.parse(textToUse)

        scope.launch {
            smartLedgerDao.upsert(
                SmartLedgerEntity(
                    id = "primary_ledger",
                    rawText = textToUse,
                    updatedAt = System.currentTimeMillis(),
                    syncedAt = null
                )
            )
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
