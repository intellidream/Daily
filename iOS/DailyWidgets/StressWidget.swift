import WidgetKit
import SwiftUI
import DailyCore

public struct StressEntry: TimelineEntry {
    public let date: Date
    public let snapshot: StressWidgetSnapshot

    public init(date: Date, snapshot: StressWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct StressTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> StressEntry {
        StressEntry(date: Date(), snapshot: StressWidgetSnapshot.placeholder)
    }

    public func getSnapshot(in context: Context, completion: @escaping (StressEntry) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchStressSnapshot()
        completion(StressEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<StressEntry>) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchStressSnapshot()
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let entry = StressEntry(date: currentDate, snapshot: snapshot)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Main Stress Widget View
public struct StressWidgetView: View {
    public let entry: StressEntry
    @Environment(\.widgetFamily) var family

    private var levelColor: Color {
        Color(hex: entry.snapshot.level.hexColor)
    }

    private var gradientColors: [Color] {
        entry.snapshot.level.gradientHex.map { Color(hex: $0) }
    }

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .accessoryCircular:
                accessoryCircularView
            case .accessoryRectangular:
                accessoryRectangularView
            case .accessoryInline:
                accessoryInlineView
            default:
                mediumView
            }
        }
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(URL(string: "daily://health/stress"))
    }

    // =========================================================================
    // MARK: - 1. SYSTEM SMALL
    // =========================================================================
    private var smallView: some View {
        VStack(spacing: 5) {
            // Header: Monkey + Label + Status Pill
            HStack {
                HStack(spacing: 3.5) {
                    Text(entry.snapshot.monkeyMood.emoji)
                        .font(.system(size: 11))
                    Text("STRESS")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundColor(levelColor)
                }

                Spacer(minLength: 2)

                Text(entry.snapshot.level.displayName)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(levelColor)
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1.5)
                    .background(levelColor.opacity(0.18))
                    .clipShape(Capsule())
            }

            // Center Circular Score Gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 5)
                    .frame(width: 52, height: 52)

                Circle()
                    .trim(from: 0, to: max(0.04, min(CGFloat(entry.snapshot.stressScore) / 100.0, 1.0)))
                    .stroke(
                        LinearGradient(
                            colors: gradientColors.isEmpty ? [levelColor, levelColor.opacity(0.7)] : gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)

                VStack(spacing: 0) {
                    Text("\(entry.snapshot.stressScore)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("/100")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                }
            }
            .padding(.vertical, 1)

            // Autonomic Balance Mini-Bar
            HStack(spacing: 3) {
                Text("\(entry.snapshot.parasympatheticPercent)% Rest")
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)
                Spacer()
                Text("\(entry.snapshot.sympatheticPercent)% Active")
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetColors.accentOrange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(WidgetColors.accentOrange.opacity(0.35))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [WidgetColors.accentCyan, WidgetColors.accentMint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(3, geo.size.width * CGFloat(entry.snapshot.parasympatheticPercent) / 100.0))
                }
            }
            .frame(height: 3)

            // Bottom Metric / Snippet
            HStack(spacing: 3) {
                if let hrv = entry.snapshot.hrvMs {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 7.5))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("\(Int(hrv)) ms HRV")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                } else {
                    Text(entry.snapshot.monkeyMood.displayName)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer(minLength: 2)

                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(levelColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // =========================================================================
    // MARK: - 2. SYSTEM MEDIUM
    // =========================================================================
    private var mediumView: some View {
        HStack(spacing: 12) {
            // Left Column (42%): Mascot + Gauge + Autonomic Balance
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(entry.snapshot.monkeyMood.emoji)
                        .font(.system(size: 13))
                    Text(entry.snapshot.level.displayName)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(levelColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(levelColor.opacity(0.18))
                        .clipShape(Capsule())
                }

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 6)
                        .frame(width: 58, height: 58)

                    Circle()
                        .trim(from: 0, to: max(0.04, min(CGFloat(entry.snapshot.stressScore) / 100.0, 1.0)))
                        .stroke(
                            LinearGradient(
                                colors: gradientColors.isEmpty ? [levelColor, levelColor.opacity(0.7)] : gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 58, height: 58)

                    VStack(spacing: 0) {
                        Text("\(entry.snapshot.stressScore)")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("STRESS")
                            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                }

                // Balance bar
                VStack(spacing: 2) {
                    HStack {
                        Text("Rest \(entry.snapshot.parasympatheticPercent)%")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                        Spacer()
                        Text("Active \(entry.snapshot.sympatheticPercent)%")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentOrange)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(WidgetColors.accentOrange.opacity(0.35))
                            Capsule()
                                .fill(LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentMint], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(3, geo.size.width * CGFloat(entry.snapshot.parasympatheticPercent) / 100.0))
                        }
                    }
                    .frame(height: 3.5)
                }
            }
            .frame(width: 108)

            // Right Column (58%): Wisdom Quote + Biometrics + Action
            VStack(alignment: .leading, spacing: 6) {
                // Biometrics mini pills
                HStack(spacing: 5) {
                    if let hrv = entry.snapshot.hrvMs {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 8))
                                .foregroundColor(WidgetColors.accentCyan)
                            Text("\(Int(hrv)) ms")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }

                    if let rhr = entry.snapshot.restingHeartRate {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundColor(WidgetColors.accentRed)
                            Text("\(Int(rhr)) bpm")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }

                    Spacer(minLength: 0)
                }

                // Monkey Wisdom Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(entry.snapshot.monkeyMood.displayName)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(levelColor)
                        Spacer()
                    }
                    Text(entry.snapshot.adviceSnippet)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.88))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#061020").opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(levelColor.opacity(0.3), lineWidth: 1)
                        )
                )

                Spacer(minLength: 0)

                // Footer Prompt
                HStack(spacing: 4) {
                    Text("Open Stress Studio")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
    }

    // =========================================================================
    // MARK: - 3. LOCK SCREEN ACCESSORIES
    // =========================================================================
    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(entry.snapshot.monkeyMood.emoji)
                    .font(.system(size: 11))
                Text("\(entry.snapshot.stressScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            HStack(spacing: 3) {
                Text(entry.snapshot.monkeyMood.emoji)
                    .font(.system(size: 9))
                Text("Stress: \(entry.snapshot.stressScore) (\(entry.snapshot.level.displayName))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            Text(entry.snapshot.adviceSnippet)
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .lineLimit(2)
        }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 3) {
            Text(entry.snapshot.monkeyMood.emoji)
            Text("Stress \(entry.snapshot.stressScore) · \(entry.snapshot.level.displayName)")
        }
    }
}

// MARK: - Widget Declaration
public struct StressWidget: Widget {
    public let kind: String = "com.intellidream.daily.widget.stress"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: StressTimelineProvider()
        ) { entry in
            StressWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Stress")
        .description("Real-time autonomic stress tracking with clinical HRV analysis and the wise monkey mascot.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
