//
//  DailyWatchWidgetExtension.swift
//  DailyWatchWidgetExtension
//

import WidgetKit
import SwiftUI
import AppIntents

struct Provider: TimelineProvider {
    private let groupSuite = "group.com.intellidream.daily"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), waterTotal: 850, smokesTotal: 3, waterGoal: 2000, smokesBaseline: 40, lastSmokeDate: Date().addingTimeInterval(-3600), isLoggedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(readLocalEntry())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let baseEntry = readLocalEntry()
        let currentDate = Date()
        var entries: [SimpleEntry] = []
        
        // Generate entries for the next 30 minutes in 5-minute ticks to refresh craving timer
        for minuteOffset in stride(from: 0, to: 35, by: 5) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate)!
            entries.append(SimpleEntry(
                date: entryDate,
                waterTotal: baseEntry.waterTotal,
                smokesTotal: baseEntry.smokesTotal,
                waterGoal: baseEntry.waterGoal,
                smokesBaseline: baseEntry.smokesBaseline,
                lastSmokeDate: baseEntry.lastSmokeDate,
                isLoggedIn: baseEntry.isLoggedIn
            ))
        }
        
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }
    
    /// Instant 0ms read from local AppGroup disk cache — zero network blocking
    private func readLocalEntry() -> SimpleEntry {
        let date = Date()
        guard let groupPrefs = UserDefaults(suiteName: groupSuite) else {
            return SimpleEntry(date: date, waterTotal: 0, smokesTotal: 0, waterGoal: 2000, smokesBaseline: 40, lastSmokeDate: nil, isLoggedIn: false)
        }
        
        let token = groupPrefs.string(forKey: "supabase_access_token")
        let isLoggedIn = (token != nil && !token!.isEmpty)
        
        let waterGoal = max(500, Int(groupPrefs.string(forKey: "water_goal") ?? "2000") ?? 2000)
        let smokesBaseline = max(1, Int(groupPrefs.string(forKey: "smokes_baseline") ?? "40") ?? 40)
        
        let waterTotal = groupPrefs.integer(forKey: "cached_water_total")
        let smokesTotal = groupPrefs.integer(forKey: "cached_smokes_total")
        
        let lastSmokeDate: Date? = {
            if let iso = groupPrefs.string(forKey: "last_smoke_timestamp") {
                let f = ISO8601DateFormatter()
                return f.date(from: iso)
            }
            return nil
        }()
        
        return SimpleEntry(
            date: date,
            waterTotal: waterTotal,
            smokesTotal: smokesTotal,
            waterGoal: waterGoal,
            smokesBaseline: smokesBaseline,
            lastSmokeDate: lastSmokeDate,
            isLoggedIn: isLoggedIn
        )
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let waterTotal: Int
    let smokesTotal: Int
    let waterGoal: Int
    let smokesBaseline: Int
    let lastSmokeDate: Date?
    let isLoggedIn: Bool
    
    var timeSinceLastSmoke: TimeInterval? {
        guard let lsd = lastSmokeDate else { return nil }
        return max(0, date.timeIntervalSince(lsd))
    }
    
    var formattedCravingTime: String {
        guard let interval = timeSinceLastSmoke else { return "0m" }
        let mins = Int(interval / 60)
        let hours = mins / 60
        let remMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remMins)m"
        } else {
            return "\(mins)m"
        }
    }
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
            Text("Link Orbit")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.cyan)
        } else {
            switch family {
            case .accessoryCircular:
                let currentMinute = Calendar.current.component(.minute, from: entry.date)
                let showWater = (currentMinute % 10) < 5
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: showWater ? "drop.fill" : "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(showWater ? .cyan : getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline))
                        Text("\(showWater ? entry.waterTotal : entry.smokesTotal)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }
                
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    // Top Row: Water & Smokes Metrics
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.cyan)
                            Text("\(entry.waterTotal)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text("/\(entry.waterGoal)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                                .foregroundColor(getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline))
                            Text("\(entry.smokesTotal)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text("(\(entry.formattedCravingTime))")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Middle Row: Dual Progress Bars
                    GeometryReader { geo in
                        HStack(spacing: 4) {
                            // Water Bar
                            let wRatio = min(1.0, CGFloat(entry.waterTotal) / CGFloat(max(entry.waterGoal, 1)))
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.cyan.opacity(0.25))
                                Capsule().fill(Color.cyan).frame(width: max(4, geo.size.width * 0.48 * wRatio))
                            }
                            .frame(height: 5)
                            
                            // Smokes Bar
                            let sRatio = min(1.0, CGFloat(entry.smokesTotal) / CGFloat(max(entry.smokesBaseline, 1)))
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.2))
                                Capsule().fill(getSmokesColor(total: entry.smokesTotal, baseline: entry.smokesBaseline))
                                    .frame(width: max(4, geo.size.width * 0.48 * sRatio))
                            }
                            .frame(height: 5)
                        }
                    }
                    .frame(height: 5)
                    
                    // Bottom Row: Interactive 1-Tap AppIntent Logging Buttons!
                    HStack(spacing: 6) {
                        Button(intent: LogWaterWidgetIntent(amountMl: 300, drinkType: "Water")) {
                            HStack(spacing: 2) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .bold))
                                Text("300ml")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(Color.cyan.opacity(0.3))
                            .foregroundColor(.cyan)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        
                        Button(intent: LogSmokeWidgetIntent(isHeated: false)) {
                            HStack(spacing: 2) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Smoke")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(Color.red.opacity(0.3))
                            .foregroundColor(.red)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                
            case .accessoryInline:
                Text("💧 \(entry.waterTotal)ml · 🔥 \(entry.smokesTotal) (⏱ \(entry.formattedCravingTime))")
                
            case .accessoryCorner:
                let wRatio = min(1.0, Double(entry.waterTotal) / Double(max(entry.waterGoal, 1)))
                Text("\(entry.waterTotal)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .widgetLabel {
                        ProgressView(value: wRatio)
                    }
                    
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
        .configurationDisplayName("Daily Habits")
        .description("Track water and tobacco with interactive 1-tap logging.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
