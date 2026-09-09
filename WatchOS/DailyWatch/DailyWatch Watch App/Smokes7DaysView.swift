import SwiftUI
import WatchKit
import Charts
import Supabase

struct SmokeDayBucket: Identifiable, Codable {
    var id: UUID = UUID()
    let date: Date
    let dayLabel: String
    var cig: Double
    var heat: Double
    var total: Double { cig + heat }
}

private struct HabitWeekLogItem: Decodable {
    let value: FlexibleDouble
    let metadata: HabitLogMetadataHelper?
    let logged_at: String
}

struct Smokes7DaysView: View {
    @State private var weekOffset: Int = 0
    @State private var dailyGoal: Int = 20
    @State private var isSyncing: Bool = false
    @State private var buckets: [SmokeDayBucket] = []
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let cachedGoalStr = groupPrefs.string(forKey: "smokes_baseline"),
           let cachedGoal = Int(cachedGoalStr) {
            _dailyGoal = State(initialValue: cachedGoal)
        }
    }
    
    // Calculates Monday-to-Sunday window
    private func getWeekWindow(offset: Int) -> (monday: Date, nextMonday: Date, sunday: Date, days: [Date]) {
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
    
    private var formattedWeekTitle: String {
        if weekOffset == 0 {
            return "This Week"
        } else if weekOffset == -1 {
            return "Last Week"
        } else {
            let window = getWeekWindow(offset: weekOffset)
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return "\(formatter.string(from: window.monday)) - \(formatter.string(from: window.sunday))"
        }
    }
    
    private var weeklyAverage: Double {
        guard !buckets.isEmpty else { return 0 }
        let sum = buckets.reduce(0.0) { $0 + $1.total }
        if weekOffset == 0 {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date())
            let daysElapsed = (weekday == 1) ? 7 : max(1, weekday - 1)
            return sum / Double(daysElapsed)
        } else {
            return sum / Double(buckets.count)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header Title - button icon (flame.fill) & color (.red)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 15))
                    Text("7 Days")
                        .font(.system(size: 17, weight: .bold))
                }
                .padding(.top, 2)
                
                // Temporal Navigation (Weeks: Monday - Sunday)
                TemporalNavHeader(
                    title: formattedWeekTitle,
                    canGoForward: weekOffset < 0,
                    accentColor: .red,
                    onPrevious: {
                        navigateWeek(by: -1)
                    },
                    onNext: {
                        if weekOffset < 0 {
                            navigateWeek(by: 1)
                        }
                    }
                )
                
                // 7 Days Chart (Mon to Sun)
                if buckets.isEmpty {
                    VStack {
                        ProgressView()
                            .padding(.vertical, 30)
                    }
                } else {
                    Chart {
                        ForEach(buckets) { item in
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
                        RuleMark(y: .value("Baseline", dailyGoal))
                            .foregroundStyle(Color.orange.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                    .frame(height: 95)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            if let intVal = value.as(Int.self), intVal == dailyGoal || intVal == 0 {
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
                    
                    // Summary row: Average & Baseline comparison with button icon & color
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
                        Text("Base: \(dailyGoal)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
                
                // Sync indicator
                SyncFooterView(isSyncing: isSyncing)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .onAppear {
            applyWeekSkeletonOrCache(for: weekOffset)
            fetchWeekData(for: weekOffset)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                fetchWeekData(for: weekOffset)
            }
        }
    }
    
    // MARK: - Navigation & Local Cache
    
    private func navigateWeek(by delta: Int) {
        let newOffset = weekOffset + delta
        if newOffset > 0 { return }
        weekOffset = newOffset
        applyWeekSkeletonOrCache(for: newOffset)
        fetchWeekData(for: newOffset)
    }
    
    private func applyWeekSkeletonOrCache(for offset: Int) {
        let window = getWeekWindow(offset: offset)
        let key = (offset == 0) ? "smokes_week_cache" : "smokes_week_cache_\(offset)"
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let data = groupPrefs.data(forKey: key),
           let cached = try? JSONDecoder().decode([SmokeDayBucket].self, from: data),
           !cached.isEmpty {
            self.buckets = cached
        } else {
            self.buckets = window.days.map { SmokeDayBucket(date: $0, dayLabel: "", cig: 0, heat: 0) }
        }
    }
    
    private func saveCache(for offset: Int, buckets: [SmokeDayBucket]) {
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let data = try? JSONEncoder().encode(buckets) {
            let key = (offset == 0) ? "smokes_week_cache" : "smokes_week_cache_\(offset)"
            groupPrefs.set(data, forKey: key)
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchWeekData(for offset: Int) {
        guard let pClient = WatchSessionManager.shared.supabaseClient else { return }
        
        isSyncing = true
        let window = getWeekWindow(offset: offset)
        
        let isoUtcFormatter = ISO8601DateFormatter()
        isoUtcFormatter.formatOptions = [.withInternetDateTime]
        isoUtcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let startStr = isoUtcFormatter.string(from: window.monday)
        let endStr = isoUtcFormatter.string(from: window.nextMonday)
        
        Task {
            do {
                var initialBuckets: [SmokeDayBucket] = window.days.map {
                    SmokeDayBucket(date: $0, dayLabel: "", cig: 0, heat: 0)
                }
                
                let logs: [HabitWeekLogItem] = try await pClient
                    .from("habits_logs")
                    .select("value,metadata,logged_at")
                    .eq("habit_type", value: "smokes")
                    .eq("is_deleted", value: false)
                    .gte("logged_at", value: startStr)
                    .lt("logged_at", value: endStr)
                    .execute()
                    .value
                
                let calendar = Calendar.current
                for log in logs {
                    guard let logDate = HabitDateParser.parse(log.logged_at) else { continue }
                    
                    if let dayIndex = window.days.firstIndex(where: { calendar.isDate($0, inSameDayAs: logDate) }) {
                        let isHeat = (log.metadata?.contains("Heat") ?? false) || (log.metadata?.contains("Vape") ?? false)
                        if isHeat {
                            initialBuckets[dayIndex].heat += log.value.value
                        } else {
                            initialBuckets[dayIndex].cig += log.value.value
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    guard self.weekOffset == offset else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.buckets = initialBuckets
                    }
                    self.isSyncing = false
                    self.saveCache(for: offset, buckets: initialBuckets)
                    WKInterfaceDevice.current().play(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.weekOffset == offset else { return }
                    self.isSyncing = false
                }
            }
        }
    }
}
