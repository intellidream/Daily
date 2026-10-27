import SwiftUI
import WatchKit
import Charts
import Supabase

private struct HabitWeekLogItem: Decodable {
    let value: FlexibleDouble
    let metadata: HabitLogMetadataHelper?
    let logged_at: String
}

struct Bubbles7DaysView: View {
    @ObservedObject private var store = WatchHabitStore.shared
    @State private var weekOffset: Int = 0
    @State private var crownAccumulator: Double = 0.0
    @State private var historicalBuckets: [WaterDayBucket] = []
    @State private var isHistoricalSyncing: Bool = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    private var isCurrentWeek: Bool { weekOffset == 0 }
    
    private var activeBuckets: [WaterDayBucket] {
        isCurrentWeek ? store.waterWeekBuckets : historicalBuckets
    }
    
    private var formattedWeekTitle: String {
        if weekOffset == 0 {
            return "This Week"
        } else if weekOffset == -1 {
            return "Last Week"
        } else {
            let window = store.getWeekWindow(offset: weekOffset)
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return "\(formatter.string(from: window.monday)) - \(formatter.string(from: window.sunday))"
        }
    }
    
    private var weeklyAverage: Int {
        guard !activeBuckets.isEmpty else { return 0 }
        let sum = activeBuckets.reduce(0.0) { $0 + $1.total }
        if weekOffset == 0 {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date()) // 1=Sun, 2=Mon, ...
            let daysElapsed = (weekday == 1) ? 7 : max(1, weekday - 1)
            return Int(sum / Double(daysElapsed))
        } else {
            return Int(sum / Double(activeBuckets.count))
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header Title
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 15))
                    Text("7 Days")
                        .font(.system(size: 16, weight: .bold))
                }
                .padding(.top, 2)
                
                // Temporal Navigation (Weeks: Monday - Sunday)
                TemporalNavHeader(
                    title: formattedWeekTitle,
                    canGoForward: weekOffset < 0,
                    accentColor: .cyan,
                    onPrevious: {
                        navigateToWeek(by: -1)
                    },
                    onNext: {
                        if weekOffset < 0 {
                            navigateToWeek(by: 1)
                        }
                    }
                )
                
                // 7 Days Chart (Mon to Sun)
                if activeBuckets.isEmpty {
                    VStack {
                        ProgressView()
                            .padding(.vertical, 30)
                    }
                } else {
                    Chart {
                        ForEach(activeBuckets) { item in
                            // Water Bar
                            BarMark(
                                x: .value("Day", item.date, unit: .day),
                                y: .value("Water", item.water)
                            )
                            .foregroundStyle(Color.cyan)
                            .cornerRadius(3)
                            
                            // Coffee Bar (Stacked on top)
                            if item.coffee > 0 {
                                BarMark(
                                    x: .value("Day", item.date, unit: .day),
                                    y: .value("Coffee", item.coffee)
                                )
                                .foregroundStyle(Color.orange)
                                .cornerRadius(3)
                            }
                        }
                        
                        // Daily Goal Target Line
                        RuleMark(y: .value("Goal", store.waterGoal))
                            .foregroundStyle(Color.blue.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                    .frame(height: 100)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            if let intVal = value.as(Int.self), intVal == store.waterGoal || intVal == 0 {
                                AxisValueLabel()
                                    .font(.system(size: 8))
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    // Summary row: Average & Goal comparison
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill")
                                .foregroundColor(.cyan)
                                .font(.system(size: 10))
                            Text("Avg: \(weeklyAverage) ml/d")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text("Goal: \(store.waterGoal) ml")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
                
                // Sync indicator
                SyncFooterView(isSyncing: store.isSyncing || isHistoricalSyncing)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .focusable()
        .digitalCrownRotation(
            $crownAccumulator,
            from: -52.0,
            through: 0.0,
            by: 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownAccumulator) { oldVal, newVal in
            let step = Int(newVal)
            if step != weekOffset && step <= 0 {
                weekOffset = step
                if step != 0 {
                    loadHistoricalWeek(offset: step)
                }
            }
        }
        .onAppear {
            if isCurrentWeek {
                store.fetchFullSync()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && isCurrentWeek {
                store.fetchFullSync()
            }
        }
    }
    
    // MARK: - Navigation & Historical Fetch
    
    private func navigateToWeek(by delta: Int) {
        let newOffset = weekOffset + delta
        if newOffset > 0 { return }
        weekOffset = newOffset
        crownAccumulator = Double(newOffset)
        if newOffset != 0 {
            loadHistoricalWeek(offset: newOffset)
        }
    }
    
    private func loadHistoricalWeek(offset: Int) {
        let window = store.getWeekWindow(offset: offset)
        let key = "bubbles_week_cache_\(offset)"
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let data = groupPrefs.data(forKey: key),
           let cached = try? JSONDecoder().decode([WaterDayBucket].self, from: data),
           !cached.isEmpty {
            self.historicalBuckets = cached
        } else {
            self.historicalBuckets = window.days.map { WaterDayBucket(date: $0) }
        }
        fetchHistoricalWeekData(for: offset)
    }
    
    private func fetchHistoricalWeekData(for offset: Int) {
        guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
        
        isHistoricalSyncing = true
        let window = store.getWeekWindow(offset: offset)
        let startStr = HabitDateParser.toIsoUtcString(window.monday)
        let endStr = HabitDateParser.toIsoUtcString(window.nextMonday)
        
        Task {
            do {
                var initialBuckets: [WaterDayBucket] = window.days.map { WaterDayBucket(date: $0) }
                
                let logs: [HabitWeekLogItem] = try await pClient
                    .from("habits_logs")
                    .select("value,metadata,logged_at")
                    .eq("habit_type", value: "water")
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startStr)
                    .lt("logged_at", value: endStr)
                    .execute()
                    .value
                
                let calendar = Calendar.current
                for log in logs {
                    guard let logDate = HabitDateParser.parse(log.logged_at) else { continue }
                    
                    if let dayIndex = window.days.firstIndex(where: { calendar.isDate($0, inSameDayAs: logDate) }) {
                        let isCoffee = log.metadata?.contains("Coffee") ?? false
                        if isCoffee {
                            initialBuckets[dayIndex].coffee += log.value.value
                        } else {
                            initialBuckets[dayIndex].water += log.value.value
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    guard self.weekOffset == offset else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.historicalBuckets = initialBuckets
                    }
                    self.isHistoricalSyncing = false
                    
                    if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
                       let data = try? JSONEncoder().encode(initialBuckets) {
                        groupPrefs.set(data, forKey: "bubbles_week_cache_\(offset)")
                    }
                    WKInterfaceDevice.current().play(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.weekOffset == offset else { return }
                    self.isHistoricalSyncing = false
                }
            }
        }
    }
}
