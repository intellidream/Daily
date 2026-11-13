import Foundation

/// High-speed (< 5 ms for 250 items), deterministic bilingual (`RO` + `EN`) story clustering,
/// bias distribution, and blindspot detection engine. Runs strictly off the main thread.
public enum StoryClusterEngine {

    // MARK: - Stop Words & Bilingual Canonical Bridge

    private static let stopWords: Set<String> = [
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
    ]

    /// Multi-word bilingual institutional & topic phrases collapsed before tokenizing.
    private static let phraseReplacements: [(pattern: String, replacement: String)] = [
        ("european central bank", "ECB"),
        ("banca centrala europeana", "ECB"),
        ("banca nationala a romaniei", "BNR"),
        ("banca nationala", "BNR"),
        ("federal reserve", "FED"),
        ("curtea constitutionala", "CCR"),
        ("comisia europeana", "EU_COMMISSION"),
        ("european commission", "EU_COMMISSION"),
        ("uniunea europeana", "EU"),
        ("european union", "EU"),
        ("zona euro", "Eurozone"),
        ("euro area", "Eurozone"),
        ("white house", "WhiteHouse"),
        ("casa alba", "WhiteHouse"),
        ("supreme court", "SupremeCourt"),
        ("world bank", "WorldBank"),
        ("banca mondiala", "WorldBank"),
        ("fondul monetar international", "IMF"),
        ("international monetary fund", "IMF")
    ]

    private static let sentenceInitialIgnore: Set<String> = [
        "the", "a", "an", "in", "on", "at", "to", "for", "of", "by", "as", "is", "are", "why", "how", "what", "who", "when", "where",
        "în", "in", "la", "pe", "cu", "de", "din", "spre", "sub", "după", "dupa", "cum", "ce", "cine", "când", "cand", "unde",
        "un", "o", "doi", "două", "doua", "trei", "mai", "tot", "toți", "toti", "toate", "fără", "fara", "peste", "prin"
    ]

    /// Maps Romanian & English geopolitical/economic synonyms and acronyms to shared canonical tokens.
    private static let bilingualSynonyms: [String: String] = [
        "sua": "usa", "american": "usa", "americane": "usa", "washington": "usa",
        "ue": "eu", "uniunea": "eu", "bruxelles": "brussels", "comisia": "eu_commission",
        "ucraina": "ukraine", "ucrainei": "ukraine", "kiev": "kyiv", "zelenski": "zelensky",
        "rusia": "russia", "rusiei": "russia", "moscova": "moscow",
        "germania": "germany", "germaniei": "germany",
        "franta": "france", "frantei": "france",
        "marea": "uk", "londra": "london",
        "ungaria": "hungary", "budapesta": "budapest",
        "republica": "moldova_rep", "chisinau": "chisinau",
        "bce": "ecb", "ecb": "ecb", "fmi": "imf", "imf": "imf", "onu": "un", "otan": "nato", "bnr": "bnr", "fed": "fed",
        "csat": "csat", "anaf": "anaf", "pnrr": "pnrr", "ccr": "ccr", "pib": "gdp", "gdp": "gdp",
        "dobanda": "interest_rate", "dobanzi": "interest_rate", "dobanzile": "interest_rate",
        "dobanzii": "interest_rate", "rate": "interest_rate", "rates": "interest_rate",
        "reduce": "cut", "scade": "cut", "scaderea": "slowdown", "scaderii": "slowdown", "cooling": "slowdown", "lowers": "cut", "cuts": "cut",
        "inflatie": "inflation", "inflatia": "inflation", "inflatiei": "inflation",
        "buget": "budget", "bugetul": "budget", "deficit": "deficit", "deficitul": "deficit",
        "taxe": "taxes", "impozit": "taxes", "impozite": "taxes", "fiscal": "fiscal", "fiscale": "fiscal",
        "tarife": "tariffs", "tarifele": "tariffs", "vamale": "tariffs",
        "alegeri": "elections", "alegerile": "elections", "prezidentiale": "presidential", "parlamentare": "parliamentary",
        "guvern": "government", "guvernul": "government", "guvernului": "government",
        "parlament": "parliament", "parlamentul": "parliament",
        "bursa": "stock_market", "actiuni": "equities", "actiunile": "equities",
        "petrol": "oil_energy", "energie": "oil_energy", "gaze": "natural_gas",
        "cutremur": "earthquake", "seism": "earthquake"
    ]

