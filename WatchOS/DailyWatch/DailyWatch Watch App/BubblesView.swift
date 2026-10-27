import SwiftUI
import WatchKit
import WidgetKit
import Supabase

struct BubblesView: View {
    @ObservedObject private var store = WatchHabitStore.shared
    @State private var dayOffset: Int = 0
    @State private var crownAccumulator: Double = 0.0
    
    // Non-zero offset local data
    @State private var historicalLogs: [HabitLog] = []
    @State private var historicalTotal: Int = 0
    @State private var historicalWater: Int = 0
    @State private var historicalCoffee: Int = 0
    @State private var isHistoricalLoading: Bool = false
    
    @State private var selectedLog: HabitLog?
    @State private var showDeleteConfirm: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    private var isToday: Bool { dayOffset == 0 }
    
    private var displayTotal: Int {
        isToday ? store.waterTotalToday : historicalTotal
    }
    
    private var displayWater: Int {
        isToday ? store.waterAmountToday : historicalWater
    }
    
    private var displayCoffee: Int {
        isToday ? store.coffeeAmountToday : historicalCoffee
    }
    
    private var displayLogs: [HabitLog] {
        isToday ? store.todayWaterLogs : historicalLogs
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 1. Category Header
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 15))
                    Text("Bubbles")
                        .font(.system(size: 16, weight: .bold))
                }
                .padding(.top, 2)
                
                // 2. Temporal Navigation Header
                TemporalNavHeader(
                    title: formattedDateTitle,
                    canGoForward: dayOffset < 0,
                    accentColor: .cyan,
                    onPrevious: {
                        navigateToDay(offset: dayOffset - 1)
                    },
                    onNext: {
                        if dayOffset < 0 {
                            navigateToDay(offset: dayOffset + 1)
                        }
                    }
                )
                
                // 3. Centered 122pt Hero Progress Ring
                ZStack {
                    let totalG = CGFloat(max(store.waterGoal, 1))
                    let wProg = CGFloat(displayWater) / totalG
                    let cProg = CGFloat(displayCoffee) / totalG
                    
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 10)
                    
                    Circle()
                        .trim(from: 0.0, to: min(wProg, 1.0))
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: wProg)
                        
                    Circle()
                        .trim(from: min(wProg, 1.0), to: min(wProg + cProg, 1.0))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: cProg)
                    
                    VStack(spacing: 1) {
                        Text("\(displayTotal)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .contentTransition(.numericText())
                        
                        Text("/ \(store.waterGoal) ml")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 122, height: 122)
                .padding(.vertical, 4)
                
                // 4. Breakdown Summary Ticker
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .foregroundColor(.cyan)
                            .font(.system(size: 11))
                        Text("\(displayWater) ml")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    Text("·")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .bold))
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("\(displayCoffee) ml")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                
                // 5. Full-Width Ergonomic Touch Chips (Apple HIG 44pt+)
                VStack(spacing: 7) {
                    QuickAddActionChip(
                        icon: "drop.fill",
                        title: "+300 ml Water",
                        color: .cyan
                    ) {
                        logWater(amount: 300, type: "Large Water")
                    }
                    
                    QuickAddActionChip(
                        icon: "drop",
                        title: "+150 ml Water",
                        color: .cyan
                    ) {
                        logWater(amount: 150, type: "Small Water")
                    }
                    
                    QuickAddActionChip(
                        icon: "cup.and.saucer.fill",
                        title: "+100 ml Coffee",
                        color: .orange
                    ) {
                        logWater(amount: 100, type: "Coffee")
                    }
                }
                .padding(.top, 4)
                
                // 6. Logs Section
                if !displayLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isToday ? "TODAY'S LOGS" : "LOGS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                            .padding(.horizontal, 2)
                        
                        ForEach(displayLogs) { log in
                            HStack {
                                Image(systemName: log.isCoffeeDrink ? "cup.and.saucer.fill" : "drop.fill")
                                    .foregroundColor(log.isCoffeeDrink ? .orange : .cyan)
                                    .font(.system(size: 13))
                                    .frame(width: 18)
                                
                                Text("\(Int(log.value)) \(log.unit) \(log.displayDrinkName)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                
                                Spacer()
                                
                                Text(HabitDateParser.formatShortTime(from: log.logged_at))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.10))
                            .cornerRadius(10)
                            .onTapGesture {
                                WKInterfaceDevice.current().play(.click)
                                selectedLog = log
                                showDeleteConfirm = true
                            }
                        }
                    }
                }
                
                // 7. Sync Footer
                SyncFooterView(isSyncing: store.isSyncing || isHistoricalLoading)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .focusable()
        .digitalCrownRotation(
            $crownAccumulator,
            from: -100.0,
            through: 0.0,
            by: 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownAccumulator) { oldVal, newVal in
            let step = Int(newVal)
            if step != dayOffset && step <= 0 {
                navigateToDay(offset: step)
            }
        }
        .alert("Delete Log?", isPresented: $showDeleteConfirm, presenting: selectedLog) { log in
            Button("Delete", role: .destructive) {
                deleteLog(log)
            }
            Button("Cancel", role: .cancel) {}
        } message: { log in
            Text("Delete \(Int(log.value)) \(log.unit) \(log.displayDrinkName)?")
        }
        .onAppear {
            if isToday {
                store.fetchFullSync()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && isToday {
                store.fetchFullSync()
            }
        }
    }
    
    // MARK: - Actions
    
    private func navigateToDay(offset: Int) {
        guard offset <= 0 else { return }
        dayOffset = offset
        crownAccumulator = Double(offset)
        if offset != 0 {
            fetchHistoricalData(offset: offset)
        }
    }
    
    private func logWater(amount: Int, type: String) {
        if isToday {
            store.logWater(amount: amount, type: type, dayOffset: 0)
        } else {
            store.logWater(amount: amount, type: type, dayOffset: dayOffset)
            // Immediately reflect in historical view
            historicalTotal += amount
            if type.lowercased().contains("coffee") {
                historicalCoffee += amount
            } else {
                historicalWater += amount
            }
            let now = Date()
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: dayOffset, to: now) ?? now)
            let timeComps = cal.dateComponents([.hour, .minute, .second], from: now)
            comps.hour = timeComps.hour
            comps.minute = timeComps.minute
            comps.second = timeComps.second
            let loggedDate = cal.date(from: comps) ?? now
            let newLog = HabitLog(
                id: UUID(),
                user_id: WatchSessionManager.shared.currentUserId,
                habit_type: "water",
                value: Double(amount),
                unit: "ml",
                logged_at: HabitDateParser.toIsoUtcString(loggedDate),
                metadata: "{\"drink\":\"\(type)\"}"
            )
            historicalLogs.insert(newLog, at: 0)
        }
    }
    
    private func deleteLog(_ log: HabitLog) {
        if isToday {
            store.deleteLog(log)
        } else {
            store.deleteLog(log)
            historicalLogs.removeAll { $0.id == log.id }
            let val = Int(log.value)
            historicalTotal = max(0, historicalTotal - val)
            if log.isCoffeeDrink {
                historicalCoffee = max(0, historicalCoffee - val)
            } else {
                historicalWater = max(0, historicalWater - val)
            }
        }
    }
    
    private func fetchHistoricalData(offset: Int) {
        guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
        isHistoricalLoading = true
        
        let cal = Calendar.current
        let targetDate = cal.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let startOfDay = cal.startOfDay(for: targetDate)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            isHistoricalLoading = false
            return
        }
        
        let startStr = HabitDateParser.toIsoUtcString(startOfDay)
        let endStr = HabitDateParser.toIsoUtcString(endOfDay)
        
        Task {
            do {
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
                
                var tot = 0.0, w = 0.0, c = 0.0
                for l in logs {
                    tot += l.value
                    if l.isCoffeeDrink { c += l.value } else { w += l.value }
                }
                
                DispatchQueue.main.async {
                    guard self.dayOffset == offset else { return }
                    self.historicalLogs = logs
                    self.historicalTotal = Int(tot)
                    self.historicalWater = Int(w)
                    self.historicalCoffee = Int(c)
                    self.isHistoricalLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.dayOffset == offset else { return }
                    self.isHistoricalLoading = false
                }
            }
        }
    }
}

// MARK: - Ergonomic Full-Width Touch Chip (44pt+ Apple HIG)

struct QuickAddActionChip: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 22)
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.white.opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
