import WidgetKit
import SwiftUI
import AppIntents
import DailyCore

public struct SmokesEntry: TimelineEntry {
    public let date: Date
    public let snapshot: SmokesWidgetSnapshot

    public init(date: Date, snapshot: SmokesWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct SmokesTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> SmokesEntry {
        SmokesEntry(
            date: Date(),
            snapshot: SmokesWidgetSnapshot(
                todayTotal: 3,
                baseline: 20,
                cigsCount: 2,
                heatedCount: 1,
                rolledCount: 0,
                cigarilloCount: 0,
                smokeBreakdown: [("Cigarette", 2, "#EF4444"), ("Heated", 1, "#3B82F6")],
                lastSmokeDate: Date().addingTimeInterval(-5400),
                spentTodayLei: 3.75
            )
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (SmokesEntry) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchSmokesSnapshot()
        completion(SmokesEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<SmokesEntry>) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchSmokesSnapshot()
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let entry = SmokesEntry(date: currentDate, snapshot: snapshot)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Smokes Widget View
public struct SmokesWidgetView: View {
    public let entry: SmokesEntry
    @Environment(\.widgetFamily) var family

    private var lungColor: Color {
        widgetLungHealthColor(countToday: entry.snapshot.todayTotal, baseline: entry.snapshot.baseline)
    }

    private var ringColor: Color {
        widgetSmokeRingColor(countToday: entry.snapshot.todayTotal, baseline: entry.snapshot.baseline)
    }

    private var formattedTime: String {
        widgetFormatCompactTimeAgo(entry.snapshot.lastSmokeDate)
    }

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
        .widgetURL(URL(string: "daily://habits/smokes"))
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        VStack(spacing: 6) {
            // Top Section: Progress circle on Left, Elapsed Time in Top-Right
            HStack(alignment: .top, spacing: 6) {
                // Circle Hero starting from Top-Left (inset with padding so ring is never clipped)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 7.0)

                    let progress = entry.snapshot.baseline > 0 ? min(Double(entry.snapshot.todayTotal) / Double(entry.snapshot.baseline), 1.0) : 0.0
                    Circle()
                        .trim(from: 0, to: max(0.03, progress))
                        .stroke(
                            LinearGradient(
                                colors: [WidgetColors.accentGreen, ringColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 7.0, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0.5) {
                        Text("\(entry.snapshot.todayTotal)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("/ \(entry.snapshot.baseline)")
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

                // Top-Right: Elapsed time in a pill (aligned flush top with circle)
                Text(formattedTime)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            // Bottom 2 Quick Action Buttons: Cig (Red, dedicated LogCigaretteIntent) & Heat (Blue, dedicated LogHeatedIntent)
            HStack(spacing: 4) {
                Button(intent: LogCigaretteIntent()) {
                    Text("Cig")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .foregroundColor(WidgetColors.accentRed)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentRed.opacity(0.15))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentRed.opacity(0.3), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: LogHeatedIntent()) {
                    Text("Heat")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .foregroundColor(WidgetColors.accentBlue)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentBlue.opacity(0.15))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentBlue.opacity(0.3), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(alignment: .trailing) {
            // Stylized Watermark Flame (scaled down: 59pt, opacity: 0.14, inward offset x: 16)
            Image(systemName: "flame.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 59)
                .foregroundColor(ringColor)
                .opacity(0.14)
                .offset(x: 16)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        HStack(spacing: 12) {
            // Left: Large Circle with Anatomical Lungs (top to bottom)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)

                let progress = entry.snapshot.baseline > 0 ? min(Double(entry.snapshot.todayTotal) / Double(entry.snapshot.baseline), 1.0) : 0.0
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(
                        LinearGradient(
                            colors: [ringColor, ringColor.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    ZStack {
                        WidgetVectorLungsShape()
                            .fill(lungColor.opacity(0.85))
                        WidgetVectorLungsBronchiShape()
                            .stroke(Color.white.opacity(0.75), lineWidth: 1.0)
                    }
                    .frame(width: 30, height: 30)

                    Text("\(entry.snapshot.todayTotal)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 88, height: 88)

            // Right: Header (Base + Time + Spent + Flame Icon), Type Breakdown Pills & 2x2 Buttons Grid
            VStack(alignment: .leading, spacing: 5) {
                // Header on same line: Base, time, spent on left, flame icon on right
                HStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 2) {
                        Text("\(entry.snapshot.baseline)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("base")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.5))
                    }

                    Text("·")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.3))

                    Text(formattedTime)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .lineLimit(1)

                    if entry.snapshot.spentTodayLei > 0 {
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundColor(Color.white.opacity(0.3))
                        Text(String(format: "%.0f Lei", entry.snapshot.spentTodayLei))
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ringColor)
                }

                // 4 Type Breakdown Mini Pills
                HStack(spacing: 4) {
                    smokeTypeMiniPill(label: "Cig", count: entry.snapshot.cigsCount, color: WidgetColors.accentRed)
                    smokeTypeMiniPill(label: "Heat", count: entry.snapshot.heatedCount, color: WidgetColors.accentBlue)
                    smokeTypeMiniPill(label: "Rol", count: entry.snapshot.rolledCount, color: WidgetColors.accentOrange)
                    smokeTypeMiniPill(label: "Cgr", count: entry.snapshot.cigarilloCount, color: WidgetColors.accentPurple)
                }

                Spacer(minLength: 0)

                // 2x2 Action Buttons Grid: Cgr & Rol (top), Cig & Heat (bottom)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Button(intent: LogSmokeIntent(smokeType: "Cgr")) {
                            Text("+Cgr")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundColor(WidgetColors.accentPurple)
                                .background(
                                    Capsule()
                                        .fill(WidgetColors.accentPurple.opacity(0.15))
                                        .overlay(Capsule().strokeBorder(WidgetColors.accentPurple.opacity(0.3), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(intent: LogSmokeIntent(smokeType: "Rol")) {
                            Text("+Rol")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundColor(WidgetColors.accentOrange)
                                .background(
                                    Capsule()
                                        .fill(WidgetColors.accentOrange.opacity(0.15))
                                        .overlay(Capsule().strokeBorder(WidgetColors.accentOrange.opacity(0.3), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        Button(intent: LogSmokeIntent(smokeType: "Cigarette")) {
                            Text("+Cig")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundColor(WidgetColors.accentRed)
                                .background(
                                    Capsule()
                                        .fill(WidgetColors.accentRed.opacity(0.15))
                                        .overlay(Capsule().strokeBorder(WidgetColors.accentRed.opacity(0.3), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(intent: LogSmokeIntent(smokeType: "Heated")) {
                            Text("+Heat")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundColor(WidgetColors.accentBlue)
                                .background(
                                    Capsule()
                                        .fill(WidgetColors.accentBlue.opacity(0.15))
                                        .overlay(Capsule().strokeBorder(WidgetColors.accentBlue.opacity(0.3), lineWidth: 1))
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
        let progress = entry.snapshot.baseline > 0 ? min(Double(entry.snapshot.todayTotal) / Double(entry.snapshot.baseline), 1.0) : 0.0
        let delta = entry.snapshot.baseline - entry.snapshot.todayTotal

        return VStack(alignment: .leading, spacing: 8) {
            // Header: Flame Icon + Title + Elapsed Badge + Baseline Badge
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ringColor)
                    Text("SMOKES & LUNGS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ringColor)
                }

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8.5))
                    Text(formattedTime)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(WidgetColors.accentCyan)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(WidgetColors.accentCyan.opacity(0.14)))

                Text("Base: \(entry.snapshot.baseline)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            // Hero Lungs & Daily Telemetry Card
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: max(0.03, progress))
                        .stroke(
                            LinearGradient(
                                colors: [ringColor, ringColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        ZStack {
                            WidgetVectorLungsShape()
                                .fill(lungColor.opacity(0.85))
                            WidgetVectorLungsBronchiShape()
                                .stroke(Color.white.opacity(0.75), lineWidth: 1.2)
                        }
                        .frame(width: 40, height: 40)

                        Text("\(entry.snapshot.todayTotal)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 102, height: 102)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("TODAY VS BASE")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.45))
                            Text("\(entry.snapshot.todayTotal) / \(entry.snapshot.baseline)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("SPENT TODAY")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.45))
                            Text(String(format: "%.1f Lei", entry.snapshot.spentTodayLei))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.accentAmber)
                        }
                    }

                    // Proportional Baseline Progress Bar
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(ringColor)
                                .frame(width: max(6, min(w, CGFloat(progress) * w)))
                        }
                    }
                    .frame(height: 8)
                    .clipShape(Capsule())

                    Text(delta >= 0 ? "\(delta) under daily baseline · Last: \(formattedTime)" : "\(abs(delta)) over daily baseline · Last: \(formattedTime)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(delta >= 0 ? Color.white.opacity(0.65) : WidgetColors.accentRed)
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

            // 4-Column Type Breakdown Cards
            HStack(spacing: 6) {
                smokeTypeCard(title: "CIG", count: entry.snapshot.cigsCount, total: entry.snapshot.todayTotal, color: WidgetColors.accentRed)
                smokeTypeCard(title: "HEAT", count: entry.snapshot.heatedCount, total: entry.snapshot.todayTotal, color: WidgetColors.accentBlue)
                smokeTypeCard(title: "ROL", count: entry.snapshot.rolledCount, total: entry.snapshot.todayTotal, color: WidgetColors.accentOrange)
                smokeTypeCard(title: "CGR", count: entry.snapshot.cigarilloCount, total: entry.snapshot.todayTotal, color: WidgetColors.accentPurple)
            }

            Spacer(minLength: 0)

            // 4-Button Interactive Action Grid (Row)
            HStack(spacing: 6) {
                Button(intent: LogSmokeIntent(smokeType: "Cgr")) {
                    VStack(spacing: 1) {
                        Text("+1 Cgr")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Text("Cigarillo")
                            .font(.system(size: 8, weight: .semibold))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(WidgetColors.accentPurple)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WidgetColors.accentPurple.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WidgetColors.accentPurple.opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogSmokeIntent(smokeType: "Rol")) {
                    VStack(spacing: 1) {
                        Text("+1 Rol")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Text("Rolled")
                            .font(.system(size: 8, weight: .semibold))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(WidgetColors.accentOrange)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WidgetColors.accentOrange.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WidgetColors.accentOrange.opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogSmokeIntent(smokeType: "Cigarette")) {
                    VStack(spacing: 1) {
                        Text("+1 Cig")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Text("Cigarette")
                            .font(.system(size: 8, weight: .semibold))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(WidgetColors.accentRed)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WidgetColors.accentRed.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WidgetColors.accentRed.opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogSmokeIntent(smokeType: "Heated")) {
                    VStack(spacing: 1) {
                        Text("+1 Heat")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Text("Heated")
                            .font(.system(size: 8, weight: .semibold))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(WidgetColors.accentBlue)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WidgetColors.accentBlue.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WidgetColors.accentBlue.opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func smokeTypeMiniPill(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
            Text("\(label) \(count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(count > 0 ? color : Color.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(count > 0 ? 0.12 : 0.05)))
    }

    private func smokeTypeCard(title: String, count: Int, total: Int, color: Color) -> some View {
        let share = total > 0 ? Int((Double(count) / Double(total)) * 100) : 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.55))
            }
            Text("\(count)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(count > 0 ? color : Color.white.opacity(0.4))
            Text("\(share)% share")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(count > 0 ? 0.25 : 0.08), lineWidth: 1))
        )
    }

    // MARK: - Lock Screen
    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            WidgetVectorLungsShape()
                .fill(Color.white)
                .frame(width: 20, height: 20)
            VStack {
                Spacer()
                Text("\(entry.snapshot.todayTotal)")
                    .font(.system(size: 10, weight: .bold))
            }
        }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
            Text("\(entry.snapshot.todayTotal) smokes (\(entry.snapshot.cigsCount) cig / \(entry.snapshot.heatedCount) heat)")
        }
    }
}

public struct SmokesWidget: Widget {
    public let kind: String = "com.intellidream.daily.SmokesWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmokesTimelineProvider()) { entry in
            SmokesWidgetView(entry: entry)
        }
        .configurationDisplayName("Smokes (Lungs & Intake)")
        .description("Track daily cigarettes, heated tobacco, rolled and cigarillos with instant quick logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryInline])
    }
}
