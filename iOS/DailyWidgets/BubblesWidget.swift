import WidgetKit
import SwiftUI
import AppIntents
import DailyCore

public struct BubblesEntry: TimelineEntry {
    public let date: Date
    public let snapshot: BubblesWidgetSnapshot

    public init(date: Date, snapshot: BubblesWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct BubblesTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> BubblesEntry {
        BubblesEntry(
            date: Date(),
            snapshot: BubblesWidgetSnapshot(
                todayMl: 1250,
                goalMl: 2000,
                progressPercent: 0.625,
                waterMl: 1150,
                coffeeMl: 100,
                teaMl: 0,
                drinkBreakdown: [("Water", 1150, "#00E5FF"), ("Coffee", 100, "#F59E0B")]
            )
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (BubblesEntry) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchBubblesSnapshot()
        completion(BubblesEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<BubblesEntry>) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchBubblesSnapshot()
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let entry = BubblesEntry(date: currentDate, snapshot: snapshot)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Multi-Drink Stratified Arc Ring
struct BubblesMultiDrinkArcRing: View {
    let todayMl: Double
    let goalMl: Double
    let breakdown: [(name: String, amount: Double, hexColor: String)]
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            
            let safeGoal = max(goalMl, 1.0)
            if breakdown.isEmpty {
                let progress = min(max(todayMl / safeGoal, 0.0), 1.0)
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(
                        LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentGreen], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: seg.start, to: seg.end)
                        .stroke(
                            seg.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }

    private struct Segment {
        let start: CGFloat
        let end: CGFloat
        let color: Color
    }

    private var segments: [Segment] {
        let safeGoal = max(goalMl, 1.0)
        var running = 0.0
        var res: [Segment] = []
        for item in breakdown {
            let start = running / safeGoal
            let end = min((running + item.amount) / safeGoal, 1.0)
            if end > start {
                res.append(Segment(start: CGFloat(start), end: CGFloat(end), color: Color(hex: item.hexColor)))
                running += item.amount
            }
        }
        return res
    }
}

// MARK: - Main Bubbles Widget View
public struct BubblesWidgetView: View {
    public let entry: BubblesEntry
    @Environment(\.widgetFamily) var family

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .systemLarge:
                largeView
            case .accessoryCircular:
                accessoryCircularView
            case .accessoryInline:
                accessoryInlineView
            default:
                mediumView
            }
        }
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(URL(string: "daily://habits/bubbles"))
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        VStack(spacing: 6) {
            // Top Section: Progress ring on Left, Percentage in Top-Right
            HStack(alignment: .top, spacing: 6) {
                // Circle Hero starting from Top-Left (inset with padding so ring is never clipped)
                ZStack {
                    BubblesMultiDrinkArcRing(
                        todayMl: entry.snapshot.todayMl,
                        goalMl: entry.snapshot.goalMl,
                        breakdown: entry.snapshot.drinkBreakdown,
                        lineWidth: 7.0
                    )

                    VStack(spacing: 0.5) {
                        Text("\(Int(entry.snapshot.todayMl))")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("/ \(Int(entry.snapshot.goalMl)) ml")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(width: 72, height: 72)
                .padding(.top, 4)
                .padding(.leading, 4)

                Spacer(minLength: 2)

                // Top-Right: Percentage in a pill (aligned flush top with progress ring)
                Text("\(Int(entry.snapshot.progressPercent * 100))%")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2.5)
                    .background(WidgetColors.accentCyan.opacity(0.18))
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            // Bottom 3 Quick Action Buttons: 100 (Coffee), 150 (Water), 300 (Water)
            HStack(spacing: 4) {
                Button(intent: LogWaterIntent(amountMl: 100, drinkType: "Coffee")) {
                    Text("100")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .foregroundColor(WidgetColors.coffeeYellow)
                        .background(
                            Capsule()
                                .fill(WidgetColors.coffeeYellow.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.coffeeYellow.opacity(0.28), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 150, drinkType: "Water")) {
                    Text("150")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .foregroundColor(WidgetColors.accentCyan)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentCyan.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 300, drinkType: "Water")) {
                    Text("300")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .foregroundColor(WidgetColors.accentCyan)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentCyan.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(alignment: .trailing) {
            // Stylized Watermark Icon (scaled further down: 74pt, opacity: 0.18, ~35% bleed outside)
            Image(systemName: "drop.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 74)
                .foregroundColor(WidgetColors.accentCyan)
                .opacity(0.18)
                .offset(x: 20)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        HStack(spacing: 14) {
            // Left: Large Multi-Color Circle Hero (spans top to bottom)
            ZStack {
                BubblesMultiDrinkArcRing(
                    todayMl: entry.snapshot.todayMl,
                    goalMl: entry.snapshot.goalMl,
                    breakdown: entry.snapshot.drinkBreakdown,
                    lineWidth: 9
                )

                VStack(spacing: 1) {
                    Text("\(Int(entry.snapshot.todayMl))")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("of \(Int(entry.snapshot.goalMl)) ml")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }
            .frame(width: 86, height: 86)

            // Right: Header (Percent + Icon), Liquid Breakdown, and 2x2 Buttons Grid
            VStack(alignment: .leading, spacing: 6) {
                // Top Row: Percentage on left, Icon on right (No text title)
                HStack(alignment: .center) {
                    Text("\(Int(entry.snapshot.progressPercent * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                    
                    Spacer()

                    Image(systemName: "drop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                // Breakdown by liquid types (color-coded, no icons, in order of importance)
                HStack(spacing: 8) {
                    if !entry.snapshot.drinkBreakdown.isEmpty {
                        ForEach(entry.snapshot.drinkBreakdown.prefix(3), id: \.name) { item in
                            Text("\(Int(item.amount)) ml")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: item.hexColor))
                        }
                    } else {
                        Text("\(Int(entry.snapshot.waterMl)) ml")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                        if entry.snapshot.coffeeMl > 0 {
                            Text("\(Int(entry.snapshot.coffeeMl)) ml")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.coffeeYellow)
                        }
                    }
                }

                Spacer(minLength: 2)

                // 2x2 Interactive Action Buttons Grid (Simple numbers, color-coded)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Button(intent: LogWaterIntent(amountMl: 300, drinkType: "Water")) {
                            Text("300")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundColor(WidgetColors.accentCyan)
                                .background(
                                    Capsule()
                                        .fill(WidgetColors.accentCyan.opacity(0.14))
                                        .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(intent: LogWaterIntent(amountMl: 150, drinkType: "Water")) {
                            Text("150")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundColor(WidgetColors.accentCyan)
                                .background(
                                    Capsule()
                                        .fill(WidgetColors.accentCyan.opacity(0.14))
                                        .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        Button(intent: LogWaterIntent(amountMl: 100, drinkType: "Coffee")) {
                            Text("100")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundColor(WidgetColors.coffeeYellow)
                                .background(
                                    Capsule()
                                        .fill(WidgetColors.coffeeYellow.opacity(0.14))
                                        .overlay(Capsule().strokeBorder(WidgetColors.coffeeYellow.opacity(0.28), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(intent: LogWaterIntent(amountMl: 200, drinkType: "Tea")) {
                            Text("200")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundColor(WidgetColors.teaLime)
                                .background(
                                    Capsule()
                                        .fill(WidgetColors.teaLime.opacity(0.14))
                                        .overlay(Capsule().strokeBorder(WidgetColors.teaLime.opacity(0.28), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Large Icon + Percentage Badge
            HStack {
                if #available(iOS 17.0, *) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                        .symbolEffect(.pulse)
                } else {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                Spacer()

                Text("\(Int(entry.snapshot.progressPercent * 100))% Goal")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WidgetColors.accentGreen.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Hero Gauge & Detailed Breakdown
            HStack(spacing: 16) {
                ZStack {
                    BubblesMultiDrinkArcRing(
                        todayMl: entry.snapshot.todayMl,
                        goalMl: entry.snapshot.goalMl,
                        breakdown: entry.snapshot.drinkBreakdown,
                        lineWidth: 12
                    )

                    VStack(spacing: 2) {
                        Text("\(Int(entry.snapshot.todayMl))")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("of \(Int(entry.snapshot.goalMl)) ml")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                }
                .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: 8) {
                    if !entry.snapshot.drinkBreakdown.isEmpty {
                        ForEach(entry.snapshot.drinkBreakdown.prefix(3), id: \.name) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name.uppercased())
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.45))
                                Text("\(Int(item.amount)) ml")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: item.hexColor))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("WATER")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.45))
                            Text("\(Int(entry.snapshot.waterMl)) ml")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.accentCyan)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("COFFEE")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.45))
                            Text("\(Int(entry.snapshot.coffeeMl)) ml")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.coffeeYellow)
                        }
                    }

                    let remaining = max(0, entry.snapshot.goalMl - entry.snapshot.todayMl)
                    Text(remaining > 0 ? "\(Int(remaining)) ml remaining" : "Goal completed 🎉")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(remaining > 0 ? Color.white.opacity(0.65) : WidgetColors.accentGreen)
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Quick Logging Grid (2x2 / Row)
            HStack(spacing: 8) {
                Button(intent: LogWaterIntent(amountMl: 300, drinkType: "Water")) {
                    Text("300")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundColor(WidgetColors.accentCyan)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentCyan.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 150, drinkType: "Water")) {
                    Text("150")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundColor(WidgetColors.accentCyan)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentCyan.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 100, drinkType: "Coffee")) {
                    Text("100")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundColor(WidgetColors.coffeeYellow)
                        .background(
                            Capsule()
                                .fill(WidgetColors.coffeeYellow.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.coffeeYellow.opacity(0.28), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 200, drinkType: "Tea")) {
                    Text("200")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundColor(WidgetColors.teaLime)
                        .background(
                            Capsule()
                                .fill(WidgetColors.teaLime.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.teaLime.opacity(0.28), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Lock Screen
    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0, to: max(0.05, min(entry.snapshot.progressPercent, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12))
                Text("\(Int(entry.snapshot.progressPercent * 100))%")
                    .font(.system(size: 10, weight: .bold))
            }
        }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 3) {
            Image(systemName: "drop.fill")
            Text("\(Int(entry.snapshot.todayMl))/\(Int(entry.snapshot.goalMl)) ml (\(Int(entry.snapshot.progressPercent * 100))%)")
        }
    }
}

public struct BubblesWidget: Widget {
    public let kind: String = "com.intellidream.daily.BubblesWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubblesTimelineProvider()) { entry in
            BubblesWidgetView(entry: entry)
        }
        .configurationDisplayName("Bubbles (Hydration)")
        .description("Track daily water, coffee, and hydration with instant interactive logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryInline])
    }
}
