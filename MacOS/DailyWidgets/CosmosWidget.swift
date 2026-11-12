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
            case .systemLarge:
                largeView
            default:
                mediumView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(URL(string: "daily://cosmos"))
    }

    // =========================================================================
    // MARK: - 1. SYSTEM SMALL
    // =========================================================================
    private var smallView: some View {
        ZStack(alignment: .bottomTrailing) {
            // Subtle background watermark matching Bubbles / Smokes / Sleep / Stress small widgets
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56, weight: .black))
                .foregroundColor(WidgetColors.accentCyan.opacity(0.05))
                .offset(x: 10, y: 10)

            VStack(alignment: .leading, spacing: 5) {
                // Row 1: Header + Verdict Pill
                HStack(spacing: 4) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("COSMOS")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    Text(entry.snapshot.stargazingVerdict)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(accentColor.opacity(0.18), in: Capsule())
                }

                Spacer(minLength: 0)

                // Row 2: Score Ring + Moon Phase Hero
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 5)
                            .frame(width: 48, height: 48)

                        Circle()
                            .trim(from: 0, to: max(0.04, min(CGFloat(entry.snapshot.stargazingScore) / 100.0, 1.0)))
                            .stroke(
                                LinearGradient(
                                    colors: [accentColor, WidgetColors.accentCyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 48, height: 48)

                        VStack(spacing: 0) {
                            Text("\(entry.snapshot.stargazingScore)")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("/100")
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.fgMuted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: entry.snapshot.moonSymbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "#FDE68A"))
                            Text("\(entry.snapshot.moonIlluminationPercent)%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Text(entry.snapshot.moonPhaseName)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(entry.snapshot.bestWindowLabel)
                            .font(.system(size: 7.5, weight: .medium, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                // Row 3: Bottom Bar (Visible Planets + Bortle Class)
                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        Image(systemName: "globe")
                            .font(.system(size: 7.5))
                            .foregroundColor(WidgetColors.accentAmber)
                        Text("\(entry.snapshot.visiblePlanetsCount) planets up")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    Text("B\(entry.snapshot.bortleClass)")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(WidgetColors.accentCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(WidgetColors.accentCyan.opacity(0.15), in: Capsule())
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
            // Left Column: Observatory Score Ring + Verdict + Moon Phase
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4.5) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("OBSERVATORY")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 5.5)
                            .frame(width: 52, height: 52)
                        Circle()
                            .trim(from: 0, to: max(0.04, min(CGFloat(entry.snapshot.stargazingScore) / 100.0, 1.0)))
                            .stroke(
                                LinearGradient(
                                    colors: [accentColor, WidgetColors.accentCyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 52, height: 52)
                        VStack(spacing: 0) {
                            Text("\(entry.snapshot.stargazingScore)")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("/100")
                                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.fgMuted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.snapshot.stargazingVerdict)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("Bortle Class \(entry.snapshot.bortleClass)")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                            .lineLimit(1)
                        Text("\(entry.snapshot.visiblePlanetsCount) planets visible")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(WidgetColors.accentAmber)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Moon Phase Card
                HStack(spacing: 5) {
                    Image(systemName: entry.snapshot.moonSymbol)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#FDE68A"))
                    Text("\(entry.snapshot.moonPhaseName) · \(entry.snapshot.moonIlluminationPercent)%")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(width: 138)
            .frame(maxHeight: .infinity)

            // Right Column: 3 Rich Telemetry Rows (Best Window, Visible Planets, ISS / Kp)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("TONIGHT'S SKY")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                    Spacer()
                    Text(entry.snapshot.provenanceBadge)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .lineLimit(1)
                }

                // 1. Best Window Tile
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(WidgetColors.accentCyan)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text("Best Observing Window")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                        Text(entry.snapshot.bestWindowLabel)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))

                // 2. Visible Planets Tile
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 9.5))
                        .foregroundColor(WidgetColors.accentAmber)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text("Visible Planets (\(entry.snapshot.visiblePlanetsCount) up)")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                        Text(entry.snapshot.topPlanetsSummary)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))

                // 3. ISS Pass & Space Weather Tile
                HStack(spacing: 6) {
                    if let iss = entry.snapshot.nextIssPassSummary {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color(hex: "#FF758F"))
                        Text(iss)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9.5))
                            .foregroundColor(WidgetColors.accentMint)
                        Text("Bortle \(entry.snapshot.bortleClass) · Dark Sky")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    if let kp = entry.snapshot.kpIndex {
                        Text(String(format: "Kp %.1f", kp))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentMint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(WidgetColors.accentMint.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text("Cosmos Observatory")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(entry.snapshot.provenanceBadge)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                    }
                }

                Spacer()

                Text(entry.snapshot.stargazingVerdict)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.18), in: Capsule())
            }

            // Row 2: Stargazing Score Ring (Left) + Lunar Phase Card (Right)
            HStack(spacing: 8) {
                // Stargazing Score Card
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 6)
                            .frame(width: 58, height: 58)
                        Circle()
                            .trim(from: 0, to: max(0.04, min(CGFloat(entry.snapshot.stargazingScore) / 100.0, 1.0)))
                            .stroke(
                                LinearGradient(
                                    colors: [accentColor, WidgetColors.accentCyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 58, height: 58)
                        VStack(spacing: 0) {
                            Text("\(entry.snapshot.stargazingScore)")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("/100")
                                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.fgMuted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SKY SCORE")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                        Text(entry.snapshot.stargazingVerdict)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                            .lineLimit(1)
                        Text("Bortle Class \(entry.snapshot.bortleClass)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Lunar Phase Card
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.snapshot.moonSymbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Color(hex: "#FDE68A"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.snapshot.moonPhaseName)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(entry.snapshot.moonIlluminationPercent)% Illuminated")
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#FDE68A"))
                                .lineLimit(1)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#FDE68A"), WidgetColors.accentAmber],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * CGFloat(entry.snapshot.moonIlluminationPercent) / 100.0))
                        }
                    }
                    .frame(height: 4.5)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Row 3: Best Window & Orbital / Space Weather Row
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(WidgetColors.accentCyan)
                        Text("OPTIMAL WINDOW")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                    Text(entry.snapshot.bestWindowLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.snapshot.nextIssPassSummary != nil ? "airplane.circle.fill" : "waveform.path.ecg")
                            .font(.system(size: 9))
                            .foregroundColor(entry.snapshot.nextIssPassSummary != nil ? Color(hex: "#FF758F") : WidgetColors.accentMint)
                        Text(entry.snapshot.nextIssPassSummary != nil ? "NEXT ISS PASS" : "SPACE WEATHER")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                    Text(entry.snapshot.nextIssPassSummary ?? (entry.snapshot.kpIndex != nil ? String(format: "Geomagnetic Kp %.1f", entry.snapshot.kpIndex!) : "Quiet Magnetosphere"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            // Row 4: Visible Planets & Ephemeris Horizon Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(WidgetColors.accentAmber)
                        Text("VISIBLE PLANETARY BODIES")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.accentAmber)
                    }
                    Spacer()
                    Text("\(entry.snapshot.visiblePlanetsCount) above horizon")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                }

                Text(entry.snapshot.topPlanetsSummary)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack {
                    Text("Bortle \(entry.snapshot.bortleClass) Sky")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Open Observatory")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(WidgetColors.accentCyan)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#061020").opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .systemLarge
        ])
    }
}
