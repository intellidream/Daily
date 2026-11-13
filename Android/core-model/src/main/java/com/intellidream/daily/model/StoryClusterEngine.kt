package com.intellidream.daily.model

import java.text.Normalizer
import java.util.Locale
import kotlin.math.abs
import kotlin.math.exp

/**
 * High-speed (< 5 ms for 250 items), deterministic bilingual (`RO` + `EN`) story clustering,
 * bias distribution, and blindspot detection engine. Runs strictly off the UI thread.
 */
object StoryClusterEngine {

    private val stopWords = setOf(
        // English
        "the", "and", "for", "that", "with", "this", "from", "have", "has", "had", "not", "are", "was", "were",
        "will", "would", "could", "should", "about", "after", "before", "into", "over", "under", "between",
        "what", "when", "where", "which", "while", "who", "whom", "whose", "why", "how", "their", "there",
        "they", "them", "then", "than", "these", "those", "been", "being", "more", "most", "some", "such",
        "only", "other", "new", "news", "says", "said", "amid", "just", "like", "make", "made", "year", "years",
        "today", "week", "month", "first", "last", "report", "reports", "update", "live", "video", "photo",
        "its", "his", "her", "our", "out", "now", "all", "can", "may", "one", "two", "per", "via", "also",
        // Romanian
        "pentru", "care", "este", "sunt", "fost", "avea", "avut", "face", "făcut", "facut", "după", "dupa",
        "peste", "prin", "între", "intre", "către", "catre", "fără", "fara", "doar", "încă", "inca", "acum",
        "când", "cand", "unde", "cum", "ceea", "acest", "această", "aceasta", "aceste", "acești", "acesti",
        "unui", "unei", "unor", "sale", "său", "sau", "lor", "lui", "mai", "mult", "multe", "foarte", "poate",
        "pot", "spune", "spus", "anunță", "anunta", "anunțat", "anuntat", "transmis", "potrivit", "conform",
        "foto", "video", "live", "breaking", "exclusiv", "știri", "stiri", "azi", "astăzi", "astazi", "ieri",
        "din", "sub", "spre", "dar", "iar", "ori", "cea", "cel", "cei", "cele", "asa", "așa", "cât", "cat"
    )

    private val phraseReplacements = listOf(
        Regex("european central bank", RegexOption.IGNORE_CASE) to "ECB",
        Regex("banca centrala europeana", RegexOption.IGNORE_CASE) to "ECB",
        Regex("banca nationala a romaniei", RegexOption.IGNORE_CASE) to "BNR",
        Regex("banca nationala", RegexOption.IGNORE_CASE) to "BNR",
        Regex("federal reserve", RegexOption.IGNORE_CASE) to "FED",
        Regex("curtea constitutionala", RegexOption.IGNORE_CASE) to "CCR",
        Regex("comisia europeana", RegexOption.IGNORE_CASE) to "EU_COMMISSION",
        Regex("european commission", RegexOption.IGNORE_CASE) to "EU_COMMISSION",
        Regex("uniunea europeana", RegexOption.IGNORE_CASE) to "EU",
        Regex("european union", RegexOption.IGNORE_CASE) to "EU",
        Regex("zona euro", RegexOption.IGNORE_CASE) to "Eurozone",
        Regex("euro area", RegexOption.IGNORE_CASE) to "Eurozone",
        Regex("white house", RegexOption.IGNORE_CASE) to "WhiteHouse",
        Regex("casa alba", RegexOption.IGNORE_CASE) to "WhiteHouse",
        Regex("supreme court", RegexOption.IGNORE_CASE) to "SupremeCourt",
        Regex("world bank", RegexOption.IGNORE_CASE) to "WorldBank",
        Regex("banca mondiala", RegexOption.IGNORE_CASE) to "WorldBank",
        Regex("fondul monetar international", RegexOption.IGNORE_CASE) to "IMF",
        Regex("international monetary fund", RegexOption.IGNORE_CASE) to "IMF"
    )

    private val decimalNumberRegex = Regex("""(\d+)[.,](\d+)""")
    private val nonWordSplitRegex = Regex("""[^\p{L}\p{N}_]+""")
    private val diacriticMarksRegex = Regex("""\p{Mn}+""")

