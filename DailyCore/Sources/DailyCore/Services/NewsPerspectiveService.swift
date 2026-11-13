import Foundation
import Supabase

/// On-demand cross-spectrum story discovery (`Google News RSS Search` + `GDELT DOC 2.0` fallback)
/// and multi-perspective framing comparison engine (`Gemini 2.5 Flash` + shared 72h `news_perspective_cache` + deterministic fallback).
///
/// Architectural guarantees:
/// - Zero background polling: external discovery and LLM calls run ONLY when the user opens `Perspectives`.
/// - Shared 72h Supabase cache written with `returning: .minimal` (`< 1.5 KB` payload, zero Realtime).
public final class NewsPerspectiveService: @unchecked Sendable {
    public static let shared = NewsPerspectiveService()

    private let lock = NSLock()
    private var expansionCache: [String: (cluster: StoryCluster, timestamp: Date)] = [:]
    private var comparisonCache: [String: PerspectiveComparison] = [:]
    private var lastGdeltRequestAt: Date = .distantPast

    private let expansionTtl: TimeInterval = 15 * 60
    private let session: URLSession
    private let primaryModel = "gemini-2.5-flash"
    private let fallbackModel = "gemini-1.5-flash"

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 14.0
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "Accept": "application/rss+xml, application/xml, application/json, text/xml, */*"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Async-Safe Cache Helpers

    private func cachedExpansion(for clusterId: String) -> StoryCluster? {
        lock.withLock {
            guard let cached = expansionCache[clusterId],
                  Date().timeIntervalSince(cached.timestamp) < expansionTtl else {
                return nil
            }
            return cached.cluster
        }
    }

    private func storeCachedExpansion(_ cluster: StoryCluster, for clusterId: String) {
        lock.withLock {
            expansionCache[clusterId] = (cluster, Date())
        }
    }

    private func tryAcquireGdeltSlot() -> Bool {
        lock.withLock {
            let now = Date()
            guard now.timeIntervalSince(lastGdeltRequestAt) >= 6.0 else {
                return false
            }
            lastGdeltRequestAt = now
            return true
        }
    }

    private func cachedComparison(for clusterId: String, minSources: Int) -> PerspectiveComparison? {
        lock.withLock {
            guard let mem = comparisonCache[clusterId], mem.sourceCount >= minSources else {
                return nil
            }
            return mem
        }
    }

    private func storeCachedComparison(_ comparison: PerspectiveComparison, for clusterId: String) {
        lock.withLock {
            comparisonCache[clusterId] = comparison
        }
    }

    // MARK: - 1. On-Demand Cross-Spectrum Coverage Expansion

    public func expandCoverage(for cluster: StoryCluster, force: Bool = false) async -> StoryCluster {
        if !force, let cached = cachedExpansion(for: cluster.id) {
            return cached
        }

        let (query, isRomanian) = StoryClusterEngine.buildDiscoveryQuery(for: cluster.leadArticle)
        guard !query.isEmpty else { return cluster }

        var discovered: [NewsArticle] = []

        if isRomanian {
            async let roResults = fetchGoogleNewsSearch(query: query, hl: "ro", gl: "RO", ceid: "RO:ro", category: cluster.leadArticle.category)
            async let intlResults = fetchGoogleNewsSearch(query: query, hl: "en-US", gl: "US", ceid: "US:en", category: cluster.leadArticle.category)
            let (roItems, intlItems) = await (roResults, intlResults)
            discovered.append(contentsOf: roItems)
            discovered.append(contentsOf: intlItems.prefix(10))
        } else {
            let intlItems = await fetchGoogleNewsSearch(query: query, hl: "en-US", gl: "US", ceid: "US:en", category: cluster.leadArticle.category)
            discovered.append(contentsOf: intlItems)
        }

        // Optional lightweight GDELT DOC 2.0 JSON fallback if Google News returned very few results
        if discovered.count < 3 {
            let gdeltItems = await fetchGdeltFallback(query: query, category: cluster.leadArticle.category)
            discovered.append(contentsOf: gdeltItems)
        }

        let merged = StoryClusterEngine.mergeExpandedArticles(into: cluster, discovered: discovered)
        storeCachedExpansion(merged, for: cluster.id)
        return merged
    }

