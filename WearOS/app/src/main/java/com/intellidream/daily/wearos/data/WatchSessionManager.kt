package com.intellidream.daily.wearos.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.intellidream.daily.wearos.domain.model.PairedWatch
import com.intellidream.daily.wearos.domain.model.WatchPairing
import com.intellidream.daily.wearos.domain.model.HabitLog
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.http.contentType
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

val Context.dataStore by preferencesDataStore(name = "daily_prefs")

class WatchSessionManager private constructor(private val context: Context) {

    companion object {
        @Volatile
        private var instance: WatchSessionManager? = null

        fun getInstance(context: Context): WatchSessionManager {
            return instance ?: synchronized(this) {
                instance ?: WatchSessionManager(context.applicationContext).also {
                    instance = it
                    it.startSessionListener()
                    it.checkExistingSession()
                }
            }
        }
    }

    private val supabaseUrl = "https://akkfouifxztnfwwiclwg.supabase.co"
    private val supabaseAnonKey = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"

    val supabaseClient: SupabaseClient = createSupabaseClient(supabaseUrl, supabaseAnonKey) {
        install(Auth) {
            alwaysAutoRefresh = false
        }
        install(Postgrest)
    }

    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated

    private val _pairingCode = MutableStateFlow("")
    val pairingCode: StateFlow<String> = _pairingCode

    private val _isPairing = MutableStateFlow(false)
    val isPairing: StateFlow<Boolean> = _isPairing

    private val _errorMessage = MutableStateFlow("")
    val errorMessage: StateFlow<String> = _errorMessage
    
    private val _currentUserId = MutableStateFlow<String?>(null)
    val currentUserId: StateFlow<String?> = _currentUserId

    // Memory caching to prevent "load from scratch" flashing during navigation
    var cachedBubblesGoal: Int? = null
    var cachedBubblesLogs: List<HabitLog>? = null
    
    var cachedSmokesGoal: Int? = null
    var cachedSmokesLogs: List<HabitLog>? = null

    // Bumped on every resume to tell screens to re-fetch data
    private val _dataRefreshTrigger = MutableStateFlow(0)
    val dataRefreshTrigger: StateFlow<Int> = _dataRefreshTrigger

    // For Complications and Tiles
    val waterTotalCacheKey = stringPreferencesKey("daily_water_total")
    val smokesTotalCacheKey = stringPreferencesKey("daily_smokes_total")

    fun persistWaterTotal(water: Int) {
        scope.launch {
            context.dataStore.edit { prefs ->
                prefs[waterTotalCacheKey] = water.toString()
            }
        }
    }

    fun persistSmokesTotal(smokes: Int) {
        scope.launch {
            context.dataStore.edit { prefs ->
                prefs[smokesTotalCacheKey] = smokes.toString()
            }
        }
    }

    private val pairedWatchIdKey = stringPreferencesKey("paired_watch_id")

