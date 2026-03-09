//
//  DailyWatchWidgetExtension.swift
//  DailyWatchWidgetExtension
//

import WidgetKit
import SwiftUI
import AppIntents

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), waterTotal: 850, smokesTotal: 3, waterGoal: 2000, smokesBaseline: 20, isLoggedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), waterTotal: 850, smokesTotal: 3, waterGoal: 2000, smokesBaseline: 20, isLoggedIn: true)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task {
            let baseEntry = await fetchTodayStats()
            let currentDate = Date()
            var entries: [SimpleEntry] = []
        
        // Generate an entry every 5 minutes for the next 30 minutes to alternate views without network calls
        for minuteOffset in stride(from: 0, to: 35, by: 5) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate)!
            entries.append(SimpleEntry(
                date: entryDate,
                waterTotal: baseEntry.waterTotal,
                smokesTotal: baseEntry.smokesTotal,
                waterGoal: baseEntry.waterGoal,
                smokesBaseline: baseEntry.smokesBaseline,
                isLoggedIn: baseEntry.isLoggedIn
            ))
        }
        
        // The policy determines when the OS provides next network sync cycle
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
        }
    }
    
    private func fetchTodayStats() async -> SimpleEntry {
        let date = Date()
        let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily")
        
        let waterGoalStr = groupPrefs?.string(forKey: "water_goal") ?? "2000"
        let waterGoal = Int(waterGoalStr) ?? 2000
        
        let smokesBaselineStr = groupPrefs?.string(forKey: "smokes_baseline") ?? "20"
        let smokesBaseline = Int(smokesBaselineStr) ?? 20
        
        guard let token = groupPrefs?.string(forKey: "supabase_access_token") else {
            return SimpleEntry(date: date, waterTotal: 0, smokesTotal: 0, waterGoal: waterGoal, smokesBaseline: smokesBaseline, isLoggedIn: false)
        }
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: date)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startString = formatter.string(from: todayStart)
        let endString = formatter.string(from: todayEnd)
        
        guard var components = URLComponents(string: "https://akkfouifxztnfwwiclwg.supabase.co/rest/v1/habits_logs") else {
            return SimpleEntry(date: date, waterTotal: 0, smokesTotal: 0, waterGoal: waterGoal, smokesBaseline: smokesBaseline, isLoggedIn: true)
        }
        components.queryItems = [
            URLQueryItem(name: "is_deleted", value: "eq.false"),
            URLQueryItem(name: "logged_at", value: "gte.\(startString)"),
            URLQueryItem(name: "logged_at", value: "lt.\(endString)")
        ]
        
        guard let url = components.url else {
            return SimpleEntry(date: date, waterTotal: 0, smokesTotal: 0, waterGoal: waterGoal, smokesBaseline: smokesBaseline, isLoggedIn: true)
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG", forHTTPHeaderField: "apikey")
        
        do {
            let (data, rsp) = try await URLSession.shared.data(for: req)
            guard let httpResponse = rsp as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // API error (401, network, etc.) — fall back to last known cached totals
                let cachedWater = groupPrefs?.integer(forKey: "cached_water_total") ?? 0
                let cachedSmokes = groupPrefs?.integer(forKey: "cached_smokes_total") ?? 0
                return SimpleEntry(date: date, waterTotal: cachedWater, smokesTotal: cachedSmokes, waterGoal: waterGoal, smokesBaseline: smokesBaseline, isLoggedIn: true)
            }
            struct LogDto: Decodable { let habit_type: String?; let value: Double? }
            let logs = try JSONDecoder().decode([LogDto].self, from: data)
            
            var water = 0.0
            var smokes = 0.0
            for log in logs {
                if log.habit_type == "water" { water += log.value ?? 0.0 }
                if log.habit_type == "smokes" { smokes += log.value ?? 0.0 }
            }
            return SimpleEntry(date: date, waterTotal: Int(water), smokesTotal: Int(smokes), waterGoal: waterGoal, smokesBaseline: smokesBaseline, isLoggedIn: true)
        } catch {
            // Network error — fall back to last known cached totals
            let cachedWater = groupPrefs?.integer(forKey: "cached_water_total") ?? 0
            let cachedSmokes = groupPrefs?.integer(forKey: "cached_smokes_total") ?? 0
            return SimpleEntry(date: date, waterTotal: cachedWater, smokesTotal: cachedSmokes, waterGoal: waterGoal, smokesBaseline: smokesBaseline, isLoggedIn: true)
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let waterTotal: Int
    let smokesTotal: Int
    let waterGoal: Int
    let smokesBaseline: Int
    let isLoggedIn: Bool
}

struct DailyWatchWidgetExtensionEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private func getSmokesColor(total: Int, baseline: Int) -> Color {
        if total == 0 { return .green }
        let ratio = Double(total) / Double(max(baseline, 1))
        if ratio >= 1.0 { return .red }
        if ratio >= 0.5 { return .orange }
        return .yellow
    }

    var body: some View {
        if !entry.isLoggedIn {
            Text("Login App")
                .font(.system(size: 10, weight: .semibold))
                .multilineTextAlignment(.center)
        } else {
            switch family {
            case .accessoryCircular:
                let currentMinute = Calendar.current.component(.minute, from: entry.date)
                // Switch every 5 minutes: 0-4 = water, 5-9 = smokes, etc.
                let showWater = (currentMinute % 10) < 5
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: showWater ? "drop.fill" : "flame.fill")
                            .font(.system(size: 12))
                            .foregroundColor(showWater ? .blue : getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline))
                        Text("\(showWater ? entry.waterTotal : entry.smokesTotal)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(showWater ? .primary : getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline))
                    }
                }
            case .accessoryRectangular:
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "drop.fill").font(.system(size: 14)).foregroundColor(.blue)
                            Text("\(entry.waterTotal) ml")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        HStack {
                            Image(systemName: "flame.fill").font(.system(size: 14)).foregroundColor(getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline))
                            Text("\(entry.smokesTotal) total")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                    
                    // Imbricated circles visual progress
                    ZStack {
                        // Water ring background
                        Circle()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                        
                        // Water ring foreground (using dynamic waterGoal)
                        let waterProgress = CGFloat(entry.waterTotal) / CGFloat(max(entry.waterGoal, 1))
                        Circle()
                            .trim(from: 0, to: min(waterProgress, 1.0))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        // Smokes ring background
                        Circle()
                            .stroke(getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline).opacity(0.3), lineWidth: 4)
                            .padding(6) // offset for imbricated effect
                        
                        // Smokes ring foreground (using dynamic smokesBaseline)
                        let smokesProgress = CGFloat(entry.smokesTotal) / CGFloat(max(entry.smokesBaseline, 1))
                        Circle()
                            .trim(from: 0, to: min(smokesProgress, 1.0))
                            .stroke(getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(6)
                    }
                    .frame(width: 44, height: 44)
                }
            case .accessoryInline:
                Text("💧 \(entry.waterTotal) \(Text("🔥 \(entry.smokesTotal)").foregroundColor(getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline)))")
            case .accessoryCorner:
                Image(systemName: "drop.fill").font(.system(size: 14))
            default:
                Text("\(entry.waterTotal) ml")
            }
        }
    }
}

struct DailyWatchWidgetExtension: Widget {
    let kind: String = "DailyWatchWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DailyWatchWidgetExtensionEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Logs")
        .description("Track your daily water and smokes on your watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

#Preview(as: .accessoryRectangular) {
    DailyWatchWidgetExtension()
} timeline: {
    SimpleEntry(date: .now, waterTotal: 850, smokesTotal: 2, waterGoal: 2000, smokesBaseline: 20, isLoggedIn: true)
}
