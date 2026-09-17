package com.intellidream.daily.network

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime

object SupabaseClientManager {
    const val SUPABASE_URL = "https://akkfouifxztnfwwiclwg.supabase.co"
    const val SUPABASE_ANON_KEY = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"
    const val REDIRECT_URL = "com.intellidream.daily://login-callback"

    val client: SupabaseClient by lazy {
        createSupabaseClient(
            supabaseUrl = SUPABASE_URL,
            supabaseKey = SUPABASE_ANON_KEY
        ) {
            install(Auth)
            install(Postgrest)
            install(Realtime)
            install(Functions)
        }
    }
}