    private val sentenceInitialIgnore = setOf(
        "the", "a", "an", "in", "on", "at", "to", "for", "of", "by", "as", "is", "are", "why", "how", "what", "who", "when", "where",
        "în", "in", "la", "pe", "cu", "de", "din", "spre", "sub", "după", "dupa", "cum", "ce", "cine", "când", "cand", "unde",
        "un", "o", "doi", "două", "doua", "trei", "mai", "tot", "toți", "toti", "toate", "fără", "fara", "peste", "prin"
    )

    private val bilingualSynonyms = mapOf(
        "sua" to "usa", "american" to "usa", "americane" to "usa", "washington" to "usa",
        "ue" to "eu", "uniunea" to "eu", "bruxelles" to "brussels", "comisia" to "eu_commission",
        "ucraina" to "ukraine", "ucrainei" to "ukraine", "kiev" to "kyiv", "zelenski" to "zelensky",
        "rusia" to "russia", "rusiei" to "russia", "moscova" to "moscow",
        "germania" to "germany", "germaniei" to "germany",
        "franta" to "france", "frantei" to "france",
        "marea" to "uk", "londra" to "london",
        "ungaria" to "hungary", "budapesta" to "budapest",
        "republica" to "moldova_rep", "chisinau" to "chisinau",
        "bce" to "ecb", "ecb" to "ecb", "fmi" to "imf", "imf" to "imf", "onu" to "un", "otan" to "nato", "bnr" to "bnr", "fed" to "fed",
        "csat" to "csat", "anaf" to "anaf", "pnrr" to "pnrr", "ccr" to "ccr", "pib" to "gdp", "gdp" to "gdp",
        "dobanda" to "interest_rate", "dobanzi" to "interest_rate", "dobanzile" to "interest_rate",
        "dobanzii" to "interest_rate", "rate" to "interest_rate", "rates" to "interest_rate",
        "reduce" to "cut", "scade" to "cut", "scaderea" to "slowdown", "scaderii" to "slowdown",
        "cooling" to "slowdown", "lowers" to "cut", "cuts" to "cut",
        "inflatie" to "inflation", "inflatia" to "inflation", "inflatiei" to "inflation",
        "buget" to "budget", "bugetul" to "budget", "deficit" to "deficit", "deficitul" to "deficit",
        "taxe" to "taxes", "impozit" to "taxes", "impozite" to "taxes", "fiscal" to "fiscal", "fiscale" to "fiscal",
        "tarife" to "tariffs", "tarifele" to "tariffs", "vamale" to "tariffs",
        "alegeri" to "elections", "alegerile" to "elections", "prezidentiale" to "presidential", "parlamentare" to "parliamentary",
        "guvern" to "government", "guvernul" to "government", "guvernului" to "government",
        "parlament" to "parliament", "parlamentul" to "parliament",
        "bursa" to "stock_market", "actiuni" to "equities", "actiunile" to "equities",
        "petrol" to "oil_energy", "energie" to "oil_energy", "gaze" to "natural_gas",
        "cutremur" to "earthquake", "seism" to "earthquake"
    )

    private val genericGeoEntities = setOf(
        "usa", "eu", "romania", "romaniei", "uk", "world", "europe", "europa"
    )

    private data class ArticleSignature(
        val article: NewsArticle,
        val profile: MediaOutletProfile,
        val framing: ArticleFramingTag,
        val anchorEntities: Set<String>,
        val displayEntities: List<String>,
        val tokens: Set<String>,
        val timestampSeconds: Double
    )

    data class ClusteringOutput(
        val clusters: List<StoryCluster>,
        val byArticleLink: Map<String, StoryCluster>
    )

