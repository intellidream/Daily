import Foundation
import SwiftUI
import Combine
import WatchKit
import WidgetKit
import Supabase
import os.log

// MARK: - Habit Day Buckets for 7-Day Trend Charts

public struct WaterDayBucket: Identifiable, Codable, Sendable {
    public var id: UUID
    public let date: Date
    public var dayLabel: String
    public var water: Double
    public var coffee: Double
    public var total: Double { water + coffee }
    
    public init(id: UUID = UUID(), date: Date, dayLabel: String = "", water: Double = 0, coffee: Double = 0) {
        self.id = id
        self.date = date
        self.dayLabel = dayLabel
        self.water = water
        self.coffee = coffee
    }
}

public struct SmokeDayBucket: Identifiable, Codable, Sendable {
    public var id: UUID
    public let date: Date
    public var dayLabel: String
    public var cig: Double
    public var heat: Double
    public var total: Double { cig + heat }
    
    public init(id: UUID = UUID(), date: Date, dayLabel: String = "", cig: Double = 0, heat: Double = 0) {
        self.id = id
        self.date = date
        self.dayLabel = dayLabel
        self.cig = cig
        self.heat = heat
    }
}

private struct HabitWeekLogDto: Decodable {
    let value: FlexibleDouble
    let metadata: HabitLogMetadataHelper?
    let logged_at: String
    let habit_type: String
}

// MARK: - Centralized Reactive WatchHabitStore

@MainActor
public class WatchHabitStore: ObservableObject {
    public static let shared = WatchHabitStore()
    
    // Goals & Baselines
    @Published public var waterGoal: Int = 2000
    @Published public var smokesBaseline: Int = 40 // Canonical user default
    
    // Today's Water State
    @Published public var waterTotalToday: Int = 0
    @Published public var waterAmountToday: Int = 0
    @Published public var coffeeAmountToday: Int = 0
    @Published public var todayWaterLogs: [HabitLog] = []
    
    // Today's Smokes State
    @Published public var smokesTotalToday: Int = 0
    @Published public var cigsCountToday: Int = 0
    @Published public var heatCountToday: Int = 0
    @Published public var todaySmokesLogs: [HabitLog] = []
    
    // 7-Day Trend Buckets (Offset 0 = Current Mon-Sun week)
    @Published public var waterWeekBuckets: [WaterDayBucket] = []
    @Published public var smokesWeekBuckets: [SmokeDayBucket] = []
    
    // Sychronization Status
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncDate: Date? = nil
    
    // MARK: - Smokes Craving & Financial Metrics (Computed Locally in O(1))
    
    public var lastSmokeDate: Date? {
        guard let first = todaySmokesLogs.first else { return nil }
        return HabitDateParser.parse(first.logged_at)
    }
    
    public var timeSinceLastSmoke: TimeInterval? {
        guard let lsd = lastSmokeDate else { return nil }
        return max(0, Date().timeIntervalSince(lsd))
    }
    
