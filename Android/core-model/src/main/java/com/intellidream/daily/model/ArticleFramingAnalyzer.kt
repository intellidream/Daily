package com.intellidream.daily.model

import java.util.Locale

/**
 * Pure deterministic, zero-network bilingual (`RO` + `EN`) classifier that separates
 * straight reporting from opinion/editorials, investigative journalism, and sensationalist/clickbait framing.
 */
object ArticleFramingAnalyzer {

    private val investigationMarkers = listOf(
        "investigație", "investigatie", "anchetă", "ancheta", "documente interne",
        "dosarul ", "cum funcționează rețeaua", "cum functioneaza reteaua", "recorder:", "snoop:",
        "investigation:", "investigates", "special report:", "leaked documents",
        "whistleblower", "inside the secret", "exclusive investigation", "occrp"
    )

    private val opinionPrefixes = listOf(
        "opinie:", "opinie |", "opinie -", "editorial:", "editorial |", "comentariu:",
        "eseu:", "punct de vedere:", "scrisoare deschisă", "scrisoare deschisa",
        "opinion:", "opinion |", "opinion -", "op-ed:", "column:", "commentary:",
        "perspective:", "letters to the editor", "review:"
    )

    private val opinionPhrases = listOf(
        "de ce cred că", "de ce cred ca", "părerea mea", "parerea mea",
        "why i think", "why we must", "why we need to", "in my view", "editorial board"
    )

    private val sensationalMarkers = listOf(
        "șocant", "socant", "halucinant", "incredibil ce ", "nu o să-ți vină să crezi",
        "nu o sa-ti vina sa crezi", "bombă pe scena", "bomba zilei", "cutremur în ",
        "cutremur in ", "dezastru total", "scandal monstru", "nucleară în", "nucleara in",
        "lovitură de teatru", "lovitura de teatru", "răsturnare spectaculoasă",
        "you won't believe", "shocking:", "bombshell!", "destroys ", "obliterates ",
        "total meltdown", "jaw-dropping", "goes nuclear"
    )

    private val investigativeDomains = setOf(
        "recorder.ro", "snoop.ro", "riseproject.ro", "propublica.org", "bellingcat.com"
    )

    fun classify(
        title: String,
        description: String? = null,
        link: String = "",
        profile: MediaOutletProfile? = null
    ): ArticleFramingTag {
        val trimmedTitle = title.trim()
        if (trimmedTitle.isEmpty()) return ArticleFramingTag.Reporting

        val lowerTitle = trimmedTitle.lowercase(Locale.ROOT)
        val lowerDesc = (description ?: "").take(240).lowercase(Locale.ROOT)
        val lowerLink = link.lowercase(Locale.ROOT)

        // 1. URL path hints
        if (lowerLink.contains("/opinion/") || lowerLink.contains("/opinii/") ||
            lowerLink.contains("/editorial/") || lowerLink.contains("/kommentar/")
        ) {
            return ArticleFramingTag.Opinion
        }
        if (lowerLink.contains("/investigatii/") || lowerLink.contains("/investigations/") ||
            lowerLink.contains("/anchete/")
        ) {
            return ArticleFramingTag.Investigation
        }

        // 2. Investigative markers
        for (marker in investigationMarkers) {
            if (lowerTitle.contains(marker) || lowerDesc.contains(marker)) {
                return ArticleFramingTag.Investigation
            }
        }
        if (profile != null && profile.domain in investigativeDomains &&
            (lowerTitle.contains("cum ") || lowerTitle.contains("banii ") ||
                lowerTitle.contains("afacerea ") || lowerTitle.contains("rețeaua") ||
                lowerTitle.contains("secret"))
        ) {
            return ArticleFramingTag.Investigation
        }

        // 3. Sensational / Clickbait markers
        for (marker in sensationalMarkers) {
            if (lowerTitle.contains(marker)) {
                return ArticleFramingTag.Sensational
            }
        }
        if (trimmedTitle.contains("?!") || trimmedTitle.contains("!!!")) {
            return ArticleFramingTag.Sensational
        }
        val words = trimmedTitle.split(" ").filter { it.isNotBlank() }
        if (words.size >= 6) {
            val shoutWords = words.count { w ->
                val letters = w.filter { it.isLetter() }
                letters.length >= 4 && letters == letters.uppercase(Locale.ROOT)
            }
            if (shoutWords.toDouble() / words.size.toDouble() >= 0.45) {
                return ArticleFramingTag.Sensational
            }
        }

        // 4. Opinion / Essay markers
        for (prefix in opinionPrefixes) {
            if (lowerTitle.startsWith(prefix) || lowerTitle.contains(" | $prefix")) {
                return ArticleFramingTag.Opinion
            }
        }
        for (phrase in opinionPhrases) {
            if (lowerTitle.contains(phrase) || lowerDesc.contains(phrase)) {
                return ArticleFramingTag.Opinion
            }
        }
        if (profile?.domain == "republica.ro") {
            return ArticleFramingTag.Opinion
        }

        return ArticleFramingTag.Reporting
    }
}
