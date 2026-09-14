import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Snapshot model for Bubbles Widget
public struct BubblesWidgetSnapshot: Sendable {
    public let todayMl: Double
    public let goalMl: Double
    public let progressPercent: Double
    public let waterMl: Double
    public let coffeeMl: Double
    public let lastLoggedAt: Date?
    
    public init(
        todayMl: Double,
        goalMl: Double,
        progressPercent: Double,
        waterMl: Double,
        coffeeMl: Double,
        lastLoggedAt: Date? = nil
    ) {
        self.todayMl = todayMl
        self.goalMl = goalMl
        self.progressPercent = progressPercent
        self.waterMl = waterMl
        self.coffeeMl = coffeeMl
        self.lastLoggedAt = lastLoggedAt
    }
}

/// Snapshot model for Smokes Widget
public struct SmokesWidgetSnapshot: Sendable {
    public let todayTotal: Int
    public let baseline: Int
    public let cigsCount: Int
    public let heatedCount: Int
    public let lastSmokeDate: Date?
    public let spentTodayLei: Double
    
    public init(
        todayTotal: Int,
        baseline: Int,
        cigsCount: Int,
        heatedCount: Int,
        lastSmokeDate: Date? = nil,
        spentTodayLei: Double = 0.0
    ) {
        self.todayTotal = todayTotal
        self.baseline = baseline
        self.cigsCount = cigsCount
        self.heatedCount = heatedCount
        self.lastSmokeDate = lastSmokeDate
        self.spentTodayLei = spentTodayLei
    }
}

/// Snapshot model for Money / SmartLedger Widget
public struct MoneyWidgetSnapshot: Sendable {
    public let netWorthLei: Double
    public let netWorthEUR: Double
    public let formattedNetWorth: String
    public let formattedNetWorthEUR: String
    public let incomingTotal: Double
    public let outgoingTotal: Double
    public let depositsTotal: Double
    public let cardAmount: Double
    public let cashAmount: Double
    public let topOutgoingAllocations: [(name: String, amount: Double)]
    
    public init(
        netWorthLei: Double,
        netWorthEUR: Double,
        formattedNetWorth: String,
        formattedNetWorthEUR: String,
        incomingTotal: Double,
        outgoingTotal: Double,
        depositsTotal: Double,
        cardAmount: Double,
        cashAmount: Double,
        topOutgoingAllocations: [(name: String, amount: Double)]
    ) {
        self.netWorthLei = netWorthLei
        self.netWorthEUR = netWorthEUR
        self.formattedNetWorth = formattedNetWorth
        self.formattedNetWorthEUR = formattedNetWorthEUR
        self.incomingTotal = incomingTotal
        self.outgoingTotal = outgoingTotal
        self.depositsTotal = depositsTotal
        self.cardAmount = cardAmount
        self.cashAmount = cashAmount
        self.topOutgoingAllocations = topOutgoingAllocations
    }
}

/// Central data coordinator managing 0ms read/write between the Main App and WidgetKit Extension.
public final class WidgetDataCoordinator: @unchecked Sendable {
    public static let shared = WidgetDataCoordinator()
    
