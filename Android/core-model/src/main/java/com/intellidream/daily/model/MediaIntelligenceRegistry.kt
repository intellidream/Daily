package com.intellidream.daily.model

import kotlinx.serialization.json.Json
import java.net.URI
import java.text.Normalizer
import java.util.Locale

/**
 * Thread-safe O(1) lookup registry mapping news domains, publication aliases, and creator platforms
 * (`Substack`, `Medium`) to verified `MediaOutletProfile` records, backed by embedded `media_intelligence_seed.json`
 * and optional 24-hour delta watermarks from `public.media_outlet_profiles`.
 */
class MediaIntelligenceRegistry {

    companion object {
        private val aggregatorHosts = setOf(
            "news.google.com",
            "google.com",
            "apple.news",
            "flipboard.com",
            "msn.com",
            "smartnews.com",
            "feedly.com"
        )

        private val json = Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

        val shared: MediaIntelligenceRegistry by lazy { MediaIntelligenceRegistry() }

        fun extractNormalizedHost(urlString: String): String {
            val trimmed = urlString.trim()
            if (trimmed.isEmpty()) return ""
            try {
                val parsed = URI(trimmed)
                val host = parsed.host
                if (!host.isNullOrBlank()) return cleanHostString(host)
            } catch (_: Exception) {}

            if (!trimmed.contains("://")) {
                try {
                    val parsed = URI("https://$trimmed")
                    val host = parsed.host
                    if (!host.isNullOrBlank()) return cleanHostString(host)
                } catch (_: Exception) {}
            }
            return ""
        }

        fun cleanHostString(raw: String): String {
            var h = raw.lowercase(Locale.ROOT).trim()
            for (prefix in listOf("www.", "m.", "mobile.", "amp.", "feeds.", "rss.", "edition.")) {
                if (h.startsWith(prefix) && h.length > prefix.length + 3) {
                    h = h.substring(prefix.length)
                }
            }
            return h.trimEnd('/')
        }

        fun normalizeLookupKey(raw: String): String {
            val decomposed = Normalizer.normalize(raw, Normalizer.Form.NFD)
                .replace("ș", "s").replace("Ș", "s")
                .replace("ț", "t").replace("Ț", "t")
                .replace("ş", "s").replace("Ş", "s")
                .replace("ţ", "t").replace("Ţ", "t")
                .replace("ă", "a").replace("Ă", "a")
                .replace("â", "a").replace("Â", "a")
                .replace("î", "i").replace("Î", "i")
            val sb = StringBuilder(decomposed.length)
            for (ch in decomposed.lowercase(Locale.ROOT)) {
                if (ch in 'a'..'z' || ch in '0'..'9') {
                    sb.append(ch)
                }
            }
            return sb.toString()
        }
    }

    @Volatile
    private var byDomain: Map<String, MediaOutletProfile> = emptyMap()

    @Volatile
    private var byNormalizedName: Map<String, MediaOutletProfile> = emptyMap()

    private val seedOutlets: List<MediaOutletProfile>

    init {
        seedOutlets = loadSeedCatalog()
        rebuildIndexes(seedOutlets)
    }

    val catalogCount: Int
        get() = byDomain.values.map { it.domain }.toSet().size

    fun resolve(article: NewsArticle): MediaOutletProfile = resolve(
        url = article.link,
        publicationName = article.publicationName,
        author = article.author,
        isSubstack = article.isSubstackItem,
        isMedium = article.isMediumItem
    )

