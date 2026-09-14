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

/// Minimalist vector lungs silhouette for Widget display
struct WidgetLungsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Trachea
        path.move(to: CGPoint(x: w * 0.47, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.53, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.53, y: h * 0.30))
        path.addLine(to: CGPoint(x: w * 0.47, y: h * 0.30))
        path.closeSubpath()

        // Left Lobe
        path.move(to: CGPoint(x: w * 0.46, y: h * 0.30))
        path.addCurve(to: CGPoint(x: w * 0.12, y: h * 0.54),
                      control1: CGPoint(x: w * 0.28, y: h * 0.28),
                      control2: CGPoint(x: w * 0.12, y: h * 0.40))
        path.addCurve(to: CGPoint(x: w * 0.38, y: h * 0.90),
                      control1: CGPoint(x: w * 0.12, y: h * 0.74),
                      control2: CGPoint(x: w * 0.22, y: h * 0.88))
        path.addCurve(to: CGPoint(x: w * 0.46, y: h * 0.40),
                      control1: CGPoint(x: w * 0.42, y: h * 0.78),
                      control2: CGPoint(x: w * 0.44, y: h * 0.52))
        path.closeSubpath()

        // Right Lobe
        path.move(to: CGPoint(x: w * 0.54, y: h * 0.30))
        path.addCurve(to: CGPoint(x: w * 0.88, y: h * 0.54),
                      control1: CGPoint(x: w * 0.72, y: h * 0.28),
                      control2: CGPoint(x: w * 0.88, y: h * 0.40))
        path.addCurve(to: CGPoint(x: w * 0.62, y: h * 0.90),
                      control1: CGPoint(x: w * 0.88, y: h * 0.74),
                      control2: CGPoint(x: w * 0.78, y: h * 0.88))
        path.addCurve(to: CGPoint(x: w * 0.54, y: h * 0.40),
                      control1: CGPoint(x: w * 0.58, y: h * 0.78),
                      control2: CGPoint(x: w * 0.56, y: h * 0.52))
        path.closeSubpath()

        return path
    }
}

public struct SmokesWidgetView: View {
    public let entry: SmokesEntry
    @Environment(\.widgetFamily) var family

