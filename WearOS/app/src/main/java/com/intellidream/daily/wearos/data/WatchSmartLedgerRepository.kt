package com.intellidream.daily.wearos.data

import android.content.Context
import android.content.SharedPreferences
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

@Serializable
internal data class RemoteLedgerRecord(
    val id: String? = null,
    val user_id: String? = null,
    val ledger_text: String,
    val created_at: String? = null,
    val updated_at: String? = null
)

class WatchSmartLedgerRepository private constructor(private val context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val scope = CoroutineScope(Dispatchers.IO)

    private val _rawText = MutableStateFlow(loadCachedText())
    val rawText: StateFlow<String> = _rawText.asStateFlow()

    private val _parsed = MutableStateFlow(SmartLedgerParser.parse(_rawText.value))
    val parsed: StateFlow<ParsedLedgerResult> = _parsed.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private var pushJob: Job? = null

    companion object {
        private const val PREFS_NAME = "daily_prefs"
        private const val KEY_RAW_TEXT = "smart_ledger_raw_text"
        private const val KEY_LAST_SYNC_TS = "smart_ledger_last_sync_ts"
        private const val KEY_NET_WORTH = "ledger_net_worth"
        private const val KEY_NET_WORTH_EUR = "ledger_net_worth_eur"
        private const val KEY_DEPOSITS = "ledger_deposits"
        private const val KEY_SOLD = "ledger_sold"

        // 10-minute cache TTL to preserve smartwatch battery and cellular/BT network
        private const val CACHE_TTL_MS = 10 * 60 * 1000L

        @Volatile
        private var instance: WatchSmartLedgerRepository? = null

        fun getInstance(context: Context): WatchSmartLedgerRepository {
            return instance ?: synchronized(this) {
                instance ?: WatchSmartLedgerRepository(context.applicationContext).also { instance = it }
            }
        }

        fun formatLei(value: Double): String {
            val symbols = DecimalFormatSymbols(Locale.GERMANY).apply {
                groupingSeparator = '.'
            }
            val df = DecimalFormat("#,##0", symbols)
            return "${df.format(value.toLong())} Lei"
        }

        fun formatEur(value: Double): String {
            val symbols = DecimalFormatSymbols(Locale.GERMANY).apply {
                groupingSeparator = '.'
            }
            val df = DecimalFormat("#,##0", symbols)
            return "~${df.format(value.toLong())} €"
        }
    }

    private fun loadCachedText(): String {
        val cached = prefs.getString(KEY_RAW_TEXT, null)
        if (!cached.isNullOrBlank()) {
            return cached
        }
        return SmartLedgerParser.DEFAULT_LEDGER_TEXT
    }

    private fun saveToCache(text: String, result: ParsedLedgerResult) {
        try {
            prefs.edit()
                .putString(KEY_RAW_TEXT, text)
                .putString(KEY_NET_WORTH, formatLei(result.netWorth))
                .putString(KEY_NET_WORTH_EUR, formatEur(result.netWorthEUR))
                .putString(KEY_DEPOSITS, formatLei(result.deposits))
                .putString(KEY_SOLD, formatLei(result.balance))
                .apply()
        } catch (_: Exception) {}
    }

    fun getCachedNetWorth(): String = prefs.getString(KEY_NET_WORTH, formatLei(_parsed.value.netWorth)) ?: formatLei(_parsed.value.netWorth)
    fun getCachedNetWorthEUR(): String = prefs.getString(KEY_NET_WORTH_EUR, formatEur(_parsed.value.netWorthEUR)) ?: formatEur(_parsed.value.netWorthEUR)
    fun getCachedDeposits(): String = prefs.getString(KEY_DEPOSITS, formatLei(_parsed.value.deposits)) ?: formatLei(_parsed.value.deposits)
    fun getCachedBalance(): String = prefs.getString(KEY_SOLD, formatLei(_parsed.value.balance)) ?: formatLei(_parsed.value.balance)

    /**
     * Synchronizes ledger data from Supabase.
     * Enforces strict 10-minute battery & network throttling unless force is true.
     */
    suspend fun syncWithSupabase(force: Boolean = false) = withContext(Dispatchers.IO) {
        val lastSync = prefs.getLong(KEY_LAST_SYNC_TS, 0L)
        val now = System.currentTimeMillis()

        if (!force && (now - lastSync < CACHE_TTL_MS)) {
            // Cache is valid (< 10m old), return immediately without touching network
            return@withContext
        }

        val sessionManager = WatchSessionManager.getInstance(context)
        val client = sessionManager.supabaseClient ?: return@withContext
        val userId = sessionManager.currentUserId.value ?: return@withContext

        _isSyncing.value = true
        try {
            val list = client.postgrest["smart_ledgers"]
                .select {
                    filter { eq("user_id", userId) }
                    order("updated_at", io.github.jan.supabase.postgrest.query.Order.DESCENDING)
                    limit(1)
                }
                .decodeList<RemoteLedgerRecord>()

            val remote = list.firstOrNull()
            if (remote != null && remote.ledger_text.isNotBlank()) {
                val remoteText = remote.ledger_text
                if (remoteText != _rawText.value) {
                    _rawText.value = remoteText
                    val newParsed = SmartLedgerParser.parse(remoteText)
                    _parsed.value = newParsed
                    saveToCache(remoteText, newParsed)
                }
                prefs.edit().putLong(KEY_LAST_SYNC_TS, now).apply()
            }
        } catch (_: Exception) {
            // Offline or error: keep serving 100% functional local cache
        } finally {
            _isSyncing.value = false
        }
    }

    /**
     * Quick adjust an item by delta, updating local cache instantly (< 1ms),
     * recalculating totals in DSL lines, and scheduling cloud synchronization with 500ms debounce.
     */
    fun adjustItem(lineIndex: Int, deltaRaw: Double) {
        val currentText = _rawText.value
        val updatedText = SmartLedgerParser.adjustItemAmount(currentText, lineIndex, deltaRaw)
        if (updatedText == currentText) return

        _rawText.value = updatedText
        val newParsed = SmartLedgerParser.parse(updatedText)
        _parsed.value = newParsed
        saveToCache(updatedText, newParsed)

        // Schedule debounced cloud push
        pushJob?.cancel()
        pushJob = scope.launch {
            delay(500L)
            pushToCloud(updatedText)
        }
    }

    private suspend fun pushToCloud(text: String) {
        try {
            val sessionManager = WatchSessionManager.getInstance(context)
            val client = sessionManager.supabaseClient ?: return
            val userId = sessionManager.currentUserId.value ?: return

            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            val record = RemoteLedgerRecord(
                user_id = userId,
                ledger_text = text,
                updated_at = isoFormat.format(Date())
            )
            client.postgrest["smart_ledgers"].upsert(record)
            prefs.edit().putLong(KEY_LAST_SYNC_TS, System.currentTimeMillis()).apply()
        } catch (_: Exception) {}
    }
}
