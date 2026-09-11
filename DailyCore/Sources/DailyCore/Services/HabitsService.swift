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
    
    // Independent Precalculated Trends & Analytics for Bubbles & Smokes
    @Published public var waterSevenDayHistory: [HabitTrendDay] = []
    @Published public var smokesSevenDayHistory: [HabitTrendDay] = []
    @Published public var waterConsistencyHeatmap: [HabitConsistencyCell] = []
    @Published public var smokesConsistencyHeatmap: [HabitConsistencyCell] = []
    
    // Daily aggregate dictionaries cached locally for 0ms instant rendering
    private var waterDailyTotals: [String: Double] = [:]
    private var smokesDailyTotals: [String: Int] = [:]
    
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
    public var lastSmokeType: String? {
        todaysSmokesLogs.first?.smokeType
    }
    public var smokesFinancialMetrics: SmokesFinancialMetrics { smokesFinancials }
    
    public var sevenDayHistory: [HabitTrendDay] {
        activeHabit == .water ? waterSevenDayHistory : smokesSevenDayHistory
    }
    public var consistencyHeatmap: [HabitConsistencyCell] {
        activeHabit == .water ? waterConsistencyHeatmap : smokesConsistencyHeatmap
    }
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
        Task { await logWater(preset: preset, customAmount: nil, multiplier: 1) }
    }
    public func logWater(preset: WaterPreset, multiplier: Int) {
        Task { await logWater(preset: preset, customAmount: nil, multiplier: multiplier) }
    }
    public func logWater(amountMl: Double, drink: String = "Water") {
        Task { await logWater(preset: .glass, customAmount: amountMl, multiplier: 1) }
    }
    public func logSmoke(preset: SmokePreset) {
        Task { await logSmoke(preset: preset, customCount: nil, multiplier: 1) }
    }
    public func logSmoke(preset: SmokePreset, multiplier: Int) {
        Task { await logSmoke(preset: preset, customCount: nil, multiplier: multiplier) }
    }
    public func logSmoke(type: String = "Cigarette") {
        Task { await logSmoke(preset: .cigarette, customCount: 1, multiplier: 1) }
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
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
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
    }
    
    // MARK: - Logging Actions
    
    public func logWater(preset: WaterPreset, customAmount: Double? = nil, multiplier: Int = 1) async {
        let safeMultiplier = max(1, multiplier)
        let baseAmount = customAmount ?? preset.defaultAmountMl
        let totalAmount = baseAmount * Double(safeMultiplier)
        
        var metaDict: [String: String] = ["drink": preset.rawValue]
        if safeMultiplier > 1 {
            metaDict["multiplier"] = "\(safeMultiplier)"
            metaDict["base_value"] = "\(baseAmount)"
        }
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
        
        let session = try? await supabase.auth.session
        let userId = session?.user.id
        
        // Ensure proper date attribution if viewing a past date
        let logDate: Date
        if Calendar.current.isDateInToday(selectedDate) {
            logDate = Date()
        } else {
            let cal = Calendar.current
            let nowTime = cal.dateComponents([.hour, .minute, .second], from: Date())
            var components = cal.dateComponents([.year, .month, .day], from: selectedDate)
            components.hour = nowTime.hour
            components.minute = nowTime.minute
            components.second = nowTime.second
            logDate = cal.date(from: components) ?? selectedDate
        }
        
        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: userId,
            habitType: "water",
            value: totalAmount,
            unit: "ml",
            loggedAt: logDate,
            metadata: metaJson,
            createdAt: Date(),
            updatedAt: Date(),
            isDeleted: false
        )
        
        // 1. Update in-memory state immediately (0ms latency)
        todaysWaterLogs.insert(newRecord, at: 0)
        recalculateDailyAggregates()
        saveLocalLogs()
        
        // 2. Update daily totals cache & precomputed histories
        let dateKey = isoDateFormatter.string(from: logDate)
        waterDailyTotals[dateKey, default: 0] += totalAmount
        saveDailyTotals()
        recomputeAllHistoriesAndHeatmaps()
        
        // 3. Trigger HealthKit hook
        onWaterLogged?(totalAmount, logDate)
        
        // 4. Queue & Push to Supabase
        await pushLogToSupabase(newRecord)
    }
    
    public func logSmoke(preset: SmokePreset, customCount: Int? = nil, multiplier: Int = 1) async {
        let safeMultiplier = max(1, multiplier)
        let baseCount = customCount ?? preset.defaultCount
        let totalCount = baseCount * safeMultiplier
        
        var metaDict: [String: String] = ["type": preset.rawValue]
        if safeMultiplier > 1 {
            metaDict["multiplier"] = "\(safeMultiplier)"
            metaDict["base_value"] = "\(baseCount)"
        }
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
        
        let session = try? await supabase.auth.session
        let userId = session?.user.id
        
        // Ensure proper date attribution if viewing a past date
        let logDate: Date
        if Calendar.current.isDateInToday(selectedDate) {
            logDate = Date()
        } else {
            let cal = Calendar.current
            let nowTime = cal.dateComponents([.hour, .minute, .second], from: Date())
            var components = cal.dateComponents([.year, .month, .day], from: selectedDate)
            components.hour = nowTime.hour
            components.minute = nowTime.minute
            components.second = nowTime.second
            logDate = cal.date(from: components) ?? selectedDate
        }
        
        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: userId,
            habitType: "smokes",
            value: Double(totalCount),
            unit: "cigs",
            loggedAt: logDate,
            metadata: metaJson,
            createdAt: Date(),
            updatedAt: Date(),
            isDeleted: false
        )
        
        // 1. Update in-memory state immediately
        todaysSmokesLogs.insert(newRecord, at: 0)
        recalculateDailyAggregates()
        saveLocalLogs()
        
        // 2. Update daily totals cache & precomputed histories
        let dateKey = isoDateFormatter.string(from: logDate)
        smokesDailyTotals[dateKey, default: 0] += totalCount
        saveDailyTotals()
        recomputeAllHistoriesAndHeatmaps()
        
        // 3. Push to Supabase
        await pushLogToSupabase(newRecord)
    }
    
    public func deleteLog(id: UUID) async {
        var deletedRecord: HabitLogRecord?
        if activeHabit == .water {
            if let idx = todaysWaterLogs.firstIndex(where: { $0.id == id }) {
                deletedRecord = todaysWaterLogs.remove(at: idx)
            }
        } else {
            if let idx = todaysSmokesLogs.firstIndex(where: { $0.id == id }) {
                deletedRecord = todaysSmokesLogs.remove(at: idx)
            }
        }
        
        if let rec = deletedRecord {
            let dateKey = isoDateFormatter.string(from: rec.loggedAt)
            if rec.habitType == "water" {
                waterDailyTotals[dateKey] = max(0, (waterDailyTotals[dateKey] ?? rec.value) - rec.value)
            } else {
                smokesDailyTotals[dateKey] = max(0, (smokesDailyTotals[dateKey] ?? Int(rec.value)) - Int(rec.value))
            }
            saveDailyTotals()
        }
        
        recalculateDailyAggregates()
        saveLocalLogs()
        recomputeAllHistoriesAndHeatmaps()
        
        // Asynchronously mark deleted in Supabase
        do {
            try await supabase.from("habits_logs")
                .update(["is_deleted": true])
                .eq("id", value: id.uuidString.lowercased())
                .execute()
        } catch {
            print("[HabitsService] Note: Offline soft-delete queued for \(id): \(error.localizedDescription)")
        }
    }
    
    public func updateWaterGoal(_ newGoal: Double) async {
        guard newGoal > 0 else { return }
        waterGoal = newGoal
        userDefaults.set(newGoal, forKey: "water_goal")
        
        let session = try? await supabase.auth.session
        if let userId = session?.user.id.uuidString.lowercased() {
            // 1. Upsert habits_goals
            let goalRecord = HabitGoalRecord(
                userId: UUID(uuidString: userId),
                habitType: "water",
                targetValue: newGoal,
                unit: "ml",
                updatedAt: Date(),
                createdAt: Date(),
                isDeleted: false
            )
            _ = try? await supabase.from("habits_goals").upsert(goalRecord).execute()
            
            // 2. Also upsert water_goal into user_preferences
            struct WaterPrefUpdate: Codable {
                let id: String
                let water_goal: Double
            }
            _ = try? await supabase.from("user_preferences").upsert(WaterPrefUpdate(id: userId, water_goal: newGoal)).execute()
        }
        recalculateDailyAggregates()
        recomputeAllHistoriesAndHeatmaps()
    }
    
    public func updateSmokesSettings(_ newSettings: SmokesSettings) async {
        smokesSettings = newSettings
        if let data = try? JSONEncoder().encode(newSettings) {
            userDefaults.set(data, forKey: "smokes_settings")
        }
        userDefaults.set(newSettings.baselineCigsPerDay, forKey: "smokes_baseline")
        
        let session = try? await supabase.auth.session
        if let userId = session?.user.id.uuidString.lowercased() {
            // 1. Upsert user_preferences
            struct SmokesPrefUpdate: Codable {
                let id: String
                let smokes_baseline: Int
                let smokes_pack_size: Int
                let smokes_pack_cost: Double
                let smokes_currency: String
                let smokes_quit_date: String
            }
            let isoQuit = isoTimestampFormatter.string(from: newSettings.quitStartDate)
            let prefUpdate = SmokesPrefUpdate(
                id: userId,
                smokes_baseline: newSettings.baselineCigsPerDay,
                smokes_pack_size: newSettings.cigsPerPack,
                smokes_pack_cost: newSettings.costPerPack,
                smokes_currency: newSettings.currency,
                smokes_quit_date: isoQuit
            )
            _ = try? await supabase.from("user_preferences").upsert(prefUpdate).execute()
            
            // 2. Also keep habits_goals synced
            let goalRecord = HabitGoalRecord(
                userId: UUID(uuidString: userId),
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
        recomputeAllHistoriesAndHeatmaps()
    }
    
    // MARK: - Data Fetching & Sync
    
    public func loadDataForSelectedDate(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: selectedDate)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        let isoUtcFormatter = ISO8601DateFormatter()
        isoUtcFormatter.formatOptions = [.withInternetDateTime]
        isoUtcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let startIso = isoUtcFormatter.string(from: startOfDay)
        let endIso = isoUtcFormatter.string(from: endOfDay)
        
        let session = try? await supabase.auth.session
        let userId = session?.user.id.uuidString.lowercased()
        
        if let uid = userId {
            // 1. Fetch user_preferences (smokes configuration & water target)
            do {
                let prefs: [UserPreferencesRecord] = try await supabase.from("user_preferences")
                    .select()
                    .eq("id", value: uid)
                    .limit(1)
                    .execute()
                    .value
                
                if let p = prefs.first {
                    if let base = p.smokes_baseline, base > 0 {
                        self.smokesSettings.baselineCigsPerDay = base
                        userDefaults.set(base, forKey: "smokes_baseline")
                    }
                    if let pack = p.smokes_pack_size, pack > 0 {
                        self.smokesSettings.cigsPerPack = pack
                    }
                    if let cost = p.smokes_pack_cost, cost >= 0 {
                        self.smokesSettings.costPerPack = cost
                    }
                    if let curr = p.smokes_currency, !curr.isEmpty {
                        self.smokesSettings.currency = curr
                    }
                    if let qStr = p.smokes_quit_date, let qDate = HabitDateParser.parse(qStr) {
                        self.smokesSettings.quitStartDate = qDate
                    }
                    if let wg = p.water_goal, wg > 0 {
                        self.waterGoal = wg
                        userDefaults.set(wg, forKey: "water_goal")
                    }
                    if let sData = try? JSONEncoder().encode(self.smokesSettings) {
                        userDefaults.set(sData, forKey: "smokes_settings")
                    }
                }
            } catch {
                print("[HabitsService] Note: Could not fetch user_preferences: \(error.localizedDescription)")
            }
            
            // 2. Fetch Goals from habits_goals (fallback / sync)
            do {
                let goals: [HabitGoalRecord] = try await supabase.from("habits_goals")
                    .select()
                    .eq("user_id", value: uid)
                    .eq("is_deleted", value: false)
                    .execute()
                    .value
                
                for g in goals {
                    if g.habitType == "water" && g.targetValue > 0 {
                        self.waterGoal = g.targetValue
                        userDefaults.set(g.targetValue, forKey: "water_goal")
                    } else if g.habitType == "smokes" && g.targetValue > 0 && self.smokesSettings.baselineCigsPerDay == 0 {
                        self.smokesSettings.baselineCigsPerDay = Int(g.targetValue)
                        userDefaults.set(Int(g.targetValue), forKey: "smokes_baseline")
                    }
                }
            } catch {
                print("[HabitsService] Note: Could not fetch habits_goals: \(error.localizedDescription)")
            }
        }
        
        // 3. Fetch Logs for this selected day
        do {
            var query = supabase.from("habits_logs")
                .select()
                .gte("logged_at", value: startIso)
                .lt("logged_at", value: endIso)
                .eq("is_deleted", value: false)
            if let uid = userId {
                query = query.eq("user_id", value: uid)
            }
            let logs: [HabitLogRecord] = try await query
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
        
        // 4. Batch query 112 days (16 full weeks) of consistency history
        let today = cal.startOfDay(for: Date())
        let heatStartDate = cal.date(byAdding: .day, value: -111, to: today) ?? today
        let startStr = isoDateFormatter.string(from: heatStartDate)
        let endStr = isoDateFormatter.string(from: today)
        
        var fetchedConsistency = false
        var newWaterTotals: [String: Double] = [:]
        var newSmokesTotals: [String: Int] = [:]
        
        // 4A. Primary: Call Supabase RPC get_habits_consistency for Water & Smokes
        do {
            let waterParams = HabitsConsistencyParams(p_habit_type: "water", p_start_date: startStr, p_end_date: endStr)
            let waterRows: [HabitsConsistencyRow] = try await supabase.rpc("get_habits_consistency", params: waterParams).execute().value
            
            let smokesParams = HabitsConsistencyParams(p_habit_type: "smokes", p_start_date: startStr, p_end_date: endStr)
            let smokesRows: [HabitsConsistencyRow] = try await supabase.rpc("get_habits_consistency", params: smokesParams).execute().value
            
            for r in waterRows {
                newWaterTotals[r.normalizedDayKey] = r.total_value.value
            }
            for r in smokesRows {
                newSmokesTotals[r.normalizedDayKey] = Int(r.total_value.value)
            }
            fetchedConsistency = true
            print("[HabitsService] Successfully fetched consistency RPC: \(waterRows.count) water days, \(smokesRows.count) smokes days.")
        } catch {
            print("[HabitsService] Note: RPC get_habits_consistency failed (\(error.localizedDescription)). Falling back to direct tables...")
        }
        
        // 4B. Fallback: Dual-Table Ingestion (habits_daily_summaries + habits_logs)
        if !fetchedConsistency {
            do {
                // 1. Fetch habits_daily_summaries
                var sumQuery = supabase.from("habits_daily_summaries")
                    .select("habit_type,date,total_value,log_count")
                    .gte("date", value: startStr)
                if let uid = userId {
                    sumQuery = sumQuery.eq("user_id", value: uid)
                }
                let summaries: [HabitsDailySummaryRow] = (try? await sumQuery.execute().value) ?? []
                for s in summaries {
                    let k = s.normalizedDayKey
                    if s.habit_type == "water" {
                        newWaterTotals[k] = s.total_value.value
                    } else if s.habit_type == "smokes" {
                        newSmokesTotals[k] = Int(s.total_value.value)
                    }
                }
                
                // 2. Fetch raw habits_logs (override summaries where raw logs exist)
                let startIso112 = isoUtcFormatter.string(from: heatStartDate)
                var logsQuery = supabase.from("habits_logs")
                    .select("value,metadata,logged_at,habit_type")
                    .gte("logged_at", value: startIso112)
                    .eq("is_deleted", value: false)
                if let uid = userId {
                    logsQuery = logsQuery.eq("user_id", value: uid)
                }
                let rawLogs: [HabitHistoricalLogItem] = (try? await logsQuery.limit(5000).execute().value) ?? []
                
                var rawWater: [String: Double] = [:]
                var rawSmokes: [String: Int] = [:]
                for l in rawLogs {
                    guard let logDate = HabitDateParser.parse(l.logged_at) else { continue }
                    let k = isoDateFormatter.string(from: logDate)
                    if l.habit_type == "water" {
                        rawWater[k, default: 0] += l.value.value
                    } else if l.habit_type == "smokes" {
                        rawSmokes[k, default: 0] += Int(l.value.value)
                    }
                }
                for (k, v) in rawWater {
                    newWaterTotals[k] = v
                }
                for (k, v) in rawSmokes {
                    newSmokesTotals[k] = v
                }
            }
        }
        
        // Merge into persistent daily totals
        for (k, v) in newWaterTotals {
            self.waterDailyTotals[k] = v
        }
        for (k, v) in newSmokesTotals {
            self.smokesDailyTotals[k] = v
        }
        
        // Ensure currently selected date's raw logs update the totals
        let selectedKey = isoDateFormatter.string(from: selectedDate)
        self.waterDailyTotals[selectedKey] = todaysWaterLogs.reduce(0.0) { $0 + $1.value }
        self.smokesDailyTotals[selectedKey] = todaysSmokesLogs.reduce(0) { $0 + Int($1.value) }
        
        saveDailyTotals()
        saveWeekCachesForWatch()
        
        // 5. Fetch Smokes Financials
        await fetchSmokesFinancials(userId: userId)
        
        recalculateDailyAggregates()
        recomputeAllHistoriesAndHeatmaps()
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
        
        // Load cached daily totals dictionary
        if let wData = userDefaults.data(forKey: "habits_water_daily_totals"),
           let wDict = try? JSONDecoder().decode([String: Double].self, from: wData) {
            self.waterDailyTotals = wDict
        }
        if let sData = userDefaults.data(forKey: "habits_smokes_daily_totals"),
           let sDict = try? JSONDecoder().decode([String: Int].self, from: sData) {
            self.smokesDailyTotals = sDict
        }
        
        loadLocalLogsForSelectedDate()
        recalculateDailyAggregates()
        recomputeAllHistoriesAndHeatmaps()
    }
    
    private func saveDailyTotals() {
        if let wData = try? JSONEncoder().encode(waterDailyTotals) {
            userDefaults.set(wData, forKey: "habits_water_daily_totals")
        }
        if let sData = try? JSONEncoder().encode(smokesDailyTotals) {
            userDefaults.set(sData, forKey: "habits_smokes_daily_totals")
        }
    }
    
    public func saveWeekCachesForWatch() {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: startOfToday) // 1=Sun, 2=Mon...
        let daysFromMonday = (weekday == 1) ? 6 : (weekday - 2)
        guard let thisMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: startOfToday) else { return }
        
        var waterBuckets: [WaterDayBucket] = []
        var smokeBuckets: [SmokeDayBucket] = []
        
        for i in 0..<7 {
            if let dayDate = cal.date(byAdding: .day, value: i, to: thisMonday) {
                let dateKey = isoDateFormatter.string(from: dayDate)
                let wVal = waterDailyTotals[dateKey] ?? 0
                let sVal = Double(smokesDailyTotals[dateKey] ?? 0)
                
                waterBuckets.append(WaterDayBucket(date: dayDate, dayLabel: "", water: wVal, coffee: 0))
                smokeBuckets.append(SmokeDayBucket(date: dayDate, dayLabel: "", cig: sVal, heat: 0))
            }
        }
        
        if let wData = try? JSONEncoder().encode(waterBuckets) {
            userDefaults.set(wData, forKey: "bubbles_week_cache")
        }
        if let sData = try? JSONEncoder().encode(smokeBuckets) {
            userDefaults.set(sData, forKey: "smokes_week_cache")
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
        let lastLog = todaysSmokesLogs.first
        let timeSince = lastLog.map { Date().timeIntervalSince($0.loggedAt) }
        
        let currentSavings = smokesFinancials.moneySaved
        let currentAvoided = smokesFinancials.cigsAvoided
        let days = smokesFinancials.daysTracked
        
        self.smokesFinancials = SmokesFinancialMetrics(
            moneySaved: currentSavings,
            cigsAvoided: currentAvoided,
            daysTracked: days,
            costPerCig: smokesSettings.costPerCig,
            lastSmokeDate: lastLog?.loggedAt,
            timeSinceLastSmoke: timeSince
        )
    }
    
    // MARK: - Smokes Financials & RPC
    
    private func fetchSmokesFinancials(userId: String?) async {
        let cal = Calendar.current
        let days = max(1, (cal.dateComponents([.day], from: smokesSettings.quitStartDate, to: Date()).day ?? 0) + 1)
        let costPerCig = smokesSettings.costPerCig
        let baseline = smokesSettings.baselineCigsPerDay
        
        var totalSmokedCount: Int?
        var daysTrackedCount: Int = days
        
        // Try RPC get_smokes_financials
        let isoSince = isoTimestampFormatter.string(from: smokesSettings.quitStartDate)
        do {
            let res: SmokesFinancialsRpcResult = try await supabase.rpc(
                "get_smokes_financials",
                params: SmokesFinancialsParams(p_since_date: isoSince)
            ).execute().value
            
            if let t = res.total_smoked?.value {
                totalSmokedCount = Int(t)
            }
            if let d = res.days_tracked, d > 0 {
                daysTrackedCount = d
            }
        } catch {
            print("[HabitsService] Note: RPC get_smokes_financials fallback (\(error.localizedDescription)). Calculating from daily totals...")
        }
        
        let totalSmoked: Int
        if let ts = totalSmokedCount {
            totalSmoked = ts
        } else {
            // Local calculation from daily totals
            var sum = 0
            for dayOffset in 0..<daysTrackedCount {
                if let d = cal.date(byAdding: .day, value: -dayOffset, to: Date()) {
                    let k = isoDateFormatter.string(from: d)
                    sum += smokesDailyTotals[k] ?? 0
                }
            }
            totalSmoked = sum
        }
        
        let avoided = max(0, (daysTrackedCount * baseline) - totalSmoked)
        let moneySaved = Double(avoided) * costPerCig
        let lastLog = todaysSmokesLogs.first
        let timeSince = lastLog.map { Date().timeIntervalSince($0.loggedAt) }
        
        self.smokesFinancials = SmokesFinancialMetrics(
            moneySaved: moneySaved,
            cigsAvoided: avoided,
            daysTracked: daysTrackedCount,
            costPerCig: costPerCig,
            lastSmokeDate: lastLog?.loggedAt,
            timeSinceLastSmoke: timeSince
        )
    }
    
    private func recomputeAllHistoriesAndHeatmaps() {
        let cal = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        let tooltipFormatter = DateFormatter()
        tooltipFormatter.dateFormat = "MMM d, yyyy"
        
        // Sync selected date total into daily totals dictionary
        let selectedKey = isoDateFormatter.string(from: selectedDate)
        waterDailyTotals[selectedKey] = waterTotalToday
        smokesDailyTotals[selectedKey] = smokesTotalToday
        
        let today = cal.startOfDay(for: Date())
        
        // 1. Precalculate 7-Day History for Water & Smokes (Last 7 days ending Today)
        var wHistory: [HabitTrendDay] = []
        var sHistory: [HabitTrendDay] = []
        
        let sevenDaysAgo = cal.date(byAdding: .day, value: -6, to: today) ?? today
        
        for i in 0..<7 {
            if let targetDate = cal.date(byAdding: .day, value: i, to: sevenDaysAgo) {
                let label = cal.isDateInToday(targetDate) ? "Today" : dayFormatter.string(from: targetDate)
                let dateKey = isoDateFormatter.string(from: targetDate)
                
                // Water
                let wVal: Double = waterDailyTotals[dateKey] ?? 0
                let wGoal = waterGoal
                let wMet = wVal >= wGoal && wGoal > 0
                wHistory.append(HabitTrendDay(date: targetDate, dayLabel: label, value: wVal, goal: wGoal, isGoalMet: wMet))
                
                // Smokes
                let sVal: Double = Double(smokesDailyTotals[dateKey] ?? 0)
                let sGoal = Double(smokesSettings.baselineCigsPerDay)
                let sMet = sVal <= sGoal
                sHistory.append(HabitTrendDay(date: targetDate, dayLabel: label, value: sVal, goal: sGoal, isGoalMet: sMet))
            }
        }
        self.waterSevenDayHistory = wHistory
        self.smokesSevenDayHistory = sHistory
        
        // 2. Precalculate 112-Day (16 full weeks) Consistency Heatmap for Water & Smokes
        var wHeatmap: [HabitConsistencyCell] = []
        var sHeatmap: [HabitConsistencyCell] = []
        
        let heatStart = cal.date(byAdding: .day, value: -111, to: today) ?? today
        
        for i in 0..<112 {
            if let dayDate = cal.date(byAdding: .day, value: i, to: heatStart) {
                let dateKey = isoDateFormatter.string(from: dayDate)
                let tipDate = tooltipFormatter.string(from: dayDate)
                
                // Water
                let wVal: Double = waterDailyTotals[dateKey] ?? 0
                let wRatio = waterGoal > 0 ? (wVal / waterGoal) : 0
                let wLevel: Int
                if wVal == 0 {
                    wLevel = 0
                } else if wRatio >= 1.0 {
                    wLevel = 4
                } else if wRatio >= 0.75 {
                    wLevel = 3
                } else if wRatio >= 0.50 {
                    wLevel = 2
                } else {
                    wLevel = 1
                }
                let wTip = "\(tipDate): \(Int(wVal)) ml"
                let wGoalMet = wVal >= waterGoal && waterGoal > 0
                wHeatmap.append(HabitConsistencyCell(date: dayDate, dateKey: dateKey, value: wVal, intensityLevel: wLevel, tooltip: wTip, isGoalMet: wGoalMet))
                
                // Smokes
                let sVal: Double = Double(smokesDailyTotals[dateKey] ?? 0)
                let baseline = Double(smokesSettings.baselineCigsPerDay)
                let sRatio = baseline > 0 ? (sVal / baseline) : 0
                let sLevel: Int
                if sVal == 0 {
                    sLevel = 0 // Dark neutral (smoke-free or no logs)
                } else if sRatio < 0.5 {
                    sLevel = 1 // Green (low consumption, great discipline)
                } else if sRatio < 0.8 {
                    sLevel = 2 // Yellow (moderate)
                } else if sRatio <= 1.0 {
                    sLevel = 3 // Orange (close to baseline limit)
                } else {
                    sLevel = 4 // Red (exceeded baseline)
                }
                let sTip = sVal == 0 ? "\(tipDate): 0 cigs" : "\(tipDate): \(Int(sVal)) cigs (Limit: \(Int(baseline)))"
                let sGoalMet = sVal <= baseline
                sHeatmap.append(HabitConsistencyCell(date: dayDate, dateKey: dateKey, value: sVal, intensityLevel: sLevel, tooltip: sTip, isGoalMet: sGoalMet))
            }
        }
        self.waterConsistencyHeatmap = wHeatmap
        self.smokesConsistencyHeatmap = sHeatmap
    }
}
