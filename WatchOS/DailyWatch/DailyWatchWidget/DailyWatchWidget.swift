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
        completion(readCachedStats())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DailyEntry>) -> Void) {
        // Serve strictly from local App Group cache (<1ms, zero network egress & battery drain)
        let entry = readCachedStats()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func readCachedStats() -> DailyEntry {
        let date = Date()
        let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily")
        let hasToken = !(groupPrefs?.string(forKey: "supabase_access_token") ?? "").isEmpty
        guard hasToken else {
            return DailyEntry(date: date, waterTotal: 0, smokesTotal: 0, isLoggedIn: false)
        }
        
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = Calendar.current.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let todayKey = fmt.string(from: date)
        let cachedDate = groupPrefs?.string(forKey: "cached_habits_date")
        
        if let cachedDate = cachedDate, cachedDate != todayKey {
            return DailyEntry(date: date, waterTotal: 0, smokesTotal: 0, isLoggedIn: true)
        }
        
        let cachedWater = groupPrefs?.integer(forKey: "cached_water_total") ?? 0
        let cachedSmokes = groupPrefs?.integer(forKey: "cached_smokes_total") ?? 0
        return DailyEntry(date: date, waterTotal: cachedWater, smokesTotal: cachedSmokes, isLoggedIn: true)
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