    fun clusterArticles(
        articles: List<NewsArticle>,
        registry: MediaIntelligenceRegistry = MediaIntelligenceRegistry.shared
    ): ClusteringOutput {
        if (articles.isEmpty()) return ClusteringOutput(emptyList(), emptyMap())

        val uniqueArticles = ArrayList<NewsArticle>(articles.size)
        val seenLinks = HashSet<String>(articles.size)
        for (art in articles) {
            val key = art.link.trim()
            if (key.isNotEmpty() && seenLinks.add(key)) {
                uniqueArticles.add(art)
            }
        }

        val signatures = uniqueArticles.map { buildSignature(it, registry) }
        val groups = ArrayList<MutableList<ArticleSignature>>()
        val maxWindowSeconds = 48.0 * 3600.0

        for (sig in signatures) {
            var bestGroupIdx = -1
            var bestScore = 0.0

            for ((gIdx, group) in groups.withIndex()) {
                val lead = group.firstOrNull() ?: continue
                if (abs(sig.timestampSeconds - lead.timestampSeconds) > maxWindowSeconds) continue

                var maxMemberScore = 0.0
                val limit = group.size.coerceAtMost(3)
                for (i in 0 until limit) {
                    val s = similarity(sig, group[i])
                    if (s > maxMemberScore) maxMemberScore = s
                }
                if (maxMemberScore > bestScore) {
                    bestScore = maxMemberScore
                    bestGroupIdx = gIdx
                }
            }

            if (bestGroupIdx >= 0) {
                groups[bestGroupIdx].add(sig)
            } else {
                groups.add(mutableListOf(sig))
            }
        }

        val builtClusters = ArrayList<StoryCluster>(groups.size)
        val linkLookup = HashMap<String, StoryCluster>(uniqueArticles.size * 2)

        for (group in groups) {
            val cluster = assembleCluster(group, emptyList(), registry, isExpanded = false)
            builtClusters.add(cluster)
            for (member in group) {
                linkLookup[member.article.link] = cluster
            }
            for (item in cluster.items) {
                linkLookup.putIfAbsent(item.article.link, cluster)
            }
        }

        val sortedClusters = builtClusters.sortedWith(
            compareByDescending<StoryCluster> { it.hasMultipleSources }
                .thenByDescending { it.uniqueOutletCount }
                .thenByDescending { it.latestPublishDateMillis }
        )

        return ClusteringOutput(sortedClusters, linkLookup)
    }

    fun mergeExpandedArticles(
        baseCluster: StoryCluster,
        discovered: List<NewsArticle>,
        registry: MediaIntelligenceRegistry = MediaIntelligenceRegistry.shared
    ): StoryCluster {
        if (discovered.isEmpty()) return baseCluster

        val leadSig = buildSignature(baseCluster.leadArticle, registry)
        val existingLinks = baseCluster.items.mapTo(HashSet()) { it.article.link }
        val existingTitleKeys = baseCluster.items.mapTo(HashSet()) {
            MediaIntelligenceRegistry.normalizeLookupKey(it.article.title.take(60))
        }

        val acceptedExternal = ArrayList<ClusterCoverageItem>()

        for (candidate in discovered) {
            if (candidate.link.isBlank() || !existingLinks.add(candidate.link)) continue
            val titleKey = MediaIntelligenceRegistry.normalizeLookupKey(candidate.title.take(60))
            if (titleKey.isEmpty() || !existingTitleKeys.add(titleKey)) continue

            val candSig = buildSignature(candidate, registry)
            val sharedEntities = leadSig.anchorEntities.intersect(candSig.anchorEntities)
            val sharedTokens = leadSig.tokens.intersect(candSig.tokens)

            if (sharedEntities.isNotEmpty() || sharedTokens.size >= 2) {
                acceptedExternal.add(
                    ClusterCoverageItem(
                        article = candidate,
                        profile = candSig.profile,
                        framing = candSig.framing,
                        isExternalDiscovery = true
                    )
                )
            }
        }

        val baseSigs = baseCluster.items
            .filter { !it.isExternalDiscovery }
            .map { buildSignature(it.article, registry) }
        val priorExternal = baseCluster.items.filter { it.isExternalDiscovery }

        return assembleCluster(
            group = baseSigs.ifEmpty { listOf(leadSig) },
            externalItems = priorExternal + acceptedExternal,
            registry = registry,
            isExpanded = true,
            preserveId = baseCluster.id
        )
    }

    fun makeSeedCluster(
        article: NewsArticle,
        registry: MediaIntelligenceRegistry = MediaIntelligenceRegistry.shared
    ): StoryCluster {
        val sig = buildSignature(article, registry)
        return assembleCluster(listOf(sig), emptyList(), registry, isExpanded = false)
    }

    fun buildDiscoveryQuery(article: NewsArticle): Pair<String, Boolean> {
        val isRo = detectRomanian("${article.title} ${article.description ?: ""}", article.link)
        val sig = buildSignature(article, MediaIntelligenceRegistry.shared)

        val terms = ArrayList<String>()
        for (ent in sig.displayEntities) {
            if (terms.size < 4 && ent.length >= 2) {
                terms.add(ent)
            }
        }
        if (terms.size < 4) {
            val titleWords = extractRawWords(article.title)
            for (w in titleWords) {
                val lower = foldDiacritics(w).lowercase(Locale.ROOT)
                if (lower.length >= 4 && lower !in stopWords && terms.none { it.equals(w, ignoreCase = true) }) {
                    terms.add(w)
                    if (terms.size >= 5) break
                }
            }
        }

        val finalQuery = if (terms.isEmpty()) article.title.take(55) else terms.take(5).joinToString(" ")
        return finalQuery to isRo
    }

