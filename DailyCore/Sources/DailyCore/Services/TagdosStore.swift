import Foundation
import Combine
import Supabase
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Reactive centralized store managing TagDoS streams, mental tags, per-stream active memos, attachments, and quick notes.
/// Backed by local App Group storage with Supabase cloud synchronization and live Realtime reflection.
@MainActor
public final class TagdosStore: ObservableObject {
    public static let shared = TagdosStore()

    // MARK: - Published State
    @Published public private(set) var streams: [TagDoStream] = []
    @Published public private(set) var quickNotes: [TagDoQuickNote] = []
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncedAt: Date? = nil
    @Published public private(set) var cloudSyncError: String? = nil

    // MARK: - Storage Keys
    private let streamsStorageKey = "daily_tagdos_raw_streams_v1"
    private let notesStorageKey = "daily_tagdos_quick_notes_v1"
    private let legacyNotesKey = "daily_tagdos_quick_notes_legacy_v1"

    // MARK: - Default Starter Streams
    public static let defaultStream1 = "MG/GM/TG & FSH/LDL & C$T/DUB/14 & PL98/PBZ/SPL/CLN/ROT$ & BP/ACTE & VER/CLD/DIV$/CNTR/!MP$/FCT$/STK/BON$ & BIA/€CO & SSD/ELVS/MEIZ & GORN/PICI/CRNA/IOA & CDO/SRN/NLU/NIN/SVS & ITP/CRRvg/Park/Ghis"
    public static let defaultStream2 = "WRK/PRJ/REV & MET/ZOOM/CALL & TKT/BUG/PR & DEPL/REL"
    public static let defaultStream3 = "FIT/GYM/RUN & PROT/CREAT & SLP/REC/HRV"
    public static let defaultStream4 = "FIN/CARD/CASH & INV/STK/CRYP & SUB/UTL/CHL"
    public static let defaultStream5 = "HOM/ORD/CLN & BUY/MKT/GROC & FAM/CALL/VIS"

