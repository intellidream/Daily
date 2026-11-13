import Foundation

/// Pure deterministic, zero-network bilingual (`RO` + `EN`) classifier that separates
/// straight reporting from opinion/editorials, investigative journalism, and sensationalist/clickbait framing.
public enum ArticleFramingAnalyzer {

    private static let investigationMarkers: [String] = [
        "investigație", "investigatie", "anchetă", "ancheta", "documente interne",
        "dosarul ", "cum funcționează rețeaua", "cum functioneaza reteaua", "recorder:", "snoop:",
        "investigation:", "investigates", "special report:", "leaked documents",
        "whistleblower", "inside the secret", "exclusive investigation", "occrp"
    ]

    private static let opinionPrefixes: [String] = [
        "opinie:", "opinie |", "opinie -", "editorial:", "editorial |", "comentariu:",
        "eseu:", "punct de vedere:", "scrisoare deschisă", "scrisoare deschisa",
        "opinion:", "opinion |", "opinion -", "op-ed:", "column:", "commentary:",
        "perspective:", "letters to the editor", "review:"
    ]

    private static let opinionPhrases: [String] = [
        "de ce cred că", "de ce cred ca", "părerea mea", "parerea mea",
        "why i think", "why we must", "why we need to", "in my view", "editorial board"
    ]

    private static let sensationalMarkers: [String] = [
        "șocant", "socant", "halucinant", "incredibil ce ", "nu o să-ți vină să crezi",
        "nu o sa-ti vina sa crezi", "bombă pe scena", "bomba zilei", "cutremur în ",
        "cutremur in ", "dezastru total", "scandal monstru", "nucleară în", "nucleara in",
        "lovitură de teatru", "lovitura de teatru", "răsturnare spectaculoasă",
        "you won't believe", "shocking:", "bombshell!", "destroys ", "obliterates ",
        "total meltdown", "jaw-dropping", "goes nuclear"
    ]

    public static func classify(
        title: String,
        description: String? = nil,
        link: String = "",
        profile: MediaOutletProfile? = nil
    ) -> ArticleFramingTag {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return .reporting }

        let lowerTitle = trimmedTitle.lowercased()
        let lowerDesc = (description ?? "").prefix(240).lowercased()
        let lowerLink = link.lowercased()

        // 1. URL path hints (/opinion/, /editorial/, /investigatii/)
        if lowerLink.contains("/opinion/") || lowerLink.contains("/opinii/") || lowerLink.contains("/editorial/") || lowerLink.contains("/kommentar/") {
            return .opinion
        }
        if lowerLink.contains("/investigatii/") || lowerLink.contains("/investigations/") || lowerLink.contains("/anchete/") {
            return .investigation
        }

        // 2. Investigative markers (also recognize dedicated investigative non-profits on long-form reports)
        for marker in investigationMarkers {
            if lowerTitle.contains(marker) || lowerDesc.contains(marker) {
                return .investigation
            }
        }
        if let p = profile,
           (p.domain == "recorder.ro" || p.domain == "snoop.ro" || p.domain == "riseproject.ro" || p.domain == "propublica.org" || p.domain == "bellingcat.com"),
           (lowerTitle.contains("cum ") || lowerTitle.contains("banii ") || lowerTitle.contains("afacerea ") || lowerTitle.contains("rețeaua") || lowerTitle.contains("secret")) {
            return .investigation
        }

        // 3. Sensational / Clickbait markers
        for marker in sensationalMarkers {
            if lowerTitle.contains(marker) {
                return .sensational
            }
        }
        if trimmedTitle.contains("?!") || trimmedTitle.contains("!!!") {
            return .sensational
        }
        let words = trimmedTitle.split(separator: " ")
        if words.count >= 6 {
            let shoutWords = words.filter { w in
                let letters = w.filter { $0.isLetter }
                return letters.count >= 4 && letters == letters.uppercased()
            }
            if Double(shoutWords.count) / Double(words.count) >= 0.45 {
                return .sensational
            }
        }

        // 4. Opinion / Essay markers
        for prefix in opinionPrefixes {
            if lowerTitle.hasPrefix(prefix) || lowerTitle.contains(" | \(prefix)") {
                return .opinion
            }
        }
        for phrase in opinionPhrases {
            if lowerTitle.contains(phrase) || lowerDesc.contains(phrase) {
                return .opinion
            }
        }
        if let p = profile, p.domain == "republica.ro" {
            return .opinion
        }

        return .reporting
    }
}
