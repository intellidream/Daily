package com.intellidream.daily.wearos.data

import android.content.Context
import com.intellidream.daily.wearos.domain.model.PairedWatch
import com.intellidream.daily.wearos.domain.model.WatchPairing
import com.intellidream.daily.wearos.domain.model.WatchPairingInsert
import com.intellidream.daily.wearos.domain.model.HabitLog
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.user.UserSession
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

class WatchSessionManager private constructor(private val context: Context) {

    companion object {
        const val PREFS_NAME = "daily_prefs"
        const val KEY_ACCESS_TOKEN = "supabase_access_token"
        const val KEY_REFRESH_TOKEN = "supabase_refresh_token"
        const val KEY_USER_ID = "supabase_user_id"
        const val KEY_PAIRED_WATCH_ID = "paired_watch_id"
        const val KEY_WATER_TOTAL = "daily_water_total"
        const val KEY_SMOKES_TOTAL = "daily_smokes_total"
        const val KEY_LAST_HEALTH_SYNC = "last_health_sync_time"

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

    private val prefs by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
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

    fun recordHealthSync() {
        val now = System.currentTimeMillis()
        prefs.edit().putString(KEY_LAST_HEALTH_SYNC, now.toString()).apply()
    }

    fun persistWaterTotal(water: Int) {
        prefs.edit().putString(KEY_WATER_TOTAL, water.toString()).apply()
    }

    fun persistSmokesTotal(smokes: Int) {
        prefs.edit().putString(KEY_SMOKES_TOTAL, smokes.toString()).apply()
    }

    @Volatile private var pollJob: Job? = null
    @Volatile private var isPolling = false
    @Volatile private var isPairingCompleted = false
    private val scope = CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.IO)
    @Volatile private var isRecovering = false
    @Volatile private var isCheckingSession = false

