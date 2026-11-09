package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

enum class PrismSearchEngine(val id: String, val displayName: String) {
    Google("google", "Google"),
    DuckDuckGo("duckduckgo", "DuckDuckGo"),
    Brave("brave", "Brave Search"),
    Perplexity("perplexity", "Perplexity AI");

    fun buildSearchUrl(query: String): String {
        val enc = URLEncoder.encode(query, StandardCharsets.UTF_8.name())
        return when (this) {
            Google -> "https://www.google.com/search?q=$enc"
            DuckDuckGo -> "https://duckduckgo.com/?q=$enc"
            Brave -> "https://search.brave.com/search?q=$enc"
            Perplexity -> "https://www.perplexity.ai/search?q=$enc"
        }
    }

    companion object {
        fun fromId(raw: String?): PrismSearchEngine {
            return entries.firstOrNull { it.id.equals(raw, ignoreCase = true) } ?: Google
        }

        fun resolveOmniboxInput(rawInput: String, engine: PrismSearchEngine = Google): String? {
            val trimmed = rawInput.trim()
            if (trimmed.isEmpty()) return null

            val lower = trimmed.lowercase(Locale.ROOT)
            val blockedSchemes = listOf("javascript:", "data:", "file:", "vbscript:", "intent:", "content:")
            if (blockedSchemes.any { lower.startsWith(it) }) return null

            if (lower.startsWith("https://") || lower.startsWith("http://")) {
                return trimmed
            }

            if (!trimmed.contains(' ') && !trimmed.contains('\n')) {
                if (lower.startsWith("localhost") || lower.startsWith("127.0.0.1")) {
                    return "http://$trimmed"
                }
                val dotIdx = trimmed.indexOf('.')
                if (dotIdx > 0 && dotIdx < trimmed.length - 1) {
                    val candidate = "https://$trimmed"
                    return try {
                        val host = URI(candidate).host
                        if (!host.isNullOrBlank() && host.contains('.')) candidate else engine.buildSearchUrl(trimmed)
                    } catch (_: Exception) {
                        engine.buildSearchUrl(trimmed)
                    }
                }
            }

            return engine.buildSearchUrl(trimmed)
        }

        fun extractCleanDomain(urlString: String): String {
            return try {
                val host = URI(urlString.trim()).host?.lowercase(Locale.ROOT) ?: return urlString
                if (host.startsWith("www.")) host.removePrefix("www.") else host
            } catch (_: Exception) {
                urlString
            }
        }

        fun faviconUrl(urlString: String): String {
            val domain = extractCleanDomain(urlString)
            if (domain.isBlank()) return ""
            return "https://www.google.com/s2/favicons?domain=$domain&sz=128"
        }
    }
}

@Serializable
enum class PrismClipType(val rawValue: String, val displayName: String, val accentHex: Long) {
    @SerialName("link") Link("link", "Links", 0xFF00E5FF),
    @SerialName("quote") Quote("quote", "Quotes", 0xFFFFB300),
    @SerialName("image") Image("image", "Images", 0xFF10B981),
    @SerialName("ai_summary") AiSummary("ai_summary", "AI Notes", 0xFFA855F7);

    companion object {
        fun fromRaw(raw: String?): PrismClipType =
            entries.firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } ?: Link
    }
}

@Serializable
data class PrismClip(
    val id: String = UUID.randomUUID().toString().lowercase(Locale.ROOT),
    @SerialName("user_id") val userId: String? = null,
    @SerialName("clip_type") val clipType: String = PrismClipType.Link.rawValue,
    val title: String = "",
    @SerialName("source_url") val sourceUrl: String,
    val domain: String = PrismSearchEngine.extractCleanDomain(sourceUrl),
    @SerialName("content_text") val contentText: String = "",
    @SerialName("user_note") val userNote: String = "",
    val tags: List<String> = emptyList(),
    @SerialName("preview_image_url") val previewImageUrl: String? = null,
    @SerialName("storage_path") val storagePath: String? = null,
    @SerialName("image_width") val imageWidth: Int? = null,
    @SerialName("image_height") val imageHeight: Int? = null,
    @SerialName("is_favorite") val isFavorite: Boolean = false,
    @SerialName("is_deleted") val isDeleted: Boolean = false,
    @SerialName("tagdos_note_id") val tagdosNoteId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
) {
    val parsedType: PrismClipType get() = PrismClipType.fromRaw(clipType)
}

