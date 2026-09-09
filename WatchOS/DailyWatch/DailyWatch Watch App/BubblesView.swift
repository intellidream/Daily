import SwiftUI
import WatchKit
import Supabase
import WidgetKit

struct BubblesView: View {
    @State private var dayOffset: Int = 0
    @State private var dayTotal: Int = 0
    @State private var dayWater: Int = 0
    @State private var dayCoffee: Int = 0
    @State private var dailyGoal: Int = 2000
    @State private var isSyncing: Bool = false
    @State private var historyLogs: [HabitLog] = []
    @State private var selectedLog: HabitLog?
    @State private var showDeleteConfirm: Bool = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let cachedGoalStr = groupPrefs.string(forKey: "water_goal"),
           let cachedGoal = Int(cachedGoalStr) {
            _dailyGoal = State(initialValue: cachedGoal)
        }
    }
    
    private var formattedDateTitle: String {
        if dayOffset == 0 {
            return "Today"
        } else if dayOffset == -1 {
            return "Yesterday"
        } else {
            let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, d MMM"
            return formatter.string(from: targetDate)
        }
    }
    
    private func parseMetadata(_ metadata: String?) -> [String: String]? {
        guard let data = metadata?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header Title - using button icon (drop.fill) and color (.cyan)
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 15))
                    Text("Bubbles")
                        .font(.system(size: 17, weight: .bold))
                }
                .padding(.top, 2)
                
                // Temporal Navigation (Days)
                TemporalNavHeader(
                    title: formattedDateTitle,
                    canGoForward: dayOffset < 0,
                    accentColor: .cyan,
                    onPrevious: {
                        dayOffset -= 1
                        fetchData()
                    },
                    onNext: {
                        if dayOffset < 0 {
                            dayOffset += 1
                            fetchData()
                        }
                    }
                )
                
                // Ring & Quick-Add Buttons
                HStack(spacing: 10) {
                    // Circular Progress Ring
                    ZStack {
                        let totalG = CGFloat(max(dailyGoal, 1))
                        let wProg = CGFloat(dayWater) / totalG
                        let cProg = CGFloat(dayCoffee) / totalG
                        
                        Circle()
                            .stroke(Color.gray.opacity(0.25), lineWidth: 9)
                        
                        Circle()
                            .trim(from: 0.0, to: min(wProg, 1.0))
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.5), value: wProg)
                            
                        Circle()
                            .trim(from: min(wProg, 1.0), to: min(wProg + cProg, 1.0))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.5), value: cProg)
                        
                        VStack(spacing: 0) {
                            Text("\(dayTotal)")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("/ \(dailyGoal)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 86, height: 86)
                    
                    // 3 Quick Add Buttons
                    VStack(spacing: 5) {
                        QuickAddMiniButton(icon: "drop.fill", amount: 300, color: .cyan) {
                            logWater(amount: 300, type: "Large Water")
                        }
                        QuickAddMiniButton(icon: "drop", amount: 150, color: .cyan) {
                            logWater(amount: 150, type: "Small Water")
                        }
                        QuickAddMiniButton(icon: "cup.and.saucer.fill", amount: 100, color: .orange) {
                            logWater(amount: 100, type: "Coffee")
                        }
                    }
                    .frame(width: 68)
                }
                .padding(.vertical, 2)
                
                // Breakdown summary text using button icons and exact colors
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "drop.fill")
                            .foregroundColor(.cyan)
                            .font(.system(size: 11))
                        Text("\(dayWater) ml")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("·")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("\(dayCoffee) ml")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }
                
                // Logs for this specific day
                if !historyLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayOffset == 0 ? "TODAY'S LOGS" : "LOGS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        ForEach(historyLogs) { log in
                            HStack {
                                let type = parseMetadata(log.metadata)?["drink"] ?? "Water"
                                let isCoffee = type.contains("Coffee")
                                let isSmall = type == "Small Water"
                                let displayType = isCoffee ? "Coffee" : (isSmall ? "Small" : "Large")
                                
                                Image(systemName: isCoffee ? "cup.and.saucer.fill" : "drop.fill")
                                    .foregroundColor(isCoffee ? .orange : .cyan)
                                    .font(.system(size: 11))
                                
                                Text("\(Int(log.value)) \(log.unit) \(displayType)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                Spacer()
                                Text(formatTime(dateString: log.logged_at))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 7)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                            .onTapGesture {
                                WKInterfaceDevice.current().play(.click)
                                selectedLog = log
                                showDeleteConfirm = true
                            }
                        }
                    }
                }
                
                // Syncing indicator
                SyncFooterView(isSyncing: isSyncing)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .alert("Delete Log?", isPresented: $showDeleteConfirm, presenting: selectedLog) { log in
            Button("Delete", role: .destructive) {
                deleteLog(log)
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            loadCache()
            fetchData()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                fetchData()
            }
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchData() {
        guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
        
        isSyncing = true
        let calendar = Calendar.current
        let baseDate = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let startOfDay = calendar.startOfDay(for: baseDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            isSyncing = false
            return
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startStr = formatter.string(from: startOfDay)
        let endStr = formatter.string(from: endOfDay)
        
        Task {
            do {
                if dayOffset == 0 {
                    struct PrefRow: Codable {
                        let water_goal: Int?
                    }
                    if let prefs: [PrefRow] = try? await pClient.from("user_preferences").select("water_goal").execute().value,
                       let first = prefs.first, let goal = first.water_goal, goal > 0 {
                        DispatchQueue.main.async {
                            self.dailyGoal = goal
                            if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                                groupPrefs.set(String(goal), forKey: "water_goal")
                            }
                        }
                    }
                }
                
                let logs: [HabitLog] = try await pClient
                    .from("habits_logs")
                    .select("id,user_id,habit_type,value,unit,logged_at,metadata")
                    .eq("habit_type", value: "water")
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startStr)
                    .lt("logged_at", value: endStr)
                    .order("logged_at", ascending: false)
                    .execute()
                    .value
                
                var total = 0.0
                var water = 0.0
                var coffee = 0.0
                
                for log in logs {
                    total += log.value
                    let type = parseMetadata(log.metadata)?["drink"] ?? "Water"
                    if type.contains("Coffee") {
                        coffee += log.value
                    } else {
                        water += log.value
                    }
                }
                
                DispatchQueue.main.async {
                    self.dayTotal = Int(total)
                    self.dayWater = Int(water)
                    self.dayCoffee = Int(coffee)
                    self.historyLogs = logs
                    self.isSyncing = false
                    
                    if self.dayOffset == 0 {
                        self.saveCache()
                    }
                    WKInterfaceDevice.current().play(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSyncing = false
                }
            }
        }
    }
    
    // MARK: - Logging Habit
    
    private func logWater(amount: Int, type: String) {
        WKInterfaceDevice.current().play(.success)
        
        let now = Date()
        let targetDate: Date
        if dayOffset == 0 {
            targetDate = now
        } else {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now)
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = timeComponents.second
            targetDate = calendar.date(from: components) ?? now
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let loggedAt = formatter.string(from: targetDate)
        
        let isCoffee = type.contains("Coffee")
        let metadataString = "{\"drink\":\"\(type)\"}"
        
        let newLog = HabitLog(
            id: UUID(),
            user_id: WatchSessionManager.shared.currentUserId,
            habit_type: "water",
            value: Double(amount),
            unit: "ml",
            logged_at: loggedAt,
            metadata: metadataString
        )
        
        dayTotal += amount
        if isCoffee {
            dayCoffee += amount
        } else {
            dayWater += amount
        }
        historyLogs.insert(newLog, at: 0)
        
        if dayOffset == 0 {
            saveCache()
        }
        
        Task {
            isSyncing = true
            do {
                guard let pClient = WatchSessionManager.shared.supabaseClient else {
                    OfflineSyncManager.shared.enqueue(log: newLog)
                    DispatchQueue.main.async { self.isSyncing = false }
                    return
                }
                
                try await pClient.from("habits_logs").insert(newLog).execute()
                
                DispatchQueue.main.async {
                    self.isSyncing = false
                    WidgetCenter.shared.reloadAllTimelines()
                    WKInterfaceDevice.current().play(.success)
                }
            } catch {
                OfflineSyncManager.shared.enqueue(log: newLog)
                DispatchQueue.main.async {
                    self.isSyncing = false
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
    
    private func deleteLog(_ log: HabitLog) {
        guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
        
        let isCoffee = (parseMetadata(log.metadata)?["drink"] ?? "").contains("Coffee")
        dayTotal = max(0, dayTotal - Int(log.value))
        if isCoffee {
            dayCoffee = max(0, dayCoffee - Int(log.value))
        } else {
            dayWater = max(0, dayWater - Int(log.value))
        }
        historyLogs.removeAll { $0.id == log.id }
        
        Task {
            struct DeleteUpdate: Encodable { let is_deleted = true }
            _ = try? await pClient.from("habits_logs")
                .update(DeleteUpdate())
                .eq("id", value: log.id.uuidString.lowercased())
                .execute()
            
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
    
    private func formatTime(dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: dateString) {
            let outFormatter = DateFormatter()
            outFormatter.timeStyle = .short
            return outFormatter.string(from: d)
        }
        return ""
    }
    
    // MARK: - Local Cache
    
    private func saveCache() {
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
            groupPrefs.set(dayTotal, forKey: "cached_water_total")
        }
    }
    
    private func loadCache() {
        if dayOffset == 0, let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
            let cached = groupPrefs.integer(forKey: "cached_water_total")
            if cached > 0 && dayTotal == 0 {
                dayTotal = cached
            }
        }
    }
}

struct QuickAddMiniButton: View {
    let icon: String
    let amount: Int
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                
                Text("\(amount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 25)
            .background(Color.white.opacity(0.12))
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }
}
