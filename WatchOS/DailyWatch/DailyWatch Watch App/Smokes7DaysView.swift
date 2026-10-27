import SwiftUI
import WatchKit
import Charts
import Supabase

private struct HabitWeekLogItem: Decodable {
    let value: FlexibleDouble
    let metadata: HabitLogMetadataHelper?
    let logged_at: String
}

struct Smokes7DaysView: View {
    @ObservedObject private var store = WatchHabitStore.shared
    @State private var weekOffset: Int = 0
    @State private var crownAccumulator: Double = 0.0
    @State private var historicalBuckets: [SmokeDayBucket] = []
    @State private var isHistoricalSyncing: Bool = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    private var isCurrentWeek: Bool { weekOffset == 0 }
    
    private var activeBuckets: [SmokeDayBucket] {
        isCurrentWeek ? store.smokesWeekBuckets : historicalBuckets
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
    
    private var weeklyAverage: Double {
        guard !activeBuckets.isEmpty else { return 0 }
        let sum = activeBuckets.reduce(0.0) { $0 + $1.total }
        if weekOffset == 0 {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date())
            let daysElapsed = (weekday == 1) ? 7 : max(1, weekday - 1)
            return sum / Double(daysElapsed)
        } else {
            return sum / Double(activeBuckets.count)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header Title
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 15))
                    Text("7 Days")
                        .font(.system(size: 16, weight: .bold))
                }
                .padding(.top, 2)
                
                // Temporal Navigation (Weeks: Monday - Sunday)
                TemporalNavHeader(
                    title: formattedWeekTitle,
                    canGoForward: weekOffset < 0,
                    accentColor: .red,
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
                            // Cigarette Bar
                            BarMark(
                                x: .value("Day", item.date, unit: .day),
                                y: .value("Cig", item.cig)
                            )
                            .foregroundStyle(Color.red)
                            .cornerRadius(3)
                            
                            // Heated Tobacco Bar (Stacked on top)
                            if item.heat > 0 {
                                BarMark(
                                    x: .value("Day", item.date, unit: .day),
                                    y: .value("Heat", item.heat)
                                )
                                .foregroundStyle(Color.blue)
                                .cornerRadius(3)
                            }
                        }
                        
                        // Baseline Reference Line
                        RuleMark(y: .value("Baseline", store.smokesBaseline))
                            .foregroundStyle(Color.orange.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                    .frame(height: 100)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            if let intVal = value.as(Int.self), intVal == store.smokesBaseline || intVal == 0 {
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
                    
                    // Summary row: Average & Baseline comparison
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 10))
                            Text(String(format: "Avg: %.1f/d", weeklyAverage))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text("Base: \(store.smokesBaseline)")
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
        let key = "smokes_week_cache_\(offset)"
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let data = groupPrefs.data(forKey: key),
           let cached = try? JSONDecoder().decode([SmokeDayBucket].self, from: data),
           !cached.isEmpty {
            self.historicalBuckets = cached
        } else {
            self.historicalBuckets = window.days.map { SmokeDayBucket(date: $0) }
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
                var initialBuckets: [SmokeDayBucket] = window.days.map { SmokeDayBucket(date: $0) }
                
                let logs: [HabitWeekLogItem] = try await pClient
                    .from("habits_logs")
                    .select("value,metadata,logged_at")
                    .in("habit_type", values: ["smokes", "smoke"])
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startStr)
                    .lt("logged_at", value: endStr)
                    .execute()
                    .value
                
                let calendar = Calendar.current
                for log in logs {
                    guard let logDate = HabitDateParser.parse(log.logged_at) else { continue }
                    
                    if let dayIndex = window.days.firstIndex(where: { calendar.isDate($0, inSameDayAs: logDate) }) {
                        let isHeat = (log.metadata?.contains("Heat") ?? false) ||
                                     (log.metadata?.contains("Vape") ?? false) ||
                                     (log.metadata?.contains("iqos") ?? false)
                        let count = max(1.0, log.value.value)
                        if isHeat {
                            initialBuckets[dayIndex].heat += count
                        } else {
                            initialBuckets[dayIndex].cig += count
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
                        groupPrefs.set(data, forKey: "smokes_week_cache_\(offset)")
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
