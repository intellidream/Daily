import Foundation
import Supabase

@MainActor
public final class HabitsService: ObservableObject {
    public static let shared = HabitsService()
    
    // MARK: - Published State
    
    @Published public var selectedDate: Date = Date()
    @Published public var activeHabit: HabitType = .water
    @Published public var isLoading: Bool = false

    
    // Bubbles (Water)
    @Published public var waterGoal: Double = 2000
    @Published public var waterTotalToday: Double = 0
    @Published public var waterDrinkBreakdown: [HabitDrinkBreakdown] = []
    @Published public var todaysWaterLogs: [HabitLogRecord] = []
    
    // Smokes (Tobacco)
    @Published public var smokesSettings: SmokesSettings = SmokesSettings()
    @Published public var smokesTotalToday: Int = 0
    @Published public var smokesTypeBreakdown: [HabitDrinkBreakdown] = []
    @Published public var todaysSmokesLogs: [HabitLogRecord] = []
    @Published public var smokesFinancials: SmokesFinancialMetrics = SmokesFinancialMetrics()
    
    // Trends & Analytics
    @Published public var sevenDayHistory: [HabitTrendDay] = []
    @Published public var consistencyHeatmap: [HabitConsistencyCell] = []
    
    // MARK: - Convenience Computed Properties
    
    public var totalWaterMlToday: Double { waterTotalToday }
    public var waterGoalMl: Double { waterGoal }
    public var waterProgressPercent: Double {
        guard waterGoal > 0 else { return 0 }
        return min(max(waterTotalToday / waterGoal, 0.0), 1.0)
    }
    