    fun detectRomanian(text: String, url: String = ""): Boolean {
        val lowerUrl = url.lowercase(Locale.ROOT)
        if (lowerUrl.contains(".ro/") || lowerUrl.endsWith(".ro")) return true
        val roChars = "ăâîșțĂÂÎȘȚşţ"
        if (text.any { it in roChars }) return true
        val lower = " ${text.lowercase(Locale.ROOT)} "
        val roMarkers = listOf(" pentru ", " care ", " este ", " sunt ", " după ", " prin ", " guvernul ", " românia ")
        val hits = roMarkers.count { lower.contains(it) }
        return hits >= 2
    }

    fun computeBlindspot(
        distribution: BiasDistribution,
        uniqueOutlets: Int,
        roCount: Int = 0,
        intlCount: Int = 0
    ): BlindspotType {
        val rated = distribution.ratedPoliticalCount
        if (rated >= 3) {
            if (distribution.leftFraction >= 0.65f && distribution.rightFraction <= 0.10f && distribution.leftCount >= 2) {
                return BlindspotType.LowRightCoverage
            }
            if (distribution.rightFraction >= 0.65f && distribution.leftFraction <= 0.10f && distribution.rightCount >= 2) {
                return BlindspotType.LowLeftCoverage
            }
        }
        if (uniqueOutlets >= 4) {
            if (intlCount >= 4 && roCount == 0) return BlindspotType.UncoveredLocally
            if (roCount >= 4 && intlCount == 0) return BlindspotType.DomesticOnlyFocus
        }
        return BlindspotType.None
    }

    private fun assembleCluster(
        group: List<ArticleSignature>,
        externalItems: List<ClusterCoverageItem>,
        registry: MediaIntelligenceRegistry,
        isExpanded: Boolean,
        preserveId: String? = null
    ): StoryCluster {
        val sortedGroup = group.sortedWith(
            compareByDescending<ArticleSignature> { !it.article.imageUrl.isNullOrBlank() }
                .thenByDescending { it.profile.factuality.numericScore }
                .thenByDescending { it.timestampSeconds }
        )

        val leadSig = sortedGroup.first()
        val allItems = ArrayList<ClusterCoverageItem>()
        val seenLinks = HashSet<String>()

        for (sig in sortedGroup) {
            if (seenLinks.add(sig.article.link)) {
                allItems.add(
                    ClusterCoverageItem(
                        article = sig.article,
                        profile = sig.profile,
                        framing = sig.framing,
                        isExternalDiscovery = false
                    )
                )
            }
            sig.article.googleNewsSiblings?.forEach { sib ->
                if (seenLinks.add(sib.link)) {
                    val sibProfile = registry.resolve(url = sib.link, publicationName = sib.publicationName)
                    val sibArticle = NewsArticle(
                        id = sib.link,
                        title = sib.title,
                        link = sib.link,
                        publishDate = sib.publishDateMillis ?: sig.article.publishDate,
                        imageUrl = null,
                        description = null,
                        content = null,
                        author = null,
                        publicationName = sib.publicationName,
                        publicationIconUrl = "https://www.google.com/s2/favicons?domain=${sibProfile.domain}&sz=64",
                        category = sig.article.category
                    )
                    val sibFraming = ArticleFramingAnalyzer.classify(title = sib.title, link = sib.link, profile = sibProfile)
                    allItems.add(
                        ClusterCoverageItem(
                            article = sibArticle,
                            profile = sibProfile,
                            framing = sibFraming,
                            isExternalDiscovery = false
                        )
                    )
                }
            }
        }

        for (ext in externalItems) {
            if (seenLinks.add(ext.article.link)) {
                allItems.add(ext)
            }
        }

        val uniqueOutlets = LinkedHashMap<String, MediaOutletProfile>()
        for (item in allItems) {
            val outletKey = if (item.profile.bias == MediaBias.Unrated) {
                MediaIntelligenceRegistry.normalizeLookupKey(item.article.publicationName ?: item.profile.domain)
            } else {
                item.profile.domain
            }
            val safeKey = outletKey.ifEmpty { item.article.link }
            uniqueOutlets.putIfAbsent(safeKey, item.profile)
        }

        var left = 0
        var center = 0
        var right = 0
        var independent = 0
        var unrated = 0
        var roCount = 0
        var intlCount = 0

        for (profile in uniqueOutlets.values) {
            when (profile.bias.bucket) {
                MediaBias.SpectrumBucket.Left -> left++
                MediaBias.SpectrumBucket.Center -> center++
                MediaBias.SpectrumBucket.Right -> right++
                MediaBias.SpectrumBucket.Independent -> independent++
                MediaBias.SpectrumBucket.Unrated -> unrated++
            }
            if (profile.countryCode == "RO") {
                roCount++
            } else if (profile.countryCode != "INT") {
                intlCount++
            }
        }

        val dist = BiasDistribution(
            leftCount = left,
            centerCount = center,
            rightCount = right,
            independentCount = independent,
            unratedCount = unrated
        )

        val outletCount = uniqueOutlets.size
        val blindspot = computeBlindspot(dist, outletCount, roCount, intlCount)

        val entityFreq = HashMap<String, Int>()
        for (sig in group) {
            for (e in sig.displayEntities) {
                entityFreq[e] = (entityFreq[e] ?: 0) + 1
            }
        }
        val topEntities = entityFreq.entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenByDescending { it.key.length })
            .take(5)
            .map { it.key }