    private func fetchGoogleNewsSearch(
        query: String,
        hl: String,
        gl: String,
        ceid: String,
        category: FeedCategory?
    ) async -> [NewsArticle] {
        let fullQuery = "\(query) when:3d"
        guard let encoded = fullQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=\(hl)&gl=\(gl)&ceid=\(ceid)") else {
            return []
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let tempFeed = FeedSource(
                id: "gnews_perspective_search",
                name: "Google News",
                url: url.absoluteString,
                type: .rss,
                category: category ?? .world
            )
            let parser = FeedParser(feed: tempFeed)
            return Array(parser.parse(xmlData: data).prefix(22))
        } catch {
            return []
        }
    }

    private func fetchGdeltFallback(query: String, category: FeedCategory?) async -> [NewsArticle] {
        guard tryAcquireGdeltSlot() else {
            return []
        }

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.gdeltproject.org/api/v2/doc/doc?query=\(encoded)&mode=ArtList&maxrecords=15&timespan=72h&format=json") else {
            return []
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let articlesJson = json["articles"] as? [[String: Any]] else {
                return []
            }

            return articlesJson.compactMap { obj -> NewsArticle? in
                guard let title = obj["title"] as? String, !title.isEmpty,
                      let articleUrl = obj["url"] as? String, !articleUrl.isEmpty else {
                    return nil
                }
                let domain = (obj["domain"] as? String) ?? MediaIntelligenceRegistry.extractNormalizedHost(from: articleUrl)
                let profile = MediaIntelligenceRegistry.shared.resolve(url: articleUrl, publicationName: domain)
                let socialImg = obj["socialimage"] as? String
                return NewsArticle(
                    id: articleUrl,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    link: articleUrl,
                    publishDate: Date(),
                    imageUrl: (socialImg?.isEmpty == false) ? socialImg : nil,
                    description: nil,
                    author: nil,
                    publicationName: profile.name,
                    publicationIconUrl: "https://www.google.com/s2/favicons?domain=\(profile.domain)&sz=64",
                    category: category
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - 2. Multi-Perspective Comparison (Supabase 72h Cache -> Gemini 2.5 Flash -> Deterministic)

    public func comparePerspectives(
        for cluster: StoryCluster,
        apiKey: String?,
        forceRefresh: Bool = false
    ) async -> PerspectiveComparison {
        if !forceRefresh, let mem = cachedComparison(for: cluster.id, minSources: max(2, cluster.uniqueOutletCount - 2)) {
            return mem
        }

        // 1. Check shared 72h Supabase cache (`public.news_perspective_cache`)
        if !forceRefresh, let remoteCached = await fetchSupabaseCachedComparison(clusterHash: cluster.id) {
            if remoteCached.sourceCount >= max(2, cluster.uniqueOutletCount - 3) {
                storeCachedComparison(remoteCached, for: cluster.id)
                return remoteCached
            }
        }

        let isRo = StoryClusterEngine.detectRomanian(
            text: "\(cluster.leadArticle.title) \(cluster.leadArticle.description ?? "")",
            url: cluster.leadArticle.link
        )
        let langCode = isRo ? "ro" : "en"

        // 2. Execute Gemini 2.5 Flash synthesis when API key is configured and >= 2 sources exist
        let cleanKey = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanKey.isEmpty && cluster.items.count >= 2 {
            if let aiResult = await generateGeminiComparison(cluster: cluster, languageCode: langCode, apiKey: cleanKey) {
                storeCachedComparison(aiResult, for: cluster.id)

                Task.detached(priority: .utility) {
                    await Self.saveComparisonToSupabaseCache(aiResult)
                }
                return aiResult
            }
        }

        // 3. Zero-latency deterministic framing comparison fallback
        let deterministic = buildDeterministicComparison(for: cluster, isRomanian: isRo)
        storeCachedComparison(deterministic, for: cluster.id)
        return deterministic
    }

    // MARK: - Supabase Cache Read/Write (`returning: .minimal`)

    private func fetchSupabaseCachedComparison(clusterHash: String) async -> PerspectiveComparison? {
        guard await AuthService.shared.currentUser != nil else { return nil }
        do {
            let client = SupabaseService.shared.client
            let res = try await client
                .from("news_perspective_cache")
                .select()
                .eq("cluster_hash", value: clusterHash)
                .limit(1)
                .execute()

            let rows = try JSONDecoder().decode([RemotePerspectiveCacheRow].self, from: res.data)
            return rows.first?.toDomain()
        } catch {
            return nil
        }
    }

    private static func saveComparisonToSupabaseCache(_ comparison: PerspectiveComparison) async {
        guard await AuthService.shared.currentUser != nil else { return }
        let row = RemotePerspectiveCacheRow(
            clusterHash: comparison.clusterHash,
            storyTitle: String(comparison.storyTitle.prefix(240)),
            summaryText: String(comparison.summaryText.prefix(900)),
            commonFacts: Array(comparison.commonFacts.prefix(5)),
            framingDifferences: Array(comparison.framingDifferences.prefix(5)),
            omissions: Array(comparison.omissions.prefix(4)),
            languageCode: comparison.languageCode,
            sourceCount: comparison.sourceCount,
            createdAt: nil
        )
        do {
            let client = SupabaseService.shared.client
            try await client
                .from("news_perspective_cache")
                .upsert(row, onConflict: "cluster_hash", returning: .minimal)
                .execute()
        } catch {
            // Silent when offline or before migration push
        }
    }

    // MARK: - Gemini 2.5 Flash Multi-Perspective Synthesizer

    private struct GeminiPerspectiveSchema: Decodable {
        struct DiffItem: Decodable {
            let perspectiveLabel: String
            let angle: String
        }
        let summaryText: String
        let commonFacts: [String]?
        let framingDifferences: [DiffItem]?
        let omissions: [String]?
    }

    private struct RawGeminiResponseEnvelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    private func generateGeminiComparison(
        cluster: StoryCluster,
        languageCode: String,
        apiKey: String
    ) async -> PerspectiveComparison? {
        for model in [primaryModel, fallbackModel] {
            if let result = try? await callGeminiModel(model: model, cluster: cluster, languageCode: languageCode, apiKey: apiKey) {
                return result
            }
        }
        return nil
    }

    private func callGeminiModel(
        model: String,
        cluster: StoryCluster,
        languageCode: String,
        apiKey: String
    ) async throws -> PerspectiveComparison {
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw URLError(.badURL)
        }

        // Select up to 12 diverse outlets across Left, Center, Right, and Independent
        let selectedItems = selectDiverseSample(from: cluster.items, maxCount: 12)
        let sourcesPromptLines = selectedItems.enumerated().map { idx, item -> String in
            let snippet = item.article.description?.prefix(160) ?? ""
            let cleanSnippet = snippet.isEmpty ? "" : " — Snippet: \(snippet)"
            return "[\(idx + 1)] \(item.profile.name) (Bias: \(item.profile.bias.displayName) / \(item.profile.biasContext), Factuality: \(item.profile.factuality.displayName), Country: \(item.profile.countryCode), Ownership: \(item.profile.ownershipType.displayName)): \"\(item.article.title)\"\(cleanSnippet)"
        }.joined(separator: "\n")

        let langInstruction = languageCode == "ro"
            ? "Write all output values in natural, concise Romanian."
            : "Write all output values in crisp, neutral English."

        let systemPrompt = """
        You are Daily Perspectives, an impartial Ground News-grade media analyst.
        Compare how different newsrooms across the political, geographic, and ownership spectrum frame the same underlying news event.
        \(langInstruction)
        Return strictly valid JSON matching this exact schema:
        {
          "summaryText": "Neutral 2-3 sentence executive synthesis of what happened",
          "commonFacts": ["3 to 4 concrete verifiable facts agreed upon across sources"],
          "framingDifferences": [
            {"perspectiveLabel": "e.g. Center / Wire or Civic Reformist or Pro-Market / Right or International Press", "angle": "1 sentence explaining how specific named outlets frame or emphasize the story"}
          ],
          "omissions": ["1 to 3 notable context points, blindspots, or nuances highlighted by some outlets but omitted by others"]
        }
        """

        let userPrompt = """
        Event Anchor Entities: \(cluster.anchorEntities.joined(separator: ", "))
        Distribution: Left \(cluster.distribution.leftCount), Center \(cluster.distribution.centerCount), Right \(cluster.distribution.rightCount), Independent \(cluster.distribution.independentCount)
        Sources (\(selectedItems.count) of \(cluster.uniqueOutletCount)):
        \(sourcesPromptLines)
        """

        let bodyDict: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": userPrompt]]]],
            "generationConfig": [
                "temperature": 0.25,
                "responseMimeType": "application/json"
            ]
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let env = try JSONDecoder().decode(RawGeminiResponseEnvelope.self, from: data)
        guard var rawJson = env.candidates?.first?.content?.parts?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawJson.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        if rawJson.hasPrefix("```") {
            rawJson = rawJson
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let decoded = try JSONDecoder().decode(GeminiPerspectiveSchema.self, from: Data(rawJson.utf8))
        let diffs = (decoded.framingDifferences ?? []).map {
            FramingDifferenceItem(perspectiveLabel: $0.perspectiveLabel, angle: $0.angle)
        }

        return PerspectiveComparison(
            clusterHash: cluster.id,
            storyTitle: cluster.leadArticle.title,
            summaryText: decoded.summaryText,
            commonFacts: decoded.commonFacts ?? [],
            framingDifferences: diffs,
            omissions: decoded.omissions ?? [],
            languageCode: languageCode,
            sourceCount: cluster.uniqueOutletCount,
            isAiGenerated: true
        )
    }

    private func selectDiverseSample(from items: [ClusterCoverageItem], maxCount: Int) -> [ClusterCoverageItem] {
        guard items.count > maxCount else { return items }
        var left = items.filter { $0.profile.bias.bucket == .left }
        var center = items.filter { $0.profile.bias.bucket == .center }
        var right = items.filter { $0.profile.bias.bucket == .right }
        var other = items.filter { $0.profile.bias.bucket == .independent || $0.profile.bias.bucket == .unrated }

        var picked: [ClusterCoverageItem] = []
        while picked.count < maxCount && (!left.isEmpty || !center.isEmpty || !right.isEmpty || !other.isEmpty) {
            if !center.isEmpty && picked.count < maxCount { picked.append(center.removeFirst()) }
            if !left.isEmpty && picked.count < maxCount { picked.append(left.removeFirst()) }
            if !right.isEmpty && picked.count < maxCount { picked.append(right.removeFirst()) }
            if !other.isEmpty && picked.count < maxCount { picked.append(other.removeFirst()) }
        }
        return picked
    }

    // MARK: - Deterministic Multi-Perspective Fallback (Instant / Offline / Zero-Key)

    public func buildDeterministicComparison(for cluster: StoryCluster, isRomanian: Bool) -> PerspectiveComparison {
        let d = cluster.distribution
        let outletNames = Array(Set(cluster.items.map { $0.profile.name })).sorted()
        let sampleNames = outletNames.prefix(4).joined(separator: ", ")

        let summaryText: String
        if isRomanian {
            summaryText = "Acest subiect este acoperit de \(cluster.uniqueOutletCount) publicații (\(sampleNames)), cu o distribuție de \(d.leftPercentInt)% Stânga, \(d.centerPercentInt)% Centru și \(d.rightPercentInt)% Dreapta."
        } else {
            summaryText = "This story is covered across \(cluster.uniqueOutletCount) distinct outlets (\(sampleNames)), spanning \(d.leftPercentInt)% Left, \(d.centerPercentInt)% Center, and \(d.rightPercentInt)% Right perspectives."
        }

        var facts: [String] = []
        if !cluster.anchorEntities.isEmpty {
            if isRomanian {
                facts.append("Entități și repere comune în titluri: \(cluster.anchorEntities.joined(separator: " • ")).")
            } else {
                facts.append("Core entities shared across reporting: \(cluster.anchorEntities.joined(separator: " • ")).")
            }
        }
        let highFactCount = cluster.items.filter { $0.profile.factuality == .veryHigh || $0.profile.factuality == .high }.count
        if highFactCount > 0 {
            if isRomanian {
                facts.append("\(highFactCount) din \(cluster.items.count) articole provin din redacții cu factualitate ridicată (High / Very High).")
            } else {
                facts.append("\(highFactCount) of \(cluster.items.count) reports originate from High or Very High factuality newsrooms.")
            }
        }

        var diffs: [FramingDifferenceItem] = []
        if let leftItem = cluster.items.first(where: { $0.profile.bias.bucket == .left }) {
            diffs.append(FramingDifferenceItem(
                perspectiveLabel: isRomanian ? "Stânga / Progresist (\(leftItem.profile.name))" : "Left / Lean Left (\(leftItem.profile.name))",
                angle: "„\(leftItem.article.title)”"
            ))
        }
        if let centerItem = cluster.items.first(where: { $0.profile.bias.bucket == .center }) {
            diffs.append(FramingDifferenceItem(
                perspectiveLabel: isRomanian ? "Centru / Echilibrat (\(centerItem.profile.name))" : "Center / Wire (\(centerItem.profile.name))",
                angle: "„\(centerItem.article.title)”"
            ))
        }
        if let rightItem = cluster.items.first(where: { $0.profile.bias.bucket == .right }) {
            diffs.append(FramingDifferenceItem(
                perspectiveLabel: isRomanian ? "Dreapta / Pro-Piață (\(rightItem.profile.name))" : "Right / Lean Right (\(rightItem.profile.name))",
                angle: "„\(rightItem.article.title)”"
            ))
        }
        if let indItem = cluster.items.first(where: { $0.profile.bias == .independentCreator || $0.profile.ownershipType.isIndependentOrNonProfit }) {
            if diffs.count < 3 {
                diffs.append(FramingDifferenceItem(
                    perspectiveLabel: isRomanian ? "Independent / Non-Profit (\(indItem.profile.name))" : "Independent / Non-Profit (\(indItem.profile.name))",
                    angle: "„\(indItem.article.title)”"
                ))
            }
        }

        var omissions: [String] = []
        if cluster.blindspot.isBlindspot {
            omissions.append(cluster.blindspot.explanation)
        }
        let opinionCount = cluster.items.filter { $0.framing == .opinion }.count
        let sensationalCount = cluster.items.filter { $0.framing == .sensational }.count
        if opinionCount > 0 {
            omissions.append(isRomanian
                ? "\(opinionCount) surse tratează subiectul în registru de editorial/opinie, nu doar relatare factuală."
                : "\(opinionCount) outlet(s) frame this event as editorial commentary rather than straight wire reporting.")
        }
        if sensationalCount > 0 {
            omissions.append(isRomanian
                ? "Atenție la încadrarea emoțională: \(sensationalCount) titluri folosesc formulări senzaționaliste."
                : "Note on tone: \(sensationalCount) headline(s) employ sensational or loaded phrasing.")
        }

        return PerspectiveComparison(
            clusterHash: cluster.id,
            storyTitle: cluster.leadArticle.title,
            summaryText: summaryText,
            commonFacts: facts,
            framingDifferences: diffs,
            omissions: omissions,
            languageCode: isRomanian ? "ro" : "en",
            sourceCount: cluster.uniqueOutletCount,
            isAiGenerated: false
        )
    }
}
