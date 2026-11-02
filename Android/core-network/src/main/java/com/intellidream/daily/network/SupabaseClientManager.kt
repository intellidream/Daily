package com.intellidream.daily.network

import android.content.Context
import com.russhwolf.settings.SharedPreferencesSettings
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.auth.SettingsCodeVerifierCache
import io.github.jan.supabase.auth.SettingsSessionManager
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import io.ktor.client.engine.okhttp.OkHttp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.InetAddress
import java.net.UnknownHostException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

object SupabaseClientManager {
    const val SUPABASE_URL = "https://akkfouifxztnfwwiclwg.supabase.co"
    const val SUPABASE_ANON_KEY = "sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG"
    const val SCHEME = "com.intellidream.daily"
    const val HOST = "login-callback"
    const val REDIRECT_URL = "$SCHEME://$HOST"

    private var appContext: Context? = null

    private val dnsJson = Json { ignoreUnknownKeys = true }
    private val dnsCache = ConcurrentHashMap<String, Pair<Long, List<InetAddress>>>()
    private const val DNS_CACHE_TTL_MS = 5 * 60 * 1000L

    private val dohBootstrapClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(4, TimeUnit.SECONDS)
            .readTimeout(4, TimeUnit.SECONDS)
            .dns(object : Dns {
                override fun lookup(hostname: String): List<InetAddress> = when (hostname) {
                    "1.1.1.1" -> listOf(InetAddress.getByAddress("1.1.1.1", byteArrayOf(1, 1, 1, 1)))
                    "1.0.0.1" -> listOf(InetAddress.getByAddress("1.0.0.1", byteArrayOf(1, 0, 0, 1)))
                    else -> Dns.SYSTEM.lookup(hostname)
                }
            })
            .build()
    }

    private val resilientDns: Dns = object : Dns {
        override fun lookup(hostname: String): List<InetAddress> {
            try {
                val systemAddresses = Dns.SYSTEM.lookup(hostname)
                if (systemAddresses.isNotEmpty()) {
                    dnsCache[hostname] = System.currentTimeMillis() to systemAddresses
                    return systemAddresses
                }
            } catch (_: UnknownHostException) {
                // Fall through to cached or Cloudflare DoH resolution (e.g., idle Tailscale Private DNS)
            }

            val now = System.currentTimeMillis()
            dnsCache[hostname]?.let { (cachedAt, cachedAddresses) ->
                if (now - cachedAt < DNS_CACHE_TTL_MS && cachedAddresses.isNotEmpty()) {
                    return cachedAddresses
                }
            }

            for (resolverIp in listOf("1.1.1.1", "1.0.0.1")) {
                try {
                    val req = Request.Builder()
                        .url("https://$resolverIp/dns-query?name=$hostname&type=A")
                        .header("Accept", "application/dns-json")
                        .get()
                        .build()
                    dohBootstrapClient.newCall(req).execute().use { resp ->
                        if (resp.isSuccessful) {
                            val body = resp.body?.string().orEmpty()
                            val root = dnsJson.parseToJsonElement(body).jsonObject
                            val answers = root["Answer"]?.jsonArray.orEmpty()
                            val resolved = answers.mapNotNull { el ->
                                val obj = el.jsonObject
                                val type = obj["type"]?.jsonPrimitive?.intOrNull
                                val ipStr = obj["data"]?.jsonPrimitive?.content
                                if (type == 1 && !ipStr.isNullOrBlank()) {
                                    val parts = ipStr.split(".")
                                    if (parts.size == 4) {
                                        val bytes = ByteArray(4) { idx -> parts[idx].toInt().toByte() }
                                        InetAddress.getByAddress(hostname, bytes)
                                    } else null
                                } else null
                            }
                            if (resolved.isNotEmpty()) {
                                dnsCache[hostname] = now to resolved
                                return resolved
                            }
                        }
                    }
                } catch (_: Exception) {
                }
            }

            throw UnknownHostException("Unable to resolve host $hostname via system DNS or DoH")
        }
    }

    val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .dns(resilientDns)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build()
    }

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
            httpEngine = OkHttp.create {
                preconfigured = okHttpClient
            }
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

    suspend fun ensureSessionReady(): Boolean {
        try {
            val auth = client.auth
            if (!auth.currentAccessTokenOrNull().isNullOrBlank()) {
                return true
            }
            if (auth.sessionStatus.value is SessionStatus.Initializing) {
                withTimeoutOrNull(2000L) {
                    auth.sessionStatus.first { it !is SessionStatus.Initializing }
                }
            }
            if (!auth.currentAccessTokenOrNull().isNullOrBlank()) {
                return true
            }
            val prefs = appContext?.getSharedPreferences("supabase_session_storage", Context.MODE_PRIVATE)
            val rawSession = prefs?.getString("session", null)
            if (!rawSession.isNullOrBlank()) {
                val obj = dnsJson.parseToJsonElement(rawSession).jsonObject
                val accessToken = obj["access_token"]?.jsonPrimitive?.content
                    ?: obj["accessToken"]?.jsonPrimitive?.content
                val refreshToken = obj["refresh_token"]?.jsonPrimitive?.content
                    ?: obj["refreshToken"]?.jsonPrimitive?.content
                    ?: ""
                if (!accessToken.isNullOrBlank()) {
                    auth.importAuthToken(accessToken, refreshToken, retrieveUser = false)
                }
            }
            return !auth.currentAccessTokenOrNull().isNullOrBlank()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            android.util.Log.w("SupabaseClientManager", "Session check warning: ${e.message}")
            return !runCatching { client.auth.currentAccessTokenOrNull() }.getOrNull().isNullOrBlank()
        }
    }

    fun currentAccessTokenOrAnonKey(): String {
        return runCatching { client.auth.currentAccessTokenOrNull() }.getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: SUPABASE_ANON_KEY
    }
}
