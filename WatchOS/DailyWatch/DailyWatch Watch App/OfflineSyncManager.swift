import Foundation
import os.log
import Supabase

class OfflineSyncManager {
    static let shared = OfflineSyncManager()
    
    private let queueKey = "offline_sync_queue"
    private let groupSuiteName = "group.com.intellidream.daily"
    private var isSyncing = false
    
    // Add a log to the offline queue
    func enqueue(log: HabitLog) {
        var queue = getQueue()
        queue.append(log)
        saveQueue(queue)
        os_log("Enqueued log for offline sync. Queue size: %d", type: .info, queue.count)
    }
    
    // Retrieve the current queue
    private func getQueue() -> [HabitLog] {
        guard let groupPrefs = UserDefaults(suiteName: groupSuiteName),
              let data = groupPrefs.data(forKey: queueKey) else {
            return []
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([HabitLog].self, from: data)
        } catch {
            os_log("Failed to decode offline queue: %@", type: .error, error.localizedDescription)
            return []
        }
    }
    
    // Save the queue
    private func saveQueue(_ queue: [HabitLog]) {
        guard let groupPrefs = UserDefaults(suiteName: groupSuiteName) else { return }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(queue)
            groupPrefs.set(data, forKey: queueKey)
        } catch {
            os_log("Failed to encode offline queue: %@", type: .error, error.localizedDescription)
        }
    }
    
    // Process the queue and send to Supabase
    func processQueue() {
        guard !isSyncing else { return }
        let queue = getQueue()
        guard !queue.isEmpty else { return }
        
        isSyncing = true
        os_log("Processing offline sync queue. Items to sync: %d", type: .info, queue.count)
        
        Task {
            do {
                guard let pClient = WatchSessionManager.shared.supabaseClient else {
                    os_log("Supabase client not available. Aborting sync.", type: .error)
                    self.isSyncing = false
                    return
                }
                
                // Attempt to insert all items in bulk
                try await pClient.from("habits_logs").insert(queue).execute()
                
                // If successful, clear the queue
                self.saveQueue([])
                os_log("Offline sync successful. Queue cleared.", type: .info)
                
            } catch {
                os_log("Offline sync failed: %@", type: .error, error.localizedDescription)
                // Queue remains untouched for next attempt
            }
            self.isSyncing = false
        }
    }
}
