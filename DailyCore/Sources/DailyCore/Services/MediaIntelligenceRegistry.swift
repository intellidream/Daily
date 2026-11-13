import Foundation
import Supabase

/// Thread-safe, O(1) lookup registry mapping news domains, publication aliases, and creator platforms
/// (`Substack`, `Medium`) to verified `MediaOutletProfile` records, backed by embedded `media_intelligence_seed.json`
/// and optional 24-hour delta watermarks from `public.media_outlet_profiles`.
public final class MediaIntelligenceRegistry: @unchecked Sendable {
    public static let shared = MediaIntelligenceRegistry()

    private let lock = NSLock()
    private var byDomain: [String: MediaOutletProfile] = [:]
    private var byNormalizedName: [String: MediaOutletProfile] = [:]

    private static let deltasCacheKey = "dayone_media_outlet_deltas_v1"
    private static let watermarkIsoKey = "dayone_media_outlet_watermark_iso_v1"
    private static let lastCheckEpochKey = "dayone_media_outlet_last_check_epoch_v1"
    private static let checkIntervalSeconds: TimeInterval = 24 * 3600 // Strict 24h TTL

    private static let aggregatorHosts: Set<String> = [
        "news.google.com",
        "google.com",
        "apple.news",
        "flipboard.com",
        "msn.com",
        "smartnews.com",
        "feedly.com"
    ]

    public init() {
        reloadFromSeedAndCachedDeltas()
    }

    // MARK: - Instant O(1) Profile Resolution

    public func resolve(for article: NewsArticle) -> MediaOutletProfile {
        resolve(
            url: article.link,
            publicationName: article.publicationName,
            author: article.author,
            isSubstack: article.isSubstackItem,
            isMedium: article.isMediumItem
        )
    }

    public func resolve(
        url: String,
        publicationName: String? = nil,
        author: String? = nil,
        isSubstack: Bool = false,
        isMedium: Bool = false
    ) -> MediaOutletProfile {
        let host = Self.extractNormalizedHost(from: url)
        let cleanPub = (publicationName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normPub = Self.normalizeLookupKey(cleanPub)

        lock.lock()
        let domainMap = self.byDomain
        let nameMap = self.byNormalizedName
        lock.unlock()

        // 1. Direct or parent-domain match (when not a generic aggregator or multi-tenant creator host)
        if !host.isEmpty && !Self.aggregatorHosts.contains(host) && host != "substack.com" && host != "open.substack.com" && host != "medium.com" {
            if let exact = domainMap[host] {
                return exact
            }
            // Check parent domains (e.g. "feeds.bbci.co.uk" -> "bbci.co.uk", "edition.cnn.com" -> "cnn.com")
            let parts = host.split(separator: ".")
            if parts.count >= 3 {
                for dropCount in 1...(parts.count - 2) {
                    let candidate = parts.dropFirst(dropCount).joined(separator: ".")
                    if candidate != "substack.com" && candidate != "medium.com" && candidate != "co.uk" && candidate != "com.au",
                       let matched = domainMap[candidate] {
                        return matched
                    }
                }
            }
        }

        // 2. Match by publication display name (crucial for Google News RSS items & custom feed titles)
        if !normPub.isEmpty && normPub != "googlenews" && normPub != "substack" && normPub != "substackinbox" && normPub != "medium" && normPub != "mediumreadinglist" {
            if let byName = nameMap[normPub] {
                return byName
            }
            // Strip trailing ".ro" / " news" / " romania" if present in display title
            for suffix in ["news", "romania", "ro", "online", "digital"] {
                if normPub.hasSuffix(suffix) && normPub.count > suffix.count + 2 {
                    let trimmed = String(normPub.dropLast(suffix.count))
                    if let matched = nameMap[trimmed] {
                        return matched
                    }
                }
            }
        }

        // 3. Substack Newsletter / Independent Creator smart profile
        if isSubstack || host.hasSuffix(".substack.com") || host == "substack.com" || host == "open.substack.com" {
            let creatorTitle: String = {
                if !cleanPub.isEmpty && cleanPub.caseInsensitiveCompare("Substack") != .orderedSame && cleanPub.caseInsensitiveCompare("Substack Inbox") != .orderedSame {
                    return cleanPub
                }
                if let a = author?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
                    return a
                }
                if host.hasSuffix(".substack.com") {
                    return String(host.dropLast(".substack.com".count)).capitalized
                }
                return "Substack Creator"
            }()
            let ownerDesc: String = {
                if let a = author?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty, a.caseInsensitiveCompare(creatorTitle) != .orderedSame {
                    return "\(a) · Independent Substack Publication"
                }
                return "\(creatorTitle) · Reader-Supported Newsletter"
            }()
            return MediaOutletProfile(
                domain: host.isEmpty ? "substack.com" : host,
                name: creatorTitle,
                bias: .independentCreator,
                biasContext: "Independent Newsletter / Essayist",
                factuality: .high,
                ownershipType: .independent,
                ownerLabel: ownerDesc,
                countryCode: "INT",
                editorialNote: "Independent creator-owned newsletter published via Substack; editorial perspective reflects the individual author rather than a corporate newsroom."
            )
        }

        // 4. Medium Author / Publication smart profile
        if isMedium || host == "medium.com" || host.hasSuffix(".medium.com") {
            let creatorTitle: String = {
                if !cleanPub.isEmpty && !cleanPub.localizedCaseInsensitiveContains("Medium Reading List") {
                    return cleanPub
                }
                if let a = author?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
                    return a
                }
                return "Medium Author"
            }()
            return MediaOutletProfile(
                domain: host.isEmpty ? "medium.com" : host,
                name: creatorTitle,
                bias: .independentCreator,
                biasContext: "Independent Essay / Technical Blog",
                factuality: .high,
                ownershipType: .independent,
                ownerLabel: "\(author ?? creatorTitle) · Independent Author on Medium",
                countryCode: "INT",
                editorialNote: "Independent author or specialist publication hosted on Medium."
            )
        }