@Serializable
data class PrismPinnedSite(
    val id: String,
    @SerialName("user_id") val userId: String? = null,
    val title: String,
    val url: String,
    val domain: String = PrismSearchEngine.extractCleanDomain(url),
    @SerialName("icon_url") val iconUrl: String? = PrismSearchEngine.faviconUrl(url),
    @SerialName("display_order") val displayOrder: Int = 0,
    @SerialName("is_deleted") val isDeleted: Boolean = false,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
) {
    companion object {
        fun deterministicId(userId: String, url: String): String {
            val normalized = "${userId.lowercase(Locale.ROOT)}:prism_pin:${url.trim().trimEnd('/').lowercase(Locale.ROOT)}"
            val md5 = MessageDigest.getInstance("MD5").digest(normalized.toByteArray(StandardCharsets.UTF_8))
            return UUID.nameUUIDFromBytes(md5).toString().lowercase(Locale.ROOT)
        }

        fun defaultStarterSites(userId: String = "local"): List<PrismPinnedSite> = listOf(
            PrismPinnedSite(id = deterministicId(userId, "https://github.com"), userId = userId, title = "GitHub", url = "https://github.com", displayOrder = 0),
            PrismPinnedSite(id = deterministicId(userId, "https://news.ycombinator.com"), userId = userId, title = "Hacker News", url = "https://news.ycombinator.com", displayOrder = 1),
            PrismPinnedSite(id = deterministicId(userId, "https://substack.com/inbox"), userId = userId, title = "Substack", url = "https://substack.com/inbox", displayOrder = 2),
            PrismPinnedSite(id = deterministicId(userId, "https://medium.com"), userId = userId, title = "Medium", url = "https://medium.com", displayOrder = 3),
            PrismPinnedSite(id = deterministicId(userId, "https://www.perplexity.ai"), userId = userId, title = "Perplexity", url = "https://www.perplexity.ai", displayOrder = 4),
            PrismPinnedSite(id = deterministicId(userId, "https://en.wikipedia.org"), userId = userId, title = "Wikipedia", url = "https://en.wikipedia.org", displayOrder = 5)
        )
    }
}

@Serializable
data class PrismTabState(
    val id: String = UUID.randomUUID().toString(),
    val url: String = "",
    val title: String = "Start Page",
    val domain: String = "",
    val scrollY: Int = 0,
    val isPrivate: Boolean = false,
    val isReaderMode: Boolean = false,
    val detectedRssUrl: String? = null,
    val detectedRssTitle: String? = null,
    val lastAccessedEpochMs: Long = System.currentTimeMillis(),
    val isHibernated: Boolean = false
) {
    val isStartPage: Boolean get() = url.isBlank()
    companion object {
        const val MAX_OPEN_TABS = 8
    }
}

enum class PrismCoPilotAction(val id: String, val title: String, val accentHex: Long) {
    Tldr("tldr", "TL;DR Summary", 0xFF00E5FF),
    ExtractTasks("extract_tasks", "Tasks → TagDoS", 0xFFFFB300),
    KeyFacts("key_facts", "Key Facts & Numbers", 0xFF10B981),
    ExplainSelection("explain_selection", "Explain Selection", 0xFFA855F7)
}

data class PrismCoPilotTurn(
    val id: String = UUID.randomUUID().toString(),
    val prompt: String,
    val responseMarkdown: String,
    val keyBullets: List<String> = emptyList(),
    val extractedTasks: List<String> = emptyList(),
    val sourceUrl: String,
    val pageTitle: String,
    val isAiGenerated: Boolean,
    val createdAtMs: Long = System.currentTimeMillis()
)

object PrismShieldRules {
    val blockedTrackerDomains: Set<String> = setOf(
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "google-analytics.com",
        "googletagmanager.com",
        "adnxs.com",
        "criteo.com",
        "criteo.net",
        "taboola.com",
        "outbrain.com",
        "scorecardresearch.com",
        "quantserve.com",
        "rubiconproject.com",
        "pubmatic.com",
        "openx.net",
        "casalemedia.com",
        "moatads.com",
        "adsrvr.org",
        "hotjar.com",
        "popads.net",
        "adform.net",
        "smartadserver.com",
        "teads.tv",
        "zemanta.com"
    )

    fun shouldBlockRequest(requestUrl: String, pageUrl: String, shieldEnabled: Boolean, allowlist: List<String>): Boolean {
        if (!shieldEnabled) return false
        val pageDomain = PrismSearchEngine.extractCleanDomain(pageUrl)
        if (pageDomain.isNotEmpty() && allowlist.any { it.equals(pageDomain, ignoreCase = true) }) {
            return false
        }
        val reqHost = PrismSearchEngine.extractCleanDomain(requestUrl)
        if (reqHost.isEmpty() || reqHost == pageDomain) return false
        return blockedTrackerDomains.any { reqHost == it || reqHost.endsWith(".$it") }
    }
}
