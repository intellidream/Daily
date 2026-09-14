import WidgetKit
import SwiftUI
import DailyCore

public struct SleepEntry: TimelineEntry {
    public let date: Date
    public let snapshot: SleepWidgetSnapshot

    public init(date: Date, snapshot: SleepWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct SleepTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> SleepEntry {
        SleepEntry(date: Date(), snapshot: SleepWidgetSnapshot.placeholder)
    }

    public func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchSleepSnapshot()
        completion(SleepEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchSleepSnapshot()
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(1800)
        let entry = SleepEntry(date: currentDate, snapshot: snapshot)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Main Sleep Widget View
public struct SleepWidgetView: View {
    public let entry: SleepEntry
    @Environment(\.widgetFamily) var family

    private let deepColor = Color(hex: "#6366F1")
    private let remColor = Color(hex: "#8B5CF6")
    private let lightColor = Color(hex: "#00E5FF")
    private let awakeColor = Color(hex: "#EF4444")

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                if entry.snapshot.hasData {
                    smallView
                } else {
                    smallNoDataView
                }
            case .systemMedium:
                if entry.snapshot.hasData {
                    mediumView
                } else {
                    mediumNoDataView
                }
            case .systemLarge:
                if entry.snapshot.hasData {
                    largeView
                } else {
                    largeNoDataView
                }
            case .accessoryCircular:
                accessoryCircularView
            case .accessoryRectangular:
                accessoryRectangularView
            case .accessoryInline:
                accessoryInlineView
            default:
                if entry.snapshot.hasData {
                    mediumView
                } else {
                    mediumNoDataView
                }
            }
        }
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(URL(string: "daily://health/sleep"))
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        VStack(spacing: 6) {
            // Top Section: Progress ring on Left, Sleep Duration in Top-Right
            HStack(alignment: .top, spacing: 6) {
                // Circle Score Hero starting from Top-Left (inset 72x72pt with padding to avoid clipping)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 7.0)

                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(entry.snapshot.sleepScore, 0), 100)) / 100.0)
                        .stroke(
                            AngularGradient(
                                colors: [WidgetColors.accentCyan, WidgetColors.accentBlue, WidgetColors.accentPurple],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 7.0, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0.5) {
                        Text("\(entry.snapshot.sleepScore)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("/ 100")
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

                // Top-Right: Sleep Duration in a pill (aligned flush top with progress ring)
                Text(entry.snapshot.totalAsleepFormatted)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentPurple)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2.5)
                    .background(WidgetColors.accentPurple.opacity(0.18))
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            // Bottom 2 Information Pills: Schedule & Efficiency/Restorative
            HStack(spacing: 4) {
                // Schedule pill: Bedtime - Wake
                HStack(spacing: 2) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 7.5))
                    Text("\(entry.snapshot.bedtimeFormatted)-\(entry.snapshot.wakeTimeFormatted)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .foregroundColor(WidgetColors.accentPurple)
                .background(
                    Capsule()
                        .fill(WidgetColors.accentPurple.opacity(0.14))
                        .overlay(Capsule().strokeBorder(WidgetColors.accentPurple.opacity(0.25), lineWidth: 1))
                )

                // Efficiency pill
                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))
                    Text("\(entry.snapshot.efficiencyPercent)% Eff")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .foregroundColor(WidgetColors.accentCyan)
                .background(
                    Capsule()
                        .fill(WidgetColors.accentCyan.opacity(0.14))
                        .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.25), lineWidth: 1))
                )
            }
        }
        .background(alignment: .trailing) {
            // Stylized Watermark Moon/Stars Icon (scaled down: 59pt, opacity: 0.14, inward offset x: 16)
            Image(systemName: "moon.stars.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 59)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.14)
                .offset(x: 16)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        HStack(spacing: 14) {
            // Left: Large Radial Sleep Score Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 7.5)

                Circle()
                    .trim(from: 0, to: CGFloat(min(max(entry.snapshot.sleepScore, 0), 100)) / 100.0)
                    .stroke(
                        AngularGradient(
                            colors: [WidgetColors.accentCyan, WidgetColors.accentBlue, WidgetColors.accentPurple],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 7.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text(entry.snapshot.totalAsleepFormatted)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("\(entry.snapshot.sleepScore) pts")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(WidgetColors.accentCyan.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .frame(width: 78, height: 78)

            // Right: Telemetry & Proportional Sleep Architecture
            VStack(alignment: .leading, spacing: 6) {
                // Header row: Schedule and Restorative/Efficiency badge
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 9))
                            .foregroundColor(WidgetColors.accentPurple)
                        Text("\(entry.snapshot.bedtimeFormatted) ➔ \(entry.snapshot.wakeTimeFormatted)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Spacer()

                    Text("\(entry.snapshot.efficiencyPercent)% Eff · \(entry.snapshot.restorativePercent)% Rest")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WidgetColors.accentPurple.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Multi-Stage Proportional Bar
                stageProportionalBar(height: 7)

                // 4 Mini Stage Metric Capsules
                HStack(spacing: 3) {
                    stagePill(label: "Deep", duration: entry.snapshot.deepFormatted, color: deepColor)
                    stagePill(label: "REM", duration: entry.snapshot.remFormatted, color: remColor)
                    stagePill(label: "Light", duration: entry.snapshot.lightFormatted, color: lightColor)
                    stagePill(label: "Awake", duration: entry.snapshot.awakeFormatted, color: awakeColor)
                }

                // In-Bed and Source row
                HStack {
                    Text("\(entry.snapshot.timeInBedFormatted) in bed")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    HStack(spacing: 3) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 8))
                        Text(entry.snapshot.sourceDevice)
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .background(alignment: .trailing) {
            Image(systemName: "moon.stars.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.08)
                .offset(x: 20)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title & Device chip
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text("SLEEP STUDIO")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 9))
                    Text(entry.snapshot.sourceDevice)
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.white.opacity(0.1)))

                Text(entry.snapshot.sleepQualityRating)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(WidgetColors.accentCyan.opacity(0.18))
                    .clipShape(Capsule())
            }

            // Top Hero Row: Score Radial Gauge on Left, Primary Stats on Right
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 9)

                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(entry.snapshot.sleepScore, 0), 100)) / 100.0)
                        .stroke(
                            AngularGradient(
                                colors: [WidgetColors.accentCyan, WidgetColors.accentBlue, WidgetColors.accentPurple],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 1) {
                        Text("\(entry.snapshot.sleepScore)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("SCORE")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(WidgetColors.accentCyan)
                    }
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.snapshot.totalAsleepFormatted)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("\(entry.snapshot.timeInBedFormatted) in bed • \(entry.snapshot.efficiencyPercent)% efficiency")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 9))
                                .foregroundColor(WidgetColors.accentPurple)
                            Text("Bed \(entry.snapshot.bedtimeFormatted)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "sun.horizon.fill")
                                .font(.system(size: 9))
                                .foregroundColor(WidgetColors.coffeeYellow)
                            Text("Wake \(entry.snapshot.wakeTimeFormatted)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            // Proportional Sleep Stage Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("STAGE ARCHITECTURE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                    Text("\(entry.snapshot.restorativePercent)% Restorative")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                stageProportionalBar(height: 10)
            }

            // 4-Column Stage Breakdown Grid
            HStack(spacing: 6) {
                stageDetailCard(label: "Deep", duration: entry.snapshot.deepFormatted, percent: entry.snapshot.deepPercent, color: deepColor)
                stageDetailCard(label: "REM", duration: entry.snapshot.remFormatted, percent: entry.snapshot.remPercent, color: remColor)
                stageDetailCard(label: "Light", duration: entry.snapshot.lightFormatted, percent: entry.snapshot.lightPercent, color: lightColor)
                stageDetailCard(label: "Awake", duration: entry.snapshot.awakeFormatted, percent: entry.snapshot.awakePercent, color: awakeColor)
            }

            // Bottom Nocturnal Vitals Row
            HStack(spacing: 6) {
                if let rhr = entry.snapshot.restingHeartRate {
                    vitalCard(title: "RESTING HR", value: "\(Int(rhr))", unit: "bpm", icon: "heart.fill", color: WidgetColors.accentRed)
                }
                if let hrv = entry.snapshot.hrvMs {
                    vitalCard(title: "HRV SDNN", value: "\(Int(hrv))", unit: "ms", icon: "waveform.path.ecg", color: WidgetColors.accentCyan)
                }
                vitalCard(title: "RESTORATIVE", value: "\(entry.snapshot.restorativePercent)", unit: "%", icon: "sparkles", color: WidgetColors.accentPurple)
            }
        }
        .background(alignment: .trailing) {
            Image(systemName: "moon.stars.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 110)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.07)
                .offset(x: 30, y: -20)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Small (1x1) No Data
    private var smallNoDataView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Sleep icon badge on Left, SLEEP pill on Right
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 4)
                        .frame(width: 40, height: 40)
                    Circle()
                        .fill(WidgetColors.accentPurple.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                Spacer(minLength: 4)

                Text("SLEEP")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentPurple)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2.5)
                    .background(WidgetColors.accentPurple.opacity(0.18))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text("No Sleep Data")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("No sleep tracked today")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Bottom CTA pill: Open Studio
            HStack(spacing: 3) {
                Text("Open Studio")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(WidgetColors.accentCyan)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(WidgetColors.accentCyan.opacity(0.14))
                    .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.25), lineWidth: 1))
            )
        }
        .background(alignment: .trailing) {
            Image(systemName: "moon.stars.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 59)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.10)
                .offset(x: 16)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Medium (2x1) No Data
    private var mediumNoDataView: some View {
        HStack(spacing: 14) {
            // Left: Clean empty gauge circle with moon icon
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                    .frame(width: 76, height: 76)

                Circle()
                    .fill(WidgetColors.accentPurple.opacity(0.14))
                    .frame(width: 56, height: 56)

                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(WidgetColors.accentPurple)
            }

            // Right: Content and action
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 9))
                            .foregroundColor(WidgetColors.accentPurple)
                        Text("SLEEP STUDIO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentPurple)
                    }

                    Spacer()

                    Text("No Data Today")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                Text("No Sleep Tracked")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Wear your watch to bed or log sleep in Health Hub to see hypnogram stages and recovery.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text("Open Sleep Studio")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(WidgetColors.accentCyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(WidgetColors.accentCyan.opacity(0.14))
                        .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.25), lineWidth: 1))
                )
            }
        }
        .background(alignment: .trailing) {
            Image(systemName: "moon.stars.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.08)
                .offset(x: 20)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Large (2x2) No Data
    private var largeNoDataView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Title & Status
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text("SLEEP STUDIO")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                Spacer()

                Text("No Data Today")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 4)

            // Center Hero Graphic
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 8)
                        .frame(width: 80, height: 80)

                    Circle()
                        .fill(WidgetColors.accentPurple.opacity(0.14))
                        .frame(width: 60, height: 60)

                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                Text("No Sleep Session Logged")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Wear your Apple Watch to bed or log sleep in Health to view hypnogram architecture, restorative sleep, and nocturnal vitals.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 4)

            // Empty Stage Cards row (Deep, REM, Light, Awake placeholders)
            HStack(spacing: 6) {
                emptyStageCard(label: "Deep", color: deepColor)
                emptyStageCard(label: "REM", color: remColor)
                emptyStageCard(label: "Light", color: lightColor)
                emptyStageCard(label: "Awake", color: awakeColor)
            }

            // Bottom CTA button
            HStack {
                Spacer()
                HStack(spacing: 5) {
                    Text("Open Sleep Studio")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(WidgetColors.accentCyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(WidgetColors.accentCyan.opacity(0.14))
                        .overlay(Capsule().strokeBorder(WidgetColors.accentCyan.opacity(0.25), lineWidth: 1))
                )
                Spacer()
            }
        }
        .background(alignment: .trailing) {
            Image(systemName: "moon.stars.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 110)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.06)
                .offset(x: 30, y: -20)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    private func emptyStageCard(label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Circle()
                    .fill(color.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text("--")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
            Text("0%")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        )
    }

    // MARK: - Lock Screen Accessories
    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 11))
                if entry.snapshot.hasData {
                    Text("\(entry.snapshot.sleepScore)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                } else {
                    Text("--")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 10))
                Text(entry.snapshot.hasData ? "Sleep: \(entry.snapshot.totalAsleepFormatted)" : "Sleep: No Data")
                    .font(.system(size: 12, weight: .bold))
            }
            if entry.snapshot.hasData {
                Text("Score \(entry.snapshot.sleepScore) • \(entry.snapshot.efficiencyPercent)% Eff")
                    .font(.system(size: 10, weight: .medium))
                Text("\(entry.snapshot.bedtimeFormatted) - \(entry.snapshot.wakeTimeFormatted)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            } else {
                Text("No sleep tracked today")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Tap to open Sleep Studio")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 3) {
            Image(systemName: "moon.stars.fill")
            Text(entry.snapshot.hasData ? "Sleep: \(entry.snapshot.totalAsleepFormatted) (\(entry.snapshot.sleepScore))" : "Sleep: No Data")
        }
    }

    // MARK: - Component Helpers
    private func stageProportionalBar(height: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = max(1.0, entry.snapshot.deepSeconds + entry.snapshot.remSeconds + entry.snapshot.lightSeconds + entry.snapshot.awakeSeconds)

            HStack(spacing: 2) {
                if entry.snapshot.deepSeconds > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(deepColor)
                        .frame(width: max(3, CGFloat(entry.snapshot.deepSeconds / total) * w))
                }
                if entry.snapshot.remSeconds > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(remColor)
                        .frame(width: max(3, CGFloat(entry.snapshot.remSeconds / total) * w))
                }
                if entry.snapshot.lightSeconds > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(lightColor)
                        .frame(width: max(3, CGFloat(entry.snapshot.lightSeconds / total) * w))
                }
                if entry.snapshot.awakeSeconds > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(awakeColor)
                        .frame(width: max(3, CGFloat(entry.snapshot.awakeSeconds / total) * w))
                }
            }
        }
        .frame(height: height)
    }

    private func stagePill(label: String, duration: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(label.prefix(1)) \(duration)")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func stageDetailCard(label: String, duration: String, percent: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            Text(duration)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            Text("\(percent)%")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private func vitalCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(unit)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

// MARK: - Widget Configuration
public struct SleepWidget: Widget {
    public let kind: String = "com.intellidream.daily.SleepWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepTimelineProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("Sleep Studio")
        .description("Track your nocturnal sleep architecture, recovery score, and stages.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
