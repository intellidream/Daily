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
            rawText: trimmed,
            clusters: parsedClusters,
            streamReminder: streamReminder,
            orderIndex: orderIndex
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
            rawText: newRawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex
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
            rawText: stream.rawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex
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
            rawText: newRawText,
            clusters: updatedClusters,
            streamReminder: stream.streamReminder,
            orderIndex: stream.orderIndex
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
