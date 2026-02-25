//
//  DailyWatchWidgetExtension.swift
//  DailyWatchWidgetExtension
//

import WidgetKit
import SwiftUI
import AppIntents

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), waterTotal: 850, smokesTotal: 3, isLoggedIn: true)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, waterTotal: 850, smokesTotal: 3, isLoggedIn: true)
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let entry = await fetchTodayStats(configuration: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    private func fetchTodayStats(configuration: ConfigurationAppIntent) async -> SimpleEntry {
        let date = Date()
        let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily")
        guard let token = groupPrefs?.string(forKey: "supabase_access_token") else {
            return SimpleEntry(date: date, configuration: configuration, waterTotal: 0, smokesTotal: 0, isLoggedIn: false)
        }
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: date)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startString = formatter.string(from: todayStart)
        let endString = formatter.string(from: todayEnd)
        
        guard var components = URLComponents(string: "https://akkfouifxztnfwwiclwg.supabase.co/rest/v1/habits_logs") else {
            return SimpleEntry(date: date, configuration: configuration, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
        }
        components.queryItems = [
            URLQueryItem(name: "is_deleted", value: "eq.false"),
            URLQueryItem(name: "logged_at", value: "gte.\(startString)"),
            URLQueryItem(name: "logged_at", value: "lt.\(endString)")
        ]
        
        guard let url = components.url else {
            return SimpleEntry(date: date, configuration: configuration, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG", forHTTPHeaderField: "apikey")
        
        do {
            let (data, rsp) = try await URLSession.shared.data(for: req)
            guard let httpResponse = rsp as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return SimpleEntry(date: date, configuration: configuration, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
            }
            struct LogDto: Decodable { let habit_type: String?; let value: Double? }
            let logs = try JSONDecoder().decode([LogDto].self, from: data)
            
            var water = 0.0
            var smokes = 0.0
            for log in logs {
                if log.habit_type == "water" { water += log.value ?? 0.0 }
                if log.habit_type == "smokes" { smokes += log.value ?? 0.0 }
            }
            return SimpleEntry(date: date, configuration: configuration, waterTotal: Int(water), smokesTotal: Int(smokes), isLoggedIn: true)
        } catch {
            return SimpleEntry(date: date, configuration: configuration, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
        }
    }

    func recommendations() -> [AppIntentRecommendation<ConfigurationAppIntent>] {
        [AppIntentRecommendation(intent: ConfigurationAppIntent(), description: "Daily Logs")]
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let waterTotal: Int
    let smokesTotal: Int
    let isLoggedIn: Bool
}

struct DailyWatchWidgetExtensionEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if !entry.isLoggedIn {
            Text("Login App")
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

struct DailyWatchWidgetExtension: Widget {
    let kind: String = "DailyWatchWidgetExtension"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            DailyWatchWidgetExtensionEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Logs")
        .description("Track your daily water and smokes on your watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

extension ConfigurationAppIntent {
    fileprivate static var defaults: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "💧"
        return intent
    }
}

#Preview(as: .accessoryRectangular) {
    DailyWatchWidgetExtension()
} timeline: {
    SimpleEntry(date: .now, configuration: .defaults, waterTotal: 850, smokesTotal: 2, isLoggedIn: true)
}
