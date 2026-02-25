//
//  DailyWatchWidget.swift
//  DailyWatchWidget
//

@preconcurrency import WidgetKit
import SwiftUI

struct DailyEntry: TimelineEntry {
    let date: Date
    let waterTotal: Int
    let smokesTotal: Int
    let isLoggedIn: Bool
}

struct DailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: Date(), waterTotal: 850, smokesTotal: 3, isLoggedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DailyEntry) -> Void) {
        completion(DailyEntry(date: Date(), waterTotal: 850, smokesTotal: 3, isLoggedIn: true))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DailyEntry>) -> Void) {
        Task {
            let entry = await fetchTodayStats()
            // Complications update roughly every 15-30 minutes dynamically based on watchOS budgets
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            DispatchQueue.main.async { completion(timeline) }
        }
    }
    
    private func fetchTodayStats() async -> DailyEntry {
        let date = Date()
        let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily")
        guard let token = groupPrefs?.string(forKey: "supabase_access_token") else {
            return DailyEntry(date: date, waterTotal: 0, smokesTotal: 0, isLoggedIn: false)
        }
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: date)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startString = formatter.string(from: todayStart)
        let endString = formatter.string(from: todayEnd)
        
        guard var components = URLComponents(string: "https://akkfouifxztnfwwiclwg.supabase.co/rest/v1/habits_logs") else {
            return DailyEntry(date: date, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
        }
        components.queryItems = [
            URLQueryItem(name: "is_deleted", value: "eq.false"),
            URLQueryItem(name: "logged_at", value: "gte.\(startString)"),
            URLQueryItem(name: "logged_at", value: "lt.\(endString)")
        ]
        
        guard let url = components.url else {
            return DailyEntry(date: date, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG", forHTTPHeaderField: "apikey")
        
        do {
            let (data, rsp) = try await URLSession.shared.data(for: req)
            guard let httpResponse = rsp as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return DailyEntry(date: date, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
            }
            struct LogDto: Decodable { let habit_type: String?; let value: Double? }
            let logs = try JSONDecoder().decode([LogDto].self, from: data)
            
            var water = 0.0
            var smokes = 0.0
            for log in logs {
                if log.habit_type == "water" { water += log.value ?? 0.0 }
                if log.habit_type == "smokes" { smokes += log.value ?? 0.0 }
            }
            return DailyEntry(date: date, waterTotal: Int(water), smokesTotal: Int(smokes), isLoggedIn: true)
        } catch {
            return DailyEntry(date: date, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
        }
    }
}

struct DailyWatchWidgetEntryView : View {
    var entry: DailyProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if !entry.isLoggedIn {
            Text("Open App\nTo Login")
                .font(.system(size: 10, weight: .semibold))
                .multilineTextAlignment(.center)
        } else {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "drop.fill").font(.system(size: 12))
                        Text("\(entry.waterTotal)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "drop.fill").font(.system(size: 14))
                        Text("\(entry.waterTotal) ml")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    HStack {
                        Image(systemName: "flame.fill").font(.system(size: 14))
                        Text("\(entry.smokesTotal) total")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                Text("💧 \(entry.waterTotal)  🔥 \(entry.smokesTotal)")
            case .accessoryCorner:
                Image(systemName: "drop.fill").font(.system(size: 14))
            default:
                Text("\(entry.waterTotal) ml")
            }
        }
    }
}

struct DailyWatchWidget: Widget {
    let kind: String = "DailyWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyProvider()) { entry in
            DailyWatchWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Logs")
        .description("Track your daily water and smokes on your watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

