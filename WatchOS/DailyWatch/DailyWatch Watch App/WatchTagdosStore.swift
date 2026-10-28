import Foundation
import SwiftUI
import Combine
import Supabase

@MainActor
public final class WatchTagdosStore: ObservableObject {
    public static let shared = WatchTagdosStore()

    @Published public var streams: [WatchTagDoStream] = []
    @Published public var quickNotes: [WatchTagDoQuickNote] = []
    @Published public var selectedStreamIndex: Int = 0
    @Published public var isSyncing: Bool = false

    private let streamsCacheKey = "watch_tagdos_streams_cache_v1"
    private let notesCacheKey = "watch_tagdos_quick_notes_cache_v1"
    private var lastFetchDate: Date? = nil

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.intellidream.daily") ?? UserDefaults.standard
    }

    private init() {
        loadCachedData()
    }

    // MARK: - Local Cache

    private func loadCachedData() {
        if let data = defaults.data(forKey: streamsCacheKey),
           let cached = try? JSONDecoder().decode([WatchTagDoStream].self, from: data),
           !cached.isEmpty {
            self.streams = cached
        } else {
            // Default starter fallback
            self.streams = [
                WatchTagdosParser.shared.parseStream(
                    rawText: "MG/GM/TG & FSH/LDL & C$T/DUB/14 & PL98/PBZ/SPL/CLN",
                    title: "Daily Ops",
                    streamNumber: 1
                ),
                WatchTagdosParser.shared.parseStream(
                    rawText: "WRK/PRJ/REV & MET/ZOOM/CALL & TKT/BUG/PR",
                    title: "Work & Code",
                    streamNumber: 2
                ),
                WatchTagdosParser.shared.parseStream(
                    rawText: "FIT/GYM/RUN & PROT/CREAT & SLP/REC/HRV",
                    title: "Health & Fitness",
                    streamNumber: 3
                ),
                WatchTagdosParser.shared.parseStream(
                    rawText: "FIN/CARD/CASH & INV/STK/CRYP & SUB/UTL/CHL",
                    title: "Finances & Bills",
                    streamNumber: 4
                ),
                WatchTagdosParser.shared.parseStream(
                    rawText: "HOM/ORD/CLN & BUY/MKT/GROC & FAM/CALL/VIS",
                    title: "Home & Life",
                    streamNumber: 5
                )
            ]
        }

        if let data = defaults.data(forKey: notesCacheKey),
           let cached = try? JSONDecoder().decode([WatchTagDoQuickNote].self, from: data) {
            self.quickNotes = cached
        } else {
            self.quickNotes = [
                WatchTagDoQuickNote(title: "Groceries", content: "Lapte de migdale, Cafea Columbia, Fructe de padure"),
                WatchTagDoQuickNote(title: "Passcode Parking", content: "#5829 intrare subteran")
            ]
        }
    }

    private func persistData() {
        if let data = try? JSONEncoder().encode(streams) {
            defaults.set(data, forKey: streamsCacheKey)
        }
        if let data = try? JSONEncoder().encode(quickNotes) {
            defaults.set(data, forKey: notesCacheKey)
        }
    }

    // MARK: - Supabase Cloud Synchronization

    public func fetchTagdosData(force: Bool = false) async {
        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < 45 {
            return
        }
        guard let client = WatchSessionManager.shared.supabaseClient,
              let userId = WatchSessionManager.shared.currentUserId else {
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            lastFetchDate = Date()
        }

        // 1. Fetch Streams
        do {
            struct RemoteStreamDTO: Codable {
                let id: UUID
                let user_id: UUID
                let stream_number: Int
                let title: String
                let raw_syntax: String
                let updated_at: Date
            }

            let res = try await client
                .from("tagdos_streams")
                .select("id, user_id, stream_number, title, raw_syntax, updated_at")
                .eq("user_id", value: userId.uuidString)
                .order("stream_number", ascending: true)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteStreams = try decoder.decode([RemoteStreamDTO].self, from: res.data)

            if !remoteStreams.isEmpty {
                var updatedStreams: [WatchTagDoStream] = []
                for remote in remoteStreams {
                    let existing = self.streams.first(where: { $0.streamNumber == remote.stream_number })
                    let parsed = WatchTagdosParser.shared.parseStream(
                        rawText: remote.raw_syntax,
                        title: remote.title,
                        streamNumber: remote.stream_number,
                        id: remote.id,
                        existingStream: existing
                    )
                    updatedStreams.append(parsed)
                }
                updatedStreams.sort { $0.streamNumber < $1.streamNumber }
                self.streams = updatedStreams
                persistData()
            }
        } catch {
            print("[WatchTagdosStore] Streams sync error: \(error)")
        }

        // 2. Fetch Pinned Quick Notes
        do {
            let resNotes = try await client
                .from("tagdos_quick_notes")
                .select("id, title, content, is_pinned, updated_at")
                .eq("user_id", value: userId.uuidString)
                .eq("is_pinned", value: true)
                .order("updated_at", ascending: false)
                .limit(10)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteNotes = try decoder.decode([WatchTagDoQuickNote].self, from: resNotes.data)

            if !remoteNotes.isEmpty {
                self.quickNotes = remoteNotes
                persistData()
            }
        } catch {
            print("[WatchTagdosStore] Notes sync error: \(error)")
        }
    }

    // MARK: - Actions

    public func completePill(streamNumber: Int, pillId: UUID) {
        guard let sIdx = streams.firstIndex(where: { $0.streamNumber == streamNumber }) else { return }
        var stream = streams[sIdx]

        // Find pill and mark completed
        var pillFound = false
        var updatedClusters: [WatchTagDoCluster] = []
        for cluster in stream.clusters {
            var updatedPills: [WatchTagDoPill] = []
            for pill in cluster.pills {
                if pill.id == pillId {
                    pillFound = true
                    var completedPill = pill
                    completedPill.isCompleted = true
                    updatedPills.append(completedPill)
                } else {
                    updatedPills.append(pill)
                }
            }
            updatedClusters.append(WatchTagDoCluster(id: cluster.id, pills: updatedPills, rawText: cluster.rawText))
        }

        guard pillFound else { return }

        // Reconstruct raw syntax without the completed pill or advance
        let activeClusterStrings = updatedClusters.compactMap { cluster -> String? in
            let activeTokens = cluster.pills.filter { !$0.isCompleted }.map { $0.rawText }
            return activeTokens.isEmpty ? nil : activeTokens.joined(separator: "/")
        }
        let newRawSyntax = activeClusterStrings.joined(separator: " & ")

        stream.clusters = updatedClusters
        stream.rawText = newRawSyntax
        stream.updatedAt = Date()
        streams[sIdx] = stream
        persistData()

        // Asynchronously update remote Supabase
        Task {
            guard let client = WatchSessionManager.shared.supabaseClient,
                  let userId = WatchSessionManager.shared.currentUserId else { return }
            do {
                try await client
                    .from("tagdos_streams")
                    .update(["raw_syntax": newRawSyntax, "updated_at": ISO8601DateFormatter().string(from: Date())])
                    .eq("user_id", value: userId.uuidString)
                    .eq("stream_number", value: streamNumber)
                    .execute()
            } catch {
                print("[WatchTagdosStore] Failed to update stream after completion: \(error)")
            }
        }
    }

    public func recycleDrivingPill(streamNumber: Int) {
        guard let sIdx = streams.firstIndex(where: { $0.streamNumber == streamNumber }) else { return }
        var stream = streams[sIdx]
        guard let driving = stream.drivingPill else { return }

        // Move driving pill to the end of the line
        var clusters = stream.clusters
        guard !clusters.isEmpty else { return }

        var firstClusterPills = clusters[0].pills.filter { $0.id != driving.id }
        if firstClusterPills.isEmpty && clusters.count > 1 {
            // Pill was sole item in first cluster, move it to end of last cluster
            var lastClusterPills = clusters[clusters.count - 1].pills
            lastClusterPills.append(driving)
            clusters[clusters.count - 1] = WatchTagDoCluster(id: clusters[clusters.count - 1].id, pills: lastClusterPills, rawText: "")
            clusters.remove(at: 0)
        } else {
            firstClusterPills.append(driving)
            clusters[0] = WatchTagDoCluster(id: clusters[0].id, pills: firstClusterPills, rawText: "")
        }

        let newRawSyntax = clusters.map { c in c.pills.map { $0.rawText }.joined(separator: "/") }.joined(separator: " & ")
        stream.clusters = clusters
        stream.rawText = newRawSyntax
        stream.updatedAt = Date()
        streams[sIdx] = stream
        persistData()

        Task {
            guard let client = WatchSessionManager.shared.supabaseClient,
                  let userId = WatchSessionManager.shared.currentUserId else { return }
            do {
                try await client
                    .from("tagdos_streams")
                    .update(["raw_syntax": newRawSyntax, "updated_at": ISO8601DateFormatter().string(from: Date())])
                    .eq("user_id", value: userId.uuidString)
                    .eq("stream_number", value: streamNumber)
                    .execute()
            } catch {
                print("[WatchTagdosStore] Failed to recycle pill: \(error)")
            }
        }
    }

    public func addQuickTask(streamNumber: Int, taskText: String) {
        let clean = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "&", with: "+")
        guard !clean.isEmpty else { return }

        guard let sIdx = streams.firstIndex(where: { $0.streamNumber == streamNumber }) else { return }
        var stream = streams[sIdx]

        let newRawSyntax: String
        if stream.rawText.isEmpty {
            newRawSyntax = clean
        } else {
            newRawSyntax = "\(stream.rawText)/\(clean)"
        }

        stream = WatchTagdosParser.shared.parseStream(
            rawText: newRawSyntax,
            title: stream.title,
            streamNumber: streamNumber,
            id: stream.id,
            existingStream: stream
        )
        streams[sIdx] = stream
        persistData()

        Task {
            guard let client = WatchSessionManager.shared.supabaseClient,
                  let userId = WatchSessionManager.shared.currentUserId else { return }
            do {
                try await client
                    .from("tagdos_streams")
                    .update(["raw_syntax": newRawSyntax, "updated_at": ISO8601DateFormatter().string(from: Date())])
                    .eq("user_id", value: userId.uuidString)
                    .eq("stream_number", value: streamNumber)
                    .execute()
            } catch {
                print("[WatchTagdosStore] Failed to add quick task: \(error)")
            }
        }
    }

    public func addQuickNote(title: String, content: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty || !cleanTitle.isEmpty else { return }

        let finalTitle = cleanTitle.isEmpty ? (cleanContent.components(separatedBy: .newlines).first ?? "Note") : cleanTitle
        let newNote = WatchTagDoQuickNote(title: finalTitle, content: cleanContent.isEmpty ? finalTitle : cleanContent, isPinned: true)
        quickNotes.insert(newNote, at: 0)
        persistData()

        Task {
            guard let client = WatchSessionManager.shared.supabaseClient,
                  let userId = WatchSessionManager.shared.currentUserId else { return }
            do {
                struct InsertNoteDTO: Encodable {
                    let id: UUID
                    let user_id: UUID
                    let title: String
                    let content: String
                    let is_pinned: Bool
                }
                let dto = InsertNoteDTO(
                    id: newNote.id,
                    user_id: userId,
                    title: newNote.title,
                    content: newNote.content,
                    is_pinned: true
                )
                try await client
                    .from("tagdos_quick_notes")
                    .insert(dto)
                    .execute()
            } catch {
                print("[WatchTagdosStore] Failed to add note: \(error)")
            }
        }
    }
}
