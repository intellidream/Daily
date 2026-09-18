package com.intellidream.daily.model

import java.util.Locale

class SmartRecommendationEngine {

    private val stopWords: Set<String> = setOf(
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
    )

    fun getRecommendations(
        currentArticle: NewsArticle,
        candidatePool: List<NewsArticle>,
        limit: Int = 10
    ): List<NewsArticle> {
        // 1. Build keyword profile
        val keywords = extractWeightedKeywords(currentArticle)
        if (keywords.isEmpty()) {
            return candidatePool.filter { it.link != currentArticle.link }.take(limit)
        }

        // 2. Score candidates
        val scored = mutableListOf<Pair<NewsArticle, Double>>()
        val seenUrls = setOf(currentArticle.link, currentArticle.id)

        for (candidate in candidatePool) {
            if (seenUrls.contains(candidate.link) || candidate.title == currentArticle.title) {
                continue
            }

            var score = 0.0

            // Category bonus
            if (currentArticle.category != null && currentArticle.category == candidate.category) {
                score += 20.0
            }

            val candTitleTokens = tokenize(candidate.title)
            val candDescTokens = tokenize(candidate.description ?: "")

            for ((keyword, weight) in keywords) {
                if (candTitleTokens.contains(keyword)) {
                    score += 5.0 * weight
                }
                if (candDescTokens.contains(keyword)) {
                    score += 1.0 * weight
                }
            }

            if (score > 0) {
                scored.add(candidate to score)
            }
        }

        // 3. Sort by score descending
        scored.sortByDescending { it.second }

        // 4. Round-robin selection by publication name to ensure diversity
        val groupedByPub = mutableMapOf<String, MutableList<NewsArticle>>()
        for ((article, _) in scored) {
            val pub = article.publicationName ?: "Unknown"
            groupedByPub.getOrPut(pub) { mutableListOf() }.add(article)
        }

        val results = mutableListOf<NewsArticle>()
        val pubKeys = groupedByPub.keys.toList()
        var addedAny = true

        while (results.size < limit && addedAny) {
            addedAny = false
            for (pub in pubKeys) {
                val list = groupedByPub[pub]
                if (!list.isNullOrEmpty()) {
                    val next = list.removeAt(0)
                    results.add(next)
                    addedAny = true
                    if (results.size >= limit) break
                }
            }
        }

        // Fallback fill if results count < limit
        if (results.size < limit) {
            for (candidate in candidatePool) {
                if (results.none { it.link == candidate.link } && candidate.link != currentArticle.link) {
                    results.add(candidate)
                    if (results.size >= limit) break
                }
            }
        }

        return results
    }

    private fun extractWeightedKeywords(article: NewsArticle): Map<String, Double> {
        val map = mutableMapOf<String, Double>()

        // Title keywords weight: 5.0
        for (token in tokenize(article.title)) {
            map[token] = (map[token] ?: 0.0) + 5.0
        }

        // Description keywords weight: 1.0
        if (!article.description.isNullOrBlank()) {
            for (token in tokenize(article.description)) {
                map[token] = (map[token] ?: 0.0) + 1.0
            }
        }

        // Keep top 15 keywords
        return map.entries
            .sortedByDescending { it.value }
            .take(15)
            .associate { it.key to it.value }
    }

    private fun tokenize(text: String): List<String> {
        val nonAlpha = Regex("[^a-zA-Z0-9ăâîșțĂÂÎȘȚ]+")
        return text.lowercase(Locale.ROOT)
            .split(nonAlpha)
            .filter { it.length >= 3 && !stopWords.contains(it) }
    }

    companion object {
        val shared = SmartRecommendationEngine()
    }
}
