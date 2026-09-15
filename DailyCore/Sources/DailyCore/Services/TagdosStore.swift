import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Reactive centralized store managing TagDoS streams, mental tags, and quick notes.
@MainActor
public final class TagdosStore: ObservableObject {
    public static let shared = TagdosStore()

    // MARK: - Published State
    @Published public private(set) var streams: [TagDoStream] = []
    @Published public private(set) var quickNotes: [String] = []

    // MARK: - Storage Keys
    private let streamsStorageKey = "daily_tagdos_raw_streams_v1"
    private let notesStorageKey = "daily_tagdos_quick_notes_v1"

    // MARK: - Default Starter Streams
    public static let defaultStream1 = "MG/GM/TG & FSH/LDL & C$T/DUB/14 & PL98/PBZ/SPL/CLN/ROT$ & BP/ACTE & VER/CLD/DIV$/CNTR/!MP$/FCT$/STK/BON$ & BIA/€CO & SSD/ELVS/MEIZ & GORN/PICI/CRNA/IOA & CDO/SRN/NLU/NIN/SVS & ITP/CRRvg/Park/Ghis"
    public static let defaultStream2 = "WRK/PRJ/REV & MET/ZOOM/CALL & TKT/BUG/PR & DEPL/REL"
    public static let defaultStream3 = "FIT/GYM/RUN & PROT/CREAT & SLP/REC/HRV"
    public static let defaultStream4 = "FIN/CARD/CASH & INV/STK/CRYP & SUB/UTL/CHL"
    public static let defaultStream5 = "HOM/ORD/CLN & BUY/MKT/GROC & FAM/CALL/VIS"

    private init() {
        loadFromStorage()
    }

    // MARK: - Persistence & Hydration

    private func loadFromStorage() {
        let groupDefaults = GroupDefaults.shared.userDefaults
        
        // Load Quick Notes
        if let storedNotes = groupDefaults.stringArray(forKey: notesStorageKey) {
            self.quickNotes = storedNotes
        } else if let localNotes = UserDefaults.standard.stringArray(forKey: notesStorageKey) {
            self.quickNotes = localNotes
        } else {
            self.quickNotes = [
                "DUBaFest bilete: ia pt CiSTiu si asigura buget 2x",
                "Urmeaza benzina 98 la urmatorul plin, apoi curatat interior"
            ]
        }

        // Load Streams Data
        if let data = groupDefaults.data(forKey: streamsStorageKey),
           let decoded = try? JSONDecoder().decode([TagDoStream].self, from: data),
           !decoded.isEmpty {
            self.streams = decoded
            syncWithWidgets()
            return
        }

        if let data = UserDefaults.standard.data(forKey: streamsStorageKey),
           let decoded = try? JSONDecoder().decode([TagDoStream].self, from: data),
           !decoded.isEmpty {
            self.streams = decoded
            syncWithWidgets()
            return
        }

        // Seed Default 5 Streams
        let parser = TagdosParser.shared
        let defaultStreams: [TagDoStream] = [
            parser.parseStream(rawText: Self.defaultStream1, title: "Stream 1: Daily Ops", orderIndex: 0),
            parser.parseStream(rawText: Self.defaultStream2, title: "Stream 2: Work & Code", orderIndex: 1),
            parser.parseStream(rawText: Self.defaultStream3, title: "Stream 3: Health & Fitness", orderIndex: 2),
            parser.parseStream(rawText: Self.defaultStream4, title: "Stream 4: Finances & Bills", orderIndex: 3),
            parser.parseStream(rawText: Self.defaultStream5, title: "Stream 5: Home & Life", orderIndex: 4)
        ]

        self.streams = defaultStreams
        save()
    }

    public func save() {
        let groupDefaults = GroupDefaults.shared.userDefaults

        // Encode Streams
        if let data = try? JSONEncoder().encode(streams) {
            groupDefaults.set(data, forKey: streamsStorageKey)
            UserDefaults.standard.set(data, forKey: streamsStorageKey)
        }

        // Save Notes
        groupDefaults.set(quickNotes, forKey: notesStorageKey)
        UserDefaults.standard.set(quickNotes, forKey: notesStorageKey)

        syncWithWidgets()
    }

    // MARK: - Stream Mutations

    public func updateStreamRawText(streamId: UUID, newRawText: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let existing = streams[index]
        let updated = TagdosParser.shared.parseStream(
            rawText: newRawText,
            title: existing.title,
            id: existing.id,
            streamReminder: existing.streamReminder,
            orderIndex: existing.orderIndex,
            existingStream: existing
        )
        streams[index] = updated
        save()
    }

    public func updateStreamTitle(streamId: UUID, newTitle: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        streams[index].title = newTitle
        save()
    }

    public func setStreamReminder(streamId: UUID, date: Date?) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        streams[index].streamReminder = date
        save()
    }

    public func recyclePillToBack(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let updated = TagdosParser.shared.recyclePillToBack(in: streams[index], pillId: pillId)
        streams[index] = updated
        save()
    }

    public func togglePillCompletion(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let updated = TagdosParser.shared.togglePillCompletion(in: streams[index], pillId: pillId)
        streams[index] = updated
        save()
    }

    public func removePill(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let updated = TagdosParser.shared.removePill(in: streams[index], pillId: pillId)
        streams[index] = updated
        save()
    }

    public func movePillToFront(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let updated = TagdosParser.shared.movePillToFront(in: streams[index], pillId: pillId)
        streams[index] = updated
        save()
    }

    public func addPill(streamId: UUID, clusterIndex: Int, text: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }),
              clusterIndex < streams[index].clusters.count else { return }

        var cluster = streams[index].clusters[clusterIndex]
        cluster.pills.append(TagDoPill(rawText: text))
        cluster.rawText = cluster.pills.map { $0.rawText }.joined(separator: "/")
        streams[index].clusters[clusterIndex] = cluster
        streams[index].rawText = TagdosParser.shared.serializeStream(streams[index])
        save()
    }

    // MARK: - Notes Mutations

    public func addQuickNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        quickNotes.insert(trimmed, at: 0)
        save()
    }

    public func removeQuickNote(at index: Int) {
        guard index < quickNotes.count else { return }
        quickNotes.remove(at: index)
        save()
    }

    // MARK: - Widget Synchronization

    public func syncWithWidgets() {
        let snapshotStreams = streams.map { stream in
            let driving = stream.drivingPill
            let reminderStr: String? = {
                guard let rem = stream.streamReminder else { return nil }
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                return formatter.string(from: rem)
            }()

            let snapshotPills = stream.allPills.prefix(10).map { pill in
                TagdosWidgetSnapshotPill(
                    text: pill.rawText,
                    typeRaw: pill.type.rawValue,
                    isCompleted: pill.isCompleted
                )
            }

            return TagdosWidgetSnapshotStream(
                id: stream.id.uuidString,
                title: stream.title,
                drivingPillText: driving?.rawText,
                drivingPillType: driving?.type.rawValue,
                activePillsCount: stream.activePills.count,
                reminderTimeFormatted: reminderStr,
                pills: Array(snapshotPills)
            )
        }

        let totalActive = streams.reduce(0) { $0 + $1.activePills.count }
        
        let nextReminderStr: String? = {
            let upcoming = streams.compactMap { $0.streamReminder }.sorted().first
            guard let date = upcoming else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }()

        let snapshot = TagdosWidgetSnapshot(
            streams: snapshotStreams,
            totalActivePills: totalActive,
            nextReminderFormatted: nextReminderStr,
            lastUpdated: Date()
        )

        WidgetDataCoordinator.shared.updateTagdosSnapshot(snapshot)
    }
}
