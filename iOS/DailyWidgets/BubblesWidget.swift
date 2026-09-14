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
                coffeeMl: 100
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

public struct BubblesWidgetView: View {
    public let entry: BubblesEntry
    @Environment(\.widgetFamily) var family

    private let accentCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    private let accentGreen = Color(red: 0.0, green: 0.9, blue: 0.46)
    private let coffeeColor = Color(red: 0.84, green: 0.65, blue: 0.45)
    private let bgGradient = LinearGradient(
        colors: [Color(red: 0.05, green: 0.03, blue: 0.08), Color(red: 0.10, green: 0.07, blue: 0.16)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

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
        .containerBackground(bgGradient, for: .widget)
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(accentCyan)
                    Text("Bubbles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("\(Int(entry.snapshot.progressPercent * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(accentCyan)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(accentCyan.opacity(0.16))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            // Circular Ring with Center Amount
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.02, min(entry.snapshot.progressPercent, 1.0)))
                    .stroke(
                        LinearGradient(colors: [accentCyan, accentGreen], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text("\(Int(entry.snapshot.todayMl))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("ml")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)

            Spacer(minLength: 0)

            // Quick Interactive Button (+150ml)
            Button(intent: LogWaterIntent(amountMl: 150, drinkType: "Water")) {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("150 ml")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .foregroundColor(accentCyan)
                .background(
                    Capsule()
                        .fill(accentCyan.opacity(0.14))
                        .overlay(Capsule().strokeBorder(accentCyan.opacity(0.3), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        HStack(spacing: 14) {
            // Left: Circular Ring Hero
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(0.02, min(entry.snapshot.progressPercent, 1.0)))
                    .stroke(
                        LinearGradient(colors: [accentCyan, accentGreen], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accentCyan)
                    Text("\(Int(entry.snapshot.progressPercent * 100))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 82, height: 82)

            // Right: Telemetry & 3 Interactive Buttons
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bubbles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(entry.snapshot.todayMl)) / \(Int(entry.snapshot.goalMl)) ml")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                }

                // Drink breakdown pills
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Circle().fill(accentCyan).frame(width: 5, height: 5)
                        Text("\(Int(entry.snapshot.waterMl)) ml")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(accentCyan)
                    }
                    Text("·").foregroundColor(Color.white.opacity(0.3))
                    HStack(spacing: 3) {
                        Circle().fill(coffeeColor).frame(width: 5, height: 5)
                        Text("\(Int(entry.snapshot.coffeeMl)) ml ☕")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(coffeeColor)
                    }
                }

                Spacer(minLength: 2)

                // 3 Interactive Buttons Row
                HStack(spacing: 6) {
                    Button(intent: LogWaterIntent(amountMl: 150, drinkType: "Water")) {
                        Text("+150")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .foregroundColor(accentCyan)
                            .background(
                                Capsule()
                                    .fill(accentCyan.opacity(0.14))
                                    .overlay(Capsule().strokeBorder(accentCyan.opacity(0.3), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(intent: LogWaterIntent(amountMl: 300, drinkType: "Water")) {
                        Text("+300")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .foregroundColor(accentGreen)
                            .background(
                                Capsule()
                                    .fill(accentGreen.opacity(0.14))
                                    .overlay(Capsule().strokeBorder(accentGreen.opacity(0.3), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(intent: LogWaterIntent(amountMl: 100, drinkType: "Coffee")) {
                        Text("+100 ☕")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .foregroundColor(coffeeColor)
                            .background(
                                Capsule()
                                    .fill(coffeeColor.opacity(0.14))
                                    .overlay(Capsule().strokeBorder(coffeeColor.opacity(0.3), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Bubbles & Hydration", systemImage: "drop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accentCyan)
                Spacer()
                Text("\(Int(entry.snapshot.progressPercent * 100))% Done")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(accentGreen)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accentGreen.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Hero Gauge & Key Stats
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(entry.snapshot.progressPercent, 1.0)))
                        .stroke(
                            LinearGradient(colors: [accentCyan, accentGreen], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WATER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text("\(Int(entry.snapshot.waterMl)) ml")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(accentCyan)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("COFFEE & LIQUIDS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text("\(Int(entry.snapshot.coffeeMl)) ml ☕")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(coffeeColor)
                    }

                    let remaining = max(0, entry.snapshot.goalMl - entry.snapshot.todayMl)
                    Text(remaining > 0 ? "\(Int(remaining)) ml to goal" : "🎉 Goal completed!")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(remaining > 0 ? Color.white.opacity(0.7) : accentGreen)
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            Text("QUICK LOG")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.white.opacity(0.45))

            // Full interactive action bar
            HStack(spacing: 8) {
                Button(intent: LogWaterIntent(amountMl: 150, drinkType: "Water")) {
                    HStack(spacing: 4) {
                        Image(systemName: "drop")
                            .font(.system(size: 11, weight: .bold))
                        Text("150 ml")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(accentCyan)
                    .background(
                        Capsule()
                            .fill(accentCyan.opacity(0.14))
                            .overlay(Capsule().strokeBorder(accentCyan.opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 300, drinkType: "Water")) {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("300 ml")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(accentGreen)
                    .background(
                        Capsule()
                            .fill(accentGreen.opacity(0.14))
                            .overlay(Capsule().strokeBorder(accentGreen.opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogWaterIntent(amountMl: 100, drinkType: "Coffee")) {
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("100 ml ☕")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(coffeeColor)
                    .background(
                        Capsule()
                            .fill(coffeeColor.opacity(0.14))
                            .overlay(Capsule().strokeBorder(coffeeColor.opacity(0.3), lineWidth: 1))
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
        .description("Track daily water and coffee with instant interactive logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryInline])
    }
}