    /**
     * Imports a 10-year Orbit watch JWT session into the Supabase Auth client.
     * We set expiresIn to 10 years (315360000L seconds) so supabase-kt never considers
     * the token expired and PostgREST always attaches the Bearer token to requests.
     */
    suspend fun importOrbitSession(accessToken: String, refreshToken: String = "") {
        try {
            val session = UserSession(
                accessToken = accessToken,
                refreshToken = refreshToken,
                expiresIn = 315360000L,
                tokenType = "bearer",
                user = null
            )
            supabaseClient.auth.importSession(session, autoRefresh = false)
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            android.util.Log.w("WatchSessionManager", "importOrbitSession non-fatal: ${e.localizedMessage}")
        }
    }

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
                        val uid = session.user?.id ?: extractUserId(session.accessToken)
                        prefs.edit()
                            .putString(KEY_ACCESS_TOKEN, session.accessToken)
                            .putString(KEY_REFRESH_TOKEN, session.refreshToken)
                            .apply()
                        if (uid != null) {
                            prefs.edit().putString(KEY_USER_ID, uid).apply()
                            _currentUserId.value = uid
                        }
                        _isAuthenticated.value = true
                        _isPairing.value = false
                    }
                    is SessionStatus.NotAuthenticated -> {
                        // Attempt recovery from SharedPreferences tokens regardless of current auth state.
                        if (!isRecovering) {
                            val savedUserId = prefs.getString(KEY_USER_ID, null)
                            if (!savedUserId.isNullOrEmpty()) {
                                val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null)
                                val refreshToken = prefs.getString(KEY_REFRESH_TOKEN, "") ?: ""
                                if (!accessToken.isNullOrEmpty()) {
                                    isRecovering = true
                                    try {
                                        importOrbitSession(accessToken, refreshToken)
                                    } catch (e: Exception) {
                                        if (e is kotlinx.coroutines.CancellationException) throw e
                                    } finally {
                                        isRecovering = false
                                    }
                                    _currentUserId.value = savedUserId
                                    _isAuthenticated.value = true
                                    _isPairing.value = false
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
        android.util.Log.d("WatchSessionManager", "checkExistingSession called: isChecking=$isCheckingSession, auth=${_isAuthenticated.value}")
        if (isCheckingSession || _isAuthenticated.value) return
        isCheckingSession = true
        scope.launch {
            try {
                // 1. Check if the Auth plugin already has a cached session.
                val existingSession = supabaseClient.auth.currentSessionOrNull()
                android.util.Log.d("WatchSessionManager", "checkExistingSession: in-memory session = ${existingSession != null}")
                if (existingSession != null) {
                    val uid = existingSession.user?.id ?: extractUserId(existingSession.accessToken)
                    if (uid != null) {
                        // Show authenticated UI immediately using cached data
                        _currentUserId.value = uid
                        _isAuthenticated.value = true
                        _isPairing.value = false
                        prefs.edit()
                            .putString(KEY_ACCESS_TOKEN, existingSession.accessToken)
                            .putString(KEY_REFRESH_TOKEN, existingSession.refreshToken)
                            .putString(KEY_USER_ID, uid)
                            .apply()
                        return@launch
                    }
                }

                // 2. Fall back to SharedPreferences tokens
                val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null)
                val refreshToken = prefs.getString(KEY_REFRESH_TOKEN, "") ?: ""
                var savedUserId = prefs.getString(KEY_USER_ID, null)
                android.util.Log.d("WatchSessionManager", "checkExistingSession SharedPreferences: hasToken=${!accessToken.isNullOrEmpty()}, uid=$savedUserId")
                
                if (savedUserId.isNullOrEmpty() && !accessToken.isNullOrEmpty()) {
                    savedUserId = extractUserId(accessToken)
                    if (savedUserId != null) {
                        prefs.edit().putString(KEY_USER_ID, savedUserId).apply()
                    }
                }

                // Note: 10-year Orbit watch JWTs have empty refresh tokens, so only require accessToken & savedUserId
                if (!accessToken.isNullOrEmpty() && !savedUserId.isNullOrEmpty()) {
                    importOrbitSession(accessToken, refreshToken)
                    _currentUserId.value = savedUserId
                    _isAuthenticated.value = true
                    _isPairing.value = false
                    android.util.Log.d("WatchSessionManager", "checkExistingSession: restored session for user $savedUserId")
                } else {
                    android.util.Log.d("WatchSessionManager", "checkExistingSession: no valid session found, isPairing=${_isPairing.value}, pin=${_pairingCode.value}")
                    if (!_isPairing.value || _pairingCode.value.isEmpty()) {
                        generatePairingCode()
                    }
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e("WatchSessionManager", "checkExistingSession exception", e)
            } finally {
                isCheckingSession = false
            }
        }
    }

    fun generatePairingCode() {
        if (_isAuthenticated.value) {
            android.util.Log.d("WatchSessionManager", "generatePairingCode: already authenticated, skipping")
            return
        }
        stopPolling()
        isPairingCompleted = false
        _isPairing.value = true
        _errorMessage.value = ""
        val code = String.format("%06d", (0..999999).random())
        _pairingCode.value = code
        android.util.Log.d("WatchSessionManager", "generatePairingCode: generated code=$code")

        scope.launch {
            try {
                val pairing = WatchPairingInsert(pin_code = code)
                supabaseClient.postgrest["watch_pairing_codes"].insert(pairing)
                android.util.Log.d("WatchSessionManager", "generatePairingCode: insert OK in Supabase, starting polling")
                startPolling()
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e("WatchSessionManager", "Pairing insert failed", e)
                val msg = e.localizedMessage ?: e.cause?.localizedMessage ?: e::class.java.simpleName
                _errorMessage.value = "Insert Err: $msg"
            }
        }
    }

    fun stopPolling() {
        android.util.Log.d("WatchSessionManager", "stopPolling called")
        isPolling = false
        pollJob?.cancel()
        pollJob = null
    }

    private fun startPolling() {
        stopPolling()
        isPolling = true
        isPairingCompleted = false
        android.util.Log.d("WatchSessionManager", "startPolling launched for pin=${_pairingCode.value}")
        pollJob = scope.launch {
            while (isActive && isPolling) {
                delay(2500)
                if (!isActive || !isPolling) break
                android.util.Log.d("WatchSessionManager", "Polling tick: checking pin=${_pairingCode.value}")
                checkPairingStatus()
            }
        }
    }

    private suspend fun checkPairingStatus() {
        if (!isPolling || isPairingCompleted || _pairingCode.value.isEmpty()) {
            android.util.Log.d("WatchSessionManager", "checkPairingStatus skipped: isPolling=$isPolling, isPairingCompleted=$isPairingCompleted, pin=${_pairingCode.value}")
            return
        }
        val currentPin = _pairingCode.value

        try {
            android.util.Log.d("WatchSessionManager", "checkPairingStatus querying watch_pairing_codes for pin=$currentPin")
            val pairings = supabaseClient.postgrest["watch_pairing_codes"]
                .select { filter { eq("pin_code", currentPin) } }
                .decodeList<WatchPairing>()

            android.util.Log.d("WatchSessionManager", "checkPairingStatus result count: ${pairings.size}")
            val pairing = pairings.firstOrNull()
            if (pairing != null) {
                val token = pairing.access_token
                android.util.Log.d("WatchSessionManager", "checkPairingStatus record: claimed=${pairing.claimed}, hasToken=${!token.isNullOrEmpty()}")
                if (!token.isNullOrEmpty()) {
                    // 1. IMMEDIATELY stop polling so no subsequent poll can ever trigger
                    if (isPairingCompleted) return
                    isPairingCompleted = true
                    stopPolling()

                    val refresh = pairing.refresh_token.orEmpty()
                    val uid = extractUserId(token) ?: pairing.user_id
                    android.util.Log.d("WatchSessionManager", "checkPairingStatus: extracted uid=$uid")

                    if (uid != null) {
                        // 2. Persistent storage in SharedPreferences (instant synchronous in-memory write + async disk flush)
                        prefs.edit()
                            .putString(KEY_ACCESS_TOKEN, token)
                            .putString(KEY_REFRESH_TOKEN, refresh)
                            .putString(KEY_USER_ID, uid)
                            .apply()
                        android.util.Log.d("WatchSessionManager", "checkPairingStatus: saved to SharedPreferences")

                        // 3. Update UI states IMMEDIATELY so the watch immediately switches to the 5-page dashboard!
                        _currentUserId.value = uid
                        _isAuthenticated.value = true
                        _isPairing.value = false
                        _pairingCode.value = ""
                        _errorMessage.value = ""
                        android.util.Log.d("WatchSessionManager", "checkPairingStatus: SUCCESS! Set isAuthenticated=true")

                        // 4. Import session into client so PostgREST has valid Bearer token
                        scope.launch {
                            importOrbitSession(token, refresh)
                        }

                        // 5. Clean up pairing code row (best-effort)
                        scope.launch {
                            try {
                                supabaseClient.postgrest["watch_pairing_codes"]
                                    .delete { filter { eq("pin_code", currentPin) } }
                            } catch (e: Exception) {
                                if (e is kotlinx.coroutines.CancellationException) throw e
                            }
                        }

                        // 6. Register device in paired_watches table (guarded for idempotency)
                        scope.launch {
                            registerPairing(token, uid)
                        }

                        _dataRefreshTrigger.value++
                    } else {
                        // In the rare event user ID cannot be determined yet, resume polling
                        android.util.Log.w("WatchSessionManager", "checkPairingStatus: uid is null, resuming polling")
                        isPairingCompleted = false
                        startPolling()
                    }
                }
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            android.util.Log.e("WatchSessionManager", "checkPairingStatus poll exception", e)
            _errorMessage.value = "Poll Err: ${e.localizedMessage}"
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
                // Auth plugin has no session at all — full recovery from SharedPreferences
                recoverFromPreferences()
            }

            // Tell screens to re-fetch their data now that auth is fresh
            _dataRefreshTrigger.value++

            // Flush any logs that were queued while offline
            if (_isAuthenticated.value) {
                OfflineSyncManager.shared.syncPendingLogs(supabaseClient)
                recordHealthSync()
            }
        }
    }

    /**
     * Recovers a Supabase session from SharedPreferences-persisted tokens. Called when the Auth
     * plugin's in-memory session is gone or its refresh attempt failed.
     */
    private suspend fun recoverFromPreferences() {
        val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null)
        val refreshToken = prefs.getString(KEY_REFRESH_TOKEN, "") ?: ""
        val savedUserId = prefs.getString(KEY_USER_ID, null)

        if (!accessToken.isNullOrEmpty() && !savedUserId.isNullOrEmpty()) {
            isRecovering = true
            try {
                importOrbitSession(accessToken, refreshToken)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
            } finally {
                isRecovering = false
            }
            _currentUserId.value = savedUserId
            _isAuthenticated.value = true
        }
    }

    /**
     * Registers this device in the persistent paired_watches table after a successful
     * pairing. Saves the returned record ID to SharedPreferences so we can check for repair
     * tokens on future app resumes. Guarded against multiple duplicate insertions.
     */
    private suspend fun registerPairing(accessToken: String, userId: String) {
        try {
            // Idempotency check: if we already have an active paired_watch_id stored, do not insert again
            val existingWatchId = prefs.getString(KEY_PAIRED_WATCH_ID, null)
            if (!existingWatchId.isNullOrEmpty()) {
                android.util.Log.i("WatchSessionManager", "Device already registered with id: $existingWatchId")
                return
            }

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
                    prefs.edit().putString(KEY_PAIRED_WATCH_ID, id).apply()
                }
            }
            client.close()
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            // Non-critical — pairing still works without the persistent record
        }
    }

    /**
     * Checks the paired_watches table for repair tokens pushed by the main app.
     * If found, imports them to restore the session and clears the pending columns.
     */
    private suspend fun checkForRepairTokens() {
        try {
            val pairedWatchId = prefs.getString(KEY_PAIRED_WATCH_ID, null) ?: return

            val records = supabaseClient.postgrest["paired_watches"]
                .select { filter { eq("id", pairedWatchId) } }
                .decodeList<PairedWatch>()

            val record = records.firstOrNull() ?: return
            val pendingAccess = record.pending_access_token
            val pendingRefresh = record.pending_refresh_token

            if (!pendingAccess.isNullOrEmpty() && !pendingRefresh.isNullOrEmpty()) {
                // Apply the fresh tokens
                importOrbitSession(pendingAccess, pendingRefresh)

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
        stopPolling()
        scope.launch {
            // Deactivate the paired_watches record
            try {
                val pairedWatchId = prefs.getString(KEY_PAIRED_WATCH_ID, null)
                if (pairedWatchId != null) {
                    supabaseClient.postgrest["paired_watches"]
                        .update({ set("is_active", false) }) {
                            filter { eq("id", pairedWatchId) }
                        }
                }
            } catch (_: Exception) {}

            prefs.edit()
                .remove(KEY_ACCESS_TOKEN)
                .remove(KEY_REFRESH_TOKEN)
                .remove(KEY_USER_ID)
                .remove(KEY_PAIRED_WATCH_ID)
                .apply()

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
