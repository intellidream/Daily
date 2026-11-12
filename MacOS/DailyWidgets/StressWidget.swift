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
            if !entry.snapshot.hasData {
                emptyView
            } else {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(URL(string: "daily://health/stress"))
    }

    private var emptyView: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 56, weight: .black))
                .foregroundColor(WidgetColors.accentCyan.opacity(0.05))
                .offset(x: 10, y: 10)

            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    WidgetMonkeyMascotView(mood: .curious, size: 18)
                    Text("STRESS")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                    Spacer()
                }

                Spacer(minLength: 0)

                Text("--")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))

                Text("No Telemetry")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)

                Text("Wear watch to track")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(WidgetColors.fgMuted.opacity(0.8))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // =========================================================================
    // MARK: - 1. SYSTEM SMALL
    // =========================================================================
    private var smallView: some View {
        ZStack(alignment: .bottomTrailing) {
            // Subtle background watermark matching Bubbles / Smokes / Sleep small widgets
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 56, weight: .black))
                .foregroundColor(levelColor.opacity(0.05))
                .offset(x: 10, y: 10)

            VStack(spacing: 4.5) {
                // Header: Monkey Mascot + STRESS + Single-line Status Pill
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        WidgetMonkeyMascotView(mood: entry.snapshot.monkeyMood, size: 18)
                        Text("STRESS")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundColor(levelColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    Text(entry.snapshot.level.displayName)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(levelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(levelColor.opacity(0.18))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                // Center Circular Score Gauge
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 5.5)
                        .frame(width: 54, height: 54)

                    Circle()
                        .trim(from: 0, to: max(0.04, min(CGFloat(entry.snapshot.stressScore) / 100.0, 1.0)))
                        .stroke(
                            LinearGradient(
                                colors: gradientColors.isEmpty ? [levelColor, levelColor.opacity(0.7)] : gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 54, height: 54)

                    VStack(spacing: 0) {
                        Text("\(entry.snapshot.stressScore)")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("/100")
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                }

                Spacer(minLength: 0)

                // Autonomic Balance Mini-Bar
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        Text("\(entry.snapshot.parasympatheticPercent)% Rest")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                            .lineLimit(1)
                        Spacer()
                        Text("\(entry.snapshot.sympatheticPercent)% Active")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentOrange)
                            .lineLimit(1)
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
                    .frame(height: 3.5)
                }

                // Bottom Biometric Bar (HRV + RHR / Mood)
                HStack(spacing: 4) {
                    if let hrv = entry.snapshot.hrvMs {
                        HStack(spacing: 2.5) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 7.5))
                                .foregroundColor(WidgetColors.accentCyan)
                            Text("\(Int(round(hrv))) ms")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                        }
                    } else {
                        Text(entry.snapshot.monkeyMood.displayName)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    if let rhr = entry.snapshot.restingHeartRate {
                        HStack(spacing: 2.5) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 7))
                                .foregroundColor(WidgetColors.accentPink)
                            Text("\(Int(round(rhr))) bpm")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                        }
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(levelColor)
                    }
                }
                .padding(.horizontal, 6.5)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // =========================================================================
    // MARK: - 2. SYSTEM MEDIUM
    // =========================================================================
    private var mediumView: some View {
        HStack(spacing: 10) {
            // Left Column: Monkey Mascot + Score Ring + Autonomic Balance
            VStack(spacing: 6) {
                HStack(spacing: 4.5) {
                    WidgetMonkeyMascotView(mood: entry.snapshot.monkeyMood, size: 20)
                    Text(entry.snapshot.level.displayName)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(levelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(levelColor.opacity(0.18))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 6)
                        .frame(width: 60, height: 60)

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
                        .frame(width: 60, height: 60)

                    VStack(spacing: 0) {
                        Text("\(entry.snapshot.stressScore)")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("STRESS")
                            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                }

                Spacer(minLength: 0)

                // Balance bar
                VStack(spacing: 2.5) {
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
                    .frame(height: 4)
                }
            }
            .frame(width: 116)
            .frame(maxHeight: .infinity)

            // Right Column: Biometrics + Monkey Wisdom Card + Recommended Action
            VStack(alignment: .leading, spacing: 5.5) {
                // Biometrics mini pills
                HStack(spacing: 5) {
                    if let hrv = entry.snapshot.hrvMs {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 8.5))
                                .foregroundColor(WidgetColors.accentCyan)
                            Text("HRV \(Int(round(hrv))) ms")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }

                    if let rhr = entry.snapshot.restingHeartRate {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8.5))
                                .foregroundColor(WidgetColors.accentPink)
                            Text("RHR \(Int(round(rhr))) bpm")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }

                    Spacer(minLength: 0)
                }

                // Monkey Wisdom Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(entry.snapshot.monkeyMood.displayName)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(levelColor)
                        Spacer()
                        Image(systemName: entry.snapshot.monkeyMood.iconSymbol)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(levelColor)
                    }
                    Text(entry.snapshot.adviceSnippet)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#061020").opacity(0.78))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(levelColor.opacity(0.32), lineWidth: 1)
                        )
                )

                // Footer Action Pill
                HStack(spacing: 5) {
                    Image(systemName: "wind")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text(entry.snapshot.monkeyMood.quickActionTitle)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("Stress Studio")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // =========================================================================
    // MARK: - 3. SYSTEM LARGE
    // =========================================================================
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Header
            HStack(spacing: 8) {
                WidgetMonkeyMascotView(mood: entry.snapshot.monkeyMood, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Stress Studio")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(entry.snapshot.monkeyMood.displayName)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(levelColor)
                }

                Spacer()

                Text(entry.snapshot.level.displayName)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(levelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(levelColor.opacity(0.18))
                    .clipShape(Capsule())
            }

            // Row 2: Hero Score Ring + Autonomic Balance Breakdown
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 7)
                        .frame(width: 72, height: 72)

                    Circle()
                        .trim(from: 0, to: max(0.04, min(CGFloat(entry.snapshot.stressScore) / 100.0, 1.0)))
                        .stroke(
                            LinearGradient(
                                colors: gradientColors.isEmpty ? [levelColor, levelColor.opacity(0.7)] : gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 72, height: 72)

                    VStack(spacing: 0) {
                        Text("\(entry.snapshot.stressScore)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("/100")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("AUTONOMIC BALANCE")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)

                    // Parasympathetic (Rest)
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack {
                            Text("Parasympathetic (Rest & Digest)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.snapshot.parasympatheticPercent)%")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.accentMint)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentMint], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, geo.size.width * CGFloat(entry.snapshot.parasympatheticPercent) / 100.0))
                            }
                        }
                        .frame(height: 5)
                    }

                    // Sympathetic (Active)
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack {
                            Text("Sympathetic (Active Load)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.snapshot.sympatheticPercent)%")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.accentOrange)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(LinearGradient(colors: [WidgetColors.accentAmber, WidgetColors.accentOrange], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, geo.size.width * CGFloat(entry.snapshot.sympatheticPercent) / 100.0))
                            }
                        }
                        .frame(height: 5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(11)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            // Row 3: 3-Tile Biometrics Grid (HRV, RHR, Recovery Tone)
            HStack(spacing: 7) {
                stressBiometricTile(
                    icon: "waveform.path.ecg",
                    label: "HRV (SDNN)",
                    value: entry.snapshot.hrvMs != nil ? "\(Int(round(entry.snapshot.hrvMs!))) ms" : "--",
                    color: WidgetColors.accentCyan
                )
                stressBiometricTile(
                    icon: "heart.fill",
                    label: "Resting HR",
                    value: entry.snapshot.restingHeartRate != nil ? "\(Int(round(entry.snapshot.restingHeartRate!))) bpm" : "--",
                    color: WidgetColors.accentPink
                )
                stressBiometricTile(
                    icon: "leaf.fill",
                    label: "Rest Ratio",
                    value: "\(entry.snapshot.parasympatheticPercent)%",
                    color: WidgetColors.accentMint
                )
            }

            // Row 4: Monkey Wisdom & Breathing Protocol Card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: entry.snapshot.monkeyMood.iconSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(levelColor)
                    Text("MONKEY WISDOM")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .foregroundColor(levelColor)
                    Spacer()
                    HStack(spacing: 3.5) {
                        Image(systemName: "wind")
                            .font(.system(size: 8.5, weight: .bold))
                        Text(entry.snapshot.monkeyMood.quickActionTitle)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(WidgetColors.accentCyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(WidgetColors.accentCyan.opacity(0.15))
                    .clipShape(Capsule())
                }

                Text(entry.snapshot.adviceSnippet)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#061020").opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(levelColor.opacity(0.32), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stressBiometricTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .systemLarge
        ])
    }
}