    public var formattedTimeSinceLastSmoke: String {
        guard let interval = timeSinceLastSmoke else {
            return "Niciun fum azi"
        }
        let mins = Int(interval / 60)
        let hours = mins / 60
        let remMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remMins)m de la ultimul"
        } else if mins > 0 {
            return "\(mins)m de la ultimul"
        } else {
            return "Chiar acum"
        }
    }
    
    public var isCravingWarning: Bool {
        guard let interval = timeSinceLastSmoke else { return false }
        return interval < 45 * 60 // Less than 45 minutes
    }
    
    public var moneySpentTodayLei: Double {
        let costPerCig = 26.50 / 20.0 // Canonical 1.325 Lei/cig
        return Double(smokesTotalToday) * costPerCig
    }
    
    public var moneySavedTodayLei: Double {
        let costPerCig = 26.50 / 20.0
        let avoided = max(0, smokesBaseline - smokesTotalToday)
        return Double(avoided) * costPerCig
    }
    
    private let groupSuiteName = "group.com.intellidream.daily"
    private var isRefreshing = false
    
    private init() {
        loadFromAppGroup()
    }
    
    // MARK: - Monday-Sunday Week Window Calculation
    
    public func getWeekWindow(offset: Int) -> (monday: Date, nextMonday: Date, sunday: Date, days: [Date]) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfToday) // 1=Sun, 2=Mon, ...
        let daysFromMonday = (weekday == 1) ? 6 : (weekday - 2)
        let thisMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfToday) ?? startOfToday
        let targetMonday = calendar.date(byAdding: .day, value: offset * 7, to: thisMonday) ?? thisMonday
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: targetMonday) ?? targetMonday
        let targetSunday = calendar.date(byAdding: .day, value: 6, to: targetMonday) ?? targetMonday
        
        var days: [Date] = []
        for i in 0..<7 {
            if let d = calendar.date(byAdding: .day, value: i, to: targetMonday) {
                days.append(d)
            }
        }
        return (targetMonday, nextMonday, targetSunday, days)
    }
    
    // MARK: - AppGroup Instant Caching (< 1ms Cold Boot)
    
    public func loadFromAppGroup() {
        guard let groupPrefs = UserDefaults(suiteName: groupSuiteName) else { return }
        
        // Goals
        if let wgStr = groupPrefs.string(forKey: "water_goal"), let wg = Int(wgStr), wg > 0 {
            self.waterGoal = wg
        }
        if let sbStr = groupPrefs.string(forKey: "smokes_baseline"), let sb = Int(sbStr), sb > 0 {
            self.smokesBaseline = sb
        } else {
            self.smokesBaseline = 40
        }
        
        // Water Daily Totals & Logs
        self.waterTotalToday = groupPrefs.integer(forKey: "cached_water_total")
        self.waterAmountToday = groupPrefs.integer(forKey: "cached_water_amount")
        self.coffeeAmountToday = groupPrefs.integer(forKey: "cached_coffee_amount")
        if let wData = groupPrefs.data(forKey: "cached_water_logs"),
           let wLogs = try? JSONDecoder().decode([HabitLog].self, from: wData) {
            self.todayWaterLogs = wLogs
            if self.waterAmountToday == 0 && self.coffeeAmountToday == 0 && !wLogs.isEmpty {
                var w = 0.0, c = 0.0
                for l in wLogs {
                    if l.isCoffeeDrink { c += l.value } else { w += l.value }
                }
                self.waterAmountToday = Int(w)
                self.coffeeAmountToday = Int(c)
                self.waterTotalToday = Int(w + c)
            }
        }
        
        // Smokes Daily Totals & Logs
        self.smokesTotalToday = groupPrefs.integer(forKey: "cached_smokes_total")
        self.cigsCountToday = groupPrefs.integer(forKey: "cached_cigs_count")
        self.heatCountToday = groupPrefs.integer(forKey: "cached_heat_count")
        if let sData = groupPrefs.data(forKey: "cached_smokes_logs"),
           let sLogs = try? JSONDecoder().decode([HabitLog].self, from: sData) {
            self.todaySmokesLogs = sLogs
            if self.cigsCountToday == 0 && self.heatCountToday == 0 && !sLogs.isEmpty {
                var cg = 0.0, ht = 0.0
                for l in sLogs {
                    let cnt = max(1.0, l.value)
                    if l.isHeatedSmoke { ht += cnt } else { cg += cnt }
                }
                self.cigsCountToday = Int(cg)
                self.heatCountToday = Int(ht)
                self.smokesTotalToday = Int(cg + ht)
            }
        }
        
        // Week Buckets
        let window = getWeekWindow(offset: 0)
        if let wbData = groupPrefs.data(forKey: "bubbles_week_cache"),
           let wBuckets = try? JSONDecoder().decode([WaterDayBucket].self, from: wbData),
           !wBuckets.isEmpty {
            self.waterWeekBuckets = wBuckets
        } else {
            self.waterWeekBuckets = window.days.map { WaterDayBucket(date: $0) }
        }
        
        if let sbData = groupPrefs.data(forKey: "smokes_week_cache"),
           let sBuckets = try? JSONDecoder().decode([SmokeDayBucket].self, from: sbData),
           !sBuckets.isEmpty {
            self.smokesWeekBuckets = sBuckets
        } else {
            self.smokesWeekBuckets = window.days.map { SmokeDayBucket(date: $0) }
        }
    }
    
    public func saveToAppGroup() {
        guard let groupPrefs = UserDefaults(suiteName: groupSuiteName) else { return }
        
        groupPrefs.set(String(waterGoal), forKey: "water_goal")
        groupPrefs.set(String(smokesBaseline), forKey: "smokes_baseline")
        
        groupPrefs.set(waterTotalToday, forKey: "cached_water_total")
        groupPrefs.set(waterAmountToday, forKey: "cached_water_amount")
        groupPrefs.set(coffeeAmountToday, forKey: "cached_coffee_amount")
        if let wData = try? JSONEncoder().encode(todayWaterLogs) {
            groupPrefs.set(wData, forKey: "cached_water_logs")
        }
        
        groupPrefs.set(smokesTotalToday, forKey: "cached_smokes_total")
        groupPrefs.set(cigsCountToday, forKey: "cached_cigs_count")
        groupPrefs.set(heatCountToday, forKey: "cached_heat_count")
        if let sData = try? JSONEncoder().encode(todaySmokesLogs) {
            groupPrefs.set(sData, forKey: "cached_smokes_logs")
        }
        
        if let wbData = try? JSONEncoder().encode(waterWeekBuckets) {
            groupPrefs.set(wbData, forKey: "bubbles_week_cache")
        }
        if let sbData = try? JSONEncoder().encode(smokesWeekBuckets) {
            groupPrefs.set(sbData, forKey: "smokes_week_cache")
        }
    }
    
    // MARK: - Zero-Latency Optimistic Habit Logging
    
    public func logWater(amount: Int, type: String, dayOffset: Int = 0) {
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
        
        let loggedAt = HabitDateParser.toIsoUtcString(targetDate)
        let isCoffee = type.lowercased().contains("coffee") || type.lowercased().contains("espresso")
        let metadataString = "{\"drink\":\"\(type)\",\"type\":\"\(type)\"}"
        
        let newLog = HabitLog(
            id: UUID(),
            user_id: WatchSessionManager.shared.currentUserId,
            habit_type: "water",
            value: Double(amount),
            unit: "ml",
            logged_at: loggedAt,
            metadata: metadataString
        )
        
        // 1. Instant local state update
        if dayOffset == 0 {
            todayWaterLogs.insert(newLog, at: 0)
            waterTotalToday += amount
            if isCoffee {
                coffeeAmountToday += amount
            } else {
                waterAmountToday += amount
            }
            
            // Update current week's bucket for today
            let cal = Calendar.current
            if let idx = waterWeekBuckets.firstIndex(where: { cal.isDate($0.date, inSameDayAs: targetDate) }) {
                if isCoffee {
                    waterWeekBuckets[idx].coffee += Double(amount)
                } else {
                    waterWeekBuckets[idx].water += Double(amount)
                }
            }
            
            saveToAppGroup()
        }
        
        // 2. Queue in Outbox & trigger network dispatch
        Task {
            await OfflineSyncManager.shared.enqueueInsert(newLog)
            await OfflineSyncManager.shared.processQueue()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    public func logSmoke(type: String, dayOffset: Int = 0) {
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
        
        let loggedAt = HabitDateParser.toIsoUtcString(targetDate)
        let isHeat = type.lowercased().contains("heat") || type.lowercased().contains("vape")
        let canonicalType = isHeat ? "Heated Tobacco" : (type.lowercased().contains("cigarillo") ? "Cigarillo" : (type.lowercased().contains("roll") ? "Rolled" : "Cigarette"))
        let metadataString = "{\"type\":\"\(canonicalType)\",\"drink\":\"\(canonicalType)\",\"brand\":\"\(canonicalType)\",\"smokeType\":\"\(canonicalType)\"}"
        
        let newLog = HabitLog(
            id: UUID(),
            user_id: WatchSessionManager.shared.currentUserId,
            habit_type: "smokes",
            value: 1.0,
            unit: "cigs",
            logged_at: loggedAt,
            metadata: metadataString
        )
        
        // 1. Instant local state update
        if dayOffset == 0 {
            todaySmokesLogs.insert(newLog, at: 0)
            smokesTotalToday += 1
            if isHeat {
                heatCountToday += 1
            } else {
                cigsCountToday += 1
            }
            
            // Update current week's bucket for today
            let cal = Calendar.current
            if let idx = smokesWeekBuckets.firstIndex(where: { cal.isDate($0.date, inSameDayAs: targetDate) }) {
                if isHeat {
                    smokesWeekBuckets[idx].heat += 1.0
                } else {
                    smokesWeekBuckets[idx].cig += 1.0
                }
            }
            
            saveToAppGroup()
        }
        
        // 2. Queue in Outbox & trigger network dispatch
        Task {
            await OfflineSyncManager.shared.enqueueInsert(newLog)
            await OfflineSyncManager.shared.processQueue()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    // MARK: - Direct Goal & Baseline Adjustments
    
    public func updateWaterGoal(_ newGoal: Int) {
        guard newGoal >= 500 && newGoal <= 6000 else { return }
        WKInterfaceDevice.current().play(.click)
        self.waterGoal = newGoal
        saveToAppGroup()
        WidgetCenter.shared.reloadAllTimelines()
        
        Task {
            guard let pClient = WatchSessionManager.shared.supabaseClient,
                  let userId = WatchSessionManager.shared.currentUserId else { return }
            struct WaterPref: Encodable {
                let id: String
                let water_goal: Int
            }
            _ = try? await pClient.from("user_preferences")
                .upsert(WaterPref(id: userId.uuidString, water_goal: newGoal))
                .execute()
        }
    }
    
    public func updateSmokesBaseline(_ newBaseline: Int) {
        guard newBaseline >= 1 && newBaseline <= 100 else { return }
        WKInterfaceDevice.current().play(.click)
        self.smokesBaseline = newBaseline
        saveToAppGroup()
        WidgetCenter.shared.reloadAllTimelines()
        
        Task {
            guard let pClient = WatchSessionManager.shared.supabaseClient,
                  let userId = WatchSessionManager.shared.currentUserId else { return }
            struct SmokesPref: Encodable {
                let id: String
                let smokes_baseline: Int
            }
            _ = try? await pClient.from("user_preferences")
                .upsert(SmokesPref(id: userId.uuidString, smokes_baseline: newBaseline))
                .execute()
        }
    }
    
    public func deleteLog(_ log: HabitLog) {
        WKInterfaceDevice.current().play(.click)
        
        let isWater = log.habit_type == "water"
        let isSmoke = log.habit_type == "smokes" || log.habit_type == "smoke"
        
        if isWater {
            todayWaterLogs.removeAll { $0.id == log.id }
            let val = Int(log.value)
            waterTotalToday = max(0, waterTotalToday - val)
            if log.isCoffeeDrink {
                coffeeAmountToday = max(0, coffeeAmountToday - val)
            } else {
                waterAmountToday = max(0, waterAmountToday - val)
            }
            
            if let logDate = HabitDateParser.parse(log.logged_at) {
                let cal = Calendar.current
                if let idx = waterWeekBuckets.firstIndex(where: { cal.isDate($0.date, inSameDayAs: logDate) }) {
                    if log.isCoffeeDrink {
                        waterWeekBuckets[idx].coffee = max(0.0, waterWeekBuckets[idx].coffee - log.value)
                    } else {
                        waterWeekBuckets[idx].water = max(0.0, waterWeekBuckets[idx].water - log.value)
                    }
                }
            }
        } else if isSmoke {
            todaySmokesLogs.removeAll { $0.id == log.id }
            let count = max(1, Int(log.value))
            smokesTotalToday = max(0, smokesTotalToday - count)
            if log.isHeatedSmoke {
                heatCountToday = max(0, heatCountToday - count)
            } else {
                cigsCountToday = max(0, cigsCountToday - count)
            }
            
            if let logDate = HabitDateParser.parse(log.logged_at) {
                let cal = Calendar.current
                if let idx = smokesWeekBuckets.firstIndex(where: { cal.isDate($0.date, inSameDayAs: logDate) }) {
                    if log.isHeatedSmoke {
                        smokesWeekBuckets[idx].heat = max(0.0, smokesWeekBuckets[idx].heat - Double(count))
                    } else {
                        smokesWeekBuckets[idx].cig = max(0.0, smokesWeekBuckets[idx].cig - Double(count))
                    }
                }
            }
        }
        
        saveToAppGroup()
        
        // 2. Queue DELETE in Outbox & trigger network dispatch
        Task {
            await OfflineSyncManager.shared.enqueueDelete(log)
            await OfflineSyncManager.shared.processQueue()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    // MARK: - Unified Network Fetch (Single-Pass Multi-Day Hydration)
    
    public func fetchFullSync(force: Bool = false) {
        guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
        guard !isRefreshing else { return }
        
        isRefreshing = true
        isSyncing = true
        
        let cal = Calendar.current
        let today = Date()
        let startOfDay = cal.startOfDay(for: today)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            isSyncing = false
            isRefreshing = false
            return
        }
        
        let weekWindow = getWeekWindow(offset: 0)
        let startOfDayStr = HabitDateParser.toIsoUtcString(startOfDay)
        let endOfDayStr = HabitDateParser.toIsoUtcString(endOfDay)
        let weekStartStr = HabitDateParser.toIsoUtcString(weekWindow.monday)
        let weekEndStr = HabitDateParser.toIsoUtcString(weekWindow.nextMonday)
        
        Task {
            do {
                // 1. Preferences Query (Water Goal + Smokes Baseline)
                struct PrefDto: Codable {
                    let water_goal: Int?
                    let smokes_baseline: Int?
                }
                if let prefs: [PrefDto] = try? await pClient.from("user_preferences")
                    .select("water_goal,smokes_baseline")
                    .execute()
                    .value,
                   let first = prefs.first {
                    if let wg = first.water_goal, wg > 0 { self.waterGoal = wg }
                    if let sb = first.smokes_baseline, sb > 0 { self.smokesBaseline = sb }
                }
                
                // 2. Single Query for Today's Logs (All habit types combined!)
                let todayLogs: [HabitLog] = try await pClient.from("habits_logs")
                    .select("id,user_id,habit_type,value,unit,logged_at,metadata")
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startOfDayStr)
                    .lt("logged_at", value: endOfDayStr)
                    .order("logged_at", ascending: false)
                    .execute()
                    .value
                
                var wLogs: [HabitLog] = []
                var sLogs: [HabitLog] = []
                var totalW = 0.0, pureW = 0.0, coffeeW = 0.0
                var totalS = 0.0, cigS = 0.0, heatS = 0.0
                
                for log in todayLogs {
                    if log.habit_type == "water" {
                        wLogs.append(log)
                        totalW += log.value
                        if log.isCoffeeDrink { coffeeW += log.value } else { pureW += log.value }
                    } else if log.habit_type == "smokes" || log.habit_type == "smoke" {
                        sLogs.append(log)
                        let count = max(1.0, log.value)
                        totalS += count
                        if log.isHeatedSmoke { heatS += count } else { cigS += count }
                    }
                }
                
                // 3. Single Query for 7-Day History
                let weekRawLogs: [HabitWeekLogDto] = try await pClient.from("habits_logs")
                    .select("value,metadata,logged_at,habit_type")
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: weekStartStr)
                    .lt("logged_at", value: weekEndStr)
                    .execute()
                    .value
                
                var newWaterBuckets: [WaterDayBucket] = weekWindow.days.map { WaterDayBucket(date: $0) }
                var newSmokesBuckets: [SmokeDayBucket] = weekWindow.days.map { SmokeDayBucket(date: $0) }
                
                for item in weekRawLogs {
                    guard let itemDate = HabitDateParser.parse(item.logged_at) else { continue }
                    if let dayIdx = weekWindow.days.firstIndex(where: { cal.isDate($0, inSameDayAs: itemDate) }) {
                        if item.habit_type == "water" {
                            let isCoffee = item.metadata?.contains("Coffee") ?? false
                            if isCoffee {
                                newWaterBuckets[dayIdx].coffee += item.value.value
                            } else {
                                newWaterBuckets[dayIdx].water += item.value.value
                            }
                        } else if item.habit_type == "smokes" || item.habit_type == "smoke" {
                            let isHeat = (item.metadata?.contains("Heat") ?? false) ||
                                         (item.metadata?.contains("Vape") ?? false) ||
                                         (item.metadata?.contains("iqos") ?? false)
                            let count = max(1.0, item.value.value)
                            if isHeat {
                                newSmokesBuckets[dayIdx].heat += count
                            } else {
                                newSmokesBuckets[dayIdx].cig += count
                            }
                        }
                    }
                }
                
                // Update State on MainActor
                self.todayWaterLogs = wLogs
                self.waterTotalToday = Int(totalW)
                self.waterAmountToday = Int(pureW)
                self.coffeeAmountToday = Int(coffeeW)
                
                self.todaySmokesLogs = sLogs
                self.smokesTotalToday = Int(totalS)
                self.cigsCountToday = Int(cigS)
                self.heatCountToday = Int(heatS)
                
                self.waterWeekBuckets = newWaterBuckets
                self.smokesWeekBuckets = newSmokesBuckets
                
                self.isSyncing = false
                self.isRefreshing = false
                self.lastSyncDate = Date()
                
                self.saveToAppGroup()
                WidgetCenter.shared.reloadAllTimelines()
                
                // Also flush any pending offline items
                await OfflineSyncManager.shared.processQueue()
                
            } catch {
                os_log("Full sync failed: %{public}@", type: .error, error.localizedDescription)
                self.isSyncing = false
                self.isRefreshing = false
            }
        }
    }
}
