import SwiftUI
import WatchKit
import WidgetKit
import Supabase

struct SmokesView: View {
    @ObservedObject private var store = WatchHabitStore.shared
    @State private var dayOffset: Int = 0
    @State private var crownAccumulator: Double = 0.0
    
    // Non-zero offset local data
    @State private var historicalLogs: [HabitLog] = []
    @State private var historicalTotal: Int = 0
    @State private var historicalCig: Int = 0
    @State private var historicalHeat: Int = 0
    @State private var isHistoricalLoading: Bool = false
    
    @State private var selectedLog: HabitLog?
    @State private var showDeleteConfirm: Bool = false
    @State private var showCustomSheet: Bool = false
    @State private var showEditGoalSheet: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    private var isToday: Bool { dayOffset == 0 }
    
    private var displayTotal: Int {
        isToday ? store.smokesTotalToday : historicalTotal
    }
    
    private var displayCig: Int {
        isToday ? store.cigsCountToday : historicalCig
    }
    
    private var displayHeat: Int {
        isToday ? store.heatCountToday : historicalHeat
    }
    
    private var displayLogs: [HabitLog] {
        isToday ? store.todaySmokesLogs : historicalLogs
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 1. Category Header
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 15))
                    Text("Smokes")
                        .font(.system(size: 16, weight: .bold))
                }
                .padding(.top, 2)
                
                // 2. Temporal Navigation Header
                TemporalNavHeader(
                    title: formattedDateTitle,
                    canGoForward: dayOffset < 0,
                    accentColor: .red,
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
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 10)
                    
                    let remaining = max(0, store.smokesBaseline - displayTotal)
                    let progress = CGFloat(remaining) / CGFloat(max(store.smokesBaseline, 1))
                    let ringColor = getSmokesColor(total: displayTotal, baseline: store.smokesBaseline)
                    
                    Circle()
                        .trim(from: 0.0, to: progress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: progress)
                    
                    VStack(spacing: 1) {
                        Text("\(displayTotal)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(displayTotal > store.smokesBaseline ? .red : .primary)
                            .contentTransition(.numericText())
                        
                        Button(action: {
                            WKInterfaceDevice.current().play(.click)
                            showEditGoalSheet = true
                        }) {
                            HStack(spacing: 2) {
                                Text("/ \(store.smokesBaseline)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Image(systemName: "pencil")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 122, height: 122)
                .padding(.vertical, 4)
                
                // 3.5 Craving & Pacing Timer (Live on Wrist)
                if isToday {
                    CravingPacingBadge()
                        .padding(.vertical, 2)
                }
                
                // 4. Breakdown Summary Ticker
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                        Text("\(displayCig) cig")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    Text("·")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .bold))
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 11))
                        Text("\(displayHeat) heat")
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
                        icon: "flame.fill",
                        title: "+1 Cigarette",
                        color: .red
                    ) {
                        logSmoke(type: "Cigarette")
                    }
                    
                    QuickAddActionChip(
                        icon: "bolt.fill",
                        title: "+1 Heated Tobacco",
                        color: .blue
                    ) {
                        logSmoke(type: "Heated Tobacco")
                    }
                    
                    QuickAddActionChip(
                        icon: "slider.horizontal.3",
                        title: "+ Custom / Retroactive",
                        color: .orange
                    ) {
                        WKInterfaceDevice.current().play(.click)
                        showCustomSheet = true
                    }
                }
                .padding(.top, 4)
                
                // 6. 7-Day Trend Section (Integrated Vertically)
                if isToday {
                    Smokes7DaysInlineSection()
                        .padding(.top, 4)
                }
                
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
                                Image(systemName: log.isHeatedSmoke ? "bolt.fill" : "flame.fill")
                                    .foregroundColor(log.isHeatedSmoke ? .blue : .red)
                                    .font(.system(size: 13))
                                    .frame(width: 18)
                                
                                Text(log.displaySmokeName)
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
            Text("Delete \(log.displaySmokeName) entry?")
        }
        .sheet(isPresented: $showCustomSheet) {
            WatchCustomSmokeSheet()
        }
        .sheet(isPresented: $showEditGoalSheet) {
            WatchEditGoalSheet(isWater: false)
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
    
    private func logSmoke(type: String) {
        if isToday {
            store.logSmoke(type: type, dayOffset: 0)
        } else {
            store.logSmoke(type: type, dayOffset: dayOffset)
            historicalTotal += 1
            let isHeat = type.lowercased().contains("heat") || type.lowercased().contains("vape")
            if isHeat {
                historicalHeat += 1
            } else {
                historicalCig += 1
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
                habit_type: "smokes",
                value: 1.0,
                unit: "items",
                logged_at: HabitDateParser.toIsoUtcString(loggedDate),
                metadata: "{\"brand\":\"\(type)\",\"type\":\"\(type)\"}"
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
            let count = max(1, Int(log.value))
            historicalTotal = max(0, historicalTotal - count)
            if log.isHeatedSmoke {
                historicalHeat = max(0, historicalHeat - count)
            } else {
                historicalCig = max(0, historicalCig - count)
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
                    .in("habit_type", values: ["smokes", "smoke"])
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startStr)
                    .lt("logged_at", value: endStr)
                    .order("logged_at", ascending: false)
                    .execute()
                    .value
                
                var tot = 0.0, cg = 0.0, ht = 0.0
                for l in logs {
                    let cnt = max(1.0, l.value)
                    tot += cnt
                    if l.isHeatedSmoke { ht += cnt } else { cg += cnt }
                }
                
                DispatchQueue.main.async {
                    guard self.dayOffset == offset else { return }
                    self.historicalLogs = logs
                    self.historicalTotal = Int(tot)
                    self.historicalCig = Int(cg)
                    self.historicalHeat = Int(ht)
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
