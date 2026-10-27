import Foundation
import os.log
import Supabase

public enum OutboxActionType: String, Codable, Sendable {
    case insert
    case delete
}

public struct OutboxItem: Codable, Identifiable, Sendable {
    public var id: UUID
    public let action: OutboxActionType
    public let log: HabitLog
    public let enqueuedAt: Date
    
    public init(id: UUID = UUID(), action: OutboxActionType, log: HabitLog, enqueuedAt: Date = Date()) {
        self.id = id
        self.action = action
        self.log = log
        self.enqueuedAt = enqueuedAt
    }
}

public actor OfflineSyncManager {
    public static let shared = OfflineSyncManager()
    
    private let queueKey = "offline_sync_outbox_v2"
    private let legacyQueueKey = "offline_sync_queue"
    private let groupSuiteName = "group.com.intellidream.daily"
    private var isSyncing = false
    
    private init() {
        migrateLegacyQueue()
    }
    
    private func migrateLegacyQueue() {
        guard let groupPrefs = UserDefaults(suiteName: groupSuiteName) else { return }
        if let legacyData = groupPrefs.data(forKey: legacyQueueKey),
           let legacyLogs = try? JSONDecoder().decode([HabitLog].self, from: legacyData),
           !legacyLogs.isEmpty {
            var currentOutbox = getOutboxItems()
            for log in legacyLogs {
                currentOutbox.append(OutboxItem(action: .insert, log: log))
            }
            saveOutbox(currentOutbox)
            groupPrefs.removeObject(forKey: legacyQueueKey)
            os_log("Migrated %d legacy offline logs to Outbox v2", type: .info, legacyLogs.count)
        }
    }
    
    public func enqueueInsert(_ log: HabitLog) {
        var items = getOutboxItems()
        items.append(OutboxItem(action: .insert, log: log))
        saveOutbox(items)
        os_log("Enqueued INSERT for habit %{public}@. Outbox size: %d", type: .info, log.habit_type, items.count)
    }
    
    public func enqueueDelete(_ log: HabitLog) {
        var items = getOutboxItems()
        // If an insert for this exact ID is still pending in the outbox, cancel both
        if let idx = items.firstIndex(where: { $0.log.id == log.id && $0.action == .insert }) {
            items.remove(at: idx)
            saveOutbox(items)
            os_log("Cancelled pending INSERT in outbox for deleted habit: %{public}@", type: .info, log.id.uuidString)
            return
        }
        items.append(OutboxItem(action: .delete, log: log))
        saveOutbox(items)
        os_log("Enqueued DELETE for habit %{public}@. Outbox size: %d", type: .info, log.id.uuidString, items.count)
    }
    
    public func getPendingCount() -> Int {
        getOutboxItems().count
    }
    
    private func getOutboxItems() -> [OutboxItem] {
        guard let groupPrefs = UserDefaults(suiteName: groupSuiteName),
              let data = groupPrefs.data(forKey: queueKey) else {
            return []
        }
        return (try? JSONDecoder().decode([OutboxItem].self, from: data)) ?? []
    }
    
    private func saveOutbox(_ items: [OutboxItem]) {
        guard let groupPrefs = UserDefaults(suiteName: groupSuiteName) else { return }
        if let data = try? JSONEncoder().encode(items) {
            groupPrefs.set(data, forKey: queueKey)
        }
    }
    
    public func processQueue() async {
        guard !isSyncing else { return }
        let items = getOutboxItems()
        guard !items.isEmpty else { return }
        
        guard let pClient = WatchSessionManager.shared.supabaseClient else {
            os_log("Supabase client not authenticated. Sync postponed.", type: .info)
            return
        }
        
        isSyncing = true
        os_log("Processing outbox sync: %d items", type: .info, items.count)
        
        var remainingItems: [OutboxItem] = []
        
        for item in items {
            do {
                switch item.action {
                case .insert:
                    try await pClient.from("habits_logs").insert(item.log).execute()
                    os_log("Successfully synced INSERT: %{public}@", type: .info, item.log.id.uuidString)
                case .delete:
                    struct DeleteUpdate: Encodable { let is_deleted = true }
                    try await pClient.from("habits_logs")
                        .update(DeleteUpdate())
                        .eq("id", value: item.log.id.uuidString.lowercased())
                        .execute()
                    os_log("Successfully synced DELETE: %{public}@", type: .info, item.log.id.uuidString)
                }
            } catch {
                let errDesc = error.localizedDescription
                // If 409 conflict or duplicate, consider processed to avoid eternal retry
                if errDesc.contains("duplicate") || errDesc.contains("23505") {
                    os_log("Item already exists or handled on remote, dropping from outbox: %{public}@", type: .info, item.log.id.uuidString)
                } else {
                    os_log("Failed to sync item %{public}@ (%{public}@): %{public}@", type: .error, item.log.id.uuidString, item.action.rawValue, errDesc)
                    remainingItems.append(item)
                }
            }
        }
        
        saveOutbox(remainingItems)
        isSyncing = false
    }
}
