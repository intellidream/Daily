package com.intellidream.daily.network

import android.content.Context
import com.intellidream.daily.model.SupabaseAdminCredentials
import com.intellidream.daily.model.SupabaseAdminSnapshot
import com.intellidream.daily.model.SupabaseAdvisorLint
import com.intellidream.daily.model.SupabaseApiCountPoint
import com.intellidream.daily.model.SupabaseCronJobRun
import com.intellidream.daily.model.SupabaseDailyEgressPoint
import com.intellidream.daily.model.SupabaseEdgeFunctionStat
import com.intellidream.daily.model.SupabaseFleetDeviceStat
import com.intellidream.daily.model.SupabaseGatewayErrorItem
import com.intellidream.daily.model.SupabaseProjectSummary
import com.intellidream.daily.model.SupabaseServiceHealthItem
import com.intellidream.daily.model.SupabaseSqlStatementStat
import com.intellidream.daily.model.SupabaseTableStat
import com.intellidream.daily.model.SupabaseTopRouteStat
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.math.BigInteger
import java.net.URI
import java.net.URLEncoder
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

// MARK: - Ephemeral P-256 ECDH + AES-256-GCM Handshake (Pure JCA)

class SupabaseCliLoginHandshake(platformLabel: String = "Android") {
    val sessionId: String = UUID.randomUUID().toString().lowercase(Locale.US)
    val tokenName: String
    val publicKeyHex: String
    val loginUrl: String
    private val privateKey: PrivateKey

    init {
        val safePlatform = platformLabel.replace(Regex("[^A-Za-z0-9_]"), "_")
        val ts = System.currentTimeMillis() / 1000L
        tokenName = "DayOne_Admin_${safePlatform}_$ts"

        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"), SecureRandom())
        val kp = kpg.generateKeyPair()
        privateKey = kp.private
        val ecPub = kp.public as ECPublicKey
        publicKeyHex = SupabaseAdminCrypto.encodeUncompressedPointHex(ecPub)

        val encSession = URLEncoder.encode(sessionId, "UTF-8")
        val encName = URLEncoder.encode(tokenName, "UTF-8")
        val encPub = URLEncoder.encode(publicKeyHex, "UTF-8")
        loginUrl = "https://supabase.com/dashboard/cli/login?session_id=$encSession&token_name=$encName&public_key=$encPub"
    }

    fun decryptToken(encryptedHex: String, serverPublicKeyHex: String, nonceHex: String): String {
        return SupabaseAdminCrypto.decryptCliToken(
            clientPrivateKey = privateKey as ECPrivateKey,
            encryptedTokenHex = encryptedHex,
            serverPublicKeyHex = serverPublicKeyHex,
            nonceHex = nonceHex
        )
    }
}

object SupabaseAdminCrypto {

    fun encodeUncompressedPointHex(pubKey: ECPublicKey): String {
        val x = bigIntToFixed32Bytes(pubKey.w.affineX)
        val y = bigIntToFixed32Bytes(pubKey.w.affineY)
        val out = ByteArray(65)
        out[0] = 0x04
        System.arraycopy(x, 0, out, 1, 32)
        System.arraycopy(y, 0, out, 33, 32)
        return hexEncode(out)
    }