    public var totalSmokesToday: Int { smokesTotalToday }
    public var smokesBaselineCount: Int { smokesSettings.baselineDailyCount }
    public var lastSmokeTimestamp: Date? {
        todaysSmokesLogs.first?.loggedAt
    }
    public var smokesFinancialMetrics: SmokesFinancialMetrics { smokesFinancials }
    public var trendDays: [HabitTrendDay] { sevenDayHistory }
    public var drinkBreakdown: [HabitDrinkBreakdown] {
        activeHabit == .water ? waterDrinkBreakdown : smokesTypeBreakdown
    }
    public var dailyLogs: [HabitLogRecord] {
        activeHabit == .water ? todaysWaterLogs : todaysSmokesLogs
    }
    public var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    public var formattedDateTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) {
            return "Today"
        } else if cal.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            let df = DateFormatter()
            df.dateFormat = "EEE, MMM d"
            return df.string(from: selectedDate)
        }
    }
    
    // MARK: - Convenience Synchronous / Fire-and-Forget Helpers
    
    public func logWater(preset: WaterPreset) {
        Task { await logWater(preset: preset, customAmount: nil) }
    }
    public func logWater(amountMl: Double, drink: String = "Water") {
        Task { await logWater(preset: .glass, customAmount: amountMl) }
    }
    public func logSmoke(preset: SmokePreset) {
        Task { await logSmoke(preset: preset, customCount: nil) }
    }
    public func logSmoke(type: String = "Cigarette") {
        Task { await logSmoke(preset: .cigarette, customCount: 1) }
    }
    public func deleteLog(_ log: HabitLogRecord) {
        Task { await deleteLog(id: log.id) }
    }
    public func goToPreviousDay() { prevDay() }
    public func goToNextDay() { nextDay() }
    public func goToToday() { jumpToToday() }
    public func selectDate(_ date: Date) { changeDate(to: date) }
    public func fetchDay(date: Date) async {
        selectedDate = date
        await loadDataForSelectedDate()
    }
    
    // MARK: - HealthKit & External Sync Hook
    /// Decoupled hook for native platforms to record dietary water into HealthKit without polluting DailyCore.
    public var onWaterLogged: ((_ amountMl: Double, _ date: Date) -> Void)? = nil

    
    // MARK: - Private State & Dependencies
    
    private let supabase = SupabaseService.shared.client
    private let userDefaults: UserDefaults
    private let groupSuiteName = "group.com.intellidream.daily"
    private var offlineLogQueue: [HabitLogRecord] = []
    
    private let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private let isoTimestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    public init() {
        self.userDefaults = UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
        loadLocalSettingsAndQueue()
        Task {
            await loadDataForSelectedDate()
        }
    }
    
    // MARK: - Navigation
    
    public func changeDate(to newDate: Date) {
        let cal = Calendar.current
        guard !cal.isDate(newDate, inSameDayAs: selectedDate) else { return }
        selectedDate = newDate
        Task {
            await loadDataForSelectedDate()
        }
    }
    
    public func prevDay() {
        if let d = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
            changeDate(to: d)
        }
    }
    
    public func nextDay() {
        if let d = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
            changeDate(to: d)
        }
    }
    
    public func jumpToToday() {
        changeDate(to: Date())
    }
    
    public func switchHabit(to habit: HabitType) {
        guard activeHabit != habit else { return }
        activeHabit = habit
        Task {
            await updateAnalyticsForCurrentHabit()
        }
    }
    
    // MARK: - Logging Actions
    
    public func logWater(preset: WaterPreset, customAmount: Double? = nil) async {
        let amount = customAmount ?? preset.defaultAmountMl
        let metaDict = ["drink": preset.rawValue]
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
        
        let session = try? await supabase.auth.session
        let userId = session?.user.id
        
        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: userId,
            habitType: "water",
            value: amount,
            unit: "ml",
            loggedAt: Date(),
            metadata: metaJson,
            createdAt: Date(),
            updatedAt: Date(),
            isDeleted: false
        )
        
        // 1. Update in-memory state immediately (0ms latency)
        todaysWaterLogs.insert(newRecord, at: 0)
        recalculateDailyAggregates()
        saveLocalLogs()
        
        // 2. Trigger HealthKit hook
        onWaterLogged?(amount, newRecord.loggedAt)
        
        // 3. Queue & Push to Supabase
        await pushLogToSupabase(newRecord)
        await updateAnalyticsForCurrentHabit()
    }
    
    public func logSmoke(preset: SmokePreset, customCount: Int? = nil) async {
        let count = customCount ?? preset.defaultCount
        let metaDict = ["type": preset.rawValue]
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
        
        let session = try? await supabase.auth.session
        let userId = session?.user.id
        
        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: userId,
            habitType: "smokes",
            value: Double(count),
            unit: "cigs",
            loggedAt: Date(),
            metadata: metaJson,
            createdAt: Date(),
            updatedAt: Date(),
            isDeleted: false
        )
        
        // 1. Update in-memory state immediately
        todaysSmokesLogs.insert(newRecord, at: 0)
        recalculateDailyAggregates()
        saveLocalLogs()
        
        // 2. Push to Supabase
        await pushLogToSupabase(newRecord)
        await updateAnalyticsForCurrentHabit()
    }
    
    public func deleteLog(id: UUID) async {
        if activeHabit == .water {
            todaysWaterLogs.removeAll { $0.id == id }
        } else {
            todaysSmokesLogs.removeAll { $0.id == id }
        }
        recalculateDailyAggregates()
        saveLocalLogs()
        
        // Asynchronously mark deleted in Supabase
        do {
            try await supabase.from("habits_logs")
                .update(["is_deleted": true])
                .eq("id", value: id.uuidString.lowercased())
                .execute()
        } catch {
            print("[HabitsService] Note: Offline soft-delete queued for \(id): \(error.localizedDescription)")
        }
        
        await updateAnalyticsForCurrentHabit()
    }
    
    public func updateWaterGoal(_ newGoal: Double) async {
        guard newGoal > 0 else { return }
        waterGoal = newGoal
        userDefaults.set(newGoal, forKey: "water_goal")
        
        let session = try? await supabase.auth.session
        if let userId = session?.user.id {
            let goalRecord = HabitGoalRecord(
                userId: userId,
                habitType: "water",
                targetValue: newGoal,
                unit: "ml",
                updatedAt: Date(),
                createdAt: Date(),
                isDeleted: false
            )
            _ = try? await supabase.from("habits_goals").upsert(goalRecord).execute()
        }
        await updateAnalyticsForCurrentHabit()
    }
    
    public func updateSmokesSettings(_ newSettings: SmokesSettings) async {
        smokesSettings = newSettings
        if let data = try? JSONEncoder().encode(newSettings) {
            userDefaults.set(data, forKey: "smokes_settings")
        }
        userDefaults.set(newSettings.baselineCigsPerDay, forKey: "smokes_baseline")
        
        let session = try? await supabase.auth.session
        if let userId = session?.user.id {
            let goalRecord = HabitGoalRecord(
                userId: userId,
                habitType: "smokes",
                targetValue: Double(newSettings.baselineCigsPerDay),
                unit: "cigs",
                updatedAt: Date(),
                createdAt: Date(),
                isDeleted: false
            )
            _ = try? await supabase.from("habits_goals").upsert(goalRecord).execute()
        }
        recalculateDailyAggregates()
        await updateAnalyticsForCurrentHabit()
    }
    
    // MARK: - Data Fetching & Sync
    
    public func loadDataForSelectedDate(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: selectedDate)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        let startIso = isoTimestampFormatter.string(from: startOfDay)
        let endIso = isoTimestampFormatter.string(from: endOfDay)
        
        let session = try? await supabase.auth.session
        if let userId = session?.user.id.uuidString.lowercased() {
            // 1. Fetch Goals
            do {
                let goals: [HabitGoalRecord] = try await supabase.from("habits_goals")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("is_deleted", value: false)
                    .execute()
                    .value
                
                for g in goals {
                    if g.habitType == "water" {
                        self.waterGoal = g.targetValue
                        userDefaults.set(g.targetValue, forKey: "water_goal")
                    } else if g.habitType == "smokes" {
                        self.smokesSettings.baselineCigsPerDay = Int(g.targetValue)
                        userDefaults.set(Int(g.targetValue), forKey: "smokes_baseline")
                    }
                }
            } catch {
                print("[HabitsService] Note: Could not fetch habits_goals: \(error.localizedDescription)")
            }
            
            // 2. Fetch Logs for this day
            do {
                let logs: [HabitLogRecord] = try await supabase.from("habits_logs")
                    .select()
                    .eq("user_id", value: userId)
                    .gte("logged_at", value: startIso)
                    .lt("logged_at", value: endIso)
                    .eq("is_deleted", value: false)
                    .order("logged_at", ascending: false)
                    .execute()
                    .value
                
                self.todaysWaterLogs = logs.filter { $0.habitType == "water" }
                self.todaysSmokesLogs = logs.filter { $0.habitType == "smokes" }
                saveLocalLogs()
            } catch {
                print("[HabitsService] Note: Could not fetch habits_logs: \(error.localizedDescription)")
                loadLocalLogsForSelectedDate()
            }
        } else {
            // Guest mode / offline
            loadLocalLogsForSelectedDate()
        }
        
        recalculateDailyAggregates()
        await updateAnalyticsForCurrentHabit()
        await flushOfflineQueue()
    }
    
    // MARK: - Offline Storage & Queue
    
    private func loadLocalSettingsAndQueue() {
        if let g = userDefaults.value(forKey: "water_goal") as? Double {
            self.waterGoal = g
        }
        if let data = userDefaults.data(forKey: "smokes_settings"),
           let settings = try? JSONDecoder().decode(SmokesSettings.self, from: data) {
            self.smokesSettings = settings
        } else if let b = userDefaults.value(forKey: "smokes_baseline") as? Int {
            self.smokesSettings.baselineCigsPerDay = b
        }
        
        if let queueData = userDefaults.data(forKey: "offline_habits_queue"),
           let queue = try? JSONDecoder().decode([HabitLogRecord].self, from: queueData) {
            self.offlineLogQueue = queue
        }
    }
    
    private func saveLocalLogs() {
        let dateKey = isoDateFormatter.string(from: selectedDate)
        if let wData = try? JSONEncoder().encode(todaysWaterLogs) {
            userDefaults.set(wData, forKey: "local_water_logs_\(dateKey)")
        }
        if let sData = try? JSONEncoder().encode(todaysSmokesLogs) {
            userDefaults.set(sData, forKey: "local_smokes_logs_\(dateKey)")
        }
    }
    
    private func loadLocalLogsForSelectedDate() {
        let dateKey = isoDateFormatter.string(from: selectedDate)
        if let wData = userDefaults.data(forKey: "local_water_logs_\(dateKey)"),
           let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: wData) {
            self.todaysWaterLogs = logs
        }
        if let sData = userDefaults.data(forKey: "local_smokes_logs_\(dateKey)"),
           let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: sData) {
            self.todaysSmokesLogs = logs
        }
    }
    
    private func pushLogToSupabase(_ record: HabitLogRecord) async {
        do {
            try await supabase.from("habits_logs").insert(record).execute()
        } catch {
            print("[HabitsService] Supabase insert failed (\(error.localizedDescription)). Queuing offline...")
            offlineLogQueue.append(record)
            if let data = try? JSONEncoder().encode(offlineLogQueue) {
                userDefaults.set(data, forKey: "offline_habits_queue")
            }
        }
    }
    
    public func flushOfflineQueue() async {
        guard !offlineLogQueue.isEmpty else { return }
        var remaining: [HabitLogRecord] = []
        for record in offlineLogQueue {
            do {
                try await supabase.from("habits_logs").insert(record).execute()
            } catch {
                remaining.append(record)
            }
        }
        self.offlineLogQueue = remaining
        if let data = try? JSONEncoder().encode(remaining) {
            userDefaults.set(data, forKey: "offline_habits_queue")
        }
    }
    
    // MARK: - Calculations & Analytics
    
    private func recalculateDailyAggregates() {
        // Water
        let wSum = todaysWaterLogs.reduce(0.0) { $0 + $1.value }
        self.waterTotalToday = wSum
        
        var wBreakdown: [String: Double] = [:]
        for log in todaysWaterLogs {
            let key = log.drinkType
            wBreakdown[key, default: 0] += log.value
        }
        self.waterDrinkBreakdown = wBreakdown.map { (key, val) in
            let pct = wSum > 0 ? (val / wSum) * 100 : 0
            let preset = WaterPreset(rawValue: key)
            return HabitDrinkBreakdown(
                drink: key,
                amount: val,
                unit: "ml",
                percentage: pct,
                hexColor: preset?.hexColor ?? "#00E5FF",
                iconName: preset?.systemImage ?? "drop.fill"
            )
        }.sorted { $0.amount > $1.amount }
        
        // Smokes
        let sCount = todaysSmokesLogs.reduce(0) { $0 + Int($1.value) }
        self.smokesTotalToday = sCount
        
        var sBreakdown: [String: Int] = [:]
        for log in todaysSmokesLogs {
            let key = log.smokeType
            sBreakdown[key, default: 0] += Int(log.value)
        }
        self.smokesTypeBreakdown = sBreakdown.map { (key, val) in
            let pct = sCount > 0 ? (Double(val) / Double(sCount)) * 100 : 0
            let preset = SmokePreset(rawValue: key)
            return HabitDrinkBreakdown(
                drink: key,
                amount: Double(val),
                unit: "cigs",
                percentage: pct,
                hexColor: preset?.hexColor ?? "#EF4444",
                iconName: preset?.systemImage ?? "flame.fill"
            )
        }.sorted { $0.amount > $1.amount }
        
        // Smokes Financials & Interval
        let cal = Calendar.current
        let days = max(1, cal.dateComponents([.day], from: smokesSettings.quitStartDate, to: selectedDate).day ?? 1)
        let expectedCeiling = days * smokesSettings.baselineCigsPerDay
        let avoided = max(0, expectedCeiling - sCount)
        let costPerCig = smokesSettings.costPerCig
        let moneySaved = Double(avoided) * costPerCig
        
        let lastLog = todaysSmokesLogs.first
        let timeSince = lastLog.map { Date().timeIntervalSince($0.loggedAt) }
        
        self.smokesFinancials = SmokesFinancialMetrics(
            moneySaved: moneySaved,
            cigsAvoided: avoided,
            daysTracked: days,
            costPerCig: costPerCig,
            lastSmokeDate: lastLog?.loggedAt,
            timeSinceLastSmoke: timeSince
        )
    }
    
    private func updateAnalyticsForCurrentHabit() async {
        let cal = Calendar.current
        
        // 1. Build 7-Day History
        var history: [HabitTrendDay] = []
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        
        for offset in (0..<7).reversed() {
            if let targetDate = cal.date(byAdding: .day, value: -offset, to: selectedDate) {
                let label = offset == 0 ? "Today" : dayFormatter.string(from: targetDate)
                let dateKey = isoDateFormatter.string(from: targetDate)
                
                let val: Double
                let goal: Double
                if activeHabit == .water {
                    if offset == 0 {
                        val = waterTotalToday
                    } else if let data = userDefaults.data(forKey: "local_water_logs_\(dateKey)"),
                              let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: data) {
                        val = logs.reduce(0.0) { $0 + $1.value }
                    } else {
                        val = 0
                    }
                    goal = waterGoal
                } else {
                    if offset == 0 {
                        val = Double(smokesTotalToday)
                    } else if let data = userDefaults.data(forKey: "local_smokes_logs_\(dateKey)"),
                              let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: data) {
                        val = logs.reduce(0.0) { $0 + $1.value }
                    } else {
                        val = 0
                    }
                    goal = Double(smokesSettings.baselineCigsPerDay)
                }
                
                let met = activeHabit == .water ? (val >= goal) : (val <= goal)
                history.append(HabitTrendDay(date: targetDate, dayLabel: label, value: val, goal: goal, isGoalMet: met))
            }
        }
        self.sevenDayHistory = history
        
        // 2. Build 4-Month Consistency Heatmap (120 days)
        var heatmap: [HabitConsistencyCell] = []
        let tooltipFormatter = DateFormatter()
        tooltipFormatter.dateFormat = "MMM d, yyyy"
        
        for dayOffset in (0..<120).reversed() {
            if let dayDate = cal.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let dateKey = isoDateFormatter.string(from: dayDate)
                let tipDate = tooltipFormatter.string(from: dayDate)
                
                let val: Double
                if activeHabit == .water {
                    if cal.isDateInToday(dayDate) {
                        val = waterTotalToday
                    } else if let data = userDefaults.data(forKey: "local_water_logs_\(dateKey)"),
                              let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: data) {
                        val = logs.reduce(0.0) { $0 + $1.value }
                    } else {
                        val = 0
                    }
                    
                    let level: Int
                    let ratio = waterGoal > 0 ? (val / waterGoal) : 0
                    if ratio >= 1.0 { level = 4 }
                    else if ratio >= 0.75 { level = 3 }
                    else if ratio >= 0.50 { level = 2 }
                    else if ratio > 0 { level = 1 }
                    else { level = 0 }
                    
                    let tip = "\(tipDate): \(Int(val)) ml (\(Int(ratio * 100))%)"
                    heatmap.append(HabitConsistencyCell(date: dayDate, dateKey: dateKey, value: val, intensityLevel: level, tooltip: tip))
                } else {
                    if cal.isDateInToday(dayDate) {
                        val = Double(smokesTotalToday)
                    } else if let data = userDefaults.data(forKey: "local_smokes_logs_\(dateKey)"),
                              let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: data) {
                        val = logs.reduce(0.0) { $0 + $1.value }
                    } else {
                        val = 0
                    }
                    
                    let level: Int
                    let baseline = Double(smokesSettings.baselineCigsPerDay)
                    if val == 0 { level = 4 } // 0 smokes = great consistency!
                    else if val <= baseline * 0.5 { level = 3 }
                    else if val <= baseline * 0.75 { level = 2 }
                    else if val <= baseline { level = 1 }
                    else { level = 0 }
                    
                    let tip = "\(tipDate): \(Int(val)) cigs"
                    heatmap.append(HabitConsistencyCell(date: dayDate, dateKey: dateKey, value: val, intensityLevel: level, tooltip: tip))
                }
            }
        }
        self.consistencyHeatmap = heatmap
    }
}