    private let groupSuiteName = "group.com.intellidream.daily"
    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
    }
    
    private let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private var todayKey: String {
        isoDateFormatter.string(from: Date())
    }
    
    // MARK: - Bubbles (Hydration)
    
    public func fetchBubblesSnapshot() -> BubblesWidgetSnapshot {
        let key = todayKey
        
        // 1. Goal
        let goalStr = groupDefaults.string(forKey: "water_goal") ?? "2000"
        let goal = Double(goalStr) ?? (groupDefaults.value(forKey: "water_goal") as? Double ?? 2000)
        
        // 2. Today's total
        var totalMl = 0.0
        if let wData = groupDefaults.data(forKey: "habits_water_daily_totals"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: wData) {
            totalMl = dict[key] ?? 0
        }
        
        // 3. Breakdown from local logs
        var waterMl = 0.0
        var coffeeMl = 0.0
        var lastLogged: Date? = nil
        
        if let logsData = groupDefaults.data(forKey: "local_water_logs_\(key)"),
           let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
            lastLogged = logs.first?.loggedAt
            for log in logs {
                let drink = (log.parsedDrink ?? "").lowercased()
                if drink.contains("coffee") {
                    coffeeMl += log.value
                } else {
                    waterMl += log.value
                }
            }
        } else {
            waterMl = totalMl
        }
        
        let progress = goal > 0 ? min(max(totalMl / goal, 0.0), 1.0) : 0.0
        return BubblesWidgetSnapshot(
            todayMl: totalMl,
            goalMl: goal,
            progressPercent: progress,
            waterMl: waterMl,
            coffeeMl: coffeeMl,
            lastLoggedAt: lastLogged
        )
    }
    
    private var cachedUserId: UUID? {
        if let idStr = groupDefaults.string(forKey: "authenticated_user_id") ?? groupDefaults.string(forKey: "current_user_id") {
            return UUID(uuidString: idStr)
        }
        return nil
    }
    
    public func logWater(amountMl: Double, drinkType: String = "Water") {
        let key = todayKey
        let now = Date()
        
        // 1. Update daily totals
        var totals: [String: Double] = [:]
        if let wData = groupDefaults.data(forKey: "habits_water_daily_totals"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: wData) {
            totals = decoded
        }
        totals[key, default: 0] += amountMl
        if let encoded = try? JSONEncoder().encode(totals) {
            groupDefaults.set(encoded, forKey: "habits_water_daily_totals")
        }
        groupDefaults.set(Int(totals[key] ?? 0), forKey: "cached_water_total")
        
        // 2. Append to local logs
        let metaDict = ["drink": drinkType]
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
        
        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: cachedUserId,
            habitType: "water",
            value: amountMl,
            unit: "ml",
            loggedAt: now,
            metadata: metaJson,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        
        var logs: [HabitLogRecord] = []
        if let logsData = groupDefaults.data(forKey: "local_water_logs_\(key)"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
            logs = decoded
        }
        logs.insert(newRecord, at: 0)
        if let encoded = try? JSONEncoder().encode(logs) {
            groupDefaults.set(encoded, forKey: "local_water_logs_\(key)")
        }
        
        // 3. Queue for Supabase background sync
        var queue: [HabitLogRecord] = []
        if let qData = groupDefaults.data(forKey: "offline_habits_queue"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: qData) {
            queue = decoded
        }
        queue.append(newRecord)
        if let encoded = try? JSONEncoder().encode(queue) {
            groupDefaults.set(encoded, forKey: "offline_habits_queue")
        }
        
        // 4. Reload Widget Timelines
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    // MARK: - Smokes (Tobacco & Cessation)
    
    public func fetchSmokesSnapshot() -> SmokesWidgetSnapshot {
        let key = todayKey
        
        // 1. Baseline
        let baselineStr = groupDefaults.string(forKey: "smokes_baseline") ?? "20"
        let baseline = Int(baselineStr) ?? (groupDefaults.value(forKey: "smokes_baseline") as? Int ?? 20)
        
        // 2. Today's total
        var totalSmokes = 0
        if let sData = groupDefaults.data(forKey: "habits_smokes_daily_totals"),
           let dict = try? JSONDecoder().decode([String: Int].self, from: sData) {
            totalSmokes = dict[key] ?? 0
        }
        
        // 3. Cigs vs Heat breakdown & last smoke date
        var cigsCount = 0
        var heatedCount = 0
        var lastSmokeDate: Date? = nil
        
        if let logsData = groupDefaults.data(forKey: "local_smokes_logs_\(key)"),
           let logs = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
            lastSmokeDate = logs.first?.loggedAt
            for log in logs {
                let type = (log.smokeType).lowercased()
                if type.contains("heat") {
                    heatedCount += Int(log.value)
                } else {
                    cigsCount += Int(log.value)
                }
            }
        } else {
            cigsCount = totalSmokes
        }
        
        // Standard pack price ~25 Lei for 20 sticks = 1.25 Lei per smoke
        let spent = Double(totalSmokes) * 1.25
        
        return SmokesWidgetSnapshot(
            todayTotal: totalSmokes,
            baseline: baseline,
            cigsCount: cigsCount,
            heatedCount: heatedCount,
            lastSmokeDate: lastSmokeDate,
            spentTodayLei: spent
        )
    }
    
    public func logSmoke(preset: SmokePreset = .cigarette) {
        let key = todayKey
        let now = Date()
        
        // 1. Update daily totals
        var totals: [String: Int] = [:]
        if let sData = groupDefaults.data(forKey: "habits_smokes_daily_totals"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: sData) {
            totals = decoded
        }
        totals[key, default: 0] += 1
        if let encoded = try? JSONEncoder().encode(totals) {
            groupDefaults.set(encoded, forKey: "habits_smokes_daily_totals")
        }
        groupDefaults.set(totals[key] ?? 0, forKey: "cached_smokes_total")
        
        // 2. Append to local logs
        let metaDict = ["type": preset.rawValue]
        let metaJson = (try? JSONSerialization.data(withJSONObject: metaDict, options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
        
        let newRecord = HabitLogRecord(
            id: UUID(),
            userId: cachedUserId,
            habitType: "smokes",
            value: 1.0,
            unit: "cigs",
            loggedAt: now,
            metadata: metaJson,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        
        var logs: [HabitLogRecord] = []
        if let logsData = groupDefaults.data(forKey: "local_smokes_logs_\(key)"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: logsData) {
            logs = decoded
        }
        logs.insert(newRecord, at: 0)
        if let encoded = try? JSONEncoder().encode(logs) {
            groupDefaults.set(encoded, forKey: "local_smokes_logs_\(key)")
        }
        
        // 3. Queue for Supabase background sync
        var queue: [HabitLogRecord] = []
        if let qData = groupDefaults.data(forKey: "offline_habits_queue"),
           let decoded = try? JSONDecoder().decode([HabitLogRecord].self, from: qData) {
            queue = decoded
        }
        queue.append(newRecord)
        if let encoded = try? JSONEncoder().encode(queue) {
            groupDefaults.set(encoded, forKey: "offline_habits_queue")
        }
        
        // 4. Reload Widget Timelines
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    // MARK: - Money (SmartLedger)
    
    private let ledgerStorageKey = "daily_smart_ledger_raw_text_v1"
    
    public func fetchMoneySnapshot() -> MoneyWidgetSnapshot {
        let rawText = groupDefaults.string(forKey: ledgerStorageKey) ?? SmartLedgerStore.defaultLedgerText
        let ledger = SmartLedgerParser.shared.parse(rawText)
        
        var card = 0.0
        var cash = 0.0
        if let incoming = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }) {
            if let cardItem = incoming.items.first(where: { $0.key.caseInsensitiveCompare("Card") == .orderedSame }) {
                card = cardItem.calculatedAmount
            }
            if let cashItem = incoming.items.first(where: { $0.key.caseInsensitiveCompare("Cash") == .orderedSame }) {
                cash = cashItem.calculatedAmount
            }
        }
        
        var topOutgoing: [(name: String, amount: Double)] = []
        if let outgoing = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Outgoing") == .orderedSame }) {
            topOutgoing = outgoing.items
                .filter { !$0.isPureNote && $0.calculatedAmount > 0 }
                .sorted { $0.calculatedAmount > $1.calculatedAmount }
                .prefix(3)
                .map { (name: $0.displayName, amount: $0.calculatedAmount) }
        }
        
        return MoneyWidgetSnapshot(
            netWorthLei: ledger.netWorth,
            netWorthEUR: ledger.netWorthEUR,
            formattedNetWorth: ledger.formattedNetWorth,
            formattedNetWorthEUR: ledger.formattedNetWorthEUR,
            incomingTotal: ledger.incomingTotal,
            outgoingTotal: ledger.outgoingTotal,
            depositsTotal: ledger.depositTotal,
            cardAmount: card,
            cashAmount: cash,
            topOutgoingAllocations: topOutgoing
        )
    }
    
    public func adjustLedgerAmount(accountName: String, deltaRaw: Double) {
        let rawText = groupDefaults.string(forKey: ledgerStorageKey) ?? SmartLedgerStore.defaultLedgerText
        let ledger = SmartLedgerParser.shared.parse(rawText)
        
        guard let incoming = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }),
              let item = incoming.items.first(where: { $0.key.caseInsensitiveCompare(accountName) == .orderedSame }) else {
            return
        }
        
        let updatedText = SmartLedgerParser.shared.adjustItemAmount(in: rawText, lineIndex: item.lineIndex, deltaRaw: deltaRaw)
        groupDefaults.set(updatedText, forKey: ledgerStorageKey)
        UserDefaults.standard.set(updatedText, forKey: ledgerStorageKey)
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
