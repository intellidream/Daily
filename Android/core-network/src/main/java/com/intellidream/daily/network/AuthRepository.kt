package com.intellidream.daily.network

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.intellidream.daily.model.AuthProvider
import com.intellidream.daily.model.AuthSessionState
import com.intellidream.daily.model.UserProfile
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.handleDeeplinks
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

class AuthRepository(
    private val context: Context? = null,
    private val coroutineScope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {
    private val supabase = SupabaseClientManager.client
    private val auth = supabase.auth

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val prefs = context?.getSharedPreferences("daily_auth_prefs", Context.MODE_PRIVATE)

    private val _sessionState = MutableStateFlow<AuthSessionState>(loadInitialState())
    val sessionState: StateFlow<AuthSessionState> = _sessionState.asStateFlow()

    private fun loadInitialState(): AuthSessionState {
        val cachedJson = prefs?.getString(KEY_CACHED_PROFILE, null)
        if (!cachedJson.isNullOrEmpty()) {
            try {
                val profile = json.decodeFromString<UserProfile>(cachedJson)
                return AuthSessionState.Authenticated(profile)
            } catch (_: Exception) {}
        }
        return AuthSessionState.Initializing
    }

    init {
        coroutineScope.launch {
            auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        val user = status.session.user
                        val meta = user?.userMetadata
                        val fullName = meta?.get("full_name")?.jsonPrimitive?.contentOrNull
                            ?: meta?.get("name")?.jsonPrimitive?.contentOrNull
                            ?: meta?.get("user_name")?.jsonPrimitive?.contentOrNull
                        val avatarUrl = meta?.get("avatar_url")?.jsonPrimitive?.contentOrNull
                            ?: meta?.get("picture")?.jsonPrimitive?.contentOrNull
                            ?: meta?.get("avatar")?.jsonPrimitive?.contentOrNull

                        val profile = UserProfile(
                            id = user?.id ?: "unknown",
                            email = user?.email,
                            fullName = fullName,
                            avatarUrl = avatarUrl,
                            provider = AuthProvider.Google,
                            createdAt = System.currentTimeMillis()
                        )
                        _sessionState.value = AuthSessionState.Authenticated(profile)
                        prefs?.edit()?.putString(KEY_CACHED_PROFILE, json.encodeToString(profile))?.apply()
                    }
                    is SessionStatus.NotAuthenticated -> {
                        if (_sessionState.value !is AuthSessionState.Guest) {
                            prefs?.edit()?.remove(KEY_CACHED_PROFILE)?.apply()
                            _sessionState.value = AuthSessionState.Unauthenticated
                        }
                    }
                    SessionStatus.Initializing -> {
                        if (_sessionState.value !is AuthSessionState.Authenticated &&
                            _sessionState.value !is AuthSessionState.Guest
                        ) {
                            _sessionState.value = AuthSessionState.Initializing
                        }
                    }
                    else -> Unit
                }
            }
        }
    }

    suspend fun getGoogleOAuthUrl(): String {
        return auth.getOAuthUrl(
            provider = Google,
            redirectUrl = SupabaseClientManager.REDIRECT_URL
        )
    }

    fun launchGoogleSignIn(context: Context) {
        coroutineScope.launch {
            try {
                auth.signInWith(Google)
            } catch (_: Exception) {
                try {
                    val url = getGoogleOAuthUrl()
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                } catch (_: Exception) {
                }
            }
        }
    }

    suspend fun handleAuthCallback(uri: Uri) {
        try {
            val code = uri.getQueryParameter("code")
            if (!code.isNullOrEmpty()) {
                auth.exchangeCodeForSession(code)
            } else {
                val fragment = uri.fragment
                if (!fragment.isNullOrEmpty()) {
                    val params = fragment.split("&").associate {
                        val parts = it.split("=", limit = 2)
                        parts[0] to (parts.getOrNull(1) ?: "")
                    }
                    val accessToken = params["access_token"]
                    val refreshToken = params["refresh_token"] ?: ""
                    if (!accessToken.isNullOrEmpty()) {
                        auth.importAuthToken(accessToken, refreshToken, retrieveUser = true)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("AuthRepository", "Failed to handle auth callback", e)
        }
    }

    fun handleIntent(intent: Intent) {
        supabase.handleDeeplinks(intent)
    }

    fun signInAsGuest() {
        _sessionState.value = AuthSessionState.Guest
    }

    suspend fun signOut() {
        try {
            if (_sessionState.value is AuthSessionState.Authenticated) {
                auth.signOut()
            }
        } catch (_: Exception) {
        } finally {
            prefs?.edit()?.remove(KEY_CACHED_PROFILE)?.apply()
            _sessionState.value = AuthSessionState.Unauthenticated
        }
    }

    companion object {
        private const val KEY_CACHED_PROFILE = "cached_user_profile"
    }
}
