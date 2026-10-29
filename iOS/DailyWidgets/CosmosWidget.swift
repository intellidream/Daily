import WidgetKit
import SwiftUI
import DailyCore

public struct CosmosWidgetEntry: TimelineEntry {
    public let date: Date
    public let snapshot: CosmosWidgetSnapshot

    public init(date: Date, snapshot: CosmosWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct CosmosTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> CosmosWidgetEntry {
        CosmosWidgetEntry(date: Date(), snapshot: WidgetDataCoordinator.shared.fetchCosmosSnapshot())
    }

    public func getSnapshot(in context: Context, completion: @escaping (CosmosWidgetEntry) -> Void) {
        completion(CosmosWidgetEntry(date: Date(), snapshot: WidgetDataCoordinator.shared.fetchCosmosSnapshot()))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<CosmosWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetDataCoordinator.shared.fetchCosmosSnapshot()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [CosmosWidgetEntry(date: now, snapshot: snapshot)], policy: .after(nextUpdate)))
    }
}

public struct CosmosWidgetView: View {
    public let entry: CosmosWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var accentColor: Color {
        Color(hex: entry.snapshot.qualityHexColor)
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
        .widgetURL(URL(string: "daily://cosmos"))
    }

    // MARK: - System Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(WidgetColors.accentCyan)
                Text("COSMOS")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)
                Spacer(minLength: 2)
                Text(entry.snapshot.stargazingVerdict)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(accentColor.opacity(0.18), in: Capsule())
            }

            Spacer(minLength: 2)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(entry.snapshot.stargazingScore)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("/100")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
                Spacer()
                Image(systemName: entry.snapshot.moonSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: "#FDE68A"))
            }

            Text("\(entry.snapshot.moonPhaseName) · \(entry.snapshot.moonIlluminationPercent)%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("\(entry.snapshot.visiblePlanetsCount) planets up")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(WidgetColors.fgMuted)
                Spacer(minLength: 2)
                Text("B\(entry.snapshot.bortleClass)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(WidgetColors.accentCyan)
            }
        }
        .padding(4)
    }

    // MARK: - System Medium

    private var mediumView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("OBSERVATORY")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.snapshot.stargazingScore)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.snapshot.stargazingVerdict.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(accentColor)
                        Text("Bortle \(entry.snapshot.bortleClass)")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                }

                Spacer(minLength: 2)

                HStack(spacing: 5) {
                    Image(systemName: entry.snapshot.moonSymbol)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#FDE68A"))
                    Text("\(entry.snapshot.moonPhaseName) (\(entry.snapshot.moonIlluminationPercent)%)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TONIGHT")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                    Spacer()
                    Text(entry.snapshot.provenanceBadge)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                        .lineLimit(1)
                }

                Label {
                    Text(entry.snapshot.bestWindowLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "clock.stars.fill")
                        .font(.system(size: 10))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                Label {
                    Text(entry.snapshot.topPlanetsSummary)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundColor(WidgetColors.accentAmber)
                }

                if let iss = entry.snapshot.nextIssPassSummary {
                    Label {
                        Text(iss)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#FF758F"))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#FF758F"))
                    }
                } else if let kp = entry.snapshot.kpIndex {
                    Label {
                        Text(String(format: "Geomagnetic Kp %.1f", kp))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(WidgetColors.accentMint)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10))
                            .foregroundColor(WidgetColors.accentMint)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
    }

    // MARK: - Lock Screen Accessories

    private var accessoryCircularView: some View {
        Gauge(value: Double(entry.snapshot.stargazingScore), in: 0...100) {
            Image(systemName: entry.snapshot.moonSymbol)
        } currentValueLabel: {
            Text("\(entry.snapshot.stargazingScore)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.snapshot.moonSymbol)
                    .font(.system(size: 11, weight: .bold))
                Text("SKY \(entry.snapshot.stargazingScore)/100 · \(entry.snapshot.stargazingVerdict.uppercased())")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            Text("\(entry.snapshot.moonPhaseName) (\(entry.snapshot.moonIlluminationPercent)% lit)")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Text(entry.snapshot.nextIssPassSummary ?? entry.snapshot.topPlanetsSummary)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var accessoryInlineView: some View {
        Text("Sky \(entry.snapshot.stargazingScore)/100 · \(entry.snapshot.moonPhaseName)")
    }
}

public struct CosmosWidget: Widget {
    public let kind: String = "DailyCosmosWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CosmosTimelineProvider()) { entry in
            CosmosWidgetView(entry: entry)
        }
        .configurationDisplayName("Cosmos & Night Sky")
        .description("Live Stargazing Score, Moon phase, visible planets, and next sunlit ISS pass.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