        // 5. Graceful fallback for uncatalogued niche blogs / domains
        let fallbackName = !cleanPub.isEmpty ? cleanPub : (host.isEmpty ? "News Source" : host)
        let inferredCountry = host.hasSuffix(".ro") ? "RO" : (host.hasSuffix(".eu") ? "EU" : (host.hasSuffix(".uk") ? "GB" : "INT"))
        return MediaOutletProfile(
            domain: host.isEmpty ? normPub : host,
            name: fallbackName,
            bias: .unrated,
            biasContext: "Specialist / Uncatalogued Source",
            factuality: .high,
            ownershipType: .independent,
            ownerLabel: host.isEmpty ? fallbackName : host,
            countryCode: inferredCountry,
            editorialNote: "Specialist or regional feed not yet assigned a political spectrum rating in the canonical media registry."
        )
    }

    public var catalogCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return Set(byDomain.values.map(\.domain)).count
    }

    // MARK: - Seed Loading & 24h Supabase Delta Watermark Sync

    private func reloadFromSeedAndCachedDeltas() {
        var loadedProfiles: [MediaOutletProfile] = []

        if let seedUrl = Bundle.module.url(forResource: "media_intelligence_seed", withExtension: "json", subdirectory: "News")
            ?? Bundle.module.url(forResource: "media_intelligence_seed", withExtension: "json"),
           let data = try? Data(contentsOf: seedUrl),
           let catalog = try? JSONDecoder().decode(MediaIntelligenceSeedCatalog.self, from: data) {
            loadedProfiles.append(contentsOf: catalog.outlets)
        }

        if let deltaData = GroupDefaults.shared.userDefaults.data(forKey: Self.deltasCacheKey),
           let deltas = try? JSONDecoder().decode([MediaOutletProfile].self, from: deltaData) {
            loadedProfiles.append(contentsOf: deltas)
        }

        rebuildIndexes(with: loadedProfiles)
    }

    private func rebuildIndexes(with profiles: [MediaOutletProfile]) {
        var domDict: [String: MediaOutletProfile] = [:]
        var nameDict: [String: MediaOutletProfile] = [:]
        domDict.reserveCapacity(profiles.count * 2)
        nameDict.reserveCapacity(profiles.count * 3)

        for profile in profiles {
            let cleanDom = Self.cleanHostString(profile.domain)
            if !cleanDom.isEmpty {
                domDict[cleanDom] = profile
            }
            let normName = Self.normalizeLookupKey(profile.name)
            if !normName.isEmpty {
                nameDict[normName] = profile
            }
            let domStem = Self.normalizeLookupKey(cleanDom)
            if !domStem.isEmpty {
                nameDict[domStem] = profile
            }
            for alias in profile.aliases {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains(".") && !trimmed.contains(" ") {
                    domDict[Self.cleanHostString(trimmed)] = profile
                }
                let normAlias = Self.normalizeLookupKey(trimmed)
                if !normAlias.isEmpty {
                    nameDict[normAlias] = profile
                }
            }
        }

        lock.lock()
        self.byDomain = domDict
        self.byNormalizedName = nameDict
        lock.unlock()
    }

    /// Pulls incremental updates (`updated_at > watermark`) from `public.media_outlet_profiles` at most once every 24 hours.
    /// Zero Realtime channels and ~0 B Egress when no rows changed.
    public func syncDeltasIfNeeded(force: Bool = false) async {
        let defaults = GroupDefaults.shared.userDefaults
        let now = Date().timeIntervalSince1970
        let lastCheck = defaults.double(forKey: Self.lastCheckEpochKey)
        if !force && lastCheck > 0 && (now - lastCheck) < Self.checkIntervalSeconds {
            return
        }

        guard await AuthService.shared.currentUser != nil else { return }
        defaults.set(now, forKey: Self.lastCheckEpochKey)

        let watermark = defaults.string(forKey: Self.watermarkIsoKey) ?? "2026-11-14T00:00:00Z"

        do {
            let client = SupabaseService.shared.client
            let res = try await client
                .from("media_outlet_profiles")
                .select()
                .gt("updated_at", value: watermark)
                .order("updated_at", ascending: true)
                .limit(200)
                .execute()

            let remoteRows = try JSONDecoder().decode([RemoteMediaOutletProfileRow].self, from: res.data)
            guard !remoteRows.isEmpty else { return }

            var existingDeltas: [String: MediaOutletProfile] = [:]
            if let cachedData = defaults.data(forKey: Self.deltasCacheKey),
               let cached = try? JSONDecoder().decode([MediaOutletProfile].self, from: cachedData) {
                for p in cached {
                    existingDeltas[p.domain] = p
                }
            }

            var maxUpdated = watermark
            for row in remoteRows {
                let mapped = row.toDomainProfile()
                existingDeltas[mapped.domain] = mapped
                if let u = row.updatedAt, u > maxUpdated {
                    maxUpdated = u
                }
            }

            let mergedArray = Array(existingDeltas.values)
            if let encoded = try? JSONEncoder().encode(mergedArray) {
                defaults.set(encoded, forKey: Self.deltasCacheKey)
            }
            defaults.set(maxUpdated, forKey: Self.watermarkIsoKey)
            reloadFromSeedAndCachedDeltas()
        } catch {
            // Gracefully silent if offline or before migration is applied
        }
    }

    // MARK: - Normalization Helpers

    public static func extractNormalizedHost(from urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let parsed = URL(string: trimmed), let host = parsed.host {
            return cleanHostString(host)
        }
        if !trimmed.contains("://"), let parsed = URL(string: "https://\(trimmed)"), let host = parsed.host {
            return cleanHostString(host)
        }
        return ""
    }

    private static func cleanHostString(_ raw: String) -> String {
        var h = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["www.", "m.", "mobile.", "amp.", "feeds.", "rss.", "edition."] {
            if h.hasPrefix(prefix) && h.count > prefix.count + 3 {
                h = String(h.dropFirst(prefix.count))
            }
        }
        while h.hasSuffix("/") {
            h.removeLast()
        }
        return h
    }

    public static func normalizeLookupKey(_ raw: String) -> String {
        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