    fun decryptCliToken(
        clientPrivateKey: ECPrivateKey,
        encryptedTokenHex: String,
        serverPublicKeyHex: String,
        nonceHex: String
    ): String {
        val serverPubBytes = hexDecode(serverPublicKeyHex)
        require(serverPubBytes.size == 65 && serverPubBytes[0] == 0x04.toByte()) {
            "Invalid uncompressed P-256 server public key."
        }
        val nonceBytes = hexDecode(nonceHex)
        val combinedBytes = hexDecode(encryptedTokenHex)
        require(combinedBytes.size > 16) { "Encrypted CLI token payload shorter than GCM tag." }

        val x = BigInteger(1, serverPubBytes.copyOfRange(1, 33))
        val y = BigInteger(1, serverPubBytes.copyOfRange(33, 65))
        val kf = KeyFactory.getInstance("EC")
        val serverPub = kf.generatePublic(ECPublicKeySpec(ECPoint(x, y), clientPrivateKey.params))

        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(clientPrivateKey)
        ka.doPhase(serverPub, true)
        val rawSecret = padSecretTo32(ka.generateSecret())

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(rawSecret, "AES"), GCMParameterSpec(128, nonceBytes))
        val plaintext = cipher.doFinal(combinedBytes)
        val token = String(plaintext, Charsets.UTF_8).trim()
        require(token.isNotEmpty()) { "Decrypted Supabase Management token is empty." }
        return token
    }

    fun encryptCliTokenForTesting(
        plaintextToken: String,
        clientPublicKeyHex: String
    ): Triple<String, String, String> {
        val clientPubBytes = hexDecode(clientPublicKeyHex)
        val x = BigInteger(1, clientPubBytes.copyOfRange(1, 33))
        val y = BigInteger(1, clientPubBytes.copyOfRange(33, 65))

        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"), SecureRandom())
        val serverKp = kpg.generateKeyPair()
        val serverPriv = serverKp.private as ECPrivateKey
        val serverPub = serverKp.public as ECPublicKey

        val kf = KeyFactory.getInstance("EC")
        val clientPub = kf.generatePublic(ECPublicKeySpec(ECPoint(x, y), serverPriv.params))

        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(serverPriv)
        ka.doPhase(clientPub, true)
        val rawSecret = padSecretTo32(ka.generateSecret())

        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(rawSecret, "AES"), GCMParameterSpec(128, nonce))
        val combined = cipher.doFinal(plaintextToken.toByteArray(Charsets.UTF_8))

        return Triple(
            hexEncode(combined),
            encodeUncompressedPointHex(serverPub),
            hexEncode(nonce)
        )
    }

    fun extractDeviceCode(urlString: String): String? {
        return try {
            val uri = URI(urlString)
            val host = uri.host?.lowercase(Locale.US) ?: return null
            if (!host.contains("supabase.com") || !(uri.path ?: "").contains("/cli/login")) return null
            val query = uri.rawQuery ?: return null
            query.split("&")
                .map { it.split("=", limit = 2) }
                .firstOrNull { it.size == 2 && it[0] == "device_code" }
                ?.get(1)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    fun shouldRecoverCliLoginRedirect(currentUrl: String): Boolean {
        return try {
            val uri = URI(currentUrl)
            val host = uri.host?.lowercase(Locale.US) ?: return false
            if (host != "supabase.com" && host != "app.supabase.com") return false
            val path = (uri.path ?: "").lowercase(Locale.US)
            if (path.contains("/cli/login") || path.contains("/sign-in") || path.contains("/authorize") || path.contains("/auth")) {
                return false
            }
            path == "/dashboard" ||
                path.startsWith("/dashboard/org") ||
                path.startsWith("/dashboard/project") ||
                path.startsWith("/dashboard/account")
        } catch (_: Exception) {
            false
        }
    }

    data class DashboardSessionTokens(
        val accessToken: String?,
        val refreshToken: String?,
        val identity: String?
    )

    fun parseDashboardSessionJson(rawJson: String?, jsonParser: Json = Json { ignoreUnknownKeys = true }): DashboardSessionTokens {
        if (rawJson.isNullOrBlank()) return DashboardSessionTokens(null, null, null)
        return try {
            val root = jsonParser.parseToJsonElement(rawJson).jsonObject
            val sessionObj = (root["currentSession"] as? JsonObject) ?: root
            val access = sessionObj["access_token"]?.jsonPrimitive?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }
            val refresh = sessionObj["refresh_token"]?.jsonPrimitive?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }
            var identity: String? = null
            val userObj = sessionObj["user"] as? JsonObject
            val metaObj = userObj?.get("user_metadata") as? JsonObject
            val ghUser = metaObj?.get("user_name")?.jsonPrimitive?.contentOrNull
                ?: metaObj?.get("preferred_username")?.jsonPrimitive?.contentOrNull
            if (!ghUser.isNullOrBlank()) {
                identity = "@$ghUser"
            } else {
                val email = userObj?.get("email")?.jsonPrimitive?.contentOrNull
                if (!email.isNullOrBlank()) identity = email
            }
            DashboardSessionTokens(access, refresh, identity)
        } catch (_: Exception) {
            DashboardSessionTokens(null, null, null)
        }
    }

    fun classifyFleetUserAgent(userAgent: String): Pair<String, String> {
        val ua = userAgent.lowercase(Locale.US)
        return when {
            ua.contains("watchos") || (ua.contains("watch") && ua.contains("cfnetwork")) ->
                "watchos" to "Apple Watch (watchOS)"
            ua.contains("macos") || ua.contains("macintosh") ->
                if (ua.contains("iphone") || ua.contains("ios")) "ios" to "iPhone · Schmitz (iOS)"
                else "macos" to "Mac · DayOne Desktop (macOS)"
            ua.contains("iphone") || ua.contains("ipad") || ua.contains("cfnetwork") || ua.contains("supabase-swift") ->
                "ios" to "Apple · iOS / Swift SDK"
            ua.contains("ktor") || ua.contains("okhttp") || ua.contains("dalvik") || ua.contains("android") ->
                if (ua.contains("wear")) "wearos" to "Pixel Watch (Wear OS)"
                else "android" to "Android · Radar / Trapper (Kotlin)"
            ua.contains("windows") || ua.contains("winui") || ua.contains(".net") ->
                "windows" to "Windows 11 · DayOne WinUI"
            ua.contains("pg_net") || ua.contains("deno") || ua.contains("edge-runtime") ->
                "cloud_cron" to "Supabase Cron & Edge Workers"
            else -> "other" to "Web & External Clients"
        }
    }

    fun hexEncode(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    fun hexDecode(hex: String): ByteArray {
        val clean = hex.trim()
        require(clean.isNotEmpty() && clean.length % 2 == 0) { "Invalid hex string length" }
        return ByteArray(clean.length / 2) { i ->
            clean.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }

    private fun bigIntToFixed32Bytes(bi: BigInteger): ByteArray {
        val raw = bi.toByteArray()
        return when {
            raw.size == 32 -> raw
            raw.size > 32 -> raw.copyOfRange(raw.size - 32, raw.size)
            else -> ByteArray(32).also { System.arraycopy(raw, 0, it, 32 - raw.size, raw.size) }
        }
    }

    private fun padSecretTo32(secret: ByteArray): ByteArray {
        return when {
            secret.size == 32 -> secret
            secret.size > 32 -> secret.copyOfRange(secret.size - 32, secret.size)
            else -> ByteArray(32).also { System.arraycopy(secret, 0, it, 32 - secret.size, secret.size) }
        }
    }
}

// MARK: - Strictly Read-Only Supabase Admin Repository

class SupabaseAdminRepository private constructor() {

    companion object {
        val shared = SupabaseAdminRepository()
        const val DEFAULT_PROJECT_REF = "akkfouifxztnfwwiclwg"
        private const val PREFS_NAME = "daily_supabase_admin_local_only"
        private const val KEY_CREDENTIALS = "admin_credentials_v1"
        private const val KEY_SNAPSHOT_PREFIX = "admin_snapshot_v1_"
        private const val CACHE_TTL_MS = 10L * 60L * 1000L // 10 minutes
    }

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val httpClient = HttpClient(CIO) {
        install(HttpTimeout) {
            requestTimeoutMillis = 18_000L
            connectTimeoutMillis = 12_000L
            socketTimeoutMillis = 18_000L
        }
    }

    private var appContext: Context? = null

    private val _credentials = MutableStateFlow(SupabaseAdminCredentials())
    val credentials: StateFlow<SupabaseAdminCredentials> = _credentials.asStateFlow()

    private val _snapshot = MutableStateFlow<SupabaseAdminSnapshot?>(null)
    val snapshot: StateFlow<SupabaseAdminSnapshot?> = _snapshot.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isAuthenticating = MutableStateFlow(false)
    val isAuthenticating: StateFlow<Boolean> = _isAuthenticating.asStateFlow()

    private val _isAnalyzingAi = MutableStateFlow(false)
    val isAnalyzingAi: StateFlow<Boolean> = _isAnalyzingAi.asStateFlow()

    private val _aiAnalysis = MutableStateFlow<String?>(null)
    val aiAnalysis: StateFlow<String?> = _aiAnalysis.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    fun initializeIfNeeded(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.getString(KEY_CREDENTIALS, null)?.let { raw ->
            runCatching { json.decodeFromString<SupabaseAdminCredentials>(raw) }.getOrNull()?.let { creds ->
                _credentials.value = creds
                if (creds.hasValidToken) {
                    loadCachedSnapshot(creds.selectedProjectRef)?.let { _snapshot.value = it }
                }
            }
        }
    }

    private fun saveCredentials(creds: SupabaseAdminCredentials) {
        _credentials.value = creds
        val ctx = appContext ?: return
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CREDENTIALS, json.encodeToString(creds))
            .apply()
    }

    private fun loadCachedSnapshot(projectRef: String): SupabaseAdminSnapshot? {
        val ctx = appContext ?: return null
        val raw = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_SNAPSHOT_PREFIX + projectRef, null) ?: return null
        return runCatching { json.decodeFromString<SupabaseAdminSnapshot>(raw) }.getOrNull()
    }

    private fun saveCachedSnapshot(snap: SupabaseAdminSnapshot) {
        _snapshot.value = snap
        val ctx = appContext ?: return
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SNAPSHOT_PREFIX + snap.project.ref, json.encodeToString(snap))
            .apply()
    }

    fun clearError() {
        _errorMessage.value = null
    }

    fun disconnect() {
        val ctx = appContext
        ctx?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)?.edit()?.clear()?.apply()
        _credentials.value = SupabaseAdminCredentials()
        _snapshot.value = null
        _aiAnalysis.value = null
        _errorMessage.value = null
    }

    suspend fun completeCliHandshake(
        handshake: SupabaseCliLoginHandshake,
        deviceCode: String,
        dashboardSessionJson: String?
    ) = withContext(Dispatchers.IO) {
        _isAuthenticating.value = true
        _errorMessage.value = null
        try {
            var decryptedMgmt: String? = null
            var lastErr: Throwable? = null
            val pollUrl = "https://api.supabase.com/platform/cli/login/${handshake.sessionId}"

            for (attempt in 1..3) {
                try {
                    val resp = httpClient.get(pollUrl) {
                        parameter("device_code", deviceCode)
                        header(HttpHeaders.Accept, "application/json")
                    }
                    if (resp.status.isSuccess()) {
                        val obj = json.parseToJsonElement(resp.bodyAsText()).jsonObject
                        val encToken = obj.str("access_token")
                        val pubKey = obj.str("public_key")
                        val nonce = obj.str("nonce")
                        if (!encToken.isNullOrBlank() && !pubKey.isNullOrBlank() && !nonce.isNullOrBlank()) {
                            decryptedMgmt = handshake.decryptToken(encToken, pubKey, nonce)
                            break
                        }
                    }
                } catch (t: Throwable) {
                    lastErr = t
                }
                if (attempt < 3) delay(650L)
            }

            val parsedDash = SupabaseAdminCrypto.parseDashboardSessionJson(dashboardSessionJson, json)
            val bearer = decryptedMgmt ?: parsedDash.accessToken
                ?: throw (lastErr ?: IllegalStateException("Could not obtain Supabase Admin token from GitHub session."))

            val (projects, identity) = verifyBearerAndFetchProjects(bearer, parsedDash.identity)
            val preferred = projects.firstOrNull { it.ref == DEFAULT_PROJECT_REF } ?: projects.firstOrNull()
            val newCreds = SupabaseAdminCredentials(
                managementAccessToken = decryptedMgmt,
                dashboardAccessToken = parsedDash.accessToken,
                dashboardRefreshToken = parsedDash.refreshToken,
                adminIdentity = identity,
                selectedProjectRef = preferred?.ref ?: DEFAULT_PROJECT_REF,
                selectedOrgSlug = preferred?.organizationSlug
            )
            saveCredentials(newCreds)
            refreshSnapshot(force = true)
        } catch (t: Throwable) {
            _errorMessage.value = t.message ?: "Authentication failed."
            throw t
        } finally {
            _isAuthenticating.value = false
        }
    }

    suspend fun connectWithPersonalAccessToken(rawPat: String) = withContext(Dispatchers.IO) {
        val trimmed = rawPat.trim()
        require(trimmed.isNotEmpty()) { "Please enter a valid Personal Access Token (sbp_...)." }
        _isAuthenticating.value = true
        _errorMessage.value = null
        try {
            val (projects, identity) = verifyBearerAndFetchProjects(trimmed, null)
            val preferred = projects.firstOrNull { it.ref == DEFAULT_PROJECT_REF } ?: projects.firstOrNull()
            val newCreds = SupabaseAdminCredentials(
                managementAccessToken = trimmed,
                adminIdentity = identity ?: "PAT Admin",
                selectedProjectRef = preferred?.ref ?: DEFAULT_PROJECT_REF,
                selectedOrgSlug = preferred?.organizationSlug
            )
            saveCredentials(newCreds)
            refreshSnapshot(force = true)
        } catch (t: Throwable) {
            _errorMessage.value = t.message ?: "Invalid Personal Access Token."
            throw t
        } finally {
            _isAuthenticating.value = false
        }
    }

    suspend fun selectProject(ref: String) {
        val current = _credentials.value
        if (current.selectedProjectRef == ref) return
        val org = _snapshot.value?.availableProjects?.firstOrNull { it.ref == ref }?.organizationSlug ?: current.selectedOrgSlug
        saveCredentials(current.copy(selectedProjectRef = ref, selectedOrgSlug = org))
        _aiAnalysis.value = null
        val cached = loadCachedSnapshot(ref)
        if (cached != null && System.currentTimeMillis() - cached.fetchedAtEpochMs < CACHE_TTL_MS) {
            _snapshot.value = cached
            return
        }
        refreshSnapshot(force = true)
    }

    suspend fun ensureLoadedOnAppear() {
        val creds = _credentials.value
        if (!creds.hasValidToken) return
        val cur = _snapshot.value
        if (cur != null && cur.project.ref == creds.selectedProjectRef &&
            System.currentTimeMillis() - cur.fetchedAtEpochMs < CACHE_TTL_MS
        ) {
            return
        }
        val cached = loadCachedSnapshot(creds.selectedProjectRef)
        if (cached != null) {
            _snapshot.value = cached
            if (System.currentTimeMillis() - cached.fetchedAtEpochMs < CACHE_TTL_MS) return
        }
        refreshSnapshot(force = false)
    }

    suspend fun refreshSnapshot(force: Boolean = true) = withContext(Dispatchers.IO) {
        val creds = _credentials.value
        val mgmtBearer = creds.primaryManagementBearer ?: return@withContext
        val existing = _snapshot.value
        if (!force && existing != null && System.currentTimeMillis() - existing.fetchedAtEpochMs < CACHE_TTL_MS) {
            return@withContext
        }

        _isLoading.value = true
        _errorMessage.value = null
        try {
            val projects = fetchProjectsList(mgmtBearer)
            val activeProject = projects.firstOrNull { it.ref == creds.selectedProjectRef }
                ?: projects.firstOrNull()
                ?: SupabaseProjectSummary(
                    ref = creds.selectedProjectRef,
                    name = "Daily",
                    organizationSlug = creds.selectedOrgSlug ?: "",
                    region = "eu-central-1",
                    status = "ACTIVE_HEALTHY"
                )
            val ref = activeProject.ref
            val orgSlug = activeProject.organizationSlug.ifEmpty { creds.selectedOrgSlug ?: "" }
            val platformBearer = creds.primaryPlatformBearer ?: mgmtBearer
            val hasDash = !creds.dashboardAccessToken.isNullOrBlank()

            coroutineScope {
                val orgDef = async { fetchOrgDetails(mgmtBearer, orgSlug) }
                val tierDef = async { fetchComputeTier(mgmtBearer, ref) }
                val healthDef = async { fetchServicesHealth(mgmtBearer, ref) }
                val diskDef = async { fetchDiskInfo(mgmtBearer, ref) }
                val apiDef = async { fetchApiCounts(mgmtBearer, ref) }
                val fnDef = async { fetchEdgeFunctions(mgmtBearer, ref) }
                val advDef = async { fetchAdvisors(mgmtBearer, ref) }
                val logsDef = async { fetchClickHouseLogs(mgmtBearer, ref) }
                val pgDef = async { fetchPostgresCatalog(mgmtBearer, ref) }
                val billDef = async { fetchPlatformUsage(platformBearer, orgSlug, ref, hasDash) }

                val (orgName, orgPlan) = orgDef.await()
                val computeTier = tierDef.await()
                val health = healthDef.await()
                val disk = diskDef.await()
                val apiCounts = apiDef.await()
                val edgeFns = fnDef.await()
                val (perfLints, secLints) = advDef.await()
                val logs = logsDef.await()
                val pg = pgDef.await()
                val bill = billDef.await()

                val isPro = orgPlan.lowercase(Locale.US) in setOf("pro", "team", "enterprise")
                val defEgressQuota = if (isPro) 268_435_456_000L else 5_368_709_120L
                val defDbQuota = if (isPro) 8_589_934_592L else 524_288_000L
                val defStorageQuota = if (isPro) 107_374_182_400L else 1_073_741_824L

                val resolvedEgress = if (bill.isExact) bill.egressUsed else logs.totalEdgeBytes
                val resolvedDb = maxOf(bill.dbSize, pg.dbSizeBytes)

                val snap = SupabaseAdminSnapshot(
                    fetchedAtEpochMs = System.currentTimeMillis(),
                    project = activeProject,
                    availableProjects = projects,
                    orgName = orgName,
                    orgPlan = orgPlan,
                    computeTier = computeTier,
                    serviceHealth = health,
                    resourceWarnings = bill.warnings,
                    isExactBillingUsageAvailable = bill.isExact,
                    egressUsedBytes = resolvedEgress,
                    egressQuotaBytes = if (bill.egressQuota > 0L) bill.egressQuota else defEgressQuota,
                    cachedEgressUsedBytes = bill.cachedEgress,
                    dbSizeBytes = resolvedDb,
                    dbQuotaBytes = if (bill.dbQuota > 0L) bill.dbQuota else defDbQuota,
                    storageSizeBytes = maxOf(bill.storageSize, pg.storageBytes),
                    storageQuotaBytes = if (bill.storageQuota > 0L) bill.storageQuota else defStorageQuota,
                    functionInvocations = if (bill.fnCalls > 0L) bill.fnCalls else edgeFns.sumOf { it.invocations24h }.toLong(),
                    functionInvocationsQuota = if (bill.fnQuota > 0L) bill.fnQuota else if (isPro) 2_000_000L else 500_000L,
                    realtimeMessages = bill.rtMessages,
                    realtimeMessagesQuota = if (bill.rtMsgQuota > 0L) bill.rtMsgQuota else 2_000_000L,
                    realtimePeakConnections = maxOf(bill.rtPeak, pg.rtActiveSubs.toLong()),
                    realtimePeakConnectionsQuota = if (bill.rtPeakQuota > 0L) bill.rtPeakQuota else 200L,
                    mauCount = if (bill.mau > 0L) bill.mau else pg.usersCount,
                    mauQuota = if (bill.mauQuota > 0L) bill.mauQuota else 50_000L,
                    logIngestionEvents = if (bill.logEvents > 0L) bill.logEvents else logs.sourceCounts.values.sum().toLong(),
                    dailyEgress = bill.dailyEgress,
                    apiCounts24h = apiCounts,
                    logCountsBySource = logs.sourceCounts,
                    http2xxCount24h = logs.ok2xx,
                    http4xxCount24h = logs.err4xx,
                    http5xxCount24h = logs.err5xx,
                    topRoutes24h = logs.topRoutes,
                    recentErrors24h = logs.recentErrors,
                    diskUsedBytes = if (disk.first > 0L) disk.first else resolvedDb,
                    diskTotalBytes = disk.second,
                    diskIops = disk.third,
                    heapDataBytes = pg.heapBytes,
                    indexTotalBytes = pg.indexBytes,
                    activeDbConnections = pg.activeConns,
                    cacheHitRatioPercent = pg.cacheHit,
                    tables = pg.tables,
                    topSqlStatements = pg.topSql,
                    cronJobs = pg.cronJobs,
                    edgeFunctions = edgeFns,
                    realtimeActiveSubscriptions = pg.rtActiveSubs,
                    realtimeSubscriptionsByTable = pg.rtByTable,
                    realtimeWalListChangesCalls = pg.rtListCalls,
                    realtimeWalCpuSharePercent = pg.rtCpuPct,
                    totalUsersCount = pg.usersCount,
                    activeAuthSessionsCount = pg.sessionsCount,
                    refreshTokenWritesCumulative = pg.refreshTokenWrites,
                    pairedWatchesCount = pg.watchesCount,
                    fleetDevices = logs.fleetDevices,
                    performanceLints = perfLints,
                    securityLints = secLints
                )
                saveCachedSnapshot(snap)
            }
        } catch (t: Throwable) {
            _errorMessage.value = t.message ?: "Failed to load Supabase telemetry."
        } finally {
            _isLoading.value = false
        }
    }

    suspend fun analyzeWithAi(geminiApiKey: String?) = withContext(Dispatchers.IO) {
        val snap = _snapshot.value ?: return@withContext
        _isAnalyzingAi.value = true
        try {
            val key = geminiApiKey?.trim().orEmpty()
            if (key.isNotEmpty()) {
                val prompt = """
                    You are a Staff PostgreSQL & Supabase SRE auditing DayOne (${snap.project.name}, plan ${snap.orgPlan.uppercase()}).
                    Summarize in 4 crisp Markdown bullet points (< 180 words):
                    1. Egress & Gateway efficiency.
                    2. PostgreSQL table storage & index bloat health.
                    3. Realtime WAL / Edge Functions / pg_cron status.
                    4. Next non-destructive optimizations.

                    REPORT:
                    ${snap.toMarkdownReport().take(7000)}
                """.trimIndent()
                val reqJson = buildJsonObject {
                    put("contents", JsonArray(listOf(buildJsonObject {
                        put("role", "user")
                        put("parts", JsonArray(listOf(buildJsonObject { put("text", prompt) })))
                    })))
                }
                val resp = runCatching {
                    httpClient.post("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$key") {
                        contentType(ContentType.Application.Json)
                        setBody(reqJson.toString())
                    }
                }.getOrNull()
                if (resp != null && resp.status.isSuccess()) {
                    val root = json.parseToJsonElement(resp.bodyAsText()).jsonObject
                    val text = root["candidates"]?.jsonArray?.firstOrNull()?.jsonObject
                        ?.get("content")?.jsonObject
                        ?.get("parts")?.jsonArray?.firstOrNull()?.jsonObject
                        ?.str("text")
                    if (!text.isNullOrBlank()) {
                        _aiAnalysis.value = text.trim()
                        return@withContext
                    }
                }
            }
            _aiAnalysis.value = buildDeterministicSummary(snap)
        } finally {
            _isAnalyzingAi.value = false
        }
    }

    fun buildDeterministicSummary(snap: SupabaseAdminSnapshot): String {
        val bullets = mutableListOf<String>()
        val egLabel = if (snap.isExactBillingUsageAvailable) "Cycle Egress" else "24h Gateway Egress"
        if (snap.egressQuotaPercent >= 85.0) {
            bullets += "• **Egress Watch (${String.format(Locale.US, "%.1f%%", snap.egressQuotaPercent)}):** $egLabel is ${SupabaseAdminSnapshot.formatBytes(snap.egressUsedBytes)} of ${SupabaseAdminSnapshot.formatBytes(snap.egressQuotaBytes)}. Keep incremental sync deltas active."
        } else {
            bullets += "• **Bandwidth Healthy (${String.format(Locale.US, "%.1f%%", snap.egressQuotaPercent)}):** $egLabel is ${SupabaseAdminSnapshot.formatBytes(snap.egressUsedBytes)} / ${SupabaseAdminSnapshot.formatBytes(snap.egressQuotaBytes)}."
        }
        val bloated = snap.tables.firstOrNull { it.hasIndexBloatWarning }
        if (bloated != null) {
            bullets += "• **Index Bloat Flag (`${bloated.schema}.${bloated.tableName}`):** Indexes use ${SupabaseAdminSnapshot.formatBytes(bloated.indexBytes)} vs ${SupabaseAdminSnapshot.formatBytes(bloated.dataBytes)} heap (${String.format(Locale.US, "%.1fx", bloated.bloatRatio)})."
        } else {
            bullets += "• **PostgreSQL Storage Nominal:** ${SupabaseAdminSnapshot.formatBytes(snap.dbSizeBytes)} total (${String.format(Locale.US, "%.2f%%", snap.cacheHitRatioPercent)} buffer cache hit)."
        }
        bullets += "• **Runtime & Realtime:** ${snap.http4xxCount24h} 4xx / ${snap.http5xxCount24h} 5xx over 24h; Realtime WAL CPU share ${String.format(Locale.US, "%.1f%%", snap.realtimeWalCpuSharePercent)} (${snap.realtimeActiveSubscriptions} subs)."
        bullets += "• **Advisors:** ${snap.securityLints.size} security and ${snap.performanceLints.size} performance lints detected."
        return bullets.joinToString("\n")
    }

    // MARK: - Internal API Helpers

    private suspend fun verifyBearerAndFetchProjects(
        bearer: String,
        fallbackIdentity: String?
    ): Pair<List<SupabaseProjectSummary>, String?> {
        val projects = fetchProjectsList(bearer)
        var identity = fallbackIdentity
        if (identity == null) {
            runCatching {
                val prof = getJsonObject("https://api.supabase.com/v1/profile", bearer)
                identity = prof?.str("primary_email") ?: prof?.str("username")?.let { "@$it" }
            }
        }
        return projects to identity
    }

    private suspend fun fetchProjectsList(bearer: String): List<SupabaseProjectSummary> {
        val resp = httpClient.get("https://api.supabase.com/v1/projects") {
            header(HttpHeaders.Authorization, "Bearer $bearer")
            header(HttpHeaders.Accept, "application/json")
        }
        if (!resp.status.isSuccess()) {
            throw IllegalStateException("Supabase Management API returned HTTP ${resp.status.value}.")
        }
        val arr = json.parseToJsonElement(resp.bodyAsText()).jsonArray
        return arr.mapNotNull { el ->
            val o = el as? JsonObject ?: return@mapNotNull null
            val ref = o.str("id") ?: o.str("ref") ?: return@mapNotNull null
            val pgVer = (o["database"] as? JsonObject)?.str("version") ?: "17"
            SupabaseProjectSummary(
                ref = ref,
                name = o.str("name") ?: ref,
                organizationSlug = o.str("organization_slug") ?: o.str("organization_id") ?: "",
                region = o.str("region") ?: "unknown",
                status = o.str("status") ?: "ACTIVE_HEALTHY",
                postgresVersion = pgVer,
                createdAt = o.str("created_at")
            )
        }
    }

    private suspend fun fetchOrgDetails(bearer: String, orgSlug: String): Pair<String, String> {
        if (orgSlug.isNotEmpty()) {
            getJsonObject("https://api.supabase.com/v1/organizations/$orgSlug", bearer)?.let { o ->
                return (o.str("name") ?: orgSlug) to (o.str("plan") ?: "free")
            }
        }
        val arr = getJsonArray("https://api.supabase.com/v1/organizations", bearer)
        val first = arr?.firstOrNull() as? JsonObject
        return (first?.str("name") ?: "DayOne Cloud") to (first?.str("plan") ?: "free")
    }

    private suspend fun fetchComputeTier(bearer: String, ref: String): String {
        val obj = getJsonObject("https://api.supabase.com/v1/projects/$ref/billing/addons", bearer) ?: return "Micro"
        val addons = obj["selected_addons"] as? JsonArray ?: return "Nano / Micro"
        for (item in addons) {
            val a = item as? JsonObject ?: continue
            if (a.str("type") == "compute_instance") {
                val name = (a["variant"] as? JsonObject)?.str("name")
                if (!name.isNullOrBlank()) return name
            }
        }
        return "Nano / Micro"
    }

    private suspend fun fetchServicesHealth(bearer: String, ref: String): List<SupabaseServiceHealthItem> {
        val arr = getJsonArray("https://api.supabase.com/v1/projects/$ref/health?services=auth,db,pooler,realtime,rest,storage", bearer)
            ?: return emptyList()
        val labels = mapOf(
            "db" to "PostgreSQL",
            "rest" to "PostgREST",
            "auth" to "GoTrue Auth",
            "realtime" to "Realtime",
            "storage" to "Storage",
            "pooler" to "Supavisor"
        )
        return arr.mapNotNull { el ->
            val o = el as? JsonObject ?: return@mapNotNull null
            val name = o.str("name") ?: return@mapNotNull null
            val status = o.str("status") ?: "ACTIVE_HEALTHY"
            val healthy = o["healthy"]?.jsonPrimitive?.booleanOrNull ?: status.contains("HEALTHY", ignoreCase = true)
            SupabaseServiceHealthItem(name, labels[name] ?: name, status, healthy)
        }
    }

    private suspend fun fetchDiskInfo(bearer: String, ref: String): Triple<Long, Long, Int> {
        var total = 8_589_934_592L
        var used = 0L
        var iops = 3000
        getJsonObject("https://api.supabase.com/v1/projects/$ref/config/disk", bearer)?.let { cfg ->
            val attrs = cfg["attributes"] as? JsonObject
            attrs?.long("size_gb")?.takeIf { it > 0 }?.let { total = it * 1_073_741_824L }
            attrs?.int("iops")?.takeIf { it > 0 }?.let { iops = it }
        }
        getJsonObject("https://api.supabase.com/v1/projects/$ref/config/disk/util", bearer)?.let { u ->
            val m = (u["metrics"] as? JsonArray)?.lastOrNull() as? JsonObject
            val fsTotal = m?.long("fs_size_bytes") ?: total
            val avail = m?.long("fs_avail_bytes") ?: 0L
            if (fsTotal > 0L) {
                total = fsTotal
                if (avail in 1..fsTotal) used = fsTotal - avail
            }
        }
        return Triple(used, total, iops)
    }

    private suspend fun fetchApiCounts(bearer: String, ref: String): List<SupabaseApiCountPoint> {
        val obj = getJsonObject("https://api.supabase.com/v1/projects/$ref/analytics/endpoints/usage.api-counts?interval=1day", bearer)
            ?: return emptyList()
        val res = obj["result"] as? JsonArray ?: return emptyList()
        return res.mapNotNull { el ->
            val r = el as? JsonObject ?: return@mapNotNull null
            val ts = r.str("timestamp") ?: return@mapNotNull null
            SupabaseApiCountPoint(
                timestamp = ts,
                restRequests = r.int("total_rest_requests") ?: 0,
                authRequests = r.int("total_auth_requests") ?: 0,
                realtimeRequests = r.int("total_realtime_requests") ?: 0,
                storageRequests = r.int("total_storage_requests") ?: 0
            )
        }
    }

    private suspend fun fetchEdgeFunctions(bearer: String, ref: String): List<SupabaseEdgeFunctionStat> = coroutineScope {
        val arr = getJsonArray("https://api.supabase.com/v1/projects/$ref/functions", bearer) ?: return@coroutineScope emptyList()
        arr.mapNotNull { el ->
            val o = el as? JsonObject ?: return@mapNotNull null
            val id = o.str("id") ?: return@mapNotNull null
            val slug = o.str("slug") ?: return@mapNotNull null
            async {
                var inv = 0
                var err = 0
                var weightedMs = 0.0
                var maxMs = 0.0
                val statsObj = getJsonObject(
                    "https://api.supabase.com/v1/projects/$ref/analytics/endpoints/functions.combined-stats?function_id=$id&interval=1day",
                    bearer
                )
                val rows = statsObj?.get("result") as? JsonArray
                rows?.forEach { rEl ->
                    val r = rEl as? JsonObject ?: return@forEach
                    val c = r.int("requests_count") ?: r.int("count") ?: 0
                    val e = (r.int("log_Functions_Error") ?: 0) + (r.int("status_4xx_count") ?: 0) + (r.int("status_5xx_count") ?: 0)
                    val avg = r.dbl("avg_execution_time") ?: 0.0
                    val mx = r.dbl("max_execution_time") ?: avg
                    inv += c
                    err += e
                    weightedMs += avg * maxOf(1, c)
                    if (mx > maxMs) maxMs = mx
                }
                SupabaseEdgeFunctionStat(
                    id = id,
                    slug = slug,
                    name = o.str("name") ?: slug,
                    status = o.str("status") ?: "ACTIVE",
                    version = o.int("version") ?: 1,
                    verifyJwt = o["verify_jwt"]?.jsonPrimitive?.booleanOrNull ?: true,
                    invocations24h = inv,
                    errors24h = minOf(inv, err),
                    avgExecutionMs = if (inv > 0) weightedMs / inv else 0.0,
                    maxExecutionMs = maxMs
                )
            }
        }.awaitAll().sortedByDescending { it.invocations24h }
    }

    private suspend fun fetchAdvisors(bearer: String, ref: String): Pair<List<SupabaseAdvisorLint>, List<SupabaseAdvisorLint>> = coroutineScope {
        val perfDef = async { getJsonObject("https://api.supabase.com/v1/projects/$ref/advisors/performance", bearer) }
        val secDef = async { getJsonObject("https://api.supabase.com/v1/projects/$ref/advisors/security", bearer) }
        parseAdvisors(perfDef.await(), "PERFORMANCE") to parseAdvisors(secDef.await(), "SECURITY")
    }

    private fun parseAdvisors(obj: JsonObject?, category: String): List<SupabaseAdvisorLint> {
        val lints = obj?.get("lints") as? JsonArray ?: return emptyList()
        return lints.mapIndexedNotNull { idx, el ->
            val o = el as? JsonObject ?: return@mapIndexedNotNull null
            val name = o.str("name") ?: "${category}_$idx"
            SupabaseAdvisorLint(
                id = "${category}_${name}_$idx",
                category = category,
                level = (o.str("level") ?: "WARN").uppercase(Locale.US),
                title = o.str("title") ?: name,
                detail = o.str("detail") ?: o.str("description") ?: "",
                remediationUrl = o.str("remediation")
            )
        }
    }

    private class LogsData {
        var sourceCounts: Map<String, Int> = emptyMap()
        var ok2xx = 0
        var err4xx = 0
        var err5xx = 0
        var totalEdgeBytes = 0L
        var topRoutes: List<SupabaseTopRouteStat> = emptyList()
        var recentErrors: List<SupabaseGatewayErrorItem> = emptyList()
        var fleetDevices: List<SupabaseFleetDeviceStat> = emptyList()
    }

    private suspend fun fetchClickHouseLogs(bearer: String, ref: String): LogsData = coroutineScope {
        val out = LogsData()
        val end = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        val start = end.minus(1425, ChronoUnit.MINUTES) // < 24h
        val startIso = DateTimeFormatter.ISO_INSTANT.format(start)
        val endIso = DateTimeFormatter.ISO_INSTANT.format(end)

        val srcDef = async {
            queryLogs(bearer, ref, "SELECT source, count() AS cnt FROM logs GROUP BY source ORDER BY cnt DESC LIMIT 12", startIso, endIso)
        }
        val routeDef = async {
            queryLogs(
                bearer, ref,
                """
                SELECT
                  log_attributes['request.method'] AS method,
                  log_attributes['request.path'] AS path,
                  count() AS req_count,
                  sum(toInt64OrZero(log_attributes['response.headers.content-length'])) AS resp_bytes,
                  avg(toFloat64OrZero(log_attributes['response.origin_time'])) AS avg_ms,
                  countIf(toInt32OrZero(log_attributes['response.status_code']) >= 200 AND toInt32OrZero(log_attributes['response.status_code']) < 400) AS ok_cnt,
                  countIf(toInt32OrZero(log_attributes['response.status_code']) >= 400 AND toInt32OrZero(log_attributes['response.status_code']) < 500) AS err_4xx,
                  countIf(toInt32OrZero(log_attributes['response.status_code']) >= 500) AS err_5xx
                FROM logs WHERE source = 'edge_logs'
                GROUP BY method, path ORDER BY resp_bytes DESC, req_count DESC LIMIT 20
                """.trimIndent(),
                startIso, endIso
            )
        }
        val fleetDef = async {
            queryLogs(
                bearer, ref,
                """
                SELECT
                  log_attributes['request.headers.user_agent'] AS ua,
                  count() AS req_count,
                  sum(toInt64OrZero(log_attributes['response.headers.content-length'])) AS resp_bytes,
                  countIf(toInt32OrZero(log_attributes['response.status_code']) >= 400 AND toInt32OrZero(log_attributes['response.status_code']) < 500) AS err_4xx
                FROM logs WHERE source = 'edge_logs'
                GROUP BY ua ORDER BY req_count DESC LIMIT 25
                """.trimIndent(),
                startIso, endIso
            )
        }
        val errDef = async {
            queryLogs(
                bearer, ref,
                """
                SELECT id, timestamp,
                  toInt32OrZero(log_attributes['response.status_code']) AS status,
                  log_attributes['request.method'] AS method,
                  log_attributes['request.path'] AS path,
                  log_attributes['request.headers.user_agent'] AS ua,
                  event_message
                FROM logs WHERE source = 'edge_logs' AND toInt32OrZero(log_attributes['response.status_code']) >= 400
                ORDER BY timestamp DESC LIMIT 12
                """.trimIndent(),
                startIso, endIso
            )
        }

        val srcMap = mutableMapOf<String, Int>()
        srcDef.await().forEach { r ->
            val s = r.str("source") ?: return@forEach
            srcMap[s] = r.int("cnt") ?: 0
        }
        out.sourceCounts = srcMap

        val routes = mutableListOf<SupabaseTopRouteStat>()
        routeDef.await().forEach { r ->
            val bytes = r.long("resp_bytes") ?: 0L
            val ok = r.int("ok_cnt") ?: 0
            val e4 = r.int("err_4xx") ?: 0
            val e5 = r.int("err_5xx") ?: 0
            out.ok2xx += ok
            out.err4xx += e4
            out.err5xx += e5
            out.totalEdgeBytes += bytes
            routes += SupabaseTopRouteStat(
                method = r.str("method") ?: "GET",
                path = r.str("path") ?: "/",
                requests24h = r.int("req_count") ?: 0,
                responseBytes24h = bytes,
                avgLatencyMs = r.dbl("avg_ms") ?: 0.0,
                errors4xx5xx = e4 + e5
            )
        }
        out.topRoutes = routes.take(10)

        data class Acc(val name: String, var req: Int = 0, var bytes: Long = 0L, var e4: Int = 0)
        val fleetMap = mutableMapOf<String, Acc>()
        val fleetRows = fleetDef.await()
        val totFleetReq = maxOf(1, fleetRows.sumOf { it.int("req_count") ?: 0 })
        fleetRows.forEach { r ->
            val (key, label) = SupabaseAdminCrypto.classifyFleetUserAgent(r.str("ua") ?: "")
            val acc = fleetMap.getOrPut(key) { Acc(label) }
            acc.req += r.int("req_count") ?: 0
            acc.bytes += r.long("resp_bytes") ?: 0L
            acc.e4 += r.int("err_4xx") ?: 0
        }
        out.fleetDevices = fleetMap.map { (k, a) ->
            SupabaseFleetDeviceStat(k, a.name, a.req, a.req * 100.0 / totFleetReq, a.bytes, a.e4)
        }.sortedByDescending { it.requests24h }

        out.recentErrors = errDef.await().mapIndexed { i, r ->
            SupabaseGatewayErrorItem(
                id = r.str("id") ?: "err_$i",
                timestamp = r.str("timestamp") ?: "",
                statusCode = r.int("status") ?: 400,
                method = r.str("method") ?: "GET",
                path = r.str("path") ?: "/",
                userAgent = r.str("ua") ?: "",
                message = r.str("event_message") ?: ""
            )
        }
        out
    }

    private suspend fun queryLogs(
        bearer: String,
        ref: String,
        sql: String,
        startIso: String,
        endIso: String
    ): List<JsonObject> {
        return runCatching {
            val resp = httpClient.get("https://api.supabase.com/v1/projects/$ref/analytics/endpoints/logs") {
                header(HttpHeaders.Authorization, "Bearer $bearer")
                parameter("sql", sql)
                parameter("iso_timestamp_start", startIso)
                parameter("iso_timestamp_end", endIso)
            }
            if (!resp.status.isSuccess()) return emptyList()
            val root = json.parseToJsonElement(resp.bodyAsText()).jsonObject
            (root["result"] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
        }.getOrDefault(emptyList())
    }

    private class PgData {
        var dbSizeBytes = 0L
        var heapBytes = 0L
        var indexBytes = 0L
        var storageBytes = 0L
        var activeConns = 0
        var cacheHit = 99.0
        var tables: List<SupabaseTableStat> = emptyList()
        var topSql: List<SupabaseSqlStatementStat> = emptyList()
        var cronJobs: List<SupabaseCronJobRun> = emptyList()
        var rtActiveSubs = 0
        var rtByTable: Map<String, Int> = emptyMap()
        var rtListCalls = 0L
        var rtCpuPct = 0.0
        var usersCount = 0L
        var sessionsCount = 0L
        var refreshTokenWrites = 0L
        var watchesCount = 0
    }

    private suspend fun fetchPostgresCatalog(bearer: String, ref: String): PgData = coroutineScope {
        val out = PgData()
        val catalogSql = """
            WITH db_meta AS (
              SELECT
                pg_catalog.pg_database_size(pg_catalog.current_database())::bigint AS db_bytes,
                (SELECT count(*)::int FROM pg_catalog.pg_stat_activity WHERE datname = pg_catalog.current_database()) AS active_conns,
                (SELECT CASE WHEN sum(blks_hit + blks_read) > 0
                        THEN round((sum(blks_hit)::numeric * 100.0) / sum(blks_hit + blks_read), 2)
                        ELSE 100.0 END
                 FROM pg_catalog.pg_stat_database WHERE datname = pg_catalog.current_database()) AS cache_hit
            ),
            tbl_stats AS (
              SELECT
                s.schemaname AS schema_name,
                s.relname AS table_name,
                pg_catalog.pg_table_size(s.relid)::bigint AS data_bytes,
                pg_catalog.pg_indexes_size(s.relid)::bigint AS index_bytes,
                pg_catalog.pg_total_relation_size(s.relid)::bigint AS total_bytes,
                COALESCE(s.n_live_tup, 0)::bigint AS live_rows,
                COALESCE(s.n_dead_tup, 0)::bigint AS dead_rows,
                (COALESCE(s.n_tup_ins, 0) + COALESCE(s.n_tup_upd, 0) + COALESCE(s.n_tup_del, 0))::bigint AS total_writes,
                s.last_autovacuum::text AS last_autovacuum
              FROM pg_catalog.pg_stat_all_tables s
              WHERE s.schemaname IN ('public', 'auth', 'realtime', 'storage', 'cron')
              ORDER BY pg_catalog.pg_total_relation_size(s.relid) DESC
              LIMIT 30
            )
            SELECT
              (SELECT db_bytes FROM db_meta) AS db_bytes,
              (SELECT active_conns FROM db_meta) AS active_conns,
              (SELECT cache_hit FROM db_meta) AS cache_hit,
              COALESCE((SELECT json_agg(t) FROM tbl_stats t), '[]'::json) AS tables_json;
        """.trimIndent()

        val stmtSql = """
            WITH total_cpu AS (SELECT GREATEST(COALESCE(sum(total_exec_time), 0.0), 0.001) AS all_ms FROM extensions.pg_stat_statements),
            rt_cpu AS (
              SELECT COALESCE(sum(calls), 0)::bigint AS rt_calls, COALESCE(sum(total_exec_time), 0.0) AS rt_ms
              FROM extensions.pg_stat_statements WHERE query ILIKE '%realtime.list_changes%'
            ),
            top_q AS (
              SELECT left(regexp_replace(query, '\s+', ' ', 'g'), 140) AS q_preview,
                calls::bigint AS calls, round(total_exec_time::numeric, 2) AS total_ms,
                round(mean_exec_time::numeric, 2) AS mean_ms, rows::bigint AS rows_ret
              FROM extensions.pg_stat_statements ORDER BY total_exec_time DESC LIMIT 8
            )
            SELECT (SELECT rt_calls FROM rt_cpu) AS rt_calls,
              round(((SELECT rt_ms FROM rt_cpu) * 100.0 / (SELECT all_ms FROM total_cpu))::numeric, 2) AS rt_pct,
              COALESCE((SELECT json_agg(q) FROM top_q q), '[]'::json) AS top_sql_json;
        """.trimIndent()

        val cronSql = """
            SELECT j.jobid::text AS id, COALESCE(j.jobname, 'job_' || j.jobid::text) AS job_name,
              j.schedule AS schedule,
              COALESCE(d.status, CASE WHEN j.active THEN 'scheduled' ELSE 'paused' END) AS status,
              COALESCE(d.start_time::text, '') AS start_time
            FROM cron.job j
            LEFT JOIN LATERAL (
              SELECT status, start_time FROM cron.job_run_details r WHERE r.jobid = j.jobid ORDER BY r.start_time DESC LIMIT 1
            ) d ON true ORDER BY j.jobid ASC LIMIT 12;
        """.trimIndent()

        val rtSql = """
            SELECT (SELECT count(*)::int FROM realtime.subscription) AS rt_subs,
              COALESCE((SELECT sum(COALESCE((metadata->>'size')::bigint, 0))::bigint FROM storage.objects), 0) AS storage_bytes;
        """.trimIndent()

        val catDef = async { queryReadOnlySql(bearer, ref, catalogSql) }
        val stmtDef = async { queryReadOnlySql(bearer, ref, stmtSql) }
        val cronDef = async { queryReadOnlySql(bearer, ref, cronSql) }
        val rtDef = async { queryReadOnlySql(bearer, ref, rtSql) }

        catDef.await().firstOrNull()?.let { row ->
            out.dbSizeBytes = row.long("db_bytes") ?: 0L
            out.activeConns = row.int("active_conns") ?: 0
            out.cacheHit = row.dbl("cache_hit") ?: 99.0
            val tblArr = row.jsonArr("tables_json")
            val parsed = mutableListOf<SupabaseTableStat>()
            tblArr.forEach { t ->
                val schema = t.str("schema_name") ?: "public"
                val name = t.str("table_name") ?: "table"
                val d = t.long("data_bytes") ?: 0L
                val ix = t.long("index_bytes") ?: 0L
                val tot = t.long("total_bytes") ?: (d + ix)
                val live = t.long("live_rows") ?: 0L
                val dead = t.long("dead_rows") ?: 0L
                val wr = t.long("total_writes") ?: 0L
                out.heapBytes += d
                out.indexBytes += ix
                if (schema == "auth" && name == "users") out.usersCount = live
                if (schema == "auth" && name == "sessions") out.sessionsCount = live
                if (schema == "auth" && name == "refresh_tokens") out.refreshTokenWrites = wr
                if (schema == "public" && name == "paired_watches") out.watchesCount = live.toInt()
                parsed += SupabaseTableStat(schema, name, d, ix, tot, live, dead, wr, t.str("last_autovacuum"))
            }
            out.tables = parsed
        }

        stmtDef.await().firstOrNull()?.let { row ->
            out.rtListCalls = row.long("rt_calls") ?: 0L
            out.rtCpuPct = row.dbl("rt_pct") ?: 0.0
            out.topSql = row.jsonArr("top_sql_json").mapIndexed { i, q ->
                SupabaseSqlStatementStat(
                    id = "sql_$i",
                    queryPreview = q.str("q_preview") ?: "",
                    calls = q.long("calls") ?: 0L,
                    totalExecTimeMs = q.dbl("total_ms") ?: 0.0,
                    meanExecTimeMs = q.dbl("mean_ms") ?: 0.0,
                    rowsReturned = q.long("rows_ret") ?: 0L
                )
            }
        }

        out.cronJobs = cronDef.await().mapIndexed { i, r ->
            SupabaseCronJobRun(
                id = r.str("id") ?: "$i",
                jobName = r.str("job_name") ?: "job",
                schedule = r.str("schedule") ?: "",
                status = r.str("status") ?: "scheduled",
                startTime = r.str("start_time") ?: ""
            )
        }

        rtDef.await().firstOrNull()?.let { r ->
            out.rtActiveSubs = r.int("rt_subs") ?: 0
            out.storageBytes = r.long("storage_bytes") ?: 0L
        }
        out
    }

    private suspend fun queryReadOnlySql(bearer: String, ref: String, query: String): List<JsonObject> {
        return runCatching {
            val body = buildJsonObject { put("query", query) }
            val resp = httpClient.post("https://api.supabase.com/v1/projects/$ref/database/query/read-only") {
                header(HttpHeaders.Authorization, "Bearer $bearer")
                contentType(ContentType.Application.Json)
                setBody(body.toString())
            }
            if (!resp.status.isSuccess()) return emptyList()
            json.parseToJsonElement(resp.bodyAsText()).jsonArray.mapNotNull { it as? JsonObject }
        }.getOrDefault(emptyList())
    }

    private class BillingData {
        var isExact = false
        var egressUsed = 0L
        var egressQuota = 0L
        var cachedEgress = 0L
        var dbSize = 0L
        var dbQuota = 0L
        var storageSize = 0L
        var storageQuota = 0L
        var fnCalls = 0L
        var fnQuota = 0L
        var rtMessages = 0L
        var rtMsgQuota = 0L
        var rtPeak = 0L
        var rtPeakQuota = 0L
        var mau = 0L
        var mauQuota = 0L
        var logEvents = 0L
        var dailyEgress: List<SupabaseDailyEgressPoint> = emptyList()
        var warnings: List<String> = emptyList()
    }

    private suspend fun fetchPlatformUsage(bearer: String, orgSlug: String, ref: String, hasDash: Boolean): BillingData {
        val out = BillingData()
        if (orgSlug.isEmpty()) return out
        getJsonObject("https://api.supabase.com/platform/organizations/$orgSlug/usage?project_ref=$ref", bearer)?.let { uObj ->
            val usages = uObj["usages"] as? JsonArray ?: return@let
            fun bytesVal(v: Double, orig: Long?): Long {
                if (orig != null && orig > 0L) return orig
                return if (v > 0.0 && v < 10_000.0) (v * 1_073_741_824.0).toLong() else v.toLong()
            }
            usages.forEach { el ->
                val u = el as? JsonObject ?: return@forEach
                val metric = u.str("metric")?.uppercase(Locale.US) ?: return@forEach
                val v = u.dbl("usage") ?: 0.0
                val orig = u.long("usage_original")
                val lim = u.dbl("pricing_free_units") ?: u.dbl("capped_quota") ?: u.dbl("available_in_plan") ?: 0.0
                when (metric) {
                    "EGRESS" -> {
                        out.isExact = true
                        out.egressUsed = bytesVal(v, orig)
                        if (lim > 0) out.egressQuota = bytesVal(lim, null)
                    }
                    "CACHED_EGRESS" -> out.cachedEgress = bytesVal(v, orig)
                    "DATABASE_SIZE" -> {
                        out.dbSize = bytesVal(v, orig)
                        if (lim > 0) out.dbQuota = bytesVal(lim, null)
                    }
                    "STORAGE_SIZE" -> {
                        out.storageSize = bytesVal(v, orig)
                        if (lim > 0) out.storageQuota = bytesVal(lim, null)
                    }
                    "FUNCTION_INVOCATIONS" -> {
                        out.fnCalls = orig ?: v.toLong()
                        if (lim > 0) out.fnQuota = lim.toLong()
                    }
                    "REALTIME_MESSAGE_COUNT" -> {
                        out.rtMessages = orig ?: v.toLong()
                        if (lim > 0) out.rtMsgQuota = lim.toLong()
                    }
                    "REALTIME_PEAK_CONNECTIONS" -> {
                        out.rtPeak = orig ?: v.toLong()
                        if (lim > 0) out.rtPeakQuota = lim.toLong()
                    }
                    "MONTHLY_ACTIVE_USERS" -> {
                        out.mau = orig ?: v.toLong()
                        if (lim > 0) out.mauQuota = lim.toLong()
                    }
                    "LOG_INGESTION", "LOG_DRAIN_EVENTS" -> out.logEvents += (orig ?: v.toLong())
                }
            }
        }

        val endIso = DateTimeFormatter.ISO_INSTANT.format(Instant.now().truncatedTo(ChronoUnit.SECONDS))
        val startIso = DateTimeFormatter.ISO_INSTANT.format(Instant.now().minus(14, ChronoUnit.DAYS).truncatedTo(ChronoUnit.SECONDS))
        getJsonObject("https://api.supabase.com/platform/organizations/$orgSlug/usage/daily?project_ref=$ref&start=$startIso&end=$endIso", bearer)?.let { dObj ->
            val series = dObj["usages"] as? JsonArray ?: return@let
            out.dailyEgress = series.mapNotNull { el ->
                val r = el as? JsonObject ?: return@mapNotNull null
                val date = (r.str("date") ?: r.str("period_start") ?: "").take(10)
                if (date.isEmpty()) return@mapNotNull null
                val b = (r["breakdown"] as? JsonObject) ?: r
                fun bv(k: String): Long {
                    val d = b.dbl(k) ?: 0.0
                    return if (d > 0.0 && d < 5_000.0) (d * 1_073_741_824.0).toLong() else d.toLong()
                }
                SupabaseDailyEgressPoint(
                    date = date,
                    restBytes = bv("egress_rest"),
                    functionBytes = bv("egress_function"),
                    realtimeBytes = bv("egress_realtime"),
                    authBytes = bv("egress_auth"),
                    storageBytes = bv("egress_storage"),
                    supavisorBytes = bv("egress_supavisor")
                )
            }.sortedBy { it.date }
        }
        return out
    }

    private suspend fun getJsonObject(url: String, bearer: String): JsonObject? {
        return runCatching {
            val resp = httpClient.get(url) {
                header(HttpHeaders.Authorization, "Bearer $bearer")
                header(HttpHeaders.Accept, "application/json")
            }
            if (!resp.status.isSuccess()) return null
            json.parseToJsonElement(resp.bodyAsText()) as? JsonObject
        }.getOrNull()
    }

    private suspend fun getJsonArray(url: String, bearer: String): JsonArray? {
        return runCatching {
            val resp = httpClient.get(url) {
                header(HttpHeaders.Authorization, "Bearer $bearer")
                header(HttpHeaders.Accept, "application/json")
            }
            if (!resp.status.isSuccess()) return null
            json.parseToJsonElement(resp.bodyAsText()) as? JsonArray
        }.getOrNull()
    }

    private fun JsonObject.str(key: String): String? =
        (this[key] as? JsonPrimitive)?.contentOrNull?.takeIf { it != "null" }

    private fun JsonObject.int(key: String): Int? =
        (this[key] as? JsonPrimitive)?.let { it.intOrNull ?: it.doubleOrNull?.toInt() }

    private fun JsonObject.long(key: String): Long? =
        (this[key] as? JsonPrimitive)?.let { it.longOrNull ?: it.doubleOrNull?.toLong() }

    private fun JsonObject.dbl(key: String): Double? =
        (this[key] as? JsonPrimitive)?.doubleOrNull

    private fun JsonObject.jsonArr(key: String): List<JsonObject> {
        val el: JsonElement = this[key] ?: return emptyList()
        if (el is JsonArray) return el.mapNotNull { it as? JsonObject }
        val str = (el as? JsonPrimitive)?.contentOrNull ?: return emptyList()
        return runCatching { json.parseToJsonElement(str).jsonArray.mapNotNull { it as? JsonObject } }.getOrDefault(emptyList())
    }
}