    private var realtimeChannel: RealtimeChannelV2?
    private var pushDebounceTask: Task<Void, Never>?

    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? UserDefaults.standard
    }

    private init() {
        loadFromStorage()
        setupLifecycleObservers()
        
        Task {
            await syncWithSupabase()
            await setupRealtimeSubscription()
        }
    }

    // MARK: - Lifecycle & Foreground Observers

    private func setupLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.loadFromStorage()
                await self.syncWithSupabase()
            }
        }
        #endif
    }

    // MARK: - Persistence & Hydration

    private func loadFromStorage() {
        // 1. Load Quick Notes (TagDoQuickNote)
        if let data = groupDefaults.data(forKey: notesStorageKey),
           let decoded = try? JSONDecoder().decode([TagDoQuickNote].self, from: data) {
            self.quickNotes = decoded
        } else if let data = UserDefaults.standard.data(forKey: notesStorageKey),
                  let decoded = try? JSONDecoder().decode([TagDoQuickNote].self, from: data) {
            self.quickNotes = decoded
        } else {
            // Migrate legacy string notes if any
            let legacyStrings = groupDefaults.stringArray(forKey: legacyNotesKey)
                ?? UserDefaults.standard.stringArray(forKey: legacyNotesKey)
                ?? [
                    "DUBaFest bilete: ia pt CiSTiu si asigura buget 2x",
                    "Urmeaza benzina 98 la urmatorul plin, apoi curatat interior"
                ]
            self.quickNotes = legacyStrings.map { text in
                TagDoQuickNote(
                    title: text.components(separatedBy: ":").first ?? "Note",
                    content: text
                )
            }
        }

        // 2. Load Streams Data
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

    public func save(triggerCloudSync: Bool = true) {
        // Encode Streams
        if let data = try? JSONEncoder().encode(streams) {
            groupDefaults.set(data, forKey: streamsStorageKey)
            UserDefaults.standard.set(data, forKey: streamsStorageKey)
        }

        // Save Quick Notes
        if let notesData = try? JSONEncoder().encode(quickNotes) {
            groupDefaults.set(notesData, forKey: notesStorageKey)
            UserDefaults.standard.set(notesData, forKey: notesStorageKey)
        }

        syncWithWidgets()

        if triggerCloudSync {
            scheduleCloudPush()
        }
    }

    // MARK: - Stream Mutations

    public func updateStreamRawText(streamId: UUID, newRawText: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let existing = streams[index]
        var updated = TagdosParser.shared.parseStream(
            rawText: newRawText,
            title: existing.customTitle ?? existing.title,
            id: existing.id,
            streamReminder: existing.streamReminder,
            orderIndex: existing.orderIndex,
            existingStream: existing
        )
        updated.customTitle = existing.customTitle
        if existing.customTitle == nil || existing.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            updated.title = updated.autoDetectedTitle
        }
        updated.activeMemos = existing.activeMemos
        updated.attachments = existing.attachments
        updated.updatedAt = Date()
        streams[index] = updated
        save()
    }

    public func updateStreamTitle(streamId: UUID, newTitle: String?) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let clean = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let clean = clean, !clean.isEmpty {
            // User explicitly set a custom title
            streams[index].customTitle = clean
            streams[index].title = clean
        } else {
            // User cleared the title -> re-detect title from stream content
            streams[index].customTitle = nil
            streams[index].title = streams[index].autoDetectedTitle
        }
        streams[index].updatedAt = Date()
        save()
    }

    public func setStreamReminder(streamId: UUID, date: Date?) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        streams[index].streamReminder = date
        streams[index].updatedAt = Date()
        save()
    }

    public func updateStreamMemos(streamId: UUID, memos: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        streams[index].activeMemos = memos
        streams[index].updatedAt = Date()
        save()
    }

    public func recyclePillToBack(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.recyclePillToBack(in: streams[index], pillId: pillId)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        save()
    }

    public func togglePillCompletion(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.togglePillCompletion(in: streams[index], pillId: pillId)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        save()
    }

    public func removePill(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.removePill(in: streams[index], pillId: pillId)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        save()
    }

    public func movePillToFront(streamId: UUID, pillId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.movePillToFront(in: streams[index], pillId: pillId)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        save()
    }

    public func addPill(streamId: UUID, clusterIndex: Int, text: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        var updated = TagdosParser.shared.addPill(in: streams[index], clusterIndex: clusterIndex, text: text)
        updated.activeMemos = streams[index].activeMemos
        updated.attachments = streams[index].attachments
        updated.updatedAt = Date()
        streams[index] = updated
        save()
    }

    // MARK: - Per-Stream Attachment Operations

    public func addAttachment(
        streamId: UUID,
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws {
        guard let index = streams.firstIndex(where: { $0.id == streamId }) else { return }
        let streamNumber = streams[index].orderIndex + 1

        let attachment = TagDoAttachment(
            streamNumber: streamNumber,
            fileName: fileName,
            fileType: mimeType,
            fileSizeBytes: Int64(data.count)
        )

        // 1. Save to local disk cache immediately
        _ = try TagdosAttachmentManager.shared.saveLocalData(data, for: attachment)

        // 2. Add to stream in memory and save locally
        streams[index].attachments.append(attachment)
        streams[index].updatedAt = Date()
        save()

        // 3. Upload to Supabase Storage in background if authenticated
        if let userId = getEffectiveUserId() {
            Task {
                do {
                    let remotePath = try await TagdosAttachmentManager.shared.uploadAttachment(
                        attachment,
                        data: data,
                        userId: userId
                    )
                    await MainActor.run {
                        if let sIdx = self.streams.firstIndex(where: { $0.id == streamId }),
                           let aIdx = self.streams[sIdx].attachments.firstIndex(where: { $0.id == attachment.id }) {
                            self.streams[sIdx].attachments[aIdx].remotePath = remotePath
                            self.save()
                        }
                    }
                } catch {
                    print("[TagdosStore] Attachment upload warning: \(error.localizedDescription)")
                }
            }
        }
    }

    public func downloadAttachment(_ attachment: TagDoAttachment) async throws -> URL {
        let localURL = try await TagdosAttachmentManager.shared.downloadAttachment(attachment)
        objectWillChange.send()
        return localURL
    }

    public func deleteAttachment(streamId: UUID, attachmentId: UUID) async {
        guard let sIdx = streams.firstIndex(where: { $0.id == streamId }),
              let aIdx = streams[sIdx].attachments.firstIndex(where: { $0.id == attachmentId }) else { return }
        
        let attachment = streams[sIdx].attachments[aIdx]
        streams[sIdx].attachments.remove(at: aIdx)
        streams[sIdx].updatedAt = Date()
        save()

        await TagdosAttachmentManager.shared.deleteAttachment(attachment)
    }

    // MARK: - Quick Notes Mutations

    public func createQuickNote(title: String = "", content: String = "") {
        let note = TagDoQuickNote(
            userId: getEffectiveUserId(),
            title: title,
            content: content
        )
        quickNotes.insert(note, at: 0)
        save()
    }

    public func updateQuickNote(id: UUID, title: String, content: String) {
        guard let index = quickNotes.firstIndex(where: { $0.id == id }) else { return }
        quickNotes[index].title = title
        quickNotes[index].content = content
        quickNotes[index].updatedAt = Date()
        save()
    }

    public func togglePinQuickNote(id: UUID) {
        guard let index = quickNotes.firstIndex(where: { $0.id == id }) else { return }
        quickNotes[index].isPinned.toggle()
        quickNotes[index].updatedAt = Date()
        // Sort pinned first
        quickNotes.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
        save()
    }

    public func deleteQuickNote(id: UUID) {
        quickNotes.removeAll { $0.id == id }
        save()
        
        // Also delete from Supabase if authenticated
        if let userId = getEffectiveUserId() {
            Task {
                let client = SupabaseService.shared.client
                _ = try? await client
                    .from("tagdos_quick_notes")
                    .delete()
                    .eq("id", value: id.uuidString.lowercased())
                    .eq("user_id", value: userId)
                    .execute()
            }
        }
    }

    // MARK: - Supabase Cloud Synchronization

    private func getEffectiveUserId() -> String? {
        if let currentId = AuthService.shared.currentUser?.id, currentId != "guest" {
            return currentId.lowercased()
        }
        if let storedId = GroupDefaults.shared.userDefaults.string(forKey: "supabase_user_id"), storedId != "guest" {
            return storedId.lowercased()
        }
        return nil
    }

    private func getEffectiveUserIdAsync() async -> String? {
        if let id = getEffectiveUserId() {
            return id
        }
        if let session = try? await SupabaseService.shared.client.auth.session {
            let uid = session.user.id.uuidString.lowercased()
            if uid != "guest" { return uid }
        }
        return nil
    }

    public func syncWithSupabase() async {
        guard let userId = await getEffectiveUserIdAsync() else {
            print("[TagdosStore] No authenticated user session, staying offline.")
            return
        }

        isSyncing = true
        cloudSyncError = nil
        defer { isSyncing = false }

        let client = SupabaseService.shared.client

        // 1. Pull & Merge Streams
        do {
            let res = try await client
                .from("tagdos_streams")
                .select()
                .eq("user_id", value: userId)
                .execute()

            struct RemoteStreamDTO: Codable {
                let id: UUID
                let user_id: UUID
                let stream_number: Int
                let title: String
                let raw_syntax: String
                let reminder_time: String?
                let active_memos: String?
                let attachments: [TagDoAttachment]?
                let updated_at: Date
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteStreams = try decoder.decode([RemoteStreamDTO].self, from: res.data)

            if !remoteStreams.isEmpty {
                var merged = self.streams
                let parser = TagdosParser.shared

                for remote in remoteStreams {
                    let orderIdx = remote.stream_number - 1
                    let reminderDate: Date? = {
                        guard let rt = remote.reminder_time, !rt.isEmpty else { return nil }
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        return formatter.date(from: rt)
                    }()

                    if let localIdx = merged.firstIndex(where: { $0.orderIndex == orderIdx }) {
                        let local = merged[localIdx]
                        if remote.updated_at >= local.updatedAt {
                            var updated = parser.parseStream(
                                rawText: remote.raw_syntax,
                                title: remote.title,
                                id: local.id,
                                streamReminder: reminderDate,
                                orderIndex: orderIdx,
                                existingStream: local
                            )
                            updated.activeMemos = remote.active_memos ?? ""
                            updated.attachments = remote.attachments ?? []
                            updated.updatedAt = remote.updated_at
                            merged[localIdx] = updated
                        }
                    } else {
                        var newStream = parser.parseStream(
                            rawText: remote.raw_syntax,
                            title: remote.title,
                            streamReminder: reminderDate,
                            orderIndex: orderIdx
                        )
                        newStream.activeMemos = remote.active_memos ?? ""
                        newStream.attachments = remote.attachments ?? []
                        newStream.updatedAt = remote.updated_at
                        merged.append(newStream)
                    }
                }

                merged.sort { $0.orderIndex < $1.orderIndex }
                self.streams = merged
                self.save(triggerCloudSync: false)
            } else {
                // Remote has no streams yet: push local initial streams up!
                await pushAllStreamsToSupabase(userId: userId)
            }
        } catch {
            print("[TagdosStore] Supabase streams sync notice: \(error.localizedDescription)")
            self.cloudSyncError = error.localizedDescription
        }

        // 2. Pull & Merge Quick Notes
        do {
            let resNotes = try await client
                .from("tagdos_quick_notes")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteNotes = try decoder.decode([TagDoQuickNote].self, from: resNotes.data)

            if !remoteNotes.isEmpty {
                var mergedNotes = self.quickNotes
                for rNote in remoteNotes {
                    if let idx = mergedNotes.firstIndex(where: { $0.id == rNote.id }) {
                        if rNote.updatedAt >= mergedNotes[idx].updatedAt {
                            mergedNotes[idx] = rNote
                        }
                    } else {
                        mergedNotes.append(rNote)
                    }
                }
                mergedNotes.sort {
                    if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                    return $0.updatedAt > $1.updatedAt
                }
                self.quickNotes = mergedNotes
                self.save(triggerCloudSync: false)
            }
        } catch {
            print("[TagdosStore] Supabase quick notes sync notice: \(error.localizedDescription)")
        }

        self.lastSyncedAt = Date()
    }

    private func scheduleCloudPush() {
        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            guard let userId = await getEffectiveUserIdAsync() else { return }
            await pushAllStreamsToSupabase(userId: userId)
            await pushAllQuickNotesToSupabase(userId: userId)
        }
    }

    private func pushAllStreamsToSupabase(userId: String) async {
        let client = SupabaseService.shared.client

        struct StreamPayload: Codable {
            let user_id: String
            let stream_number: Int
            let title: String
            let raw_syntax: String
            let reminder_time: String?
            let active_memos: String
            let attachments: [TagDoAttachment]
            let updated_at: String
        }

        let isoFormatter = ISO8601DateFormatter()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for stream in streams {
            let reminderStr = stream.streamReminder.map { timeFormatter.string(from: $0) }
            let payload = StreamPayload(
                user_id: userId,
                stream_number: stream.orderIndex + 1,
                title: stream.title,
                raw_syntax: stream.rawText,
                reminder_time: reminderStr,
                active_memos: stream.activeMemos,
                attachments: stream.attachments,
                updated_at: isoFormatter.string(from: stream.updatedAt)
            )

            do {
                _ = try await client
                    .from("tagdos_streams")
                    .upsert(payload, onConflict: "user_id,stream_number")
                    .execute()
            } catch {
                print("[TagdosStore] Failed to upsert stream \(stream.orderIndex + 1): \(error.localizedDescription)")
            }
        }
    }

    private func pushAllQuickNotesToSupabase(userId: String) async {
        let client = SupabaseService.shared.client
        for note in quickNotes {
            var n = note
            n.userId = userId
            _ = try? await client
                .from("tagdos_quick_notes")
                .upsert(n)
                .execute()
        }
    }

    // MARK: - Supabase Realtime Subscription

    private func setupRealtimeSubscription() async {
        guard let userId = await getEffectiveUserIdAsync() else { return }
        
        let client = SupabaseService.shared.client
        let channelName = "daily_tagdos_\(userId)"
        let channel = client.channel(channelName)

        let streamUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "tagdos_streams",
            filter: "user_id=eq.\(userId)"
        )

        let streamInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "tagdos_streams",
            filter: "user_id=eq.\(userId)"
        )

        do {
            try await channel.subscribeWithError()
            self.realtimeChannel = channel

            Task { [weak self] in
                for await _ in streamUpdates {
                    await self?.syncWithSupabase()
                }
            }

            Task { [weak self] in
                for await _ in streamInserts {
                    await self?.syncWithSupabase()
                }
            }
        } catch {
            print("[TagdosStore] Realtime subscription notice: \(error.localizedDescription)")
        }
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

            let memosPreview = stream.activeMemos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : String(stream.activeMemos.prefix(60))

            return TagdosWidgetSnapshotStream(
                id: stream.id.uuidString,
                title: stream.displayTitle,
                drivingPillText: driving?.rawText,
                drivingPillType: driving?.type.rawValue,
                activePillsCount: stream.activePills.count,
                reminderTimeFormatted: reminderStr,
                pills: Array(snapshotPills),
                activeMemosPreview: memosPreview
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