    private static let genericGeoEntities: Set<String> = [
        "usa", "eu", "romania", "romaniei", "uk", "world", "europe", "europa"
    ]

    // MARK: - Internal Signature

    private struct ArticleSignature: Sendable {
        let article: NewsArticle
        let profile: MediaOutletProfile
        let framing: ArticleFramingTag
        let anchorEntities: Set<String>
        let displayEntities: [String]
        let tokens: Set<String>
        let timestamp: TimeInterval
    }

    public struct ClusteringOutput: Sendable {
        public let clusters: [StoryCluster]
        public let byArticleLink: [String: StoryCluster]

        public init(clusters: [StoryCluster], byArticleLink: [String: StoryCluster]) {
            self.clusters = clusters
            self.byArticleLink = byArticleLink
        }
    }

    // MARK: - Primary Clustering Entry Point

    public static func clusterArticles(
        _ articles: [NewsArticle],
        registry: MediaIntelligenceRegistry = .shared
    ) -> ClusteringOutput {
        guard !articles.isEmpty else {
            return ClusteringOutput(clusters: [], byArticleLink: [:])
        }

        // Deduplicate by link preserving chronological priority
        var uniqueArticles: [NewsArticle] = []
        uniqueArticles.reserveCapacity(articles.count)
        var seenLinks = Set<String>()
        for art in articles {
            let key = art.link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && seenLinks.insert(key).inserted {
                uniqueArticles.append(art)
            }
        }

        let signatures: [ArticleSignature] = uniqueArticles.map { buildSignature(for: $0, registry: registry) }

        // Group using single-pass greedy agglomerative matching over 48h window
        var groups: [[ArticleSignature]] = []
        let maxWindowSeconds: TimeInterval = 48 * 3600

        for sig in signatures {
            var bestGroupIdx: Int? = nil
            var bestScore: Double = 0.0

            for (gIdx, group) in groups.enumerated() {
                guard let lead = group.first else { continue }
                let dt = abs(sig.timestamp - lead.timestamp)
                if dt > maxWindowSeconds { continue }

                // Compare against lead and up to 2 additional members for stability
                var maxMemberScore = 0.0
                for candidate in group.prefix(3) {
                    let s = similarity(sig, candidate)
                    if s > maxMemberScore {
                        maxMemberScore = s
                    }
                }

                if maxMemberScore > bestScore {
                    bestScore = maxMemberScore
                    bestGroupIdx = gIdx
                }
            }

            if let idx = bestGroupIdx {
                groups[idx].append(sig)
            } else {
                groups.append([sig])
            }
        }

        var builtClusters: [StoryCluster] = []
        builtClusters.reserveCapacity(groups.count)
        var linkLookup: [String: StoryCluster] = [:]

        for group in groups {
            let cluster = assembleCluster(from: group, externalItems: [], registry: registry, isExpanded: false)
            builtClusters.append(cluster)
            for member in group {
                linkLookup[member.article.link] = cluster
            }
            for item in cluster.items {
                if linkLookup[item.article.link] == nil {
                    linkLookup[item.article.link] = cluster
                }
            }
        }

        // Sort clusters: multi-source major stories first (by outlet count & recency), then chronological
        let sortedClusters = builtClusters.sorted { lhs, rhs in
            if lhs.hasMultipleSources != rhs.hasMultipleSources {
                return lhs.hasMultipleSources
            }
            if lhs.uniqueOutletCount != rhs.uniqueOutletCount {
                return lhs.uniqueOutletCount > rhs.uniqueOutletCount
            }
            return lhs.latestPublishDate > rhs.latestPublishDate
        }

        return ClusteringOutput(clusters: sortedClusters, byArticleLink: linkLookup)
    }

    // MARK: - On-Demand Cross-Spectrum Merge

