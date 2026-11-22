package com.intellidream.daily.network

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.FormBody
import okhttp3.Request
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

enum class ExternalTaskProvider(val id: String, val displayName: String) {
    MicrosoftToDo("MicrosoftToDo", "Microsoft To Do"),
    GoogleTasks("GoogleTasks", "Google Tasks")
}

@Serializable
data class ExternalTaskAccount(
    val id: String,
    val providerId: String,
    val email: String,
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMillis: Long,
    val oauthClientKind: String = "mobile",
    val fromCalendarSync: Boolean = false
) {
    val provider: ExternalTaskProvider
        get() = if (providerId == ExternalTaskProvider.GoogleTasks.id) ExternalTaskProvider.GoogleTasks else ExternalTaskProvider.MicrosoftToDo
}

data class ExternalTaskList(
    val id: String,
    val title: String,
    val isDefault: Boolean = false
)

data class ExternalTaskItem(
    val id: String,
    val title: String,
    val notes: String? = null,
    val isHighImportance: Boolean = false
)

class ExternalTasksAuthException(
    message: String,
    val needsReauth: Boolean = false
) : Exception(message)

object TagdosExternalTasksService {
    private const val PREFS_NAME = "daily_tagdos_external_accounts"
    private const val KEY_ACCOUNTS = "accounts_json_v1"

    private val MICROSOFT_CLIENT_ID: String get() = BuildConfig.MICROSOFT_CLIENT_ID
    private const val MICROSOFT_REDIRECT_URI = "com.intellidream.daily.desktop://login-callback"
    private const val MICROSOFT_SCHEME = "com.intellidream.daily.desktop"

    private val GOOGLE_MOBILE_CLIENT_ID: String get() = BuildConfig.GOOGLE_MOBILE_CLIENT_ID
    private val GOOGLE_MOBILE_SCHEME: String
        get() = "com.googleusercontent.apps." + BuildConfig.GOOGLE_MOBILE_CLIENT_ID
            .removeSuffix(".apps.googleusercontent.com")
    private val GOOGLE_MOBILE_REDIRECT_URI: String
        get() = "$GOOGLE_MOBILE_SCHEME:/oauth2redirect"

    private val GOOGLE_DESKTOP_CLIENT_ID: String get() = BuildConfig.GOOGLE_DESKTOP_CLIENT_ID
    private val GOOGLE_DESKTOP_CLIENT_SECRET: String get() = BuildConfig.GOOGLE_DESKTOP_CLIENT_SECRET

    private val staticSalt = byteArrayOf(
        0x44, 0x61, 0x69, 0x6c, 0x79, 0x5f, 0x53, 0x65,
        0x63, 0x75, 0x72, 0x65, 0x5f, 0x4b, 0x65, 0x79
    )

    private val json = Json { ignoreUnknownKeys = true }
    private var appContext: Context? = null

    private val _accounts = MutableStateFlow<List<ExternalTaskAccount>>(emptyList())
    val accounts: StateFlow<List<ExternalTaskAccount>> = _accounts.asStateFlow()

    private val _isLoadingAccounts = MutableStateFlow(false)
    val isLoadingAccounts: StateFlow<Boolean> = _isLoadingAccounts.asStateFlow()

    @Volatile
    private var pendingAuthDeferred: CompletableDeferred<Uri>? = null

    @Volatile
    private var pendingAuthExpectedScheme: String? = null

    fun initialize(context: Context) {
        if (appContext == null) {
            appContext = context.applicationContext
            loadLocalAccounts()
        }
    }

    fun handleOAuthCallback(uri: Uri?): Boolean {
        if (uri == null) return false
        val scheme = uri.scheme ?: return false
        if (scheme == MICROSOFT_SCHEME || scheme == GOOGLE_MOBILE_SCHEME) {
            val expected = pendingAuthExpectedScheme
            if (expected == null || expected == scheme) {
                pendingAuthDeferred?.complete(uri)
                return true
            }
        }
        return false
    }

    private fun currentKeyScope(): String {
        val uid = runCatching { SupabaseClientManager.client.auth.currentUserOrNull()?.id }.getOrNull()
        return uid?.takeIf { it.isNotBlank() && it != "guest" }?.lowercase() ?: "daily_local_tagdos_scope"
    }

