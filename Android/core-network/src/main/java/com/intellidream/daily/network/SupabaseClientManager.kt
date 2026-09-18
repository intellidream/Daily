package com.intellidream.daily.network

import android.content.Context
import com.russhwolf.settings.SharedPreferencesSettings
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.auth.SettingsCodeVerifierCache
import io.github.jan.supabase.auth.SettingsSessionManager
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime

object SupabaseClientManager {
    const val SUPABASE_URL = "https://akkfouifxztnfwwiclwg.supabase.co"
    const val SUPABASE_ANON_KEY = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"
    const val SCHEME = "com.intellidream.daily"
    const val HOST = "login-callback"
    const val REDIRECT_URL = "$SCHEME://$HOST"

    private var appContext: Context? = null

    fun initialize(context: Context) {
        if (appContext == null) {
            appContext = context.applicationContext
        }
    }

    val client: SupabaseClient by lazy {
        val context = appContext
        createSupabaseClient(
            supabaseUrl = SUPABASE_URL,
            supabaseKey = SUPABASE_ANON_KEY
        ) {
            install(Auth) {
                flowType = FlowType.PKCE
                scheme = SCHEME
                host = HOST
                defaultRedirectUrl = REDIRECT_URL
                autoLoadFromStorage = true
                autoSaveToStorage = true
                alwaysAutoRefresh = true

                if (context != null) {
                    val prefs = context.getSharedPreferences("supabase_session_storage", Context.MODE_PRIVATE)
                    val settings = SharedPreferencesSettings(prefs)
                    sessionManager = SettingsSessionManager(settings)
                    codeVerifierCache = SettingsCodeVerifierCache(settings)
                }
            }
            install(Postgrest)
            install(Realtime)
            install(Functions)
        }
    }
}
