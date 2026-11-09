package com.intellidream.daily.database

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.intellidream.daily.database.dao.PrismDao
import com.intellidream.daily.database.entity.PrismClipEntity
import com.intellidream.daily.database.entity.PrismPinnedSiteEntity
import com.intellidream.daily.model.PrismClip
import com.intellidream.daily.model.PrismClipType
import com.intellidream.daily.model.PrismCoPilotTurn
import com.intellidream.daily.model.PrismPinnedSite
import com.intellidream.daily.model.PrismSearchEngine
import com.intellidream.daily.model.PrismTabState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt

interface PrismSyncHandler {
    suspend fun fetchClipsDelta(userId: String, watermarkIso: String?): List<PrismClip>
    suspend fun upsertClip(clip: PrismClip): Boolean
    suspend fun fetchPinnedSitesDelta(userId: String, watermarkIso: String?): List<PrismPinnedSite>
    suspend fun upsertPinnedSite(pin: PrismPinnedSite): Boolean
    suspend fun uploadClipImage(userId: String, clipId: String, jpegBytes: ByteArray): String?
    suspend fun downloadClipImage(storagePath: String?, fallbackUrl: String?): ByteArray?
    suspend fun deleteRemoteClipImage(storagePath: String?)
}

class PrismRepository(
    private val context: Context,
    private val prismDao: PrismDao,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    private val prefs = context.getSharedPreferences("daily_prism_prefs_v1", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    var syncHandler: PrismSyncHandler? = null
    var currentUserId: String = "guest"

    private val _clips = MutableStateFlow<List<PrismClip>>(emptyList())
    val clips: StateFlow<List<PrismClip>> = _clips.asStateFlow()

    private val _pinnedSites = MutableStateFlow<List<PrismPinnedSite>>(emptyList())
    val pinnedSites: StateFlow<List<PrismPinnedSite>> = _pinnedSites.asStateFlow()

    private val _tabs = MutableStateFlow<List<PrismTabState>>(emptyList())
    val tabs: StateFlow<List<PrismTabState>> = _tabs.asStateFlow()

    private val _activeTabId = MutableStateFlow<String?>(null)
    val activeTabId: StateFlow<String?> = _activeTabId.asStateFlow()

    private val _pendingUrlRequest = MutableStateFlow<String?>(null)
    val pendingUrlRequest: StateFlow<String?> = _pendingUrlRequest.asStateFlow()

    private val _clipboardCandidateUrl = MutableStateFlow<String?>(null)
    val clipboardCandidateUrl: StateFlow<String?> = _clipboardCandidateUrl.asStateFlow()

    val cacheDir: File by lazy {
        File(context.cacheDir, "PrismClips").apply { if (!exists()) mkdirs() }
    }

    init {
        loadTabsFromPrefs()
        scope.launch {
            prismDao.observeActiveClips().collectLatest { entities ->
                _clips.value = entities.map { it.toDomain() }
            }
        }
        scope.launch {
            prismDao.observeActivePinnedSites().collectLatest { entities ->
                if (entities.isEmpty() && prismDao.getAllPinnedSites().isEmpty()) {
                    val seeds = PrismPinnedSite.defaultStarterSites(currentUserId.ifBlank { "local" })
                    prismDao.upsertPinnedSites(seeds.map { it.toEntity(isDirty = false) })
                } else {
                    _pinnedSites.value = entities.map { it.toDomain() }
                }
            }
        }
    }

    // MARK: - Tab Hibernation Engine (Max 8 Open Tabs, 1 Mounted WebView)

    private fun loadTabsFromPrefs() {
        val raw = prefs.getString("open_tabs_json", null)
        val restored = if (!raw.isNullOrBlank()) {
            try {
                json.decodeFromString<List<PrismTabState>>(raw).filter { !it.isPrivate }
            } catch (_: Exception) {
                emptyList()
            }
        } else emptyList()

        val initialTabs = restored.ifEmpty { listOf(PrismTabState(title = "Start Page")) }
        val savedActive = prefs.getString("active_tab_id", null)
        val resolvedActive = initialTabs.firstOrNull { it.id == savedActive }?.id ?: initialTabs.first().id
        _activeTabId.value = resolvedActive
        _tabs.value = initialTabs.map { it.copy(isHibernated = it.id != resolvedActive) }
    }

    private fun persistTabs() {
        val active = _activeTabId.value
        val persistent = _tabs.value.filter { !it.isPrivate }
        prefs.edit()
            .putString("open_tabs_json", json.encodeToString(persistent))
            .putString("active_tab_id", active)
            .apply()
    }

    fun activeTab(): PrismTabState? {
        val id = _activeTabId.value
        return _tabs.value.firstOrNull { it.id == id } ?: _tabs.value.firstOrNull()
    }

    fun selectTab(tabId: String) {
        val current = _tabs.value
        if (current.none { it.id == tabId }) return
        _activeTabId.value = tabId
        val now = System.currentTimeMillis()
        _tabs.value = current.map {
            it.copy(
                isHibernated = it.id != tabId,
                lastAccessedEpochMs = if (it.id == tabId) now else it.lastAccessedEpochMs
            )
        }
        persistTabs()
    }

    fun openNewTab(url: String = "", title: String? = null, isPrivate: Boolean = false): PrismTabState {
        val list = _tabs.value.toMutableList()
        val currentActive = _activeTabId.value
        if (list.size >= PrismTabState.MAX_OPEN_TABS) {
            val victim = list.filter { it.id != currentActive }.minByOrNull { it.lastAccessedEpochMs }
            if (victim != null) list.remove(victim)
        }
        val resolvedTitle = title?.takeIf { it.isNotBlank() }
            ?: if (url.isBlank()) (if (isPrivate) "Private Tab" else "Start Page") else PrismSearchEngine.extractCleanDomain(url)
        val created = PrismTabState(
            url = url,
            title = resolvedTitle,
            domain = if (url.isBlank()) "" else PrismSearchEngine.extractCleanDomain(url),
            isPrivate = isPrivate,
            isHibernated = false
        )
        list.add(created)
        _activeTabId.value = created.id
        _tabs.value = list.map { it.copy(isHibernated = it.id != created.id) }
        persistTabs()
        return created
    }

    fun closeTab(tabId: String) {
        val list = _tabs.value.toMutableList()
        val idx = list.indexOfFirst { it.id == tabId }
        if (idx < 0) return
        val wasActive = (_activeTabId.value == tabId)
        list.removeAt(idx)
        if (list.isEmpty()) {
            val fresh = PrismTabState(title = "Start Page")
            _activeTabId.value = fresh.id
            _tabs.value = listOf(fresh)
        } else {
            val nextId = if (wasActive) list[minOf(idx, list.lastIndex)].id else (_activeTabId.value ?: list.first().id)
            _activeTabId.value = nextId
            _tabs.value = list.map { it.copy(isHibernated = it.id != nextId) }
        }
        persistTabs()
    }

    fun updateActiveTabMetadata(
        url: String? = null,
        title: String? = null,
        scrollY: Int? = null,
        isReaderMode: Boolean? = null,
        detectedRssUrl: String? = "__keep__",
        detectedRssTitle: String? = "__keep__"
    ) {
        val activeId = _activeTabId.value ?: return
        _tabs.value = _tabs.value.map { tab ->
            if (tab.id != activeId) tab
            else tab.copy(
                url = url?.takeIf { it.isNotBlank() } ?: tab.url,
                domain = if (!url.isNullOrBlank()) PrismSearchEngine.extractCleanDomain(url) else tab.domain,
                title = title?.takeIf { it.isNotBlank() } ?: tab.title,
                scrollY = scrollY ?: tab.scrollY,
                isReaderMode = isReaderMode ?: tab.isReaderMode,
                detectedRssUrl = if (detectedRssUrl == "__keep__") tab.detectedRssUrl else detectedRssUrl,
                detectedRssTitle = if (detectedRssTitle == "__keep__") tab.detectedRssTitle else detectedRssTitle
            )
        }
        persistTabs()
    }

    fun requestOpenUrlInPrism(rawUrl: String, title: String? = null, openInNewTab: Boolean = false) {
        val safe = PrismSearchEngine.resolveOmniboxInput(rawUrl) ?: return
        if (openInNewTab || activeTab()?.isPrivate == true) {
            openNewTab(url = safe, title = title, isPrivate = false)
        } else {
            updateActiveTabMetadata(url = safe, title = title, isReaderMode = false, detectedRssUrl = null, detectedRssTitle = null)
        }
        _pendingUrlRequest.value = safe
    }

    fun consumePendingUrlRequest(): String? {
        val v = _pendingUrlRequest.value
        _pendingUrlRequest.value = null
        return v
    }

    fun checkClipboardCandidate(rawClipText: String?, enabled: Boolean) {
        if (!enabled || rawClipText.isNullOrBlank()) {
            _clipboardCandidateUrl.value = null
            return
        }
        val trimmed = rawClipText.trim()
        if ((!trimmed.startsWith("https://") && !trimmed.startsWith("http://")) || trimmed.contains(' ')) return
        val lastDismissed = prefs.getString("last_dismissed_clip_url", null)
        val alreadyOpen = _tabs.value.any { it.url == trimmed }
        val alreadySaved = _clips.value.any { it.sourceUrl == trimmed }
        if (trimmed != lastDismissed && !alreadyOpen && !alreadySaved) {
            _clipboardCandidateUrl.value = trimmed
        }
    }

    fun dismissClipboardCandidate() {
        val cur = _clipboardCandidateUrl.value
        if (!cur.isNullOrBlank()) {
            prefs.edit().putString("last_dismissed_clip_url", cur).apply()
        }
        _clipboardCandidateUrl.value = null
    }

    // MARK: - Vault Clipping Operations

    fun saveLinkClip(url: String, title: String, previewImageUrl: String? = null, userNote: String = "", tags: List<String> = emptyList()) {
        scope.launch(Dispatchers.IO) {
            val now = System.currentTimeMillis()
            val clip = PrismClip(
                userId = currentUserId.takeIf { it != "guest" },
                clipType = PrismClipType.Link.rawValue,
                title = title.ifBlank { PrismSearchEngine.extractCleanDomain(url) },
                sourceUrl = url,
                userNote = userNote,
                tags = tags,
                previewImageUrl = previewImageUrl,
                createdAt = Instant.ofEpochMilli(now).toString(),
                updatedAt = Instant.ofEpochMilli(now).toString()
            )
            prismDao.upsertClip(clip.toEntity(createdMs = now, updatedMs = now, isDirty = true))
            pushClipIfAuthenticated(clip)
        }
    }

    fun saveQuoteClip(quoteText: String, sourceUrl: String, pageTitle: String, userNote: String = "", tags: List<String> = emptyList()): PrismClip {
        val now = System.currentTimeMillis()
        val clip = PrismClip(
            userId = currentUserId.takeIf { it != "guest" },
            clipType = PrismClipType.Quote.rawValue,
            title = pageTitle.ifBlank { PrismSearchEngine.extractCleanDomain(sourceUrl) },
            sourceUrl = sourceUrl,
            contentText = quoteText.trim(),
            userNote = userNote,
            tags = tags,
            createdAt = Instant.ofEpochMilli(now).toString(),
            updatedAt = Instant.ofEpochMilli(now).toString()
        )
        scope.launch(Dispatchers.IO) {
            prismDao.upsertClip(clip.toEntity(createdMs = now, updatedMs = now, isDirty = true))
            pushClipIfAuthenticated(clip)
        }
        return clip
    }

    fun saveAiSummaryClip(turn: PrismCoPilotTurn) {
        scope.launch(Dispatchers.IO) {
            val now = System.currentTimeMillis()
            val content = buildString {
                append(turn.responseMarkdown)
                if (turn.keyBullets.isNotEmpty()) {
                    append("\n\n")
                    turn.keyBullets.forEach { append("• ").append(it).append('\n') }
                }
            }.trim()
            val clip = PrismClip(
                userId = currentUserId.takeIf { it != "guest" },
                clipType = PrismClipType.AiSummary.rawValue,
                title = if (turn.pageTitle.isBlank()) turn.prompt else "${turn.pageTitle} — ${turn.prompt}",
                sourceUrl = turn.sourceUrl,
                contentText = content,
                tags = listOf("ai"),
                createdAt = Instant.ofEpochMilli(now).toString(),
                updatedAt = Instant.ofEpochMilli(now).toString()
            )
            prismDao.upsertClip(clip.toEntity(createdMs = now, updatedMs = now, isDirty = true))
            pushClipIfAuthenticated(clip)
        }
    }

    suspend fun saveImageClip(
        bitmap: Bitmap? = null,
        rawBytes: ByteArray? = null,
        remoteImageUrl: String? = null,
        sourceUrl: String,
        title: String,
        tags: List<String> = emptyList()
    ): PrismClip = withContext(Dispatchers.IO) {
        val clipId = UUID.randomUUID().toString().lowercase(Locale.ROOT)
        var jpegBytes: ByteArray? = null
        var width: Int? = null
        var height: Int? = null

        val sourceBitmap = when {
            bitmap != null -> bitmap
            rawBytes != null -> BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size)
            !remoteImageUrl.isNullOrBlank() -> {
                val dl = syncHandler?.downloadClipImage(null, remoteImageUrl)
                if (dl != null) BitmapFactory.decodeByteArray(dl, 0, dl.size) else null
            }
            else -> null
        }

        if (sourceBitmap != null) {
            val maxEdge = max(sourceBitmap.width, sourceBitmap.height)
            val scaled = if (maxEdge > 1600) {
                val ratio = 1600f / maxEdge.toFloat()
                Bitmap.createScaledBitmap(
                    sourceBitmap,
                    (sourceBitmap.width * ratio).roundToInt().coerceAtLeast(1),
                    (sourceBitmap.height * ratio).roundToInt().coerceAtLeast(1),
                    true
                )
            } else sourceBitmap
            width = scaled.width
            height = scaled.height
            val bos = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 82, bos)
            jpegBytes = bos.toByteArray()
            File(cacheDir, "$clipId.jpg").writeBytes(jpegBytes)
        }

        var storagePath: String? = null
        val uid = currentUserId
        if (uid.isNotBlank() && uid != "guest" && jpegBytes != null) {
            storagePath = syncHandler?.uploadClipImage(uid, clipId, jpegBytes)
        }

        val now = System.currentTimeMillis()
        val clip = PrismClip(
            id = clipId,
            userId = uid.takeIf { it != "guest" },
            clipType = PrismClipType.Image.rawValue,
            title = title.ifBlank { PrismSearchEngine.extractCleanDomain(sourceUrl) },
            sourceUrl = sourceUrl,
            tags = tags,
            previewImageUrl = remoteImageUrl,
            storagePath = storagePath,
            imageWidth = width,
            imageHeight = height,
            createdAt = Instant.ofEpochMilli(now).toString(),
            updatedAt = Instant.ofEpochMilli(now).toString()
        )
        prismDao.upsertClip(clip.toEntity(createdMs = now, updatedMs = now, isDirty = true))
        pushClipIfAuthenticated(clip)
        clip
    }

    fun localClipImageFile(clipId: String): File = File(cacheDir, "${clipId.lowercase(Locale.ROOT)}.jpg")

    suspend fun loadOrDownloadClipImage(clip: PrismClip): File? = withContext(Dispatchers.IO) {
        val local = localClipImageFile(clip.id)
        if (local.exists() && local.length() > 0) return@withContext local
        val downloaded = syncHandler?.downloadClipImage(clip.storagePath, clip.previewImageUrl) ?: return@withContext null
        local.writeBytes(downloaded)
        local
    }

    fun toggleFavoriteClip(clipId: String) {
        scope.launch(Dispatchers.IO) {
            val existing = prismDao.getClipById(clipId) ?: return@launch
            val now = System.currentTimeMillis()
            val updated = existing.copy(isFavorite = !existing.isFavorite, updatedAtMs = now, isDirty = true)
            prismDao.upsertClip(updated)
            pushClipIfAuthenticated(updated.toDomain())
        }
    }

    fun updateClipNoteAndTags(clipId: String, note: String, tags: List<String>) {
        scope.launch(Dispatchers.IO) {
            val existing = prismDao.getClipById(clipId) ?: return@launch
            val cleanTags = tags.map { it.trim().trimStart('#').lowercase(Locale.ROOT) }.filter { it.isNotBlank() }.distinct()
            val now = System.currentTimeMillis()
            val updated = existing.copy(
                userNote = note.trim(),
                tagsCsv = cleanTags.joinToString(","),
                updatedAtMs = now,
                isDirty = true
            )
            prismDao.upsertClip(updated)
            pushClipIfAuthenticated(updated.toDomain())
        }
    }

    fun deleteClip(clip: PrismClip) {
        scope.launch(Dispatchers.IO) {
            val existing = prismDao.getClipById(clip.id) ?: return@launch
            val now = System.currentTimeMillis()
            val deleted = existing.copy(isDeleted = true, updatedAtMs = now, isDirty = true)
            prismDao.upsertClip(deleted)
            localClipImageFile(clip.id).delete()
            syncHandler?.deleteRemoteClipImage(clip.storagePath)
            pushClipIfAuthenticated(deleted.toDomain())
        }
    }

    // MARK: - Pinned Speed Dial

    fun isPinned(url: String): Boolean {
        val dom = PrismSearchEngine.extractCleanDomain(url)
        return _pinnedSites.value.any { it.url.equals(url, ignoreCase = true) || it.domain == dom }
    }

    fun togglePinSite(title: String, url: String) {
        scope.launch(Dispatchers.IO) {
            val all = prismDao.getAllPinnedSites()
            val existing = all.firstOrNull { !it.isDeleted && it.url.equals(url, ignoreCase = true) }
            val now = System.currentTimeMillis()
            if (existing != null) {
                val removed = existing.copy(isDeleted = true, updatedAtMs = now, isDirty = true)
                prismDao.upsertPinnedSite(removed)
                pushPinIfAuthenticated(removed.toDomain())
            } else {
                val uid = currentUserId.takeIf { it != "guest" } ?: "local"
                val created = PrismPinnedSite(
                    id = PrismPinnedSite.deterministicId(uid, url),
                    userId = currentUserId.takeIf { it != "guest" },
                    title = title.ifBlank { PrismSearchEngine.extractCleanDomain(url) },
                    url = url,
                    displayOrder = _pinnedSites.value.size,
                    createdAt = Instant.ofEpochMilli(now).toString(),
                    updatedAt = Instant.ofEpochMilli(now).toString()
                )
                prismDao.upsertPinnedSite(created.toEntity(createdMs = now, updatedMs = now, isDirty = true))
                pushPinIfAuthenticated(created)
            }
        }
    }

    fun deletePinnedSite(pinId: String) {
        scope.launch(Dispatchers.IO) {
            val existing = prismDao.getAllPinnedSites().firstOrNull { it.id == pinId } ?: return@launch
            val now = System.currentTimeMillis()
            val removed = existing.copy(isDeleted = true, updatedAtMs = now, isDirty = true)
            prismDao.upsertPinnedSite(removed)
            pushPinIfAuthenticated(removed.toDomain())
        }
    }

    // MARK: - Supabase Cloud Sync

    fun syncWithSupabase(userId: String = currentUserId) {
        if (userId.isBlank() || userId == "guest") return
        currentUserId = userId
        val handler = syncHandler ?: return

        scope.launch(Dispatchers.IO) {
            // 1. Push dirty local rows first
            for (dirty in prismDao.getDirtyClips()) {
                val domain = dirty.toDomain().copy(userId = userId)
                if (handler.upsertClip(domain)) {
                    prismDao.upsertClip(dirty.copy(userId = userId, isDirty = false))
                }
            }

            // 2. Pull incremental deltas via `updated_at` watermark
            val clipWm = prefs.getString("clips_watermark_$userId", null)
            val remoteClips = handler.fetchClipsDelta(userId, clipWm)
            if (remoteClips.isNotEmpty()) {
                var maxIso: String? = clipWm
                val entities = remoteClips.map { rc ->
                    if (!rc.updatedAt.isNullOrBlank() && (maxIso == null || rc.updatedAt!! > maxIso!!)) {
                        maxIso = rc.updatedAt
                    }
                    rc.toEntity(isDirty = false)
                }
                prismDao.upsertClips(entities)
                if (!maxIso.isNullOrBlank()) {
                    prefs.edit().putString("clips_watermark_$userId", maxIso).apply()
                }
            }

            val pinWm = prefs.getString("pins_watermark_$userId", null)
            val remotePins = handler.fetchPinnedSitesDelta(userId, pinWm)
            if (remotePins.isNotEmpty()) {
                var maxPinIso: String? = pinWm
                val pinEntities = remotePins.map { rp ->
                    if (!rp.updatedAt.isNullOrBlank() && (maxPinIso == null || rp.updatedAt!! > maxPinIso!!)) {
                        maxPinIso = rp.updatedAt
                    }
                    rp.toEntity(isDirty = false)
                }
                prismDao.upsertPinnedSites(pinEntities)
                if (!maxPinIso.isNullOrBlank()) {
                    prefs.edit().putString("pins_watermark_$userId", maxPinIso).apply()
                }
            }
        }
    }

    private suspend fun pushClipIfAuthenticated(clip: PrismClip) {
        val uid = currentUserId
        if (uid.isBlank() || uid == "guest") return
        val handler = syncHandler ?: return
        val ok = handler.upsertClip(clip.copy(userId = uid))
        if (ok) {
            prismDao.getClipById(clip.id)?.let { prismDao.upsertClip(it.copy(userId = uid, isDirty = false)) }
        }
    }

    private suspend fun pushPinIfAuthenticated(pin: PrismPinnedSite) {
        val uid = currentUserId
        if (uid.isBlank() || uid == "guest") return
        val handler = syncHandler ?: return
        val canonicalId = PrismPinnedSite.deterministicId(uid, pin.url)
        handler.upsertPinnedSite(pin.copy(id = canonicalId, userId = uid))
    }

    private fun parseIsoMs(iso: String?): Long {
        if (iso.isNullOrBlank()) return System.currentTimeMillis()
        return try {
            Instant.parse(iso).toEpochMilli()
        } catch (_: Exception) {
            System.currentTimeMillis()
        }
    }

    private fun PrismClip.toEntity(
        createdMs: Long = parseIsoMs(createdAt),
        updatedMs: Long = parseIsoMs(updatedAt),
        isDirty: Boolean = false
    ) = PrismClipEntity(
        id = id,
        userId = userId,
        clipType = clipType,
        title = title,
        sourceUrl = sourceUrl,
        domain = domain,
        contentText = contentText,
        userNote = userNote,
        tagsCsv = tags.joinToString(","),
        previewImageUrl = previewImageUrl,
        storagePath = storagePath,
        imageWidth = imageWidth,
        imageHeight = imageHeight,
        isFavorite = isFavorite,
        isDeleted = isDeleted,
        tagdosNoteId = tagdosNoteId,
        createdAtMs = createdMs,
        updatedAtMs = updatedMs,
        isDirty = isDirty
    )

    private fun PrismClipEntity.toDomain() = PrismClip(
        id = id,
        userId = userId,
        clipType = clipType,
        title = title,
        sourceUrl = sourceUrl,
        domain = domain,
        contentText = contentText,
        userNote = userNote,
        tags = tagsCsv.split(',').map { it.trim() }.filter { it.isNotBlank() },
        previewImageUrl = previewImageUrl,
        storagePath = storagePath,
        imageWidth = imageWidth,
        imageHeight = imageHeight,
        isFavorite = isFavorite,
        isDeleted = isDeleted,
        tagdosNoteId = tagdosNoteId,
        createdAt = Instant.ofEpochMilli(createdAtMs).toString(),
        updatedAt = Instant.ofEpochMilli(updatedAtMs).toString()
    )

    private fun PrismPinnedSite.toEntity(
        createdMs: Long = parseIsoMs(createdAt),
        updatedMs: Long = parseIsoMs(updatedAt),
        isDirty: Boolean = false
    ) = PrismPinnedSiteEntity(
        id = id,
        userId = userId,
        title = title,
        url = url,
        domain = domain,
        iconUrl = iconUrl,
        displayOrder = displayOrder,
        isDeleted = isDeleted,
        createdAtMs = createdMs,
        updatedAtMs = updatedMs,
        isDirty = isDirty
    )

    private fun PrismPinnedSiteEntity.toDomain() = PrismPinnedSite(
        id = id,
        userId = userId,
        title = title,
        url = url,
        domain = domain,
        iconUrl = iconUrl,
        displayOrder = displayOrder,
        isDeleted = isDeleted,
        createdAt = Instant.ofEpochMilli(createdAtMs).toString(),
        updatedAt = Instant.ofEpochMilli(updatedAtMs).toString()
    )
}
