import SwiftUI
import WatchKit
import Charts
import Supabase

struct WaterDayBucket: Identifiable, Codable {
    var id: UUID = UUID()
    let date: Date
    let dayLabel: String
    var water: Double
    var coffee: Double
    var total: Double { water + coffee }
}

private struct HabitWeekLogItem: Decodable {
    let value: FlexibleDouble
    let metadata: HabitLogMetadataHelper?
    let logged_at: String
}

struct Bubbles7DaysView: View {
    @State private var weekOffset: Int = 0
    @State private var dailyGoal: Int = 2000
    @State private var isSyncing: Bool = false
    @State private var buckets: [WaterDayBucket] = []
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let cachedGoalStr = groupPrefs.string(forKey: "water_goal"),
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
    
    private var weeklyAverage: Int {
        guard !buckets.isEmpty else { return 0 }
        let sum = buckets.reduce(0.0) { $0 + $1.total }
        if weekOffset == 0 {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date()) // 1=Sun, 2=Mon, ...
            let daysElapsed = (weekday == 1) ? 7 : max(1, weekday - 1)
            return Int(sum / Double(daysElapsed))
        } else {
            return Int(sum / Double(buckets.count))
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header Title - button icon (drop.fill) & color (.cyan)
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 15))
                    Text("7 Days")
                        .font(.system(size: 17, weight: .bold))
                }
                .padding(.top, 2)
                
                // Temporal Navigation (Weeks: Monday - Sunday)
                TemporalNavHeader(
                    title: formattedWeekTitle,
                    canGoForward: weekOffset < 0,
                    accentColor: .cyan,
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
                        RuleMark(y: .value("Goal", dailyGoal))
                            .foregroundStyle(Color.blue.opacity(0.6))
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
                    
                    // Summary row: Average & Goal comparison with button icons & colors
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
                        Text("Goal: \(dailyGoal) ml")
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
        let key = (offset == 0) ? "bubbles_week_cache" : "bubbles_week_cache_\(offset)"
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let data = groupPrefs.data(forKey: key),
           let cached = try? JSONDecoder().decode([WaterDayBucket].self, from: data),
           !cached.isEmpty {
            self.buckets = cached
        } else {
            self.buckets = window.days.map { WaterDayBucket(date: $0, dayLabel: "", water: 0, coffee: 0) }
        }
    }
    
    private func saveCache(for offset: Int, buckets: [WaterDayBucket]) {
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily"),
           let data = try? JSONEncoder().encode(buckets) {
            let key = (offset == 0) ? "bubbles_week_cache" : "bubbles_week_cache_\(offset)"
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
                var initialBuckets: [WaterDayBucket] = window.days.map {
                    WaterDayBucket(date: $0, dayLabel: "", water: 0, coffee: 0)
                }
                
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