        val latestMillis = allItems.maxOfOrNull { it.article.publishDate } ?: leadSig.article.publishDate
        val hashEntities = topEntities.ifEmpty { leadSig.tokens.take(4) }
        val clusterId = preserveId ?: StoryCluster.makeDeterministicHash(hashEntities, latestMillis)

        return StoryCluster(
            id = clusterId,
            leadArticle = leadSig.article,
            items = allItems,
            uniqueOutletCount = outletCount,
            distribution = dist,
            blindspot = blindspot,
            anchorEntities = topEntities,
            latestPublishDateMillis = latestMillis,
            isExpandedExternally = isExpanded
        )
    }

    private fun similarity(a: ArticleSignature, b: ArticleSignature): Double {
        val sameOutlet = (a.profile.domain == b.profile.domain && a.profile.bias != MediaBias.Unrated)
        if (sameOutlet) return 0.0

        val sharedEntities = a.anchorEntities.intersect(b.anchorEntities)
        val specificSharedEntities = sharedEntities - genericGeoEntities
        val sharedTokens = a.tokens.intersect(b.tokens)

        if (specificSharedEntities.isEmpty() && sharedTokens.size < 3) {
            return 0.0
        }

        val entTotal = a.anchorEntities.size + b.anchorEntities.size
        val entDice = if (entTotal > 0) (2.0 * sharedEntities.size.toDouble()) / entTotal.toDouble() else 0.0

        val tokTotal = a.tokens.size + b.tokens.size
        val tokDice = if (tokTotal > 0) (2.0 * sharedTokens.size.toDouble()) / tokTotal.toDouble() else 0.0

        val dtHours = abs(a.timestampSeconds - b.timestampSeconds) / 3600.0
        val timeDecay = exp(-dtHours / 36.0)

        val rawScore = (0.55 * entDice + 0.45 * tokDice) * timeDecay

        if (specificSharedEntities.size >= 2 && sharedTokens.size >= 2 && rawScore >= 0.26) return rawScore
        if (specificSharedEntities.isNotEmpty() && sharedTokens.size >= 3 && rawScore >= 0.30) return rawScore
        if (specificSharedEntities.isNotEmpty() && sharedTokens.size >= 2 && rawScore >= 0.36) return rawScore
        if (tokDice >= 0.52 && timeDecay >= 0.65) return rawScore
        return 0.0
    }

    private fun preprocessHeadlineText(text: String): String {
        var working = foldDiacritics(text)
        working = decimalNumberRegex.replace(working, "$1_$2")
        for ((pattern, repl) in phraseReplacements) {
            working = pattern.replace(working, repl)
        }
        return working
    }

    private fun buildSignature(
        article: NewsArticle,
        registry: MediaIntelligenceRegistry
    ): ArticleSignature {
        val profile = registry.resolve(article)
        val framing = ArticleFramingAnalyzer.classify(
            title = article.title,
            description = article.description,
            link = article.link,
            profile = profile
        )

        val normalizedTitle = preprocessHeadlineText(article.title)
        val titleWords = extractRawWords(normalizedTitle)
        val rawDisplayWords = extractRawWords(article.title)
        val anchorSet = HashSet<String>()
        val displayEntities = ArrayList<String>(6)

        for (word in rawDisplayWords) {
            val clean = word.trim { !it.isLetterOrDigit() }
            if (clean.length < 2) continue
            val folded = foldDiacritics(clean).lowercase(Locale.ROOT)
            val isAllCaps = clean.length >= 2 && clean == clean.uppercase(Locale.ROOT) && clean.any { it.isLetter() }
            val startsUpper = clean.first().isUpperCase()
            if ((isAllCaps || startsUpper) && folded !in sentenceInitialIgnore && folded !in stopWords) {
                if (displayEntities.size < 6 && displayEntities.none { it.equals(clean, ignoreCase = true) }) {
                    displayEntities.add(clean)
                }
            }
        }

        for ((idx, word) in titleWords.withIndex()) {
            val clean = word.trim { !it.isLetterOrDigit() && it != '_' }
            if (clean.length < 2) continue
            val folded = foldDiacritics(clean).lowercase(Locale.ROOT)

            if (clean.any { it.isDigit() } && clean.length >= 2) {
                anchorSet.add(folded)
                continue
            }

            val isAllCaps = clean.length >= 2 && clean == clean.uppercase(Locale.ROOT) && clean.any { it.isLetter() }
            val startsUpper = clean.first().isUpperCase()
            if (isAllCaps || (startsUpper && !(idx == 0 && folded in sentenceInitialIgnore))) {
                if (folded !in stopWords) {
                    val canonical = canonicalizeToken(folded)
                    if (canonical.length >= 2) {
                        anchorSet.add(canonical)
                    }
                }
            }
        }

        val tokenSet = HashSet<String>()
        for (word in titleWords) {
            val lowerWord = foldDiacritics(word).lowercase(Locale.ROOT)
            val norm = canonicalizeToken(lowerWord)
            if (norm.length >= 3 && norm !in stopWords) {
                tokenSet.add(norm)
                if (bilingualSynonyms.containsKey(lowerWord) && norm.length <= 5) {
                    anchorSet.add(norm)
                }
            }
        }
        val desc = article.description
        if (!desc.isNullOrBlank()) {
            val descWords = extractRawWords(preprocessHeadlineText(desc.take(180)))
            for (word in descWords) {
                val lowerWord = foldDiacritics(word).lowercase(Locale.ROOT)
                val norm = canonicalizeToken(lowerWord)
                if (norm.length >= 3 && norm !in stopWords) {
                    tokenSet.add(norm)
                    bilingualSynonyms[lowerWord]?.let { anchorSet.add(it) }
                }
            }
        }

        return ArticleSignature(
            article = article,
            profile = profile,
            framing = framing,
            anchorEntities = anchorSet,
            displayEntities = displayEntities,
            tokens = tokenSet,
            timestampSeconds = article.publishDate.toDouble() / 1000.0
        )
    }

    private fun extractRawWords(text: String): List<String> =
        nonWordSplitRegex.split(text).filter { it.isNotEmpty() }

    private fun foldDiacritics(text: String): String {
        val pre = text
            .replace("ș", "s").replace("Ș", "S")
            .replace("ț", "t").replace("Ț", "T")
            .replace("ş", "s").replace("Ş", "S")
            .replace("ţ", "t").replace("Ţ", "T")
            .replace("ă", "a").replace("Ă", "A")
            .replace("â", "a").replace("Â", "A")
            .replace("î", "i").replace("Î", "I")
        val norm = Normalizer.normalize(pre, Normalizer.Form.NFD)
        return diacriticMarksRegex.replace(norm, "")
    }

    private fun canonicalizeToken(lowerFolded: String): String {
        bilingualSynonyms[lowerFolded]?.let { return it }
        var stem = lowerFolded
        for (suffix in listOf("urilor", "iilor", "elor", "ilor", "ului", "escu", "atie", "atia", "ing", "tion", "ment")) {
            if (stem.length > suffix.length + 4 && stem.endsWith(suffix)) {
                stem = stem.dropLast(suffix.length)
                break
            }
        }
        when {
            stem.length > 5 && stem.endsWith("ul") -> stem = stem.dropLast(2)
            stem.length > 5 && stem.endsWith("le") -> stem = stem.dropLast(2)
            stem.length > 5 && stem.endsWith("es") -> stem = stem.dropLast(2)
            stem.length > 4 && stem.endsWith("s") && !stem.endsWith("ss") -> stem = stem.dropLast(1)
        }
        return bilingualSynonyms[stem] ?: stem
    }
}
