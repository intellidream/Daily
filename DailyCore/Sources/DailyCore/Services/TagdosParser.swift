import Foundation

/// Fast, deterministic parser for the TagDoS syntax.
/// Syntactic rules:
/// - Streams are collections of clusters separated by ` & `
/// - Clusters are sequences of mental action tags separated by `/`
/// - Semantic tokens: `$` or `€` (financial), `!` (urgent), numbers (metric/date)
public struct TagdosParser: Sendable {
    public static let shared = TagdosParser()

    public init() {}

    /// Parses a raw TagDoS line into a fully populated `TagDoStream`.
    public func parseStream(
        rawText: String,
        title: String,
        id: UUID = UUID(),
        streamReminder: Date? = nil,
        orderIndex: Int = 0,
        existingStream: TagDoStream? = nil
    ) -> TagDoStream {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TagDoStream(
                id: id,
                title: title,
                customTitle: existingStream?.customTitle,
                rawText: "",
                clusters: [],
                streamReminder: streamReminder,
                orderIndex: orderIndex
            )
        }

        // Split by cluster separator: ` & ` (support variable spacing around `&`)
        let rawClusters = trimmed.components(separatedBy: "&")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parsedClusters: [TagDoCluster] = []

        for rawCluster in rawClusters {
            // Split cluster by pill separator: `/`
            let rawPillTokens = rawCluster.components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var pills: [TagDoPill] = []
            for token in rawPillTokens {
                // If an existing pill with the same token exists, preserve its completion and notes state
                if let existing = existingStream?.allPills.first(where: { $0.rawText == token }) {
                    pills.append(TagDoPill(
                        id: existing.id,
                        rawText: token,
                        type: existing.type,
                        isCompleted: existing.isCompleted,
                        customReminderDate: existing.customReminderDate,
                        decodedNote: existing.decodedNote
                    ))
                } else {
                    pills.append(TagDoPill(rawText: token))
                }
            }

            if !pills.isEmpty {
                parsedClusters.append(TagDoCluster(pills: pills, rawText: rawCluster))
            }
        }