    public static func mergeExpandedArticles(
        into baseCluster: StoryCluster,
        discovered: [NewsArticle],
        registry: MediaIntelligenceRegistry = .shared
    ) -> StoryCluster {
        guard !discovered.isEmpty else { return baseCluster }

        let leadSig = buildSignature(for: baseCluster.leadArticle, registry: registry)
        var existingLinks = Set(baseCluster.items.map(\.article.link))
        var existingTitleKeys = Set(baseCluster.items.map { MediaIntelligenceRegistry.normalizeLookupKey(String($0.article.title.prefix(60))) })

        var acceptedExternal: [ClusterCoverageItem] = []

        for candidate in discovered {
            guard !candidate.link.isEmpty, existingLinks.insert(candidate.link).inserted else { continue }
            let titleKey = MediaIntelligenceRegistry.normalizeLookupKey(String(candidate.title.prefix(60)))
            guard !titleKey.isEmpty, existingTitleKeys.insert(titleKey).inserted else { continue }

            let candSig = buildSignature(for: candidate, registry: registry)
            let sharedEntities = leadSig.anchorEntities.intersection(candSig.anchorEntities)
            let sharedTokens = leadSig.tokens.intersection(candSig.tokens)

            // Accept if search result shares at least 1 anchor entity or >= 2 content tokens with the lead story
            if !sharedEntities.isEmpty || sharedTokens.count >= 2 {
                acceptedExternal.append(
                    ClusterCoverageItem(
                        article: candidate,
                        profile: candSig.profile,
                        framing: candSig.framing,
                        isExternalDiscovery: true
                    )
                )
            }
        }

        let baseSigs = baseCluster.items
            .filter { !$0.isExternalDiscovery }
            .map { buildSignature(for: $0.article, registry: registry) }
        let priorExternal = baseCluster.items.filter { $0.isExternalDiscovery }

        return assembleCluster(
            from: baseSigs.isEmpty ? [leadSig] : baseSigs,
            externalItems: priorExternal + acceptedExternal,
            registry: registry,
            isExpanded: true,
            preserveId: baseCluster.id
        )
    }

    /// Builds a single-article seed `StoryCluster` when opening Perspectives on an unclustered article (e.g. from Saved Articles).
    public static func makeSeedCluster(
        for article: NewsArticle,
        registry: MediaIntelligenceRegistry = .shared
    ) -> StoryCluster {
        let sig = buildSignature(for: article, registry: registry)
        return assembleCluster(from: [sig], externalItems: [], registry: registry, isExpanded: false)
    }

    // MARK: - Search Query & Language Extraction for On-Demand Expansion

    public static func buildDiscoveryQuery(for article: NewsArticle) -> (query: String, isRomanian: Bool) {
        let isRo = detectRomanian(text: "\(article.title) \(article.description ?? "")", url: article.link)
        let sig = buildSignature(for: article, registry: .shared)

        var terms: [String] = []
        for ent in sig.displayEntities {
            if terms.count < 4 && ent.count >= 2 {
                terms.append(ent)
            }
        }
        if terms.count < 4 {
            let titleWords = extractRawWords(from: article.title)
            for w in titleWords {
                let lower = foldDiacritics(w).lowercased()
                if lower.count >= 4 && !stopWords.contains(lower) && !terms.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) {
                    terms.append(w)
                    if terms.count >= 5 { break }
                }
            }
        }

