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
            // Stylized Watermark Icon (scaled down: 59pt, opacity: 0.14, inward offset x: 16)
            Image(systemName: "drop.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 59)
                .foregroundColor(WidgetColors.accentCyan)
                .opacity(0.14)
                .offset(x: 16)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        let remaining = max(0, entry.snapshot.goalMl - entry.snapshot.todayMl)

        return HStack(spacing: 12) {
            // Left: Large Multi-Color Circle Hero (spans top to bottom)
            ZStack {
                BubblesMultiDrinkArcRing(
                    todayMl: entry.snapshot.todayMl,
                    goalMl: entry.snapshot.goalMl,
                    breakdown: entry.snapshot.drinkBreakdown,
                    lineWidth: 8.5
                )

                VStack(spacing: 1) {
                    Text("\(Int(entry.snapshot.todayMl))")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("of \(Int(entry.snapshot.goalMl)) ml")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(width: 88, height: 88)

            // Right: Header (Percent + Remaining + Icon), Labeled Liquid Breakdown, and 2x2 Buttons Grid
            VStack(alignment: .leading, spacing: 5) {
                // Top Row: Percentage + Remaining on left, Icon on right
                HStack(alignment: .center, spacing: 6) {
                    Text("\(Int(entry.snapshot.progressPercent * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)

                    Text(remaining > 0 ? "· \(Int(remaining)) ml left" : "· Goal met 🎉")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(remaining > 0 ? Color.white.opacity(0.55) : WidgetColors.accentGreen)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    Image(systemName: "drop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                // Breakdown by liquid types (labeled pills in order of importance)
                HStack(spacing: 5) {
                    if !entry.snapshot.drinkBreakdown.isEmpty {
                        ForEach(entry.snapshot.drinkBreakdown.prefix(3), id: \.name) { item in
                            let itemColor = Color(hex: item.hexColor)
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(itemColor)
                                    .frame(width: 5, height: 5)
                                Text("\(item.name.prefix(3)) \(Int(item.amount))")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(itemColor)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(itemColor.opacity(0.12)))
                        }
                    } else {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(WidgetColors.accentCyan)
                                .frame(width: 5, height: 5)
                            Text("Wtr \(Int(entry.snapshot.waterMl))")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.accentCyan)
                        }
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(WidgetColors.accentCyan.opacity(0.12)))

                        if entry.snapshot.coffeeMl > 0 {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(WidgetColors.coffeeYellow)
                                    .frame(width: 5, height: 5)
                                Text("Cof \(Int(entry.snapshot.coffeeMl))")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(WidgetColors.coffeeYellow)
                            }
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(WidgetColors.coffeeYellow.opacity(0.12)))
                        }
                    }
                }

                Spacer(minLength: 0)

                // 2x2 Interactive Action Buttons Grid
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Button(intent: LogWaterIntent(amountMl: 300, drinkType: "Water")) {
                            Text("+300 Wtr")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
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
                            Text("+150 Wtr")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
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
                            Text("+100 Cof")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
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
                            Text("+200 Tea")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        let remaining = max(0, entry.snapshot.goalMl - entry.snapshot.todayMl)
        let otherMl = max(0, entry.snapshot.todayMl - entry.snapshot.waterMl - entry.snapshot.coffeeMl)

        return VStack(alignment: .leading, spacing: 8) {
            // Header: Icon + Title + Remaining & Goal Badge
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("BUBBLES HYDRATION")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                Spacer(minLength: 4)

                Text(remaining > 0 ? "\(Int(remaining)) ml left" : "Goal Met 🎉")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(remaining > 0 ? Color.white.opacity(0.7) : WidgetColors.accentGreen)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))

                Text("\(Int(entry.snapshot.progressPercent * 100))% Goal")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WidgetColors.accentGreen.opacity(0.15))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            // Hero Gauge & Hydration Progress Card
            HStack(spacing: 14) {
                ZStack {
                    BubblesMultiDrinkArcRing(
                        todayMl: entry.snapshot.todayMl,
                        goalMl: entry.snapshot.goalMl,
                        breakdown: entry.snapshot.drinkBreakdown,
                        lineWidth: 11
                    )

                    VStack(spacing: 1) {
                        Text("\(Int(entry.snapshot.todayMl))")
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("of \(Int(entry.snapshot.goalMl)) ml")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                }
                .frame(width: 102, height: 102)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DAILY TARGET")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.45))
                            Text("\(Int(entry.snapshot.goalMl)) ml")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("REMAINING")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.45))
                            Text("\(Int(remaining)) ml")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(remaining > 0 ? WidgetColors.accentCyan : WidgetColors.accentGreen)
                        }
                    }

                    // Proportional Hydration Progress Bar
                    GeometryReader { geo in
                        let w = geo.size.width
                        let goal = max(1.0, entry.snapshot.goalMl)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            HStack(spacing: 1.5) {
                                if entry.snapshot.waterMl > 0 {
                                    Capsule()
                                        .fill(WidgetColors.accentCyan)
                                        .frame(width: max(4, min(w, CGFloat(entry.snapshot.waterMl / goal) * w)))
                                }
                                if entry.snapshot.coffeeMl > 0 {
                                    Capsule()
                                        .fill(WidgetColors.coffeeYellow)
                                        .frame(width: max(4, min(w, CGFloat(entry.snapshot.coffeeMl / goal) * w)))
                                }
                                if otherMl > 0 {
                                    Capsule()
                                        .fill(WidgetColors.teaLime)
                                        .frame(width: max(4, min(w, CGFloat(otherMl / goal) * w)))
                                }
                            }
                        }
                    }
                    .frame(height: 8)
                    .clipShape(Capsule())

                    let pureShare = entry.snapshot.todayMl > 0 ? Int((entry.snapshot.waterMl / entry.snapshot.todayMl) * 100) : 0
                    Text("Pure water share: \(pureShare)% · \(entry.snapshot.drinkBreakdown.count) drink types today")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                )
            }

            Spacer(minLength: 0)

            // 3-Column Drink Breakdown Cards
            HStack(spacing: 6) {
                drinkStatCard(
                    title: "WATER",
                    amountMl: Int(entry.snapshot.waterMl),
                    sharePercent: entry.snapshot.todayMl > 0 ? Int((entry.snapshot.waterMl / entry.snapshot.todayMl) * 100) : 0,
                    icon: "drop.fill",
                    color: WidgetColors.accentCyan
                )
                drinkStatCard(
                    title: "COFFEE",
                    amountMl: Int(entry.snapshot.coffeeMl),
                    sharePercent: entry.snapshot.todayMl > 0 ? Int((entry.snapshot.coffeeMl / entry.snapshot.todayMl) * 100) : 0,
                    icon: "cup.and.saucer.fill",
                    color: WidgetColors.coffeeYellow
                )
                drinkStatCard(
                    title: "TEA / OTHER",
                    amountMl: Int(otherMl),
                    sharePercent: entry.snapshot.todayMl > 0 ? Int((otherMl / entry.snapshot.todayMl) * 100) : 0,
                    icon: "leaf.fill",
                    color: WidgetColors.teaLime
                )
            }

            Spacer(minLength: 0)

            // Quick Logging Grid (Row of 4 interactive capsules)
            HStack(spacing: 6) {
                Button(intent: LogWaterIntent(amountMl: 300, drinkType: "Water")) {
                    VStack(spacing: 1) {
                        Text("+300 ml")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Text("Water")
                            .font(.system(size: 8.5, weight: .semibold))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(WidgetColors.accentCyan)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WidgetColors.accentCyan.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 150, drinkType: "Water")) {
                    VStack(spacing: 1) {
                        Text("+150 ml")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Text("Water")
                            .font(.system(size: 8.5, weight: .semibold))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(WidgetColors.accentCyan)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WidgetColors.accentCyan.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 100, drinkType: "Coffee")) {
                    VStack(spacing: 1) {
                        Text("+100 ml")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Text("Coffee")
                            .font(.system(size: 8.5, weight: .semibold))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(WidgetColors.coffeeYellow)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WidgetColors.coffeeYellow.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WidgetColors.coffeeYellow.opacity(0.28), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 200, drinkType: "Tea")) {
                    VStack(spacing: 1) {
                        Text("+200 ml")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Text("Tea")
                            .font(.system(size: 8.5, weight: .semibold))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(WidgetColors.teaLime)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WidgetColors.teaLime.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WidgetColors.teaLime.opacity(0.28), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func drinkStatCard(title: String, amountMl: Int, sharePercent: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3.5) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            Text("\(amountMl) ml")
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            Text("\(sharePercent)% of total")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.2), lineWidth: 1))
        )
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
