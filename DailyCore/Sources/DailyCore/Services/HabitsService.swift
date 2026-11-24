import Foundation
import Supabase
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

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
        Task {
            let preset = WaterPreset.matching(drink) ?? .glass
            await logWater(preset: preset, customAmount: amountMl, multiplier: 1, customDrinkName: drink)
        }
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
    private let groupSuiteName = GroupDefaults.suiteName
    private var offlineLogQueue: [HabitLogRecord] = []
    private var pendingInFlightRecords: [UUID: HabitLogRecord] = [:]
    private var recentlyPushedRecords: [UUID: (record: HabitLogRecord, pushedAt: Date)] = [:]
    private var pendingInFlightDeleteIds: Set<String> = []
    private var lastWrittenBridgeUpdatedAt: Date = .distantPast
    private var activeFlushTask: Task<Void, Never>?
    private var needsFlushRecheck = false
    private var activeForegroundSyncTask: Task<Void, Never>?
    private var lastForegroundRefreshAt: Date = .distantPast
    private var lastConsistencyAndPrefsFetchAt: Date = .distantPast
    private var lastKnownTodayStart: Date = Calendar.current.startOfDay(for: Date())
    private var lastPastDateNavigationAt: Date? = nil
    
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
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let rolledOver = self.checkMidnightRolloverIfNeeded()
                await self.syncForForegroundTransition(dayRolledOver: rolledOver)
            }
        }
        #elseif canImport(AppKit)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let rolledOver = self.checkMidnightRolloverIfNeeded()
                await self.syncForForegroundTransition(dayRolledOver: rolledOver)
            }
        }
        #endif
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.lastForegroundRefreshAt = Date()
            await self.flushOfflineQueue()
            await self.loadDataForSelectedDate()
        }
    }

    /// Single-flight foreground transition sync used by UIApplication/NSApplication observers
    /// and SwiftUI scenePhase transitions without double-fetching Supabase.
    public func syncForForegroundTransition(dayRolledOver: Bool) async {
        if let existingTask = activeForegroundSyncTask {
            await existingTask.value
            if !dayRolledOver {
                return
            }
        }

        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.reloadFromLocalStorage()
            await self.flushOfflineQueue()
            guard dayRolledOver || Date().timeIntervalSince(self.lastForegroundRefreshAt) >= 120 else { return }
            self.lastForegroundRefreshAt = Date()
            await self.loadDataForSelectedDate(forceRefresh: dayRolledOver)
        }
        activeForegroundSyncTask = task
        await task.value
        activeForegroundSyncTask = nil
    }
    
    // MARK: - Midnight Rollover & Date Navigation
    
    @discardableResult
    public func checkMidnightRolloverIfNeeded() -> Bool {
        let cal = Calendar.current
        let now = Date()
        let currentTodayStart = cal.startOfDay(for: now)
        if currentTodayStart > lastKnownTodayStart {
            lastKnownTodayStart = currentTodayStart
            selectedDate = now
            lastPastDateNavigationAt = nil
            loadLocalLogsForSelectedDate()
            recalculateDailyAggregates()
            saveDailyTotals()
            return true
        }
        if !cal.isDateInToday(selectedDate) {
            if let navAt = lastPastDateNavigationAt, now.timeIntervalSince(navAt) > 1800 {
                selectedDate = now
                lastPastDateNavigationAt = nil
                loadLocalLogsForSelectedDate()
                recalculateDailyAggregates()
                saveDailyTotals()
                return true
            } else if lastPastDateNavigationAt == nil {
                selectedDate = now
                loadLocalLogsForSelectedDate()
                recalculateDailyAggregates()
                saveDailyTotals()
                return true
            }
        }
        return false
    }
    
    public func changeDate(to newDate: Date) {
        let cal = Calendar.current
        let isNavigatingToToday = cal.isDateInToday(newDate)
        if isNavigatingToToday {
            lastPastDateNavigationAt = nil
        } else {
            lastPastDateNavigationAt = Date()
        }
        guard !cal.isDate(newDate, inSameDayAs: selectedDate) else {
            if isNavigatingToToday {
                Task {
                    await loadDataForSelectedDate(forceRefresh: true)
                }
            }
            return
        }
        selectedDate = newDate
        loadLocalLogsForSelectedDate()
        recalculateDailyAggregates()
        if isNavigatingToToday {
            saveDailyTotals()
        }
        Task {
            await loadDataForSelectedDate(forceRefresh: isNavigatingToToday)
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
        lastPastDateNavigationAt = nil
        changeDate(to: Date())
    }
    
    public func switchHabit(to habit: HabitType) {
        guard activeHabit != habit else { return }
        activeHabit = habit
    }
    
    // MARK: - Logging Actions

    private func cachedSyncUserId() -> UUID? {
        for key in ["supabase_user_id", "authenticated_user_id", "current_user_id"] {
            if let idStr = userDefaults.string(forKey: key),
               !idStr.isEmpty,
               idStr.lowercased() != "guest",
               let uuid = UUID(uuidString: idStr) {
                return uuid
            }
        }
        return nil
    }

    private func computeLogDate(for targetDate: Date) -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(targetDate) {
            return Date()
        }
        let nowTime = cal.dateComponents([.hour, .minute, .second], from: Date())
        var components = cal.dateComponents([.year, .month, .day], from: targetDate)
        components.hour = nowTime.hour
        components.minute = nowTime.minute
        components.second = nowTime.second
        return cal.date(from: components) ?? targetDate
    }

    public func logWater(preset: WaterPreset, customAmount: Double? = nil, multiplier: Int = 1, customDrinkName: String? = nil) async {
        let safeMultiplier = max(1, multiplier)
        let baseAmount = customAmount ?? preset.defaultAmountMl
        let totalAmount = baseAmount * Double(safeMultiplier)

        let drinkName = customDrinkName ?? preset.rawValue
        var metaDict: [String: String] = ["drink": drinkName]
        if safeMultiplier > 1 {
            metaDict["multiplier"] = "\(safeMultiplier)"
            metaDict["base_value"] = "\(baseAmount)"
        }
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }

        let logDate = computeLogDate(for: selectedDate)
        let isLogForToday = Calendar.current.isDateInToday(logDate)
        let now = Date()

        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: cachedSyncUserId(),
            habitType: "water",
            value: totalAmount,
            unit: "ml",
            loggedAt: logDate,
            metadata: metaJson,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )

        // 1. Protect against concurrent fetches and update in-memory + atomic App Group state synchronously (0ms latency)
        pendingInFlightRecords[newRecord.id] = newRecord
        todaysWaterLogs.insert(newRecord, at: 0)
        recalculateDailyAggregates()
        saveLocalLogs()

        let dateKey = isoDateFormatter.string(from: logDate)
        waterDailyTotals[dateKey, default: 0] += totalAmount
        saveDailyTotals(reloadingKinds: isLogForToday ? [
            WidgetDataCoordinator.WidgetKind.bubbles,
            WidgetDataCoordinator.WidgetKind.combined
        ] : [])
        recomputeAllHistoriesAndHeatmaps()

        // 2. Trigger HealthKit hook
        onWaterLogged?(totalAmount, logDate)

        // 3. Push to Supabase (pendingInFlightRecords protects until pushed or queued)
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

        let logDate = computeLogDate(for: selectedDate)
        let isLogForToday = Calendar.current.isDateInToday(logDate)
        let now = Date()

        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: cachedSyncUserId(),
            habitType: "smokes",
            value: Double(totalCount),
            unit: "cigs",
            loggedAt: logDate,
            metadata: metaJson,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )

        // 1. Protect against concurrent fetches and update in-memory + atomic App Group state synchronously (0ms latency)
        pendingInFlightRecords[newRecord.id] = newRecord
        todaysSmokesLogs.insert(newRecord, at: 0)
        recalculateDailyAggregates()
        saveLocalLogs()

        let dateKey = isoDateFormatter.string(from: logDate)
        smokesDailyTotals[dateKey, default: 0] += totalCount
        saveDailyTotals(reloadingKinds: isLogForToday ? [
            WidgetDataCoordinator.WidgetKind.smokes,
            WidgetDataCoordinator.WidgetKind.combined
        ] : [])
        recomputeAllHistoriesAndHeatmaps()

        // 2. Push to Supabase BEFORE RPC financials so server state & concurrent refreshes see the record immediately
        await pushLogToSupabase(newRecord)

        // 3. Update smokes financials
        let resolvedUserId: String?
        if let cachedId = newRecord.userId?.uuidString.lowercased() {
            resolvedUserId = cachedId
        } else {
            resolvedUserId = (try? await supabase.auth.session)?.user.id.uuidString.lowercased()
        }
        await fetchSmokesFinancials(userId: resolvedUserId)
    }

    public func deleteLog(id: UUID) async {
        let idString = id.uuidString

        // 1. Record persistent tombstone + in-flight delete guard synchronously before awaiting
        pendingInFlightDeleteIds.insert(idString)
        pendingInFlightRecords.removeValue(forKey: id)
        recentlyPushedRecords.removeValue(forKey: id)
        var deletedIds = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
        deletedIds.insert(idString)
        if deletedIds.count > 1000 {
            deletedIds = Set(deletedIds.suffix(1000))
        }
        userDefaults.set(Array(deletedIds), forKey: "deleted_habit_log_ids")

        // 2. Immediately purge from offlineLogQueue in memory & storage
        offlineLogQueue.removeAll { $0.id == id || deletedIds.contains($0.id.uuidString) }
        WidgetDataCoordinator.shared.removePendingHabitLogs(ids: [id])

        // 3. Remove from in-memory arrays
        var deletedRecord: HabitLogRecord?
        if let idx = todaysWaterLogs.firstIndex(where: { $0.id == id }) {
            deletedRecord = todaysWaterLogs.remove(at: idx)
        } else if let idx = todaysSmokesLogs.firstIndex(where: { $0.id == id }) {
            deletedRecord = todaysSmokesLogs.remove(at: idx)
        }

        // 4. Recalculate daily totals, persist logs & atomic widget bridge cleanly
        let isSelectedToday = Calendar.current.isDateInToday(selectedDate)
        var reloadKinds: [String] = []
        if let rec = deletedRecord {
            let dateKey = isoDateFormatter.string(from: rec.loggedAt)
            let isRecToday = Calendar.current.isDateInToday(rec.loggedAt)
            if rec.habitType == "water" {
                waterDailyTotals[dateKey] = max(0, (waterDailyTotals[dateKey] ?? rec.value) - rec.value)
                if let wData = userDefaults.data(forKey: "local_water_logs_\(dateKey)"),
                   var logs = try? JSONDecoder().decode([HabitLogRecord].self, from: wData) {
                    logs.removeAll { $0.id == id || deletedIds.contains($0.id.uuidString) }
                    if let encoded = try? JSONEncoder().encode(logs) {
                        userDefaults.set(encoded, forKey: "local_water_logs_\(dateKey)")
                    }
                }
                if isRecToday {
                    reloadKinds = [WidgetDataCoordinator.WidgetKind.bubbles, WidgetDataCoordinator.WidgetKind.combined]
                }
            } else {
                smokesDailyTotals[dateKey] = max(0, (smokesDailyTotals[dateKey] ?? Int(rec.value)) - Int(rec.value))
                if let sData = userDefaults.data(forKey: "local_smokes_logs_\(dateKey)"),
                   var logs = try? JSONDecoder().decode([HabitLogRecord].self, from: sData) {
                    logs.removeAll { $0.id == id || deletedIds.contains($0.id.uuidString) }
                    if let encoded = try? JSONEncoder().encode(logs) {
                        userDefaults.set(encoded, forKey: "local_smokes_logs_\(dateKey)")
                    }
                }
                if isRecToday {
                    reloadKinds = [WidgetDataCoordinator.WidgetKind.smokes, WidgetDataCoordinator.WidgetKind.combined]
                }
            }
        } else if isSelectedToday {
            reloadKinds = [
                WidgetDataCoordinator.WidgetKind.bubbles,
                WidgetDataCoordinator.WidgetKind.smokes,
                WidgetDataCoordinator.WidgetKind.combined
            ]
        }

        recalculateDailyAggregates()
        saveLocalLogs()
        saveDailyTotals(reloadingKinds: reloadKinds)
        recomputeAllHistoriesAndHeatmaps()

        if deletedRecord?.habitType == "smokes" {
            let session = try? await supabase.auth.session
            await fetchSmokesFinancials(userId: session?.user.id.uuidString.lowercased())
        }

        // 5. Asynchronously mark deleted in Supabase (with offline fallback queue)
        defer { pendingInFlightDeleteIds.remove(idString) }
        do {
            try await supabase.from("habits_logs")
                .update(["is_deleted": true], returning: .minimal)
                .eq("id", value: idString.lowercased())
                .execute()
        } catch {
            print("[HabitsService] Offline soft-delete queued for \(idString): \(error.localizedDescription)")
            var pendingDeletes = userDefaults.stringArray(forKey: "offline_deleted_habits_queue") ?? []
            if !pendingDeletes.contains(idString) {
                pendingDeletes.append(idString)
                userDefaults.set(pendingDeletes, forKey: "offline_deleted_habits_queue")
            }
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
            _ = try? await supabase.from("habits_goals").upsert(goalRecord, returning: .minimal).execute()
            
            // 2. Also upsert water_goal into user_preferences
            struct WaterPrefUpdate: Codable {
                let id: String
                let water_goal: Double
            }
            _ = try? await supabase.from("user_preferences").upsert(WaterPrefUpdate(id: userId, water_goal: newGoal), returning: .minimal).execute()
        }
        recalculateDailyAggregates()
        recomputeAllHistoriesAndHeatmaps()
        saveDailyTotals(reloadingKinds: [
            WidgetDataCoordinator.WidgetKind.bubbles,
            WidgetDataCoordinator.WidgetKind.combined
        ])
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
            _ = try? await supabase.from("user_preferences").upsert(prefUpdate, returning: .minimal).execute()
            
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
            _ = try? await supabase.from("habits_goals").upsert(goalRecord, returning: .minimal).execute()
        }
        recalculateDailyAggregates()
        recomputeAllHistoriesAndHeatmaps()
        saveDailyTotals(reloadingKinds: [
            WidgetDataCoordinator.WidgetKind.smokes,
            WidgetDataCoordinator.WidgetKind.combined
        ])
        await fetchSmokesFinancials(userId: session?.user.id.uuidString.lowercased())
    }
    
    // MARK: - Data Fetching & Sync
    
    public func loadDataForSelectedDate(forceRefresh: Bool = false) async {
        let rolledOver = checkMidnightRolloverIfNeeded()
        let requestDate = selectedDate
        let requestKey = isoDateFormatter.string(from: requestDate)
        let todayKey = isoDateFormatter.string(from: Date())
        let prevTodayWater = waterDailyTotals[todayKey] ?? 0
        let prevTodaySmokes = smokesDailyTotals[todayKey] ?? 0
        let prevWaterGoal = waterGoal
        let prevSmokesBaseline = smokesSettings.baselineCigsPerDay
        let prevTodayWaterIds = Calendar.current.isDateInToday(selectedDate) ? todaysWaterLogs.map(\.id) : []
        let prevTodaySmokesIds = Calendar.current.isDateInToday(selectedDate) ? todaysSmokesLogs.map(\.id) : []

        isLoading = true
        defer { isLoading = false }
        
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: requestDate)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        let isoUtcFormatter = ISO8601DateFormatter()
        isoUtcFormatter.formatOptions = [.withInternetDateTime]
        isoUtcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let startIso = isoUtcFormatter.string(from: startOfDay)
        let endIso = isoUtcFormatter.string(from: endOfDay)
        
        // 0. Flush any pending offline or widget logs first so remote database is up-to-date
        await flushOfflineQueue()
        
        let session = try? await supabase.auth.session
        let userId = session?.user.id.uuidString.lowercased()
        let shouldRefreshConsistencyAndPrefs = forceRefresh
            || waterDailyTotals.isEmpty
            || Date().timeIntervalSince(lastConsistencyAndPrefsFetchAt) > 900
        
        if let uid = userId {
            userDefaults.set(uid, forKey: "current_user_id")
            userDefaults.set(uid, forKey: "authenticated_user_id")
            
            if shouldRefreshConsistencyAndPrefs {
                // 1. Fetch user_preferences (only habits columns, omitting unrelated profile blobs)
                do {
                    let prefs: [UserPreferencesRecord] = try await supabase.from("user_preferences")
                        .select("id,water_goal,smokes_baseline,smokes_pack_size,smokes_pack_cost,smokes_currency,smokes_quit_date")
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
        }
        
        // 3. Fetch Logs for this selected day (including deleted ones to sync tombstones across devices)
        do {
            var query = supabase.from("habits_logs")
                .select()
                .gte("logged_at", value: startIso)
                .lt("logged_at", value: endIso)
            if let uid = userId {
                query = query.eq("user_id", value: uid)
            }
            let allDayRemoteLogs: [HabitLogRecord] = try await query
                .order("logged_at", ascending: false)
                .execute()
                .value
            
            // Sync remote tombstones (records deleted on any other device/instance)
            let remoteDeletedIds = Set(allDayRemoteLogs.filter { $0.isDeleted }.map { $0.id.uuidString })
            var deletedIds = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
            if !remoteDeletedIds.isEmpty {
                deletedIds.formUnion(remoteDeletedIds)
                if deletedIds.count > 1000 {
                    deletedIds = Set(deletedIds.suffix(1000))
                }
                userDefaults.set(Array(deletedIds), forKey: "deleted_habit_log_ids")
                
                // Purge remote-deleted items from offlineLogQueue if present
                self.offlineLogQueue.removeAll { deletedIds.contains($0.id.uuidString) }
                if let data = try? JSONEncoder().encode(self.offlineLogQueue) {
                    userDefaults.set(data, forKey: "offline_habits_queue")
                }
            }
            
            let activeDeletedIds = deletedIds.union(pendingInFlightDeleteIds)
            let activeRemoteLogs = allDayRemoteLogs.filter { !$0.isDeleted && !activeDeletedIds.contains($0.id.uuidString) }
            let remoteIds = Set(activeRemoteLogs.map(\.id))
            pruneConfirmedRecentlyPushed(confirmedIds: remoteIds)

            let pendingWater = pendingRecords(habitType: "water", on: requestDate, excluding: remoteIds, deletedIds: activeDeletedIds)
            let pendingSmokes = pendingRecords(habitType: "smokes", on: requestDate, excluding: remoteIds, deletedIds: activeDeletedIds)

            let mergedWater = deduplicatedSortedLogs(pendingWater + activeRemoteLogs.filter { $0.habitType == "water" })
            let mergedSmokes = deduplicatedSortedLogs(pendingSmokes + activeRemoteLogs.filter { $0.habitType == "smokes" })

            if let wData = try? JSONEncoder().encode(mergedWater) {
                userDefaults.set(wData, forKey: "local_water_logs_\(requestKey)")
            }
            if let sData = try? JSONEncoder().encode(mergedSmokes) {
                userDefaults.set(sData, forKey: "local_smokes_logs_\(requestKey)")
            }
            if isoDateFormatter.string(from: selectedDate) == requestKey {
                self.todaysWaterLogs = mergedWater
                self.todaysSmokesLogs = mergedSmokes
            }
            self.waterDailyTotals[requestKey] = mergedWater.reduce(0.0) { $0 + $1.value }
            self.smokesDailyTotals[requestKey] = mergedSmokes.reduce(0) { $0 + Int($1.value) }
        } catch {
            print("[HabitsService] Note: Could not fetch habits_logs: \(error.localizedDescription)")
            if isoDateFormatter.string(from: selectedDate) == requestKey {
                loadLocalLogsForSelectedDate()
            }
        }
        
        // 4. Batch query 112 days (16 full weeks) of consistency history (throttled to 15m unless forced)
        if shouldRefreshConsistencyAndPrefs {
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
                lastConsistencyAndPrefsFetchAt = Date()
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
                    lastConsistencyAndPrefsFetchAt = Date()
                }
            }
            
            // Merge into persistent daily totals
            for (k, v) in newWaterTotals {
                self.waterDailyTotals[k] = v
            }
            for (k, v) in newSmokesTotals {
                self.smokesDailyTotals[k] = v
            }
        }
        
        // Ensure currently selected date's raw logs update the totals
        let currentSelectedKey = isoDateFormatter.string(from: selectedDate)
        if currentSelectedKey == requestKey {
            self.waterDailyTotals[requestKey] = todaysWaterLogs.reduce(0.0) { $0 + $1.value }
            self.smokesDailyTotals[requestKey] = todaysSmokesLogs.reduce(0) { $0 + Int($1.value) }
        }

        let isSelectedToday = Calendar.current.isDateInToday(selectedDate)
        let waterChanged = rolledOver
            || abs((waterDailyTotals[todayKey] ?? 0) - prevTodayWater) > 0.01
            || abs(waterGoal - prevWaterGoal) > 0.01
            || (isSelectedToday && todaysWaterLogs.map(\.id) != prevTodayWaterIds)
        let smokesChanged = rolledOver
            || (smokesDailyTotals[todayKey] ?? 0) != prevTodaySmokes
            || smokesSettings.baselineCigsPerDay != prevSmokesBaseline
            || (isSelectedToday && todaysSmokesLogs.map(\.id) != prevTodaySmokesIds)

        var kindsToReload: [String] = []
        if waterChanged {
            kindsToReload.append(WidgetDataCoordinator.WidgetKind.bubbles)
        }
        if smokesChanged {
            kindsToReload.append(WidgetDataCoordinator.WidgetKind.smokes)
        }
        if waterChanged || smokesChanged {
            kindsToReload.append(WidgetDataCoordinator.WidgetKind.combined)
        }

        saveDailyTotals(reloadingKinds: kindsToReload)
        saveWeekCachesForWatch()
        
        // 5. Fetch Smokes Financials (throttled alongside consistency unless forced)
        if shouldRefreshConsistencyAndPrefs {
            await fetchSmokesFinancials(userId: userId)
        }
        
        recalculateDailyAggregates()
        recomputeAllHistoriesAndHeatmaps()
        await flushOfflineQueue()
    }
    
    // MARK: - Offline Storage & Queue
    
    private func refreshPendingQueueFromBridge() {
        let pending = WidgetDataCoordinator.shared.readPendingHabitLogs()
        var merged = pending
        var seen = Set(pending.map(\.id))
        let deletedIds = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
            .union(pendingInFlightDeleteIds)
        for record in offlineLogQueue where !deletedIds.contains(record.id.uuidString) {
            if seen.insert(record.id).inserted {
                merged.append(record)
            }
        }
        self.offlineLogQueue = merged
    }

    private func adoptHabitsBridgeIfNewer() {
        // Adopt newer widget-side mutations from the atomic App Group bridge file
        // so interactive widget taps sync cleanly back into the running app.
        let today = Date()
        let todayKey = isoDateFormatter.string(from: today)
        guard let bridge = WidgetDataCoordinator.shared.readHabitsBridgeState(for: todayKey),
              bridge.updatedAt > lastWrittenBridgeUpdatedAt else {
            return
        }
        lastWrittenBridgeUpdatedAt = bridge.updatedAt
        var deletedIds = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
        deletedIds.formUnion(bridge.deletedIds)
        deletedIds.formUnion(pendingInFlightDeleteIds)
        if !bridge.deletedIds.isEmpty {
            userDefaults.set(Array(deletedIds), forKey: "deleted_habit_log_ids")
        }

        let pendingWater = pendingRecords(habitType: "water", on: today, excluding: Set(bridge.waterLogs.map(\.id)), deletedIds: deletedIds)
        let pendingSmokes = pendingRecords(habitType: "smokes", on: today, excluding: Set(bridge.smokesLogs.map(\.id)), deletedIds: deletedIds)
        let mergedWater = deduplicatedSortedLogs(pendingWater + bridge.waterLogs.filter { !deletedIds.contains($0.id.uuidString) })
        let mergedSmokes = deduplicatedSortedLogs(pendingSmokes + bridge.smokesLogs.filter { !deletedIds.contains($0.id.uuidString) })

        if let wData = try? JSONEncoder().encode(mergedWater) {
            userDefaults.set(wData, forKey: "local_water_logs_\(todayKey)")
        }
        if let sData = try? JSONEncoder().encode(mergedSmokes) {
            userDefaults.set(sData, forKey: "local_smokes_logs_\(todayKey)")
        }
        self.waterDailyTotals[todayKey] = mergedWater.isEmpty
            ? bridge.waterTotalMl
            : mergedWater.reduce(0.0) { $0 + $1.value }
        self.smokesDailyTotals[todayKey] = mergedSmokes.isEmpty
            ? bridge.smokesTotal
            : mergedSmokes.reduce(0) { $0 + Int($1.value) }
    }

    public func reloadFromLocalStorage() {
        userDefaults.synchronize()
        refreshPendingQueueFromBridge()
        if let wData = userDefaults.data(forKey: "habits_water_daily_totals"),
           let wDict = try? JSONDecoder().decode([String: Double].self, from: wData) {
            self.waterDailyTotals = wDict
        }
        if let sData = userDefaults.data(forKey: "habits_smokes_daily_totals"),
           let sDict = try? JSONDecoder().decode([String: Int].self, from: sData) {
            self.smokesDailyTotals = sDict
        }

        adoptHabitsBridgeIfNewer()

        loadLocalLogsForSelectedDate()
        recalculateDailyAggregates()
        recomputeAllHistoriesAndHeatmaps()
    }
    
    private func loadLocalSettingsAndQueue() {
        userDefaults.synchronize()
        if let g = userDefaults.value(forKey: "water_goal") as? Double {
            self.waterGoal = g
        }
        if let data = userDefaults.data(forKey: "smokes_settings"),
           let settings = try? JSONDecoder().decode(SmokesSettings.self, from: data) {
            self.smokesSettings = settings
        } else if let b = userDefaults.value(forKey: "smokes_baseline") as? Int {
            self.smokesSettings.baselineCigsPerDay = b
        }
        
        refreshPendingQueueFromBridge()
        
        // Load cached daily totals dictionary
        if let wData = userDefaults.data(forKey: "habits_water_daily_totals"),
           let wDict = try? JSONDecoder().decode([String: Double].self, from: wData) {
            self.waterDailyTotals = wDict
        }
        if let sData = userDefaults.data(forKey: "habits_smokes_daily_totals"),
           let sDict = try? JSONDecoder().decode([String: Int].self, from: sData) {
            self.smokesDailyTotals = sDict
        }

        adoptHabitsBridgeIfNewer()
        
        loadLocalLogsForSelectedDate()
        recalculateDailyAggregates()
        recomputeAllHistoriesAndHeatmaps()
    }
    
    public func saveDailyTotals() {
        saveDailyTotals(reloadingKinds: [
            WidgetDataCoordinator.WidgetKind.bubbles,
            WidgetDataCoordinator.WidgetKind.smokes,
            WidgetDataCoordinator.WidgetKind.combined
        ])
    }

    public func saveDailyTotals(reloadingKinds: [String]) {
        let today = Date()
        let todayKey = isoDateFormatter.string(from: today)
        let activeDeletedIds = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
            .union(pendingInFlightDeleteIds)

        let pendingBridgeLogs = WidgetDataCoordinator.shared.readPendingHabitLogs()
            .filter {
                !$0.isDeleted
                && !activeDeletedIds.contains($0.id.uuidString)
                && isoDateFormatter.string(from: $0.loggedAt) == todayKey
            }

        var todayWaterLogs: [HabitLogRecord]
        var todaySmokesLogs: [HabitLogRecord]
        if Calendar.current.isDateInToday(selectedDate) {
            todayWaterLogs = self.todaysWaterLogs.filter { !activeDeletedIds.contains($0.id.uuidString) }
            todaySmokesLogs = self.todaysSmokesLogs.filter { !activeDeletedIds.contains($0.id.uuidString) }
        } else {
            todayWaterLogs = cachedLocalLogs(forKey: todayKey, habitType: "water", on: today, deletedIds: activeDeletedIds)
            todaySmokesLogs = cachedLocalLogs(forKey: todayKey, habitType: "smokes", on: today, deletedIds: activeDeletedIds)
        }

        let pendingWater = pendingBridgeLogs.filter { $0.habitType == "water" }
        if !pendingWater.isEmpty {
            todayWaterLogs = deduplicatedSortedLogs(pendingWater + todayWaterLogs)
            if !todayWaterLogs.isEmpty {
                waterDailyTotals[todayKey] = max(waterDailyTotals[todayKey] ?? 0, todayWaterLogs.reduce(0.0) { $0 + $1.value })
            }
        }
        let pendingSmokes = pendingBridgeLogs.filter { $0.habitType == "smokes" }
        if !pendingSmokes.isEmpty {
            todaySmokesLogs = deduplicatedSortedLogs(pendingSmokes + todaySmokesLogs)
            if !todaySmokesLogs.isEmpty {
                smokesDailyTotals[todayKey] = max(smokesDailyTotals[todayKey] ?? 0, todaySmokesLogs.reduce(0) { $0 + Int($1.value) })
            }
        }

        if let wData = try? JSONEncoder().encode(waterDailyTotals) {
            userDefaults.set(wData, forKey: "habits_water_daily_totals")
        }
        if let sData = try? JSONEncoder().encode(smokesDailyTotals) {
            userDefaults.set(sData, forKey: "habits_smokes_daily_totals")
        }
        let todayWaterTotal = waterDailyTotals[todayKey] ?? 0
        let todaySmokesTotal = smokesDailyTotals[todayKey] ?? 0
        userDefaults.set(Int(todayWaterTotal), forKey: "cached_water_total")
        userDefaults.set(todaySmokesTotal, forKey: "cached_smokes_total")
        userDefaults.set(todayKey, forKey: "cached_habits_date")
        userDefaults.synchronize()

        let now = Date()
        let bridgeState = HabitsWidgetBridgeState(
            dateKey: todayKey,
            waterTotalMl: todayWaterTotal,
            waterGoalMl: waterGoal,
            waterLogs: todayWaterLogs,
            smokesTotal: todaySmokesTotal,
            smokesBaseline: smokesSettings.baselineCigsPerDay,
            smokesLogs: todaySmokesLogs,
            deletedIds: Array(activeDeletedIds),
            updatedAt: now
        )
        lastWrittenBridgeUpdatedAt = now
        WidgetDataCoordinator.shared.writeHabitsBridgeState(bridgeState)

        if !reloadingKinds.isEmpty {
            WidgetDataCoordinator.shared.reloadTimelines(kinds: reloadingKinds)
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
    
    private func cachedLocalLogs(
        forKey dateKey: String,
        habitType: String,
        on date: Date,
        deletedIds: Set<String>
    ) -> [HabitLogRecord] {
        let storageKey = habitType == "water" ? "local_water_logs_\(dateKey)" : "local_smokes_logs_\(dateKey)"
        let stored: [HabitLogRecord]
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: data) {
            stored = decoded.filter { !deletedIds.contains($0.id.uuidString) }
        } else {
            stored = []
        }
        let pending = pendingRecords(habitType: habitType, on: date, excluding: Set(stored.map(\.id)), deletedIds: deletedIds)
        return deduplicatedSortedLogs(pending + stored)
    }

    private func loadLocalLogsForSelectedDate() {
        let deletedIds = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
            .union(pendingInFlightDeleteIds)
        let dateKey = isoDateFormatter.string(from: selectedDate)
        self.todaysWaterLogs = cachedLocalLogs(forKey: dateKey, habitType: "water", on: selectedDate, deletedIds: deletedIds)
        self.todaysSmokesLogs = cachedLocalLogs(forKey: dateKey, habitType: "smokes", on: selectedDate, deletedIds: deletedIds)
    }

    private func pruneConfirmedRecentlyPushed(confirmedIds: Set<UUID>) {
        let cutoff = Date().addingTimeInterval(-15)
        recentlyPushedRecords = recentlyPushedRecords.filter { id, entry in
            !confirmedIds.contains(id) && entry.pushedAt > cutoff
        }
    }

    private func pendingRecords(
        habitType: String,
        on date: Date,
        excluding remoteIds: Set<UUID>,
        deletedIds: Set<String>
    ) -> [HabitLogRecord] {
        let targetKey = isoDateFormatter.string(from: date)
        let cutoff = Date().addingTimeInterval(-15)
        var result: [HabitLogRecord] = []
        var seen = remoteIds

        let recentRecords = recentlyPushedRecords.values
            .filter { $0.pushedAt > cutoff }
            .map(\.record)
        let bridgedPending = WidgetDataCoordinator.shared.readPendingHabitLogs()
        for record in Array(pendingInFlightRecords.values) + offlineLogQueue + bridgedPending + recentRecords {
            guard record.habitType == habitType else { continue }
            guard !deletedIds.contains(record.id.uuidString) else { continue }
            guard isoDateFormatter.string(from: record.loggedAt) == targetKey else { continue }
            if seen.insert(record.id).inserted {
                result.append(record)
            }
        }
        return result
    }

    private func deduplicatedSortedLogs(_ logs: [HabitLogRecord]) -> [HabitLogRecord] {
        var seen = Set<UUID>()
        var unique: [HabitLogRecord] = []
        for log in logs {
            if seen.insert(log.id).inserted {
                unique.append(log)
            }
        }
        return unique.sorted { $0.loggedAt > $1.loggedAt }
    }

    private func pushLogToSupabase(_ record: HabitLogRecord) async {
        defer { pendingInFlightRecords.removeValue(forKey: record.id) }

        let deletedIds = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
            .union(pendingInFlightDeleteIds)
        guard !deletedIds.contains(record.id.uuidString) else { return }

        var toInsert = record
        if toInsert.userId == nil {
            let session = try? await supabase.auth.session
            let currentUserId = session?.user.id ?? cachedSyncUserId()
            toInsert.userId = currentUserId
            if let uid = currentUserId?.uuidString.lowercased() {
                userDefaults.set(uid, forKey: "current_user_id")
            }
        }

        do {
            try await supabase.from("habits_logs").insert(toInsert, returning: .minimal).execute()
            if !pendingInFlightDeleteIds.contains(toInsert.id.uuidString) {
                recentlyPushedRecords[toInsert.id] = (toInsert, Date())
            }
        } catch {
            let latestDeleted = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
                .union(pendingInFlightDeleteIds)
            guard !latestDeleted.contains(toInsert.id.uuidString) else { return }
            print("[HabitsService] Supabase insert failed (\(error.localizedDescription)). Queuing offline...")
            WidgetDataCoordinator.shared.enqueuePendingHabitLog(toInsert)
            refreshPendingQueueFromBridge()
        }
    }
    
    public func flushOfflineQueue() async {
        if let existingTask = activeFlushTask {
            needsFlushRecheck = true
            await existingTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            repeat {
                self.needsFlushRecheck = false
                await self.performFlushOfflineQueuePass()
            } while self.needsFlushRecheck
        }
        activeFlushTask = task
        await task.value
        activeFlushTask = nil
    }

    private func performFlushOfflineQueuePass() async {
        userDefaults.synchronize()
        let deletedIds = Set(userDefaults.stringArray(forKey: "deleted_habit_log_ids") ?? [])
            .union(pendingInFlightDeleteIds)

        // 1. Reconcile in-memory queue with atomic App Group pending file & synchronized UserDefaults
        refreshPendingQueueFromBridge()
        let purgedDeletedUUIDs = Set(offlineLogQueue.filter { deletedIds.contains($0.id.uuidString) }.map(\.id))
        if !purgedDeletedUUIDs.isEmpty {
            WidgetDataCoordinator.shared.removePendingHabitLogs(ids: purgedDeletedUUIDs)
            offlineLogQueue.removeAll { purgedDeletedUUIDs.contains($0.id) }
        }

        // 2. Flush pending deletions queue
        let pendingDeletes = userDefaults.stringArray(forKey: "offline_deleted_habits_queue") ?? []
        if !pendingDeletes.isEmpty {
            var remainingDeletes: [String] = []
            for delId in pendingDeletes {
                do {
                    try await supabase.from("habits_logs")
                        .update(["is_deleted": true], returning: .minimal)
                        .eq("id", value: delId.lowercased())
                        .execute()
                } catch {
                    remainingDeletes.append(delId)
                }
            }
            userDefaults.set(remainingDeletes, forKey: "offline_deleted_habits_queue")
        }

        let snapshotQueue = offlineLogQueue
        guard !snapshotQueue.isEmpty else { return }

        let session = try? await supabase.auth.session
        let currentUserId = session?.user.id ?? cachedSyncUserId()

        var processedIds = Set<UUID>()
        for var record in snapshotQueue {
            if deletedIds.contains(record.id.uuidString) {
                processedIds.insert(record.id)
                continue
            }
            if record.userId == nil, let uid = currentUserId {
                record.userId = uid
            }
            do {
                try await supabase.from("habits_logs").insert(record, returning: .minimal).execute()
                processedIds.insert(record.id)
                if !pendingInFlightDeleteIds.contains(record.id.uuidString) {
                    recentlyPushedRecords[record.id] = (record, Date())
                }
            } catch {
                let errStr = error.localizedDescription.lowercased()
                if errStr.contains("duplicate") || errStr.contains("already exists") || errStr.contains("23505") || errStr.contains("unique") {
                    processedIds.insert(record.id)
                    if !pendingInFlightDeleteIds.contains(record.id.uuidString) {
                        recentlyPushedRecords[record.id] = (record, Date())
                    }
                    print("[HabitsService] flushOfflineQueue: record \(record.id) already exists in Supabase.")
                } else {
                    print("[HabitsService] flushOfflineQueue error (\(error.localizedDescription)). Retaining in queue.")
                }
            }
        }

        if !processedIds.isEmpty {
            WidgetDataCoordinator.shared.removePendingHabitLogs(ids: processedIds)
            refreshPendingQueueFromBridge()
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
            let preset = WaterPreset.matching(key)
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
        
        let cal = Calendar.current
        let defaultDays = max(1, (cal.dateComponents([.day], from: smokesSettings.quitStartDate, to: Date()).day ?? 0) + 1)
        let days = smokesFinancials.daysTracked > 0 ? smokesFinancials.daysTracked : defaultDays
        
        // Calculate fallback avoided & savings if not set
        var currentSavings = smokesFinancials.moneySaved
        var currentAvoided = smokesFinancials.cigsAvoided
        if currentSavings == 0 && currentAvoided == 0 {
            var sum = 0
            for dayOffset in 0..<days {
                if let d = cal.date(byAdding: .day, value: -dayOffset, to: Date()) {
                    let k = isoDateFormatter.string(from: d)
                    sum += smokesDailyTotals[k] ?? 0
                }
            }
            let avoided = max(0, (days * smokesSettings.baselineCigsPerDay) - sum)
            currentAvoided = avoided
            currentSavings = Double(avoided) * smokesSettings.costPerCig
        }
        
        self.smokesFinancials = SmokesFinancialMetrics(
            moneySaved: currentSavings,
            cigsAvoided: currentAvoided,
            daysTracked: days,
            costPerCig: smokesSettings.costPerCig,
            currency: smokesSettings.currency,
            lastSmokeDate: lastLog?.loggedAt ?? smokesFinancials.lastSmokeDate,
            timeSinceLastSmoke: timeSince ?? smokesFinancials.timeSinceLastSmoke
        )
    }
    
    // MARK: - Smokes Financials & RPC
    
    private func fetchSmokesFinancials(userId: String?) async {
        let cal = Calendar.current
        let days = max(1, (cal.dateComponents([.day], from: smokesSettings.quitStartDate, to: Date()).day ?? 0) + 1)
        let costPerCig = smokesSettings.costPerCig
        let baseline = smokesSettings.baselineCigsPerDay
        let currency = smokesSettings.currency
        
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
            currency: currency,
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