        let finalQuery = terms.isEmpty ? String(article.title.prefix(55)) : terms.prefix(5).joined(separator: " ")
        return (finalQuery, isRo)
    }

    public static func detectRomanian(text: String, url: String = "") -> Bool {
        if url.lowercased().contains(".ro/") || url.lowercased().hasSuffix(".ro") {
            return true
        }
        let roChars = CharacterSet(charactersIn: "ăâîșțĂÂÎȘȚşţ")
        if text.rangeOfCharacter(from: roChars) != nil {
            return true
        }
        let lower = " " + text.lowercased() + " "
        let roMarkers = [" pentru ", " care ", " este ", " sunt ", " după ", " prin ", " guvernul ", " românia "]
        var hits = 0
        for m in roMarkers where lower.contains(m) {
            hits += 1
        }
        return hits >= 2
    }

    // MARK: - Private Assembly & Similarity Math

    private static func assembleCluster(
        from group: [ArticleSignature],
        externalItems: [ClusterCoverageItem],
        registry: MediaIntelligenceRegistry,
        isExpanded: Bool,
        preserveId: String? = nil
    ) -> StoryCluster {
        // Choose highest-factuality / richest lead article
        let sortedGroup = group.sorted { lhs, rhs in
            if lhs.article.imageUrl != nil && rhs.article.imageUrl == nil { return true }
            if lhs.article.imageUrl == nil && rhs.article.imageUrl != nil { return false }
            if lhs.profile.factuality.numericScore != rhs.profile.factuality.numericScore {
                return lhs.profile.factuality.numericScore > rhs.profile.factuality.numericScore
            }
            return lhs.timestamp > rhs.timestamp
        }

        let leadSig = sortedGroup[0]
        var allItems: [ClusterCoverageItem] = []
        var seenLinks = Set<String>()

        for sig in sortedGroup {
            if seenLinks.insert(sig.article.link).inserted {
                allItems.append(ClusterCoverageItem(
                    article: sig.article,
                    profile: sig.profile,
                    framing: sig.framing,
                    isExternalDiscovery: false
                ))
            }
            // Unpack Google News `<ol><li>` siblings if present
            if let siblings = sig.article.googleNewsSiblings {
                for sib in siblings {
                    guard seenLinks.insert(sib.link).inserted else { continue }
                    let sibProfile = registry.resolve(url: sib.link, publicationName: sib.publicationName)
                    let sibArticle = NewsArticle(
                        id: sib.link,
                        title: sib.title,
                        link: sib.link,
                        publishDate: sib.publishDate ?? sig.article.publishDate,
                        imageUrl: nil,
                        description: nil,
                        content: nil,
                        author: nil,
                        publicationName: sib.publicationName,
                        publicationIconUrl: "https://www.google.com/s2/favicons?domain=\(sibProfile.domain)&sz=64",
                        category: sig.article.category
                    )
                    let sibFraming = ArticleFramingAnalyzer.classify(title: sib.title, link: sib.link, profile: sibProfile)
                    allItems.append(ClusterCoverageItem(
                        article: sibArticle,
                        profile: sibProfile,
                        framing: sibFraming,
                        isExternalDiscovery: false
                    ))
                }
            }
        }

        for ext in externalItems {
            if seenLinks.insert(ext.article.link).inserted {
                allItems.append(ext)
            }
        }

        // Compute unique outlet distribution (1 vote per distinct outlet domain/name)
        var uniqueOutlets: [String: MediaOutletProfile] = [:]
        for item in allItems {
            let outletKey = item.profile.bias == .unrated
                ? MediaIntelligenceRegistry.normalizeLookupKey(item.article.publicationName ?? item.profile.domain)
                : item.profile.domain
            let safeKey = outletKey.isEmpty ? item.article.link : outletKey
            if uniqueOutlets[safeKey] == nil {
                uniqueOutlets[safeKey] = item.profile
            }
        }

        var left = 0
        var center = 0
        var right = 0
        var independent = 0
        var unrated = 0
        var roCount = 0
        var intlCount = 0

        for profile in uniqueOutlets.values {
            switch profile.bias.bucket {
            case .left: left += 1
            case .center: center += 1
            case .right: right += 1
            case .independent: independent += 1
            case .unrated: unrated += 1
            }
            if profile.countryCode == "RO" {
                roCount += 1
            } else if profile.countryCode != "INT" {
                intlCount += 1
            }
        }

        let dist = BiasDistribution(
            leftCount: left,
            centerCount: center,
            rightCount: right,
            independentCount: independent,
            unratedCount: unrated
        )

        let outletCount = uniqueOutlets.count
        let blindspot = computeBlindspot(distribution: dist, uniqueOutlets: outletCount, roCount: roCount, intlCount: intlCount)

        // Collect top anchor entities
        var entityFreq: [String: Int] = [:]
        for sig in group {
            for e in sig.displayEntities {
                entityFreq[e, default: 0] += 1
            }
        }
        let topEntities = entityFreq
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.count > rhs.key.count
            }
            .prefix(5)
            .map(\.key)

        let latestDate = allItems.map(\.article.publishDate).max() ?? leadSig.article.publishDate
        let hashEntities = topEntities.isEmpty ? Array(leadSig.tokens.prefix(4)) : topEntities
        let clusterId = preserveId ?? StoryCluster.makeDeterministicHash(entities: hashEntities, referenceDate: latestDate)

        return StoryCluster(
            id: clusterId,
            leadArticle: leadSig.article,
            items: allItems,
            uniqueOutletCount: outletCount,
            distribution: dist,
            blindspot: blindspot,
            anchorEntities: topEntities,
            latestPublishDate: latestDate,
            isExpandedExternally: isExpanded
        )
    }

    public static func computeBlindspot(
        distribution: BiasDistribution,
        uniqueOutlets: Int,
        roCount: Int = 0,
        intlCount: Int = 0
    ) -> BlindspotType {
        let rated = distribution.ratedPoliticalCount
        if rated >= 3 {
            if distribution.leftFraction >= 0.65 && distribution.rightFraction <= 0.10 && distribution.leftCount >= 2 {
                return .lowRightCoverage
            }
            if distribution.rightFraction >= 0.65 && distribution.leftFraction <= 0.10 && distribution.rightCount >= 2 {
                return .lowLeftCoverage
            }
        }
        if uniqueOutlets >= 4 {
            if intlCount >= 4 && roCount == 0 {
                return .uncoveredLocally
            }
            if roCount >= 4 && intlCount == 0 {
                return .domesticOnlyFocus
            }
        }
        return .none
    }

    private static func similarity(_ a: ArticleSignature, _ b: ArticleSignature) -> Double {
        // Avoid clustering two articles from the exact same publication unless virtually identical
        let sameOutlet = (a.profile.domain == b.profile.domain && a.profile.bias != .unrated)
        if sameOutlet { return 0.0 }

        let sharedEntities = a.anchorEntities.intersection(b.anchorEntities)
        let specificSharedEntities = sharedEntities.subtracting(genericGeoEntities)
        let sharedTokens = a.tokens.intersection(b.tokens)

        // Strict entity guard to prevent false-positive topic merges
        if specificSharedEntities.isEmpty && sharedTokens.count < 3 {
            return 0.0
        }

        let entTotal = a.anchorEntities.count + b.anchorEntities.count
        let entDice = entTotal > 0 ? (2.0 * Double(sharedEntities.count)) / Double(entTotal) : 0.0

        let tokTotal = a.tokens.count + b.tokens.count
        let tokDice = tokTotal > 0 ? (2.0 * Double(sharedTokens.count)) / Double(tokTotal) : 0.0

        let dtHours = abs(a.timestamp - b.timestamp) / 3600.0
        let timeDecay = exp(-dtHours / 36.0)

        let rawScore = (0.55 * entDice + 0.45 * tokDice) * timeDecay

        if specificSharedEntities.count >= 2 && sharedTokens.count >= 2 && rawScore >= 0.26 {
            return rawScore
        }
        if specificSharedEntities.count >= 1 && sharedTokens.count >= 3 && rawScore >= 0.30 {
            return rawScore
        }
        if specificSharedEntities.count >= 1 && sharedTokens.count >= 2 && rawScore >= 0.36 {
            return rawScore
        }
        if tokDice >= 0.52 && timeDecay >= 0.65 {
            return rawScore
        }
        return 0.0
    }

    private static func preprocessHeadlineText(_ text: String) -> String {
        var working = foldDiacritics(text)
        // Unify decimal numbers (e.g., 2,25% or 2.25% -> 2_25) so RO & EN numeric figures match identically
        if let decRegex = try? NSRegularExpression(pattern: #"(\d+)[.,](\d+)"#) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            working = decRegex.stringByReplacingMatches(in: working, range: range, withTemplate: "$1_$2")
        }
        for item in phraseReplacements {
            working = working.replacingOccurrences(
                of: item.pattern,
                with: item.replacement,
                options: [.caseInsensitive]
            )
        }
        return working
    }

    private static func buildSignature(
        for article: NewsArticle,
        registry: MediaIntelligenceRegistry
    ) -> ArticleSignature {
        let profile = registry.resolve(for: article)
        let framing = ArticleFramingAnalyzer.classify(
            title: article.title,
            description: article.description,
            link: article.link,
            profile: profile
        )

        let normalizedTitle = preprocessHeadlineText(article.title)
        let titleWords = extractRawWords(from: normalizedTitle)
        let rawDisplayWords = extractRawWords(from: article.title)
        var anchorSet = Set<String>()
        var displayEntities: [String] = []

        for word in rawDisplayWords {
            let clean = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard clean.count >= 2 else { continue }
            let folded = foldDiacritics(clean).lowercased()
            let isAllCaps = clean.count >= 2 && clean == clean.uppercased() && clean.rangeOfCharacter(from: .letters) != nil
            let startsUpper = clean.first?.isUppercase == true
            if (isAllCaps || startsUpper) && !sentenceInitialIgnore.contains(folded) && !stopWords.contains(folded) {
                if displayEntities.count < 6 && !displayEntities.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                    displayEntities.append(clean)
                }
            }
        }

        for (idx, word) in titleWords.enumerated() {
            let clean = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "_")))
            guard clean.count >= 2 else { continue }
            let folded = foldDiacritics(clean).lowercased()

            // Numbers / percentages / years (e.g. 2026, 2_25, 100)
            if clean.rangeOfCharacter(from: .decimalDigits) != nil && clean.count >= 2 {
                anchorSet.insert(folded)
                tokenSetPlaceholder: do {}
                continue
            }

            let isAllCaps = clean.count >= 2 && clean == clean.uppercased() && clean.rangeOfCharacter(from: .letters) != nil
            let startsUpper = clean.first?.isUppercase == true

            if isAllCaps || (startsUpper && !(idx == 0 && sentenceInitialIgnore.contains(folded))) {
                if !stopWords.contains(folded) {
                    let canonical = canonicalizeToken(folded)
                    if canonical.count >= 2 {
                        anchorSet.insert(canonical)
                    }
                }
            }
        }

        // Lexical tokens from title + short lead snippet
        var tokenSet = Set<String>()
        for word in titleWords {
            let norm = canonicalizeToken(foldDiacritics(word).lowercased())
            if norm.count >= 3 && !stopWords.contains(norm) {
                tokenSet.insert(norm)
                if bilingualSynonyms[foldDiacritics(word).lowercased()] != nil && norm.count <= 5 {
                    // Institutional acronyms mapped via synonym table also count as anchor entities
                    anchorSet.insert(norm)
                }
            }
        }
        if let desc = article.description, !desc.isEmpty {
            let descWords = extractRawWords(from: preprocessHeadlineText(String(desc.prefix(180))))
            for word in descWords {
                let norm = canonicalizeToken(foldDiacritics(word).lowercased())
                if norm.count >= 3 && !stopWords.contains(norm) {
                    tokenSet.insert(norm)
                    if let syn = bilingualSynonyms[foldDiacritics(word).lowercased()] {
                        anchorSet.insert(syn)
                    }
                }
            }
        }

        return ArticleSignature(
            article: article,
            profile: profile,
            framing: framing,
            anchorEntities: anchorSet,
            displayEntities: displayEntities,
            tokens: tokenSet,
            timestamp: article.publishDate.timeIntervalSince1970
        )
    }

    private static func extractRawWords(from text: String) -> [String] {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return text.components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
    }

    private static func foldDiacritics(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func canonicalizeToken(_ lowerFolded: String) -> String {
        if let mapped = bilingualSynonyms[lowerFolded] {
            return mapped
        }
        var stem = lowerFolded
        // Light Romanian & English suffix stemming so inflected forms match cleanly
        for suffix in ["urilor", "iilor", "elor", "ilor", "ului", "escu", "atie", "atia", "ing", "tion", "ment"] {
            if stem.count > suffix.count + 4 && stem.hasSuffix(suffix) {
                stem = String(stem.dropLast(suffix.count))
                break
            }
        }
        if stem.count > 5 && stem.hasSuffix("ul") {
            stem = String(stem.dropLast(2))
        } else if stem.count > 5 && stem.hasSuffix("le") {
            stem = String(stem.dropLast(2))
        } else if stem.count > 5 && stem.hasSuffix("es") {
            stem = String(stem.dropLast(2))
        } else if stem.count > 4 && stem.hasSuffix("s") && !stem.hasSuffix("ss") {
            stem = String(stem.dropLast(1))
        }
        return bilingualSynonyms[stem] ?? stem
    }
}