    private fun loadLocalAccounts() {
        val ctx = appContext ?: return
        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_ACCOUNTS, null) ?: run {
            _accounts.value = emptyList()
            return
        }
        val scope = currentKeyScope()
        val parsed = runCatching { json.decodeFromString<List<ExternalTaskAccount>>(raw) }.getOrNull().orEmpty()
        _accounts.value = parsed.map { acc ->
            acc.copy(
                accessToken = decryptToken(acc.accessToken, scope),
                refreshToken = decryptToken(acc.refreshToken, scope)
            )
        }
    }

    private fun persistLocalAccounts(localOnly: List<ExternalTaskAccount>) {
        val ctx = appContext ?: return
        val scope = currentKeyScope()
        val encrypted = localOnly.map { acc ->
            acc.copy(
                accessToken = encryptToken(acc.accessToken, scope),
                refreshToken = encryptToken(acc.refreshToken, scope)
            )
        }
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ACCOUNTS, json.encodeToString(encrypted))
            .apply()
    }

    @Serializable
    private data class RemoteCalendarAccountDto(
        val id: String,
        val user_id: String,
        val account_type: String,
        val email: String,
        val access_token: String,
        val refresh_token: String? = null,
        val token_expires_at: String? = null,
        val is_deleted: Boolean? = false
    )

    suspend fun refreshAvailableAccounts() = withContext(Dispatchers.IO) {
        _isLoadingAccounts.value = true
        try {
            loadLocalAccounts()
            val merged = _accounts.value.filter { !it.fromCalendarSync }.toMutableList()

            val ready = SupabaseClientManager.ensureSessionReady()
            val userId = if (ready) {
                runCatching { SupabaseClientManager.client.auth.currentUserOrNull()?.id }.getOrNull()?.lowercase()
            } else null

            if (!userId.isNullOrBlank() && userId != "guest") {
                val remoteRows = runCatching {
                    SupabaseClientManager.client.postgrest["calendar_accounts"]
                        .select(Columns.list("id,user_id,account_type,email,access_token,refresh_token,token_expires_at,is_deleted")) {
                            filter { eq("user_id", userId) }
                        }
                        .decodeList<RemoteCalendarAccountDto>()
                }.getOrNull().orEmpty()

                for (row in remoteRows) {
                    if (row.is_deleted == true) continue
                    val provider = when (row.account_type) {
                        "MicrosoftPersonal", "MicrosoftWork" -> ExternalTaskProvider.MicrosoftToDo
                        "Google" -> ExternalTaskProvider.GoogleTasks
                        else -> null
                    } ?: continue

                    val decryptedAccess = decryptToken(row.access_token, userId)
                    val decryptedRefresh = decryptToken(row.refresh_token.orEmpty(), userId)
                    val existsLocally = merged.any {
                        it.provider == provider && it.email.equals(row.email, ignoreCase = true)
                    }
                    if (!existsLocally && (decryptedAccess.isNotBlank() || decryptedRefresh.isNotBlank())) {
                        merged.add(
                            ExternalTaskAccount(
                                id = row.id.lowercase(),
                                providerId = provider.id,
                                email = row.email,
                                accessToken = decryptedAccess,
                                refreshToken = decryptedRefresh,
                                expiresAtMillis = parseIsoMillis(row.token_expires_at),
                                oauthClientKind = "desktop",
                                fromCalendarSync = true
                            )
                        )
                    }
                }
            }
            _accounts.value = merged
        } finally {
            _isLoadingAccounts.value = false
        }
    }

    suspend fun signIn(context: Context, provider: ExternalTaskProvider): ExternalTaskAccount {
        return when (provider) {
            ExternalTaskProvider.MicrosoftToDo -> signInMicrosoft(context)
            ExternalTaskProvider.GoogleTasks -> signInGoogle(context)
        }
    }

    private suspend fun signInMicrosoft(context: Context): ExternalTaskAccount {
        val codeVerifier = generateCodeVerifier()
        val codeChallenge = generateCodeChallenge(codeVerifier)
        val scopes = "offline_access https://graph.microsoft.com/User.Read https://graph.microsoft.com/Calendars.Read https://graph.microsoft.com/Tasks.Read"

        val authUrl = Uri.Builder()
            .scheme("https")
            .authority("login.microsoftonline.com")
            .appendPath("common")
            .appendPath("oauth2")
            .appendPath("v2.0")
            .appendPath("authorize")
            .appendQueryParameter("client_id", MICROSOFT_CLIENT_ID)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("redirect_uri", MICROSOFT_REDIRECT_URI)
            .appendQueryParameter("response_mode", "query")
            .appendQueryParameter("scope", scopes)
            .appendQueryParameter("prompt", "select_account")
            .appendQueryParameter("code_challenge", codeChallenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()

        val callbackUri = launchBrowserAndAwaitCallback(context, authUrl, MICROSOFT_SCHEME)
        val code = callbackUri.getQueryParameter("code")
        if (code.isNullOrBlank()) {
            val err = callbackUri.getQueryParameter("error_description") ?: callbackUri.getQueryParameter("error")
            throw ExternalTasksAuthException(err ?: "Microsoft sign-in did not return an authorization code.")
        }

        val tokenBody = FormBody.Builder()
            .add("client_id", MICROSOFT_CLIENT_ID)
            .add("code", code)
            .add("redirect_uri", MICROSOFT_REDIRECT_URI)
            .add("grant_type", "authorization_code")
            .add("code_verifier", codeVerifier)
            .build()

        val tokenObj = postFormJson("https://login.microsoftonline.com/common/oauth2/v2.0/token", tokenBody)
        val accessToken = tokenObj["access_token"]?.jsonPrimitive?.content.orEmpty()
        if (accessToken.isBlank()) throw ExternalTasksAuthException("Failed to obtain Microsoft access token.")
        val refreshToken = tokenObj["refresh_token"]?.jsonPrimitive?.content.orEmpty()
        val expiresIn = tokenObj["expires_in"]?.jsonPrimitive?.content?.toLongOrNull() ?: 3600L

        var email = "Microsoft Account"
        runCatching {
            val meObj = getJson("https://graph.microsoft.com/v1.0/me", accessToken)
            val mail = meObj["mail"]?.jsonPrimitive?.content
            val upn = meObj["userPrincipalName"]?.jsonPrimitive?.content
            if (!mail.isNullOrBlank()) email = mail
            else if (!upn.isNullOrBlank()) email = upn
        }
        if (email == "Microsoft Account") {
            runCatching {
                val calObj = getJson("https://graph.microsoft.com/v1.0/me/calendar", accessToken)
                val addr = calObj["owner"]?.jsonObject?.get("address")?.jsonPrimitive?.content
                if (!addr.isNullOrBlank()) email = addr
            }
        }

        val account = ExternalTaskAccount(
            id = "ms_${email.lowercase()}",
            providerId = ExternalTaskProvider.MicrosoftToDo.id,
            email = email,
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresAtMillis = System.currentTimeMillis() + expiresIn * 1000L,
            oauthClientKind = "mobile",
            fromCalendarSync = false
        )
        upsertLocalAccount(account)
        return account
    }

    private suspend fun signInGoogle(context: Context): ExternalTaskAccount {
        val codeVerifier = generateCodeVerifier()
        val codeChallenge = generateCodeChallenge(codeVerifier)
        val scopes = "https://www.googleapis.com/auth/tasks.readonly https://www.googleapis.com/auth/userinfo.email email profile"

        val authUrl = Uri.Builder()
            .scheme("https")
            .authority("accounts.google.com")
            .appendPath("o")
            .appendPath("oauth2")
            .appendPath("v2")
            .appendPath("auth")
            .appendQueryParameter("client_id", GOOGLE_MOBILE_CLIENT_ID)
            .appendQueryParameter("redirect_uri", GOOGLE_MOBILE_REDIRECT_URI)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("scope", scopes)
            .appendQueryParameter("access_type", "offline")
            .appendQueryParameter("prompt", "select_account consent")
            .appendQueryParameter("code_challenge", codeChallenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()

        val callbackUri = launchBrowserAndAwaitCallback(context, authUrl, GOOGLE_MOBILE_SCHEME)
        val code = callbackUri.getQueryParameter("code")
        if (code.isNullOrBlank()) {
            val err = callbackUri.getQueryParameter("error")
            throw ExternalTasksAuthException(err ?: "Google sign-in did not return an authorization code.")
        }

        val tokenBody = FormBody.Builder()
            .add("client_id", GOOGLE_MOBILE_CLIENT_ID)
            .add("code", code)
            .add("redirect_uri", GOOGLE_MOBILE_REDIRECT_URI)
            .add("grant_type", "authorization_code")
            .add("code_verifier", codeVerifier)
            .build()

        val tokenObj = postFormJson("https://oauth2.googleapis.com/token", tokenBody)
        val accessToken = tokenObj["access_token"]?.jsonPrimitive?.content.orEmpty()
        if (accessToken.isBlank()) throw ExternalTasksAuthException("Failed to obtain Google access token.")
        val refreshToken = tokenObj["refresh_token"]?.jsonPrimitive?.content.orEmpty()
        val expiresIn = tokenObj["expires_in"]?.jsonPrimitive?.content?.toLongOrNull() ?: 3600L

        var email = "Google Account"
        runCatching {
            val infoObj = getJson("https://www.googleapis.com/oauth2/v2/userinfo", accessToken)
            val fetched = infoObj["email"]?.jsonPrimitive?.content
            if (!fetched.isNullOrBlank()) email = fetched
        }

        val account = ExternalTaskAccount(
            id = "google_${email.lowercase()}",
            providerId = ExternalTaskProvider.GoogleTasks.id,
            email = email,
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresAtMillis = System.currentTimeMillis() + expiresIn * 1000L,
            oauthClientKind = "mobile",
            fromCalendarSync = false
        )
        upsertLocalAccount(account)
        return account
    }

    private suspend fun launchBrowserAndAwaitCallback(context: Context, authUri: Uri, expectedScheme: String): Uri {
        val deferred = CompletableDeferred<Uri>()
        pendingAuthDeferred = deferred
        pendingAuthExpectedScheme = expectedScheme

        withContext(Dispatchers.Main) {
            val intent = Intent(Intent.ACTION_VIEW, authUri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }

        return try {
            withTimeoutOrNull(180_000L) {
                deferred.await()
            } ?: throw ExternalTasksAuthException("Sign-in timed out. Please try again.")
        } finally {
            if (pendingAuthDeferred === deferred) {
                pendingAuthDeferred = null
                pendingAuthExpectedScheme = null
            }
        }
    }

    private fun upsertLocalAccount(account: ExternalTaskAccount) {
        val localOnly = _accounts.value
            .filter { !it.fromCalendarSync && !(it.provider == account.provider && it.email.equals(account.email, ignoreCase = true)) }
            .toMutableList()
        localOnly.add(0, account)
        persistLocalAccounts(localOnly)

        val merged = _accounts.value
            .filter { !(it.provider == account.provider && it.email.equals(account.email, ignoreCase = true)) }
            .toMutableList()
        merged.add(0, account)
        _accounts.value = merged
    }

    private suspend fun ensureValidAccessToken(account: ExternalTaskAccount): ExternalTaskAccount {
        if (System.currentTimeMillis() + 120_000L < account.expiresAtMillis && account.accessToken.isNotBlank()) {
            return account
        }
        if (account.refreshToken.isBlank()) {
            if (account.accessToken.isNotBlank()) return account
            throw ExternalTasksAuthException("${account.provider.displayName} session expired. Please sign in again.", needsReauth = true)
        }

        return when (account.provider) {
            ExternalTaskProvider.MicrosoftToDo -> {
                val body = FormBody.Builder()
                    .add("client_id", MICROSOFT_CLIENT_ID)
                    .add("grant_type", "refresh_token")
                    .add("refresh_token", account.refreshToken)
                    .add("redirect_uri", MICROSOFT_REDIRECT_URI)
                    .build()
                val obj = runCatching { postFormJson("https://login.microsoftonline.com/common/oauth2/v2.0/token", body) }.getOrNull()
                    ?: throw ExternalTasksAuthException("Microsoft session expired. Please sign in again.", needsReauth = true)
                val newAccess = obj["access_token"]?.jsonPrimitive?.content.orEmpty()
                if (newAccess.isBlank()) throw ExternalTasksAuthException("Microsoft session expired. Please sign in again.", needsReauth = true)
                val newRefresh = obj["refresh_token"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() } ?: account.refreshToken
                val expiresIn = obj["expires_in"]?.jsonPrimitive?.content?.toLongOrNull() ?: 3600L
                val updated = account.copy(
                    accessToken = newAccess,
                    refreshToken = newRefresh,
                    expiresAtMillis = System.currentTimeMillis() + expiresIn * 1000L
                )
                updateCachedToken(updated)
                updated
            }

            ExternalTaskProvider.GoogleTasks -> {
                val attempts = if (account.oauthClientKind == "desktop") {
                    listOf(GOOGLE_DESKTOP_CLIENT_ID to GOOGLE_DESKTOP_CLIENT_SECRET, GOOGLE_MOBILE_CLIENT_ID to null)
                } else {
                    listOf(GOOGLE_MOBILE_CLIENT_ID to null, GOOGLE_DESKTOP_CLIENT_ID to GOOGLE_DESKTOP_CLIENT_SECRET)
                }
                for ((cid, secret) in attempts) {
                    val builder = FormBody.Builder()
                        .add("client_id", cid)
                        .add("grant_type", "refresh_token")
                        .add("refresh_token", account.refreshToken)
                    if (secret != null) builder.add("client_secret", secret)

                    val obj = runCatching { postFormJson("https://oauth2.googleapis.com/token", builder.build()) }.getOrNull()
                    val newAccess = obj?.get("access_token")?.jsonPrimitive?.content.orEmpty()
                    if (newAccess.isNotBlank()) {
                        val expiresIn = obj?.get("expires_in")?.jsonPrimitive?.content?.toLongOrNull() ?: 3600L
                        val updated = account.copy(
                            accessToken = newAccess,
                            expiresAtMillis = System.currentTimeMillis() + expiresIn * 1000L
                        )
                        updateCachedToken(updated)
                        return updated
                    }
                }
                throw ExternalTasksAuthException("Google session expired. Please sign in again.", needsReauth = true)
            }
        }
    }

    private fun updateCachedToken(updated: ExternalTaskAccount) {
        _accounts.value = _accounts.value.map { if (it.id == updated.id) updated else it }
        if (!updated.fromCalendarSync) {
            persistLocalAccounts(_accounts.value.filter { !it.fromCalendarSync })
        }
    }

    suspend fun fetchTaskLists(account: ExternalTaskAccount): List<ExternalTaskList> = withContext(Dispatchers.IO) {
        val valid = ensureValidAccessToken(account)
        when (valid.provider) {
            ExternalTaskProvider.MicrosoftToDo -> {
                val obj = getJsonWithRefresh("https://graph.microsoft.com/v1.0/me/todo/lists", valid)
                val values = obj["value"]?.jsonArray ?: return@withContext emptyList()
                values.mapNotNull { el ->
                    val row = el.jsonObject
                    val id = row["id"]?.jsonPrimitive?.content ?: return@mapNotNull null
                    val name = row["displayName"]?.jsonPrimitive?.content ?: return@mapNotNull null
                    val wellKnown = row["wellknownListName"]?.jsonPrimitive?.content.orEmpty()
                    ExternalTaskList(id = id, title = name, isDefault = wellKnown.equals("defaultList", ignoreCase = true))
                }
            }

            ExternalTaskProvider.GoogleTasks -> {
                val obj = getJsonWithRefresh("https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100", valid)
                val items = obj["items"]?.jsonArray ?: return@withContext emptyList()
                items.mapIndexedNotNull { idx, el ->
                    val row = el.jsonObject
                    val id = row["id"]?.jsonPrimitive?.content ?: return@mapIndexedNotNull null
                    val title = row["title"]?.jsonPrimitive?.content ?: return@mapIndexedNotNull null
                    ExternalTaskList(id = id, title = title, isDefault = idx == 0)
                }
            }
        }
    }

    suspend fun fetchTasks(account: ExternalTaskAccount, listId: String): List<ExternalTaskItem> = withContext(Dispatchers.IO) {
        val valid = ensureValidAccessToken(account)
        val encodedId = URLEncoder.encode(listId, "UTF-8").replace("+", "%20")
        when (valid.provider) {
            ExternalTaskProvider.MicrosoftToDo -> {
                val obj = getJsonWithRefresh("https://graph.microsoft.com/v1.0/me/todo/lists/$encodedId/tasks?\$top=100", valid)
                val values = obj["value"]?.jsonArray ?: return@withContext emptyList()
                values.mapNotNull { el ->
                    val row = el.jsonObject
                    val status = row["status"]?.jsonPrimitive?.content.orEmpty()
                    if (status.equals("completed", ignoreCase = true)) return@mapNotNull null
                    val id = row["id"]?.jsonPrimitive?.content ?: return@mapNotNull null
                    val title = row["title"]?.jsonPrimitive?.content?.trim().orEmpty()
                    if (title.isEmpty()) return@mapNotNull null

                    val bodyObj = row["body"]?.jsonObject
                    val rawBody = bodyObj?.get("content")?.jsonPrimitive?.content.orEmpty()
                    val contentType = bodyObj?.get("contentType")?.jsonPrimitive?.content.orEmpty()
                    val notes = if (contentType.equals("html", ignoreCase = true)) stripHtml(rawBody) else rawBody.trim()
                    val importance = row["importance"]?.jsonPrimitive?.content.orEmpty()

                    ExternalTaskItem(
                        id = id,
                        title = title,
                        notes = notes.ifEmpty { null },
                        isHighImportance = importance.equals("high", ignoreCase = true)
                    )
                }
            }

            ExternalTaskProvider.GoogleTasks -> {
                val obj = getJsonWithRefresh(
                    "https://tasks.googleapis.com/tasks/v1/lists/$encodedId/tasks?showCompleted=false&showHidden=false&maxResults=100",
                    valid
                )
                val items = obj["items"]?.jsonArray ?: return@withContext emptyList()
                items.mapNotNull { el ->
                    val row = el.jsonObject
                    val status = row["status"]?.jsonPrimitive?.content.orEmpty()
                    if (status.equals("completed", ignoreCase = true)) return@mapNotNull null
                    val id = row["id"]?.jsonPrimitive?.content ?: return@mapNotNull null
                    val title = row["title"]?.jsonPrimitive?.content?.trim().orEmpty()
                    if (title.isEmpty()) return@mapNotNull null
                    val notes = row["notes"]?.jsonPrimitive?.content?.trim()?.ifEmpty { null }
                    ExternalTaskItem(id = id, title = title, notes = notes, isHighImportance = false)
                }
            }
        }
    }

    private suspend fun getJsonWithRefresh(url: String, account: ExternalTaskAccount): kotlinx.serialization.json.JsonObject {
        val req = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer ${account.accessToken}")
            .get()
            .build()
        val (code, body) = executeRequest(req)
        if (code == 401) {
            val refreshed = ensureValidAccessToken(account.copy(expiresAtMillis = 0L))
            val retryReq = Request.Builder()
                .url(url)
                .header("Authorization", "Bearer ${refreshed.accessToken}")
                .get()
                .build()
            val (retryCode, retryBody) = executeRequest(retryReq)
            if (retryCode == 403) {
                throw ExternalTasksAuthException("${account.provider.displayName} requires Tasks read permission. Please sign in to grant access.", needsReauth = true)
            }
            if (retryCode == 401) {
                throw ExternalTasksAuthException("${account.provider.displayName} session expired. Please sign in again.", needsReauth = true)
            }
            if (retryCode !in 200..299) {
                throw ExternalTasksAuthException("Request failed (HTTP $retryCode): $retryBody")
            }
            return json.parseToJsonElement(retryBody).jsonObject
        }
        if (code == 403) {
            throw ExternalTasksAuthException("${account.provider.displayName} requires Tasks read permission. Please sign in to grant access.", needsReauth = true)
        }
        if (code !in 200..299) {
            throw ExternalTasksAuthException("Request failed (HTTP $code): $body")
        }
        return json.parseToJsonElement(body).jsonObject
    }

    private suspend fun getJson(url: String, accessToken: String): kotlinx.serialization.json.JsonObject {
        val req = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $accessToken")
            .get()
            .build()
        val (code, body) = executeRequest(req)
        if (code !in 200..299) throw ExternalTasksAuthException("HTTP $code: $body")
        return json.parseToJsonElement(body).jsonObject
    }

    private suspend fun postFormJson(url: String, formBody: FormBody): kotlinx.serialization.json.JsonObject {
        val req = Request.Builder().url(url).post(formBody).build()
        val (code, body) = executeRequest(req)
        if (code !in 200..299) throw ExternalTasksAuthException("HTTP $code: $body")
        return json.parseToJsonElement(body).jsonObject
    }

    private suspend fun executeRequest(request: Request): Pair<Int, String> = withContext(Dispatchers.IO) {
        SupabaseClientManager.okHttpClient.newCall(request).execute().use { resp ->
            resp.code to (resp.body?.string().orEmpty())
        }
    }

    // MARK: - AES-GCM Crypto (Compatible with EncryptionHelper.cs)

    private fun deriveKey(keyScope: String): SecretKeySpec? {
        return runCatching {
            val spec = PBEKeySpec(keyScope.toCharArray(), staticSalt, 1000, 256)
            val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            SecretKeySpec(factory.generateSecret(spec).encoded, "AES")
        }.getOrNull()
    }

    private fun encryptToken(plainText: String, keyScope: String): String {
        if (plainText.isEmpty() || keyScope.isEmpty()) return plainText
        return runCatching {
            val key = deriveKey(keyScope) ?: return plainText
            val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
            val cipherWithTag = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
            val tagStart = cipherWithTag.size - 16
            val ciphertext = cipherWithTag.copyOfRange(0, tagStart)
            val tag = cipherWithTag.copyOfRange(tagStart, cipherWithTag.size)

            val combined = ByteArray(12 + 16 + ciphertext.size)
            System.arraycopy(nonce, 0, combined, 0, 12)
            System.arraycopy(tag, 0, combined, 12, 16)
            System.arraycopy(ciphertext, 0, combined, 28, ciphertext.size)
            Base64.encodeToString(combined, Base64.NO_WRAP)
        }.getOrDefault(plainText)
    }

    private fun decryptToken(cipherText: String, keyScope: String): String {
        if (cipherText.isEmpty() || keyScope.isEmpty()) return cipherText
        var current = cipherText
        repeat(2) {
            var didDecrypt = false
            for (scopeCandidate in listOf(keyScope.lowercase(), keyScope, keyScope.uppercase())) {
                val plain = decryptSingleLayer(current, scopeCandidate)
                if (plain != null) {
                    current = plain
                    didDecrypt = true
                    break
                }
            }
            if (!didDecrypt) return current
        }
        return current
    }

    private fun decryptSingleLayer(cipherBase64: String, keyScope: String): String? {
        return runCatching {
            val raw = Base64.decode(cipherBase64, Base64.DEFAULT)
            if (raw.size < 28) return null
            val key = deriveKey(keyScope) ?: return null
            val nonce = raw.copyOfRange(0, 12)
            val tag = raw.copyOfRange(12, 28)
            val ciphertext = raw.copyOfRange(28, raw.size)

            // Java AES/GCM expects ciphertext || tag
            val payload = ByteArray(ciphertext.size + 16)
            System.arraycopy(ciphertext, 0, payload, 0, ciphertext.size)
            System.arraycopy(tag, 0, payload, ciphertext.size, 16)

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
            String(cipher.doFinal(payload), Charsets.UTF_8)
        }.getOrNull()
    }

    private fun generateCodeVerifier(): String {
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun generateCodeChallenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun stripHtml(html: String): String {
        val stripped = html
            .replace(Regex("<head[^>]*>.*?</head>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)), "")
            .replace(Regex("<style[^>]*>.*?</style>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)), "")
            .replace(Regex("<br\\s*/?>|</(p|div|li|h[1-6]|tr)>", RegexOption.IGNORE_CASE), "\n")
            .replace(Regex("<[^>]+>"), " ")
            .replace("&nbsp;", " ")
            .replace("&#160;", " ")
            .replace("\u00A0", " ")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&apos;", "'")

        return stripped
            .lines()
            .map { it.replace(Regex("[ \\t]+"), " ").trim() }
            .filter { it.isNotEmpty() }
            .joinToString("\n")
            .trim()
    }

    private fun parseIsoMillis(iso: String?): Long {
        if (iso.isNullOrBlank()) return 0L
        return runCatching { java.time.Instant.parse(iso).toEpochMilli() }.getOrDefault(0L)
    }
}