    private let accentGreen = Color(red: 0.0, green: 0.9, blue: 0.46)
    private let accentPink = Color(red: 1.0, green: 0.22, blue: 0.38)
    private let accentCyan = Color(red: 0.0, green: 0.85, blue: 1.0)
    private let bgGradient = LinearGradient(
        colors: [Color(red: 0.05, green: 0.03, blue: 0.08), Color(red: 0.10, green: 0.07, blue: 0.16)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var gaugeColor: Color {
        if entry.snapshot.todayTotal == 0 {
            return accentGreen
        } else if entry.snapshot.todayTotal < entry.snapshot.baseline {
            return accentCyan
        } else {
            return accentPink
        }
    }

    private var formattedTimeSinceLastSmoke: String {
        guard let last = entry.snapshot.lastSmokeDate else {
            return "Clean today"
        }
        let diff = max(0, Int(Date().timeIntervalSince(last)))
        let hours = diff / 3600
        let minutes = (diff % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m ago"
        } else {
            return "\(minutes)m ago"
        }
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
        .containerBackground(bgGradient, for: .widget)
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(gaugeColor)
                    Text("Smokes")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("\(entry.snapshot.todayTotal)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(gaugeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(gaugeColor.opacity(0.16))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            // Lungs Icon inside Circular Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 7)
                let progress = entry.snapshot.baseline > 0 ? min(Double(entry.snapshot.todayTotal) / Double(entry.snapshot.baseline), 1.0) : 0.0
                Circle()
                    .trim(from: 0, to: max(0.04, progress))
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                WidgetLungsShape()
                    .fill(gaugeColor.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)

            HStack {
                Spacer()
                Text(formattedTimeSinceLastSmoke)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
            }

            Spacer(minLength: 0)

            // 2 Quick Buttons in Small Widget
            HStack(spacing: 4) {
                Button(intent: LogSmokeIntent(smokeType: "Cigarette")) {
                    Text("+1 Cig")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(accentPink)
                        .background(
                            Capsule()
                                .fill(accentPink.opacity(0.14))
                                .overlay(Capsule().strokeBorder(accentPink.opacity(0.3), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: LogSmokeIntent(smokeType: "Heated")) {
                    Text("+1 Heat")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
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
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        HStack(spacing: 14) {
            // Left: Circular Lungs Hero
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                let progress = entry.snapshot.baseline > 0 ? min(Double(entry.snapshot.todayTotal) / Double(entry.snapshot.baseline), 1.0) : 0.0
                Circle()
                    .trim(from: 0, to: max(0.04, progress))
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    WidgetLungsShape()
                        .fill(gaugeColor.opacity(0.85))
                        .frame(width: 26, height: 26)
                    Text("\(entry.snapshot.todayTotal)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 82, height: 82)

            // Right: Telemetry & 2 Interactive Action Buttons
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Smokes")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Base: \(entry.snapshot.baseline)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.55))
                }

                HStack(spacing: 6) {
                    Text("🚬 \(entry.snapshot.cigsCount) Cig")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(accentPink)
                    Text("·").foregroundColor(Color.white.opacity(0.3))
                    Text("💨 \(entry.snapshot.heatedCount) Heat")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(accentCyan)
                    Spacer()
                    Text(formattedTimeSinceLastSmoke)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                }

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    Button(intent: LogSmokeIntent(smokeType: "Cigarette")) {
                        HStack(spacing: 3) {
                            Text("🚬")
                                .font(.system(size: 10))
                            Text("+1 Cig")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .foregroundColor(accentPink)
                        .background(
                            Capsule()
                                .fill(accentPink.opacity(0.14))
                                .overlay(Capsule().strokeBorder(accentPink.opacity(0.3), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    Button(intent: LogSmokeIntent(smokeType: "Heated")) {
                        HStack(spacing: 3) {
                            Text("💨")
                                .font(.system(size: 10))
                            Text("+1 Heat")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
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
                }
            }
        }
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Smokes & Tobacco", systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(gaugeColor)
                Spacer()
                Text("Base: \(entry.snapshot.baseline)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.6))
            }

            // Hero Lungs & Key Telemetry
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    let progress = entry.snapshot.baseline > 0 ? min(Double(entry.snapshot.todayTotal) / Double(entry.snapshot.baseline), 1.0) : 0.0
                    Circle()
                        .trim(from: 0, to: max(0.04, progress))
                        .stroke(gaugeColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        WidgetLungsShape()
                            .fill(gaugeColor.opacity(0.85))
                            .frame(width: 36, height: 36)
                        Text("\(entry.snapshot.todayTotal)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CIGARETTES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text("\(entry.snapshot.cigsCount) 🚬")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(accentPink)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("HEATED TOBACCO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text("\(entry.snapshot.heatedCount) 💨")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(accentCyan)
                    }

                    Text("Last: \(formattedTimeSinceLastSmoke)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.7))
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            HStack {
                Text("ESTIMATED SPENT TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.45))
                Spacer()
                Text(String(format: "%.2f Lei", entry.snapshot.spentTodayLei))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white)
            }

            // Interactive Action Buttons
            HStack(spacing: 8) {
                Button(intent: LogSmokeIntent(smokeType: "Cigarette")) {
                    HStack(spacing: 4) {
                        Text("🚬")
                            .font(.system(size: 12))
                        Text("+1 Cigarette")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundColor(accentPink)
                    .background(
                        Capsule()
                            .fill(accentPink.opacity(0.14))
                            .overlay(Capsule().strokeBorder(accentPink.opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Button(intent: LogSmokeIntent(smokeType: "Heated")) {
                    HStack(spacing: 4) {
                        Text("💨")
                            .font(.system(size: 12))
                        Text("+1 Heated")
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
            }
        }
    }

    // MARK: - Lock Screen
    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            WidgetLungsShape()
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
        .description("Track daily cigarettes and heated tobacco with instant quick logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryInline])
    }
}
