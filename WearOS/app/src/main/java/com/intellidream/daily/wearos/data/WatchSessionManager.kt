package com.intellidream.daily.wearos.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.intellidream.daily.wearos.domain.model.WatchPairing
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

val Context.dataStore by preferencesDataStore(name = "daily_prefs")

class WatchSessionManager(private val context: Context) {

    private val supabaseUrl = "https://akkfouifxztnfwwiclwg.supabase.co"
    private val supabaseAnonKey = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"

    val supabaseClient: SupabaseClient = createSupabaseClient(supabaseUrl, supabaseAnonKey) {
        install(Auth)
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

    private var pollJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    fun checkExistingSession() {
        scope.launch {
            val prefs = context.dataStore.data.first()
            val accessToken = prefs[stringPreferencesKey("supabase_access_token")]
            val refreshToken = prefs[stringPreferencesKey("supabase_refresh_token")]
            val savedUserId = prefs[stringPreferencesKey("supabase_user_id")]

            if (!accessToken.isNullOrEmpty() && !refreshToken.isNullOrEmpty() && !savedUserId.isNullOrEmpty()) {
                // Optimistic UI loading instantly
                _currentUserId.value = savedUserId
                _isAuthenticated.value = true
                _isPairing.value = false
                
                try {
                    supabaseClient.auth.importAuthToken(accessToken, refreshToken)
                    
                    // Attempt background refresh so API calls don't fail later
                    supabaseClient.auth.refreshCurrentSession()
                    
                    val session = supabaseClient.auth.currentSessionOrNull()
                    if (session != null) {
                        context.dataStore.edit { editPrefs ->
                            editPrefs[stringPreferencesKey("supabase_access_token")] = session.accessToken
                            editPrefs[stringPreferencesKey("supabase_refresh_token")] = session.refreshToken
                        }
                    }
                } catch (e: Exception) {
                    // Do not aggressively logout if network fails here. 
                    // Let the offline manager handle API failures gracefully.
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
                    
                    supabaseClient.auth.importAuthToken(token, refresh)
                    val uid = supabaseClient.auth.currentUserOrNull()?.id

                    if (uid != null) {
                        context.dataStore.edit { prefs ->
                            prefs[stringPreferencesKey("supabase_access_token")] = token
                            prefs[stringPreferencesKey("supabase_refresh_token")] = refresh
                            prefs[stringPreferencesKey("supabase_user_id")] = uid
                        }
    
                        _currentUserId.value = uid
                        _isAuthenticated.value = true
                        _isPairing.value = false
    
                        supabaseClient.postgrest["watch_pairings"]
                            .delete { filter { eq("code", _pairingCode.value) } }
                            
                        pollJob?.cancel()
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

    fun logout() {
        pollJob?.cancel()
        scope.launch {
            context.dataStore.edit { prefs ->
                prefs.remove(stringPreferencesKey("supabase_access_token"))
                prefs.remove(stringPreferencesKey("supabase_refresh_token"))
                prefs.remove(stringPreferencesKey("supabase_user_id"))
            }
            try { supabaseClient.auth.signOut() } catch (e: Exception) {}
            _isAuthenticated.value = false
            _currentUserId.value = null
            generatePairingCode()
        }
    }
}
