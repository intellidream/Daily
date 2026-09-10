import Foundation

/// WinUI-parity recommendation engine utilizing term-frequency heuristics, category weighting, and round-robin source fairness.
public final class SmartRecommendationEngine: Sendable {
    
    public static let shared = SmartRecommendationEngine()
    
    private let stopWords: Set<String> = [
        // English
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with",
        "he", "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her",
        "she", "or", "an", "will", "my", "one", "all", "would", "there", "their", "what", "so", "up",
        "out", "if", "about", "who", "get", "which", "go", "me", "when", "make", "can", "like", "time",
        "no", "just", "him", "know", "take", "people", "into", "year", "your", "good", "some", "could",
        "them", "see", "other", "than", "then", "now", "look", "only", "come", "its", "over", "think",
        "also", "back", "after", "use", "two", "how", "our", "work", "first", "well", "way", "even",
        "new", "want", "because", "any", "these", "give", "day", "most", "us",
        
        // Romanian
        "si", "de", "la", "in", "pe", "cu", "o", "un", "au", "ai", "am", "este", "sunt", "care", "pentru",
        "din", "ca", "ce", "nu", "mai", "fost", "ale", "al", "ai", "sa", "se", "va", "vor", "iar", "sau",
        "cum", "tot", "dar", "desi", "dupa", "prin", "intre", "sub", "peste", "despre", "foarte", "mult",
        "fara", "catre", "astfel", "acest", "aceasta", "aceste", "acesti", "ani", "ziua", "zile"
    ]
    
    public init() {}
    
    /// Returns up to `limit` recommended articles matching `currentArticle` with round-robin diversity.
    public func getRecommendations(
        for currentArticle: NewsArticle,
        candidatePool: [NewsArticle],
        limit: Int = 10
    ) -> [NewsArticle] {
        // 1. Build keyword profile from current article
        let keywords = extractWeightedKeywords(from: currentArticle)
        guard !keywords.isEmpty else {
            // Fallback: Return newest non-current articles
            return Array(candidatePool.filter { $0.link != currentArticle.link }.prefix(limit))
        }
        
        // 2. Score candidates
        var scored: [(article: NewsArticle, score: Double)] = []
        let seenUrls = Set([currentArticle.link, currentArticle.id])
        
        for candidate in candidatePool {
            guard !seenUrls.contains(candidate.link) && candidate.title != currentArticle.title else {
                continue
            }
            
            var score: Double = 0.0
            
            // Category bonus
            if let cat1 = currentArticle.category, let cat2 = candidate.category, cat1 == cat2 {
                score += 20.0
            }
            
            let candTitleTokens = tokenize(candidate.title)
            let candDescTokens = tokenize(candidate.description ?? "")
            
            for (keyword, weight) in keywords {
                if candTitleTokens.contains(keyword) {
                    score += 5.0 * weight
                }
                if candDescTokens.contains(keyword) {
                    score += 1.0 * weight
                }
            }
            
            if score > 0 {
                scored.append((candidate, score))
            }
        }
        
        // 3. Sort candidates by score descending
        scored.sort { $0.score > $1.score }
        
        // 4. Round-Robin selection by publication name to ensure diversity
        var groupedByPub: [String: [NewsArticle]] = [:]
        for (article, _) in scored {
            let pub = article.publicationName ?? "Unknown"
            groupedByPub[pub, default: []].append(article)
        }
        
        var results: [NewsArticle] = []
        var pubKeys = Array(groupedByPub.keys)
        var addedAny = true
        
        while results.count < limit && addedAny {
            addedAny = false
            for pub in pubKeys {
                if var list = groupedByPub[pub], !list.isEmpty {
                    let next = list.removeFirst()
                    results.append(next)
                    groupedByPub[pub] = list
                    addedAny = true
                    if results.count >= limit { break }
                }
            }
        }
        
        // Fallback fill if results count < limit
        if results.count < limit {
            for candidate in candidatePool {
                if !results.contains(where: { $0.link == candidate.link }) && candidate.link != currentArticle.link {
                    results.append(candidate)
                    if results.count >= limit { break }
                }
            }
        }
        
        return results
    }
    
    private func extractWeightedKeywords(from article: NewsArticle) -> [String: Double] {
        var map: [String: Double] = [:]
        
        // Title keywords weight: 5.0
        for token in tokenize(article.title) {
            map[token, default: 0.0] += 5.0
        }
        
        // Description keywords weight: 1.0
        if let desc = article.description {
            for token in tokenize(desc) {
                map[token, default: 0.0] += 1.0
            }
        }
        
        // Keep top 15 keywords
        let sorted = map.sorted { $0.value > $1.value }.prefix(15)
        var result: [String: Double] = [:]
        for (k, v) in sorted {
            result[k] = v
        }
        return result
    }
    
    private func tokenize(_ text: String) -> [String] {
        let clean = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        return clean
    }
}
