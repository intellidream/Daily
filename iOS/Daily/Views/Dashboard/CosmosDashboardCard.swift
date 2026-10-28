import SwiftUI
import DailyCore

/// Liquid Glass Cosmos Card on the main Dashboard displaying real-time night sky observation telemetry,
/// stargazing quality score, live moon phase, visible planets, and satellite pass tracking.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct CosmosDashboardCard: View, Equatable {
    @ObservedObject private var cosmosVM = CosmosViewModel.shared
    @ObservedObject private var cosmosLive = CosmosLiveService.shared
    @ObservedObject private var weatherService = WeatherService.shared

    public let size: DashboardWidgetSize
    private let onTap: () -> Void

    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
    }

    public static func == (lhs: CosmosDashboardCard, rhs: CosmosDashboardCard) -> Bool {
        lhs.size == rhs.size
    }

    public var body: some View {
        Button(action: onTap) {
            GlassCard(cornerRadius: 20, padding: size == .small ? 14 : 18) {
                switch size {
                case .small:
                    smallContent
                case .wide:
                    wideContent
                case .tall:
                    tallContent
                case .large:
                    largeContent
                }
            }
            .dashboardCardFrame(for: size)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Small (1x1) Compact Glance
    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ThemeColors.accentCyan, ThemeColors.accentBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Spacer()

                // Stargazing Score Badge
                HStack(spacing: 3) {
                    Circle()
                        .fill(scoreColor(cosmosVM.stargazingScore))
                        .frame(width: 6, height: 6)
                    Text("\(cosmosVM.stargazingScore)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }

            Spacer(minLength: 2)

            // Moon phase & Illumination
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(cosmosVM.currentMoonPhase.illuminationPercent)%")
                    .font(.system(size: 34, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                Text("Moon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .padding(.bottom, 6)
            }

            Text(cosmosVM.currentMoonPhase.quarter.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(cosmosVM.stargazingVerdict)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(scoreColor(cosmosVM.stargazingScore))
                    .lineLimit(1)
                Spacer()
                if cosmosVM.visiblePlanetsCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "circle.circle.fill")
                            .font(.system(size: 7))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("\(cosmosVM.visiblePlanetsCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Wide (2x1) Standard Full Card
    @ViewBuilder
    private var wideContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card Header
            HStack {
                Label("Cosmos & Night Sky", systemImage: "moon.stars.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)

                Spacer()

                HStack(spacing: 4) {
                    Text(cosmosVM.observerLocationName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }

            HStack(alignment: .center, spacing: 16) {
                // Left Column: Stargazing Score + Verdict
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(cosmosVM.stargazingScore)")
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .foregroundColor(.white)
                        Text("/ 100")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }

                    Text(cosmosVM.stargazingVerdict)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(scoreColor(cosmosVM.stargazingScore))
                        .lineLimit(1)

                    Text("Phase: \(cosmosVM.currentMoonPhase.quarter.displayName)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 48)

                // Right Column: Mini Sky Dome / Highlight Badges
                VStack(alignment: .leading, spacing: 8) {
                    // Visible planets chip
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("\(cosmosVM.visiblePlanetsCount) Planets in sky")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Next Event / ISS Pass or Moon illumination
                    HStack(spacing: 6) {
                        Image(systemName: "satellite.fill")
                            .font(.system(size: 10))
                            .foregroundColor(ThemeColors.accentPink)
                        if let pass = cosmosLive.upcomingIssPasses.first {
                            Text("ISS \(pass.startTime.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        } else {
                            Text("Moon Illumination: \(cosmosVM.currentMoonPhase.illuminationPercent)%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Tall (1x2) Vertical Card
    @ViewBuilder
    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Cosmos", systemImage: "moon.stars.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                Text("\(cosmosVM.stargazingScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor(cosmosVM.stargazingScore))
            }

            // Big Stargazing Score
            VStack(alignment: .leading, spacing: 2) {
                Text("\(cosmosVM.stargazingScore)")
                    .font(.system(size: 42, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                Text(cosmosVM.stargazingVerdict)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(scoreColor(cosmosVM.stargazingScore))
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Moon Section
            VStack(alignment: .leading, spacing: 4) {
                Text("MOON")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Text(cosmosVM.currentMoonPhase.quarter.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(cosmosVM.currentMoonPhase.illuminationPercent)% illuminated")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }

            Spacer(minLength: 4)

            // Planets & ISS Pass
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("\(cosmosVM.visiblePlanetsCount) Planets visible")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }

                if let pass = cosmosLive.upcomingIssPasses.first {
                    HStack(spacing: 6) {
                        Image(systemName: "satellite.fill")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("ISS: \(pass.startTime.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large (2x2) Executive Card
    @ViewBuilder
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Cosmos & Night Sky Observer", systemImage: "moon.stars.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                HStack(spacing: 4) {
                    Text(cosmosVM.observerLocationName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }

            // Top Row: Big Stargazing Score + Moon Phase Card
            HStack(spacing: 16) {
                // Stargazing Index Tile
                VStack(alignment: .leading, spacing: 4) {
                    Text("STARGAZING QUALITY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(cosmosVM.stargazingScore)")
                            .font(.system(size: 46, weight: .thin, design: .rounded))
                            .foregroundColor(.white)
                        Text("/100")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }

                    Text(cosmosVM.stargazingVerdict)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(scoreColor(cosmosVM.stargazingScore))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Moon Phase Tile
                VStack(alignment: .leading, spacing: 4) {
                    Text("MOON PHASE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)

                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#FFF9E6"), Color(hex: "#FFD54F")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(cosmosVM.currentMoonPhase.quarter.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("\(cosmosVM.currentMoonPhase.illuminationPercent)% illuminated")
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // 3-Column Metrics Grid
            HStack(spacing: 10) {
                metricCell(
                    title: "PLANETS",
                    value: "\(cosmosVM.visiblePlanetsCount) Visible",
                    icon: "sparkles",
                    tint: ThemeColors.accentCyan
                )

                metricCell(
                    title: "ISS SATELLITE",
                    value: cosmosLive.upcomingIssPasses.first.map { $0.startTime.formatted(date: .omitted, time: .shortened) } ?? "--:--",
                    icon: "satellite.fill",
                    tint: ThemeColors.accentPink
                )

                metricCell(
                    title: "AURORA (KP)",
                    value: cosmosLive.spaceWeather.map { "Kp \(String(format: "%.1f", $0.kpIndex))" } ?? "Kp Quiet",
                    icon: "waveform.path.ecg",
                    tint: ThemeColors.accentGreen
                )
            }

            Spacer()

            // Footer action indicator
            HStack {
                Text("Tap to open interactive 3D Observatory")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(ThemeColors.accentCyan)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func metricCell(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return ThemeColors.accentGreen
        case 60..<80:  return ThemeColors.accentCyan
        case 40..<60:  return ThemeColors.accentOrange
        default:       return ThemeColors.accentPink
        }
    }
}