    fun resolve(
        url: String,
        publicationName: String? = null,
        author: String? = null,
        isSubstack: Boolean = false,
        isMedium: Boolean = false
    ): MediaOutletProfile {
        val host = extractNormalizedHost(url)
        val cleanPub = (publicationName ?: "").trim()
        val normPub = normalizeLookupKey(cleanPub)

        val domainMap = byDomain
        val nameMap = byNormalizedName

        // 1. Direct or parent-domain match
        if (host.isNotEmpty() && host !in aggregatorHosts &&
            host != "substack.com" && host != "open.substack.com" && host != "medium.com"
        ) {
            domainMap[host]?.let { return it }

            val parts = host.split(".")
            if (parts.size >= 3) {
                for (dropCount in 1..(parts.size - 2)) {
                    val candidate = parts.drop(dropCount).joinToString(".")
                    if (candidate != "substack.com" && candidate != "medium.com" &&
                        candidate != "co.uk" && candidate != "com.au"
                    ) {
                        domainMap[candidate]?.let { return it }
                    }
                }
            }
        }

        // 2. Match by publication display name (crucial for Google News RSS items & custom feed titles)
        if (normPub.isNotEmpty() &&
            normPub != "googlenews" && normPub != "substack" &&
            normPub != "substackinbox" && normPub != "medium" && normPub != "mediumreadinglist"
        ) {
            nameMap[normPub]?.let { return it }
            for (suffix in listOf("news", "romania", "ro", "online", "digital")) {
                if (normPub.endsWith(suffix) && normPub.length > suffix.length + 2) {
                    val trimmed = normPub.dropLast(suffix.length)
                    nameMap[trimmed]?.let { return it }
                }
            }
        }

        // 3. Substack Newsletter / Independent Creator smart profile
        if (isSubstack || host.endsWith(".substack.com") || host == "substack.com" || host == "open.substack.com") {
            val creatorTitle = when {
                cleanPub.isNotEmpty() && !cleanPub.equals("Substack", ignoreCase = true) && !cleanPub.equals("Substack Inbox", ignoreCase = true) -> cleanPub
                !author.isNullOrBlank() -> author.trim()
                host.endsWith(".substack.com") -> host.removeSuffix(".substack.com").replaceFirstChar { it.uppercase() }
                else -> "Substack Creator"
            }
            val ownerDesc = if (!author.isNullOrBlank() && !author.trim().equals(creatorTitle, ignoreCase = true)) {
                "${author.trim()} · Independent Substack Publication"
            } else {
                "$creatorTitle · Reader-Supported Newsletter"
            }
            return MediaOutletProfile(
                domain = host.ifEmpty { "substack.com" },
                name = creatorTitle,
                bias = MediaBias.IndependentCreator,
                biasContext = "Independent Newsletter / Essayist",
                factuality = FactualityTier.High,
                ownershipType = OwnershipCategory.Independent,
                ownerLabel = ownerDesc,
                countryCode = "INT",
                editorialNote = "Independent creator-owned newsletter published via Substack; editorial perspective reflects the individual author rather than a corporate newsroom."
            )
        }

        // 4. Medium Author / Publication smart profile
        if (isMedium || host == "medium.com" || host.endsWith(".medium.com")) {
            val creatorTitle = when {
                cleanPub.isNotEmpty() && !cleanPub.contains("Medium Reading List", ignoreCase = true) -> cleanPub
                !author.isNullOrBlank() -> author.trim()
                else -> "Medium Author"
            }
            return MediaOutletProfile(
                domain = host.ifEmpty { "medium.com" },
                name = creatorTitle,
                bias = MediaBias.IndependentCreator,
                biasContext = "Independent Essay / Technical Blog",
                factuality = FactualityTier.High,
                ownershipType = OwnershipCategory.Independent,
                ownerLabel = "${author?.trim()?.ifEmpty { creatorTitle } ?: creatorTitle} · Independent Author on Medium",
                countryCode = "INT",
                editorialNote = "Independent author or specialist publication hosted on Medium."
            )
        }

        // 5. Graceful fallback for uncatalogued niche blogs / domains
        val fallbackName = cleanPub.ifEmpty { host.ifEmpty { "News Source" } }
        val inferredCountry = when {
            host.endsWith(".ro") -> "RO"
            host.endsWith(".eu") -> "EU"
            host.endsWith(".uk") -> "GB"
            else -> "INT"
        }
        return MediaOutletProfile(
            domain = host.ifEmpty { normPub.ifEmpty { "news" } },
            name = fallbackName,
            bias = MediaBias.Unrated,
            biasContext = "Specialist / Uncatalogued Source",
            factuality = FactualityTier.High,
            ownershipType = OwnershipCategory.Independent,
            ownerLabel = host.ifEmpty { fallbackName },
            countryCode = inferredCountry,
            editorialNote = "Specialist or regional feed not yet assigned a political spectrum rating in the canonical media registry."
        )
    }

    fun applyRemoteDeltas(deltas: List<MediaOutletProfile>) {
        if (deltas.isEmpty()) return
        val combined = ArrayList<MediaOutletProfile>(seedOutlets.size + deltas.size)
        combined.addAll(seedOutlets)
        combined.addAll(deltas)
        rebuildIndexes(combined)
    }

    private fun loadSeedCatalog(): List<MediaOutletProfile> {
        return try {
            val stream = MediaIntelligenceRegistry::class.java.getResourceAsStream("/media_intelligence_seed.json")
                ?: MediaIntelligenceRegistry::class.java.classLoader?.getResourceAsStream("media_intelligence_seed.json")
                ?: return emptyList()
            val raw = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            json.decodeFromString<MediaIntelligenceSeedCatalog>(raw).outlets
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun rebuildIndexes(profiles: List<MediaOutletProfile>) {
        val domDict = HashMap<String, MediaOutletProfile>(profiles.size * 2)
        val nameDict = HashMap<String, MediaOutletProfile>(profiles.size * 3)

        for (profile in profiles) {
            val cleanDom = cleanHostString(profile.domain)
            if (cleanDom.isNotEmpty()) {
                domDict[cleanDom] = profile
            }
            val normName = normalizeLookupKey(profile.name)
            if (normName.isNotEmpty()) {
                nameDict[normName] = profile
            }
            val domStem = normalizeLookupKey(cleanDom)
            if (domStem.isNotEmpty()) {
                nameDict[domStem] = profile
            }
            for (alias in profile.aliases) {
                val trimmed = alias.trim()
                if (trimmed.contains(".") && !trimmed.contains(" ")) {
                    domDict[cleanHostString(trimmed)] = profile
                }
                val normAlias = normalizeLookupKey(trimmed)
                if (normAlias.isNotEmpty()) {
                    nameDict[normAlias] = profile
                }
            }
        }

        byDomain = domDict
        byNormalizedName = nameDict
    }
}