        return TagDoStream(
            id: id,
            title: title,
            customTitle: existingStream?.customTitle,
            rawText: trimmed,
            clusters: parsedClusters,
            streamReminder: streamReminder,
            orderIndex: orderIndex,
            activeMemos: existingStream?.activeMemos ?? "",
            attachments: existingStream?.attachments ?? []
        )
    }

    /// Serializes a `TagDoStream` back to its canonical raw string format.
    public func serializeStream(_ stream: TagDoStream) -> String {
        let clusterStrings = stream.clusters.map { cluster in
            cluster.pills.map { $0.rawText }.joined(separator: "/")
        }
        return clusterStrings.joined(separator: " & ")
    }

    // MARK: - Interactive Mutations

    /// Updates the text of an existing pill in-place, re-evaluates its semantic type, and re-serializes rawText.
    public func updatePillText(in stream: TagDoStream, pillId: UUID, newText: String) -> TagDoStream {
        let cleanText = newText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "&", with: "+")
        guard !cleanText.isEmpty else { return stream }

        var updatedClusters = stream.clusters
        var didChange = false

        for clusterIndex in 0..<updatedClusters.count {
            var cluster = updatedClusters[clusterIndex]
            if let pillIndex = cluster.pills.firstIndex(where: { $0.id == pillId }) {
                let existing = cluster.pills[pillIndex]
                cluster.pills[pillIndex] = TagDoPill(
                    id: existing.id,
                    rawText: cleanText,
                    type: nil, // Auto-reclassify semantic type from new text
                    isCompleted: existing.isCompleted,
                    customReminderDate: existing.customReminderDate,
                    decodedNote: existing.decodedNote
                )
                cluster.rawText = cluster.pills.map { $0.rawText }.joined(separator: "/")
                updatedClusters[clusterIndex] = cluster
                didChange = true
                break
            }
        }

        guard didChange else { return stream }
        let newRawText = updatedClusters.map { $0.rawText }.joined(separator: " & ")
        return TagDoStream(
            id: stream.id,
            title: stream.title,
            customTitle: stream.customTitle,
            rawText: newRawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex,
            activeMemos: stream.activeMemos,
            attachments: stream.attachments,
            updatedAt: Date()
        )
    }

    // MARK: - DSL Detection & Import Helpers

    /// Returns true if `text` already conforms to TagDoS DSL (e.g., `MG/GM/TG & FSH/LDL`, `MG/GM & CRR vg/PL 98`, `C$T`, `EXP!`, `5K`).
    public func isAlreadyTagdosDsl(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") {
            return false
        }

        if trimmed.contains("/") || trimmed.contains("&") {
            let clusters = trimmed.components(separatedBy: "&")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !clusters.isEmpty else { return false }

            if trimmed.contains("/") {
                var totalTokens = 0
                var hasSpaceInsideToken = false
                var hasMnemonicSignal = false
                for cluster in clusters {
                    let tokens = cluster.components(separatedBy: "/")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if tokens.isEmpty { return false }
                    for token in tokens {
                        let words = token.components(separatedBy: .whitespacesAndNewlines)
                            .filter { !$0.isEmpty }
                        if token.count > 24 || words.count > 3 {
                            return false
                        }
                        if words.count > 1 {
                            hasSpaceInsideToken = true
                        }
                        if token.contains("$") || token.contains("€") || token.contains("!") {
                            hasMnemonicSignal = true
                        }
                        for w in words {
                            let wLetters = w.unicodeScalars.filter { CharacterSet.letters.contains($0) }
                            if wLetters.count >= 2 && wLetters.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) {
                                hasMnemonicSignal = true
                            }
                        }
                        totalTokens += 1
                    }
                }
                guard totalTokens >= 2 || clusters.count >= 2 else { return false }
                return !hasSpaceInsideToken || hasMnemonicSignal
            } else {
                guard clusters.count >= 2 else { return false }
                var hasMnemonicSignal = false
                for cluster in clusters {
                    let words = cluster.components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                    if cluster.count > 24 || words.count > 3 {
                        return false
                    }
                    let lettersOnly = cluster.unicodeScalars.filter { CharacterSet.letters.contains($0) }
                    let isAllCaps = !lettersOnly.isEmpty && lettersOnly.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
                    let hasGlyph = cluster.contains("$") || cluster.contains("€") || cluster.contains("!") ||
                        cluster.rangeOfCharacter(from: .decimalDigits) != nil
                    if hasGlyph || isAllCaps || cluster.count <= 5 {
                        hasMnemonicSignal = true
                    }
                }
                return hasMnemonicSignal
            }
        }

        // Single-token check: no spaces, compact length, and mnemonic formatting
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.count <= 12 else {
            return false
        }
        if lower.contains(".com") {
            return false
        }
        let hasSemanticGlyph = trimmed.contains("$") || trimmed.contains("€") || trimmed.contains("!") ||
            trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        if hasSemanticGlyph {
            return true
        }
        let lettersOnly = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let isAllCaps = !lettersOnly.isEmpty && lettersOnly.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
        return isAllCaps || trimmed.count <= 4
    }

    /// Generates an editable mnemonic tag proposal for natural-language tasks.
    public func proposeMnemonic(for title: String, isHighImportance: Bool = false) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return isHighImportance ? "TASK!" : "TASK" }
        if isAlreadyTagdosDsl(trimmed) {
            if isHighImportance && !trimmed.contains("!") && !trimmed.contains("/") && !trimmed.contains("&") {
                return "\(trimmed)!"
            }
            return trimmed
        }

        let stopWords: Set<String> = [
            "the", "a", "an", "to", "for", "of", "in", "on", "at", "and", "or", "with", "my", "this", "that",
            "la", "de", "si", "cu", "pt", "pentru", "pe", "din", "un", "o", "sa"
        ]
        let financialWords: Set<String> = [
            "pay", "bill", "bills", "invoice", "tax", "taxes", "bank", "card", "budget", "buy", "rent",
            "salary", "transfer", "money", "cost", "price", "fee", "plata", "factura", "bani", "buget", "eur", "usd", "ron"
        ]
        let urgentWords: Set<String> = ["urgent", "asap", "important", "deadline", "critical", "immediately"]

        let rawTokens = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let significant = rawTokens.filter { !stopWords.contains($0.lowercased()) }
        let words = significant.isEmpty ? rawTokens : significant

        let hasEuro = trimmed.contains("€") || rawTokens.contains(where: { $0.lowercased() == "eur" || $0.lowercased() == "euro" })
        let hasDollar = trimmed.contains("$") || rawTokens.contains(where: { financialWords.contains($0.lowercased()) })
        let isUrgent = isHighImportance || trimmed.contains("!") || rawTokens.contains(where: { urgentWords.contains($0.lowercased()) })

        var base: String
        if words.isEmpty {
            base = "TASK"
        } else if words.count == 1 {
            base = String(words[0].prefix(5)).uppercased()
        } else if words.count == 2 {
            let p1 = String(words[0].prefix(3))
            let p2 = String(words[1].prefix(3))
            base = String((p1 + p2).prefix(6)).uppercased()
        } else {
            let p1 = String(words[0].prefix(2))
            let p2 = String(words[1].prefix(2))
            let p3 = String(words[2].prefix(2))
            base = String((p1 + p2 + p3).prefix(6)).uppercased()
        }

        if hasEuro && !base.contains("€") {
            base += "€"
        } else if hasDollar && !base.contains("$") {
            base += "$"
        }
        if isUrgent && !base.contains("!") {
            base += "!"
        }
        return base
    }

    public func prepareImportItem(
        title: String,
        notes: String? = nil,
        isHighImportance: Bool = false
    ) -> (tagOrDsl: String, isAlreadyDsl: Bool, memoEntry: String?) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanNotes = rawNotes.caseInsensitiveCompare(cleanTitle) == .orderedSame ? "" : rawNotes
        let isDsl = isAlreadyTagdosDsl(cleanTitle)
        let tag = isDsl ? cleanTitle : proposeMnemonic(for: cleanTitle, isHighImportance: isHighImportance)

        if isDsl {
            // Plain notes only without any [DSL] prefix or title duplication
            let memo = cleanNotes.isEmpty ? nil : cleanNotes
            return (tag, true, memo)
        } else {
            let memo = cleanNotes.isEmpty
                ? "• [\(tag)] \(cleanTitle)"
                : "• [\(tag)] \(cleanTitle) — \(cleanNotes)"
            return (tag, false, memo)
        }
    }

    /// Cycles a pill to the end of its cluster (or end of stream) for recurring habits.
    public func recyclePillToBack(in stream: TagDoStream, pillId: UUID) -> TagDoStream {
        var updatedClusters = stream.clusters

        for clusterIndex in 0..<updatedClusters.count {
            var cluster = updatedClusters[clusterIndex]
            if let pillIndex = cluster.pills.firstIndex(where: { $0.id == pillId }) {
                var pill = cluster.pills.remove(at: pillIndex)
                pill.isCompleted = false // Reset completed status for next cycle
                cluster.pills.append(pill)
                cluster.rawText = cluster.pills.map { $0.rawText }.joined(separator: "/")
                updatedClusters[clusterIndex] = cluster
                break
            }
        }

        let newRawText = updatedClusters.map { $0.rawText }.joined(separator: " & ")
        return TagDoStream(
            id: stream.id,
            title: stream.title,
            customTitle: stream.customTitle,
            rawText: newRawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex,
            activeMemos: stream.activeMemos,
            attachments: stream.attachments,
            updatedAt: Date()
        )
    }

    /// Toggles completion status of a pill in-place.
    public func togglePillCompletion(in stream: TagDoStream, pillId: UUID) -> TagDoStream {
        var updatedClusters = stream.clusters

        for clusterIndex in 0..<updatedClusters.count {
            var cluster = updatedClusters[clusterIndex]
            if let pillIndex = cluster.pills.firstIndex(where: { $0.id == pillId }) {
                cluster.pills[pillIndex].isCompleted.toggle()
                updatedClusters[clusterIndex] = cluster
                break
            }
        }

        return TagDoStream(
            id: stream.id,
            title: stream.title,
            customTitle: stream.customTitle,
            rawText: stream.rawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex,
            activeMemos: stream.activeMemos,
            attachments: stream.attachments,
            updatedAt: Date()
        )
    }

    /// Removes a pill from the stream (one-off task).
    public func removePill(in stream: TagDoStream, pillId: UUID) -> TagDoStream {
        var updatedClusters = stream.clusters

        for clusterIndex in (0..<updatedClusters.count).reversed() {
            var cluster = updatedClusters[clusterIndex]
            if let pillIndex = cluster.pills.firstIndex(where: { $0.id == pillId }) {
                cluster.pills.remove(at: pillIndex)
                if cluster.pills.isEmpty {
                    updatedClusters.remove(at: clusterIndex)
                } else {
                    cluster.rawText = cluster.pills.map { $0.rawText }.joined(separator: "/")
                    updatedClusters[clusterIndex] = cluster
                }
                break
            }
        }

        let newRawText = updatedClusters.map { $0.rawText }.joined(separator: " & ")
        return TagDoStream(
            id: stream.id,
            title: stream.title,
            customTitle: stream.customTitle,
            rawText: newRawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex,
            activeMemos: stream.activeMemos,
            attachments: stream.attachments,
            updatedAt: Date()
        )
    }

    /// Moves a pill to the very beginning of its cluster (highest priority).
    public func movePillToFront(in stream: TagDoStream, pillId: UUID) -> TagDoStream {
        var updatedClusters = stream.clusters

        for clusterIndex in 0..<updatedClusters.count {
            var cluster = updatedClusters[clusterIndex]
            if let pillIndex = cluster.pills.firstIndex(where: { $0.id == pillId }) {
                let pill = cluster.pills.remove(at: pillIndex)
                cluster.pills.insert(pill, at: 0)
                cluster.rawText = cluster.pills.map { $0.rawText }.joined(separator: "/")
                updatedClusters[clusterIndex] = cluster
                break
            }
        }

        let newRawText = updatedClusters.map { $0.rawText }.joined(separator: " & ")
        return TagDoStream(
            id: stream.id,
            title: stream.title,
            customTitle: stream.customTitle,
            rawText: newRawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex,
            activeMemos: stream.activeMemos,
            attachments: stream.attachments,
            updatedAt: Date()
        )
    }

    /// Adds a new pill into a specific cluster or creates a new one.
    public func addPill(in stream: TagDoStream, clusterIndex: Int, text: String) -> TagDoStream {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return stream }

        var updatedClusters = stream.clusters
        let newPill = TagDoPill(rawText: cleanText)

        if updatedClusters.isEmpty {
            updatedClusters.append(TagDoCluster(pills: [newPill], rawText: cleanText))
        } else if clusterIndex >= 0 && clusterIndex < updatedClusters.count {
            var cluster = updatedClusters[clusterIndex]
            cluster.pills.append(newPill)
            cluster.rawText = cluster.pills.map { $0.rawText }.joined(separator: "/")
            updatedClusters[clusterIndex] = cluster
        } else {
            if var last = updatedClusters.last {
                last.pills.append(newPill)
                last.rawText = last.pills.map { $0.rawText }.joined(separator: "/")
                updatedClusters[updatedClusters.count - 1] = last
            } else {
                updatedClusters.append(TagDoCluster(pills: [newPill], rawText: cleanText))
            }
        }

        let newRawText = updatedClusters.map { $0.rawText }.joined(separator: " & ")
        return TagDoStream(
            id: stream.id,
            title: stream.title,
            customTitle: stream.customTitle,
            rawText: newRawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex,
            activeMemos: stream.activeMemos,
            attachments: stream.attachments,
            updatedAt: Date()
        )
    }
}