    private var pollJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO)
    @Volatile private var isRecovering = false

    /**
     * Listens to the Supabase Auth plugin's session status. When the plugin auto-refreshes
     * tokens (e.g. before access-token expiry), the NEW tokens are persisted to DataStore
     * so we never have stale credentials on disk.
     */
    private fun startSessionListener() {
        scope.launch {
            supabaseClient.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        val session = status.session
                        context.dataStore.edit { prefs ->
                            prefs[stringPreferencesKey("supabase_access_token")] = session.accessToken
                            prefs[stringPreferencesKey("supabase_refresh_token")] = session.refreshToken
                        }
                        val uid = session.user?.id ?: extractUserId(session.accessToken)
                        if (uid != null) {
                            context.dataStore.edit { prefs ->
                                prefs[stringPreferencesKey("supabase_user_id")] = uid
                            }
                            _currentUserId.value = uid
                        }
                        _isAuthenticated.value = true
                        _isPairing.value = false
                    }
                    is SessionStatus.NotAuthenticated -> {
                        // Attempt recovery from DataStore tokens regardless of current auth state.
                        // The Auth plugin fires NotAuthenticated on process restart with expired tokens
                        // AND when auto-refresh fails — we must recover in both cases.
                        if (!isRecovering) {
                            val prefs = context.dataStore.data.first()
                            val savedUserId = prefs[stringPreferencesKey("supabase_user_id")]
                            if (!savedUserId.isNullOrEmpty()) {
                                val accessToken = prefs[stringPreferencesKey("supabase_access_token")]
                                val refreshToken = prefs[stringPreferencesKey("supabase_refresh_token")]
                                if (!accessToken.isNullOrEmpty() && !refreshToken.isNullOrEmpty()) {
                                    isRecovering = true
                                    try {
                                        supabaseClient.auth.importAuthToken(accessToken, refreshToken)
                                        // AutoRefresh is false, relying on Token Pushes
                                    } catch (e: Exception) {
                                        // Recovery failed — keep _isAuthenticated optimistically true
                                        // so screens can still show cached data. Will retry on next resume.
                                        _isAuthenticated.value = true
                                        _currentUserId.value = savedUserId
                                        _isPairing.value = false
                                    } finally {
                                        isRecovering = false
                                    }
                                }
                            } else if (_isAuthenticated.value) {
                                // No stored user — truly logged out
                                _isAuthenticated.value = false
                                _currentUserId.value = null
                            }
                        }
                    }
                    else -> { /* LoadingFromStorage, NetworkError — no action */ }
                }
            }
        }
    }

    fun checkExistingSession() {
        scope.launch {
            // 1. Check if the Auth plugin already has a cached session.
            val existingSession = supabaseClient.auth.currentSessionOrNull()
            if (existingSession != null) {
                val uid = existingSession.user?.id ?: extractUserId(existingSession.accessToken)
                if (uid != null) {
                    // Show authenticated UI immediately using cached data
                    _currentUserId.value = uid
                    _isAuthenticated.value = true
                    _isPairing.value = false
                    // Sync to DataStore so complication/tile services can read user_id
                    context.dataStore.edit { prefs ->
                        prefs[stringPreferencesKey("supabase_access_token")] = existingSession.accessToken
                        prefs[stringPreferencesKey("supabase_refresh_token")] = existingSession.refreshToken
                        prefs[stringPreferencesKey("supabase_user_id")] = uid
                    }
                    // We rely on pushing tokens from MAUI instead
                    // try {
                    //    supabaseClient.auth.refreshCurrentSession()
                    // } catch (e: Exception) {
                    // }
                    return@launch
                }
            }

            // 2. Fall back to DataStore tokens (e.g. first launch after pairing, before Auth plugin
            //    had a chance to persist to its own storage).
            val prefs = context.dataStore.data.first()
            val accessToken = prefs[stringPreferencesKey("supabase_access_token")]
            val refreshToken = prefs[stringPreferencesKey("supabase_refresh_token")]
            var savedUserId = prefs[stringPreferencesKey("supabase_user_id")]
            
            if (savedUserId.isNullOrEmpty() && !accessToken.isNullOrEmpty()) {
                // Self-heal from previous bug where user_id wasn't saved reliably
                savedUserId = extractUserId(accessToken)
                if (savedUserId != null) {
                    context.dataStore.edit { p -> p[stringPreferencesKey("supabase_user_id")] = savedUserId }
                }
            }

            if (!accessToken.isNullOrEmpty() && !refreshToken.isNullOrEmpty() && !savedUserId.isNullOrEmpty()) {
                // Optimistic UI loading instantly
                _currentUserId.value = savedUserId
                _isAuthenticated.value = true
                _isPairing.value = false
                
                isRecovering = true
                try {
                    supabaseClient.auth.importAuthToken(accessToken, refreshToken)
                } catch (e: Exception) {
                    // Do not aggressively logout if network fails here.
                    // The session listener's NotAuthenticated handler will retry.
                } finally {
                    isRecovering = false
                }
            } else {
                generatePairingCode()
            }
        }
    }

    fun generatePairingCode() {
        _isPairing.value = true
        _errorMessage.value = ""
        val code = String.format("%06d", (0..999999).random())
        _pairingCode.value = code

        scope.launch {
            try {
                val pairing = WatchPairing(code = code)
                supabaseClient.postgrest["watch_pairings"].insert(pairing)
                startPolling()
            } catch (e: Exception) {
                _errorMessage.value = "Insert Err: ${e.message}"
            }
        }
    }

    private fun startPolling() {
        pollJob?.cancel()
        pollJob = scope.launch {
            while (isActive) {
                delay(3000)
                checkPairingStatus()
            }
        }
    }

    private suspend fun checkPairingStatus() {
        try {
            val pairings = supabaseClient.postgrest["watch_pairings"]
                .select { filter { eq("code", _pairingCode.value) } }
                .decodeList<WatchPairing>()

            val pairing = pairings.firstOrNull()
            if (pairing != null) {
                if (!pairing.access_token.isNullOrEmpty()) {
                    val token = pairing.access_token
                    val refresh = pairing.refresh_token.orEmpty()
                    
                    // importAuthToken triggers the session listener, which will persist
                    // tokens to DataStore and update _isAuthenticated / _currentUserId.
                    supabaseClient.auth.importAuthToken(token, refresh)
                    val uid = extractUserId(token)

                    if (uid != null) {
                        // Session listener handles DataStore persistence and state updates.
                        // Just clean up the pairing row and stop polling.
                        supabaseClient.postgrest["watch_pairings"]
                            .delete { filter { eq("code", _pairingCode.value) } }

                        // Register this device in the persistent paired_watches table
                        registerPairing(token, uid)
                            
                        pollJob?.cancel()
                        _dataRefreshTrigger.value++
                    }
                }
            } else {
               // The row disappears when the Phone app claims it OR if we explicitly delete it after success.
               // We only consider it an error if we are still actively "Pairing".
               if (_isPairing.value) {
                   _errorMessage.value = "Row deleted/missing"
                   pollJob?.cancel()
               }
            }
        } catch (e: Exception) {
            if (e !is kotlinx.coroutines.CancellationException) {
                _errorMessage.value = "Poll Err: ${e.localizedMessage}"
            }
        }
    }

    fun onAppResumed() {
        // Always attempt a full session refresh on resume. WearOS Doze mode kills the
        // Auth plugin's auto-refresh coroutine, so the access token is almost certainly
        // expired after any meaningful sleep period. We must proactively refresh here.
        scope.launch {
            // Step 0: Check if the main app pushed repair tokens (fresh credentials)
            checkForRepairTokens()

            // Step 1: Try importing the in-memory session
            val session = supabaseClient.auth.currentSessionOrNull()
            if (session != null) {
                _isAuthenticated.value = true
                _currentUserId.value = session.user?.id ?: extractUserId(session.accessToken)
            } else {
                // Auth plugin has no session at all — full recovery from DataStore
                recoverFromDataStore()
            }

            // Tell screens to re-fetch their data now that auth is fresh
            _dataRefreshTrigger.value++

            // Flush any logs that were queued while offline
            if (_isAuthenticated.value) {
                OfflineSyncManager.shared.syncPendingLogs(supabaseClient)
            }
        }
    }

    /**
     * Recovers a Supabase session from DataStore-persisted tokens. Called when the Auth
     * plugin's in-memory session is gone or its refresh attempt failed. The refresh token
     * stored in DataStore has a much longer lifetime than the access token (90 days default)
     * so this should succeed even after extended sleep/Doze periods.
     */
    private suspend fun recoverFromDataStore() {
        val prefs = context.dataStore.data.first()
        val accessToken = prefs[stringPreferencesKey("supabase_access_token")]
        val refreshToken = prefs[stringPreferencesKey("supabase_refresh_token")]
        val savedUserId = prefs[stringPreferencesKey("supabase_user_id")]

        if (!accessToken.isNullOrEmpty() && !refreshToken.isNullOrEmpty()) {
            // Keep user authenticated while we attempt recovery
            if (!savedUserId.isNullOrEmpty()) {
                _isAuthenticated.value = true
                _currentUserId.value = savedUserId
            }
            isRecovering = true
            try {
                supabaseClient.auth.importAuthToken(accessToken, refreshToken)
                // Success — the session listener will persist the new tokens
            } catch (e: Exception) {
                // Recovery failed — don't logout on transient network failures.
                // The refresh token is still valid. Will retry on next resume.
            } finally {
                isRecovering = false
            }
        }
    }

    /**
     * Registers this device in the persistent paired_watches table after a successful
     * pairing. Saves the returned record ID to DataStore so we can check for repair
     * tokens on future app resumes.
     */
    private suspend fun registerPairing(accessToken: String, userId: String) {
        try {
            val deviceName = android.os.Build.MODEL ?: "Wear OS"

            val client = HttpClient(CIO) {
                install(io.ktor.client.plugins.contentnegotiation.ContentNegotiation) {
                    kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                }
            }
            
            val jsonBody = """
                {
                    "user_id": "$userId",
                    "platform": "wearos",
                    "device_name": "$deviceName",
                    "is_active": true
                }
            """.trimIndent()

            val response = client.request(supabaseUrl + "/rest/v1/paired_watches") {
                method = io.ktor.http.HttpMethod.Post
                header("Authorization", "Bearer $accessToken")
                header("apikey", supabaseAnonKey)
                header("Prefer", "return=representation")
                contentType(io.ktor.http.ContentType.Application.Json)
                setBody(jsonBody)
            }

            if (response.status.value in 200..299) {
                val responseText = response.bodyAsText()
                val jsonArray = kotlinx.serialization.json.Json.parseToJsonElement(responseText) as? kotlinx.serialization.json.JsonArray
                val firstObj = jsonArray?.firstOrNull() as? kotlinx.serialization.json.JsonObject
                val id = firstObj?.get("id")?.jsonPrimitive?.content
                
                if (id != null) {
                    context.dataStore.edit { prefs ->
                        prefs[pairedWatchIdKey] = id
                    }
                }
            }
            client.close()
        } catch (e: Exception) {
            // Non-critical — pairing still works without the persistent record
        }
    }

    /**
     * Checks the paired_watches table for repair tokens pushed by the main app.
     * If found, imports them to restore the session and clears the pending columns.
     */
    private suspend fun checkForRepairTokens() {
        try {
            val prefs = context.dataStore.data.first()
            val pairedWatchId = prefs[pairedWatchIdKey] ?: return

            val records = supabaseClient.postgrest["paired_watches"]
                .select { filter { eq("id", pairedWatchId) } }
                .decodeList<PairedWatch>()

            val record = records.firstOrNull() ?: return
            val pendingAccess = record.pending_access_token
            val pendingRefresh = record.pending_refresh_token

            if (!pendingAccess.isNullOrEmpty() && !pendingRefresh.isNullOrEmpty()) {
                // Apply the fresh tokens
                supabaseClient.auth.importAuthToken(pendingAccess, pendingRefresh)

                // Clear the pending tokens so we don't re-apply on next resume
                supabaseClient.postgrest["paired_watches"]
                    .update({
                        set("pending_access_token", null as String?)
                        set("pending_refresh_token", null as String?)
                    }) { filter { eq("id", pairedWatchId) } }
            }
        } catch (e: Exception) {
            // Non-critical — normal session refresh will still run
        }
    }

    fun logout() {
        pollJob?.cancel()
        scope.launch {
            // Deactivate the paired_watches record
            try {
                val prefs = context.dataStore.data.first()
                val pairedWatchId = prefs[pairedWatchIdKey]
                if (pairedWatchId != null) {
                    supabaseClient.postgrest["paired_watches"]
                        .update({ set("is_active", false) }) {
                            filter { eq("id", pairedWatchId) }
                        }
                }
            } catch (_: Exception) {}

            context.dataStore.edit { prefs ->
                prefs.remove(stringPreferencesKey("supabase_access_token"))
                prefs.remove(stringPreferencesKey("supabase_refresh_token"))
                prefs.remove(stringPreferencesKey("supabase_user_id"))
                prefs.remove(pairedWatchIdKey)
            }
            try { supabaseClient.auth.signOut() } catch (e: Exception) {}
            _isAuthenticated.value = false
            _currentUserId.value = null
            generatePairingCode()
        }
    }

    private fun extractUserId(jwt: String): String? {
        try {
            val parts = jwt.split(".")
            if (parts.size != 3) return null
            var base64 = parts[1].replace("-", "+").replace("_", "/")
            val pad = base64.length % 4
            if (pad > 0) {
                base64 += "=".repeat(4 - pad)
            }
            val jsonBytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
            val jsonString = String(jsonBytes, Charsets.UTF_8)
            val jsonObject = kotlinx.serialization.json.Json.parseToJsonElement(jsonString) as kotlinx.serialization.json.JsonObject
            return jsonObject["sub"]?.jsonPrimitive?.content
        } catch (e: Exception) {
            return null
        }
    }
}
