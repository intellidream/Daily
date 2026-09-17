package com.intellidream.daily.network

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.intellidream.daily.model.AuthProvider
import com.intellidream.daily.model.AuthSessionState
import com.intellidream.daily.model.UserProfile
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AuthRepository(
    private val coroutineScope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {
    private val supabase = SupabaseClientManager.client
    private val auth = supabase.auth

    private val _sessionState = MutableStateFlow<AuthSessionState>(AuthSessionState.Initializing)
    val sessionState: StateFlow<AuthSessionState> = _sessionState.asStateFlow()

    init {
        coroutineScope.launch {
            auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        val user = status.session.user
                        val profile = UserProfile(
                            id = user?.id ?: "unknown",
                            email = user?.email,
                            fullName = user?.userMetadata?.get("full_name")?.toString()
                                ?: user?.userMetadata?.get("name")?.toString(),
                            avatarUrl = user?.userMetadata?.get("avatar_url")?.toString(),
                            provider = AuthProvider.Google,
                            createdAt = System.currentTimeMillis()
                        )
                        _sessionState.value = AuthSessionState.Authenticated(profile)
                    }
                    is SessionStatus.NotAuthenticated -> {
                        if (_sessionState.value !is AuthSessionState.Guest) {
                            _sessionState.value = AuthSessionState.Unauthenticated
                        }
                    }
                    SessionStatus.Initializing -> {
                        if (_sessionState.value !is AuthSessionState.Guest) {
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
                val url = getGoogleOAuthUrl()
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                // Fallback or log error
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
                    auth.importAuthToken(fragment)
                }
            }
        } catch (e: Exception) {
            // Handle callback error
        }
    }

    fun signInAsGuest() {
        _sessionState.value = AuthSessionState.Guest
    }

    suspend fun signOut() {
        try {
            if (_sessionState.value is AuthSessionState.Authenticated) {
                auth.signOut()
            }
        } catch (e: Exception) {
            // Ignore network errors on sign out
        } finally {
            _sessionState.value = AuthSessionState.Unauthenticated
        }
    }
}
