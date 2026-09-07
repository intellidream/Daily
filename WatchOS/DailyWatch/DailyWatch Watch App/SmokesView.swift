import SwiftUI
import WatchKit
import Supabase
import WidgetKit

struct SmokesView: View {
    @State private var dayOffset: Int = 0
    @State private var dayTotal: Int = 0
    @State private var dayCig: Int = 0
    @State private var dayHeat: Int = 0
    @State private var dailyGoal: Int = 20
    @State private var isSyncing: Bool = false
    @State private var historyLogs: [HabitLog] = []
    @State private var selectedLog: HabitLog?
    @State private var showDeleteConfirm: Bool = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let cachedGoalStr = groupPrefs.string(forKey: "smokes_baseline"),
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
    
    private func getSmokesColor(total: Int, baseline: Int) -> Color {
        if total == 0 { return .green }
        let ratio = Double(total) / Double(max(baseline, 1))
        if ratio >= 1.0 { return .red }
        if ratio >= 0.5 { return .orange }
        return .yellow
    }
    
    private func parseMetadata(_ metadata: String?) -> [String: String]? {
        guard let data = metadata?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header Title - button icon (flame.fill) & color (.red)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 15))
                    Text("Smokes")
                        .font(.system(size: 17, weight: .bold))
                }
                .padding(.top, 2)
                
                // Temporal Navigation (Days)
                TemporalNavHeader(
                    title: formattedDateTitle,
                    canGoForward: dayOffset < 0,
                    accentColor: .red,
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
                HStack(spacing: 12) {
                    // Circular Progress Ring
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.25), lineWidth: 9)
                        
                        let remaining = max(0, dailyGoal - dayTotal)
                        let progress = CGFloat(remaining) / CGFloat(max(dailyGoal, 1))
                        let ringColor = getSmokesColor(total: dayTotal, baseline: dailyGoal)
                        
                        Circle()
                            .trim(from: 0.0, to: progress)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.5), value: progress)
                        
                        VStack(spacing: 0) {
                            Text("\(dayTotal)")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundColor(dayTotal > dailyGoal ? .red : .primary)
                            Text("/ \(dailyGoal)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 86, height: 86)
                    
                    // 2 Quick Add Buttons (Cig & Heat)
                    VStack(spacing: 6) {
                        SmokesMiniButton(icon: "flame.fill", color: .red, title: "+1 Cig") {
                            logSmoke(type: "Cigarette")
                        }
                        SmokesMiniButton(icon: "bolt.fill", color: .blue, title: "+1 Heat") {
                            logSmoke(type: "Heated Tobacco")
                        }
                    }
                    .frame(width: 72)
                }
                .padding(.vertical, 2)
                
                // Breakdown summary text using button icons and exact colors
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                        Text("\(dayCig) cig")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("·")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 11))
                        Text("\(dayHeat) heat")
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
                                let type = parseMetadata(log.metadata)?["type"] ?? "Cigarette"
                                let isHeat = type.contains("Heat") || type.contains("Vape")
                                
                                Image(systemName: isHeat ? "bolt.fill" : "flame.fill")
                                    .foregroundColor(isHeat ? .blue : .red)
                                    .font(.system(size: 11))
                                
                                Text(isHeat ? "Heated Tobacco" : "Cigarette")
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
                            .onLongPressGesture {
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
                        let smokes_baseline: Int?
                    }
                    if let prefs: [PrefRow] = try? await pClient.from("user_preferences").select("smokes_baseline").execute().value,
                       let first = prefs.first, let baseline = first.smokes_baseline, baseline > 0 {
                        DispatchQueue.main.async {
                            self.dailyGoal = baseline
                            if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
                                groupPrefs.set(String(baseline), forKey: "smokes_baseline")
                            }
                        }
                    }
                }
                
                let logs: [HabitLog] = try await pClient
                    .from("habits_logs")
                    .select("id,user_id,habit_type,value,unit,logged_at,metadata")
                    .eq("habit_type", value: "smokes")
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startStr)
                    .lt("logged_at", value: endStr)
                    .order("logged_at", ascending: false)
                    .execute()
                    .value
                
                var total = 0.0
                var cig = 0.0
                var heat = 0.0
                
                for log in logs {
                    total += log.value
                    let type = parseMetadata(log.metadata)?["type"] ?? "Cigarette"
                    if type.contains("Heat") || type.contains("Vape") {
                        heat += log.value
                    } else {
                        cig += log.value
                    }
                }
                
                DispatchQueue.main.async {
                    self.dayTotal = Int(total)
                    self.dayCig = Int(cig)
                    self.dayHeat = Int(heat)
                    self.historyLogs = logs
                    self.isSyncing = false
                    
                    if self.dayOffset == 0 {
                        self.saveCache()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSyncing = false
                }
            }
        }
    }
    
    // MARK: - Logging Habit
    
    private func logSmoke(type: String) {
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
        
        let isHeat = type.contains("Heat") || type.contains("Vape")
        let metadataString = "{\"type\":\"\(type)\"}"
        
        let newLog = HabitLog(
            id: UUID(),
            user_id: WatchSessionManager.shared.currentUserId,
            habit_type: "smokes",
            value: 1.0,
            unit: "items",
            logged_at: loggedAt,
            metadata: metadataString
        )
        
        dayTotal += 1
        if isHeat {
            dayHeat += 1
        } else {
            dayCig += 1
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
        
        let isHeat = (parseMetadata(log.metadata)?["type"] ?? "").contains("Heat")
        dayTotal = max(0, dayTotal - 1)
        if isHeat {
            dayHeat = max(0, dayHeat - 1)
        } else {
            dayCig = max(0, dayCig - 1)
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
            groupPrefs.set(dayTotal, forKey: "cached_smokes_total")
        }
    }
    
    private func loadCache() {
        if dayOffset == 0, let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
            let cached = groupPrefs.integer(forKey: "cached_smokes_total")
            if cached > 0 && dayTotal == 0 {
                dayTotal = cached
            }
        }
    }
}

struct SmokesMiniButton: View {
    let icon: String
    let color: Color
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(Color.white.opacity(0.12))
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }
}
