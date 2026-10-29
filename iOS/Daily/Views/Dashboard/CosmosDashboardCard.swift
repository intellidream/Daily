import SwiftUI
import DailyCore

/// Live Zenith Stereographic Mini Sky Dome rendered on the Dashboard card.
/// Uses the exact same 3D `SkyProjectionMatrix` (`EQJ_HOR` + camera basis) as the full 120Hz Observatory.
private struct CosmosMiniSkyDomeView: View {
    let latitude: Double
    let longitude: Double
    let diameter: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30.0)) { timeline in
            Canvas { context, size in
                let dim = min(size.width, size.height)
                let radius = dim * 0.46
                let cx = size.width * 0.5
                let cy = size.height * 0.5
                let center = CGPoint(x: cx, y: cy)
                let domeRect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)

                // 1. Deep Obsidian Sky Dome Fill
                context.fill(
                    Path(ellipseIn: domeRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.06, green: 0.10, blue: 0.22),
                            Color(red: 0.02, green: 0.03, blue: 0.08)
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )

                // Subtle zenith crosshair & 45° altitude ring
                let midRect = domeRect.insetBy(dx: radius * 0.5, dy: radius * 0.5)
                context.stroke(Path(ellipseIn: midRect), with: .color(.white.opacity(0.08)), lineWidth: 0.6)

                let proj = AstronomyService.shared.makeProjectionMatrix(
                    observerLatitudeDegrees: latitude,
                    observerLongitudeDegrees: longitude,
                    date: timeline.date,
                    cameraAzimuthDegrees: 180.0,
                    cameraAltitudeDegrees: 89.9,
                    cameraRollDegrees: 0.0,
                    fovDegrees: 180.0,
                    viewportWidth: Double(dim),
                    viewportHeight: Double(dim)
                )
                let offsetX = (size.width - dim) * 0.5
                let offsetY = (size.height - dim) * 0.5

                // 2. Bright Catalog Stars (Vmag <= 3.5) above local horizon
                let stars = CosmosCatalogService.shared.stars
                for star in stars {
                    if star.vMag > 3.5 { break }
                    let sinAlt = proj.h20 * Double(star.ux) + proj.h21 * Double(star.uy) + proj.h22 * Double(star.uz)
                    guard sinAlt > 0,
                          let p = proj.projectEQJUnitVector(
                              ux: Double(star.ux),
                              uy: Double(star.uy),
                              uz: Double(star.uz)
                          ),
                          p.isVisible else { continue }
                    let sx = CGFloat(p.x) + offsetX
                    let sy = CGFloat(p.y) + offsetY
                    let dx = sx - cx
                    let dy = sy - cy
                    guard (dx * dx + dy * dy) <= radius * radius else { continue }

                    let rgb = PackedStar.ballesterosRGB(bv: Double(star.bv))
                    let dotR = max(0.8, CGFloat(2.3 - Double(star.vMag) * 0.35))
                    let rRect = CGRect(x: sx - dotR, y: sy - dotR, width: dotR * 2, height: dotR * 2)
                    context.fill(
                        Path(ellipseIn: rRect),
                        with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b).opacity(0.9))
                    )
                }

                // 3. Solar System Bodies Above Horizon
                let obs3 = (latitude: latitude, longitude: longitude, elevation: 50.0)
                for body in [CelestialBody.moon, .mercury, .venus, .mars, .jupiter, .saturn] {
                    let b = AstronomyService.shared.coordinates(of: body, for: obs3, at: timeline.date)
                    guard b.isVisible,
                          let hp = proj.projectHorizontal(azimuthDegrees: b.azimuthDegrees, altitudeDegrees: b.altitudeDegrees),
                          hp.isVisible else { continue }
                    let bx = CGFloat(hp.x) + offsetX
                    let by = CGFloat(hp.y) + offsetY
                    let dx = bx - cx
                    let dy = by - cy
                    guard (dx * dx + dy * dy) <= radius * radius else { continue }

                    let isMoon = body == .moon
                    let orbR: CGFloat = isMoon ? 3.4 : 2.3
                    let tint: Color = isMoon
                        ? Color(hex: "#FFE082")
                        : Color(hex: body.baseColorHex)

                    let glowRect = CGRect(x: bx - orbR * 2, y: by - orbR * 2, width: orbR * 4, height: orbR * 4)
                    context.fill(Path(ellipseIn: glowRect), with: .color(tint.opacity(0.28)))
                    let coreRect = CGRect(x: bx - orbR, y: by - orbR, width: orbR * 2, height: orbR * 2)
                    context.fill(Path(ellipseIn: coreRect), with: .color(tint))
                }

                // 4. Horizon Ring & Cardinal Markers
                context.stroke(
                    Path(ellipseIn: domeRect),
                    with: .color(ThemeColors.accentCyan.opacity(0.38)),
                    lineWidth: 1.0
                )

                let cardinals: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
                for (label, az) in cardinals {
                    guard let hp = proj.projectHorizontal(azimuthDegrees: az, altitudeDegrees: 2.0),
                          hp.isVisible else { continue }
                    let lx = CGFloat(hp.x) + offsetX
                    let ly = CGFloat(hp.y) + offsetY
                    let text = Text(label)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundColor(label == "N" ? ThemeColors.accentCyan : .white.opacity(0.65))
                    context.draw(text, at: CGPoint(x: lx, y: ly))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// Liquid Glass Cosmos Card on the main Dashboard displaying real-time night sky observation telemetry,
/// a live Zenith Mini Sky Dome planisphere, stargazing quality score, moon phase, visible planets, and ISS passes.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct CosmosDashboardCard: View, Equatable {
    @ObservedObject private var cosmosVM = CosmosViewModel.shared
    @ObservedObject private var cosmosLive = CosmosLiveService.shared

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
        .task {
            await cosmosLive.refreshCosmosData(
                latitude: cosmosVM.observerLatitude,
                longitude: cosmosVM.observerLongitude
            )
        }
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

            HStack(alignment: .bottom, spacing: 6) {
                Text("\(cosmosVM.currentMoonPhase.illuminationPercent)%")
                    .font(.system(size: 32, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                Text("Moon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .padding(.bottom, 5)
            }

            Text(cosmosVM.currentMoonPhase.quarter.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(cosmosVM.stargazingVerdict)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(scoreColor(cosmosVM.stargazingScore))
                    .lineLimit(1)
                Spacer()
                if cosmosVM.visiblePlanetsCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
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

    // MARK: - Wide (2x1) Standard Full Card with Live Mini Sky Dome
    @ViewBuilder
    private var wideContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Cosmos & Night Sky", systemImage: "moon.stars.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)

                Spacer()

                HStack(spacing: 4) {
                    Text(cosmosVM.observerLocationName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                // Left: Stargazing Score + Best Dark Window / Moon
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(cosmosVM.stargazingScore)")
                            .font(.system(size: 36, weight: .light, design: .rounded))
                            .foregroundColor(.white)
                        Text("/100")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }

                    Text(cosmosVM.stargazingVerdict)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(scoreColor(cosmosVM.stargazingScore))
                        .lineLimit(1)

                    Text("\(cosmosVM.currentMoonPhase.quarter.displayName) · \(cosmosVM.currentMoonPhase.illuminationPercent)%")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center: Live Zenith Mini Sky Dome
                CosmosMiniSkyDomeView(
                    latitude: cosmosVM.observerLatitude,
                    longitude: cosmosVM.observerLongitude,
                    diameter: 76
                )

                // Right: Live Telemetry Pills
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("\(cosmosVM.visiblePlanetsCount) Planets")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 5) {
                        Image(systemName: "satellite.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(ThemeColors.accentPink)
                        if let pass = cosmosLive.upcomingIssPasses.first {
                            Text("ISS \(pass.startTime.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                        } else {
                            Text("Bortle \(cosmosVM.stargazingConditions.bortleClass)")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Cosmos", systemImage: "moon.stars.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                Text("\(cosmosVM.stargazingScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor(cosmosVM.stargazingScore))
            }

            HStack {
                Spacer()
                CosmosMiniSkyDomeView(
                    latitude: cosmosVM.observerLatitude,
                    longitude: cosmosVM.observerLongitude,
                    diameter: 104
                )
                Spacer()
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(cosmosVM.stargazingVerdict)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(scoreColor(cosmosVM.stargazingScore))
                Text("\(cosmosVM.currentMoonPhase.quarter.displayName) · \(cosmosVM.currentMoonPhase.illuminationPercent)%")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("\(cosmosVM.visiblePlanetsCount) Planets above horizon")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                if let pass = cosmosLive.upcomingIssPasses.first {
                    HStack(spacing: 5) {
                        Image(systemName: "satellite.fill")
                            .font(.system(size: 10))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("ISS: \(pass.startTime.formatted(date: .omitted, time: .shortened)) (\(Int(pass.maxAltitudeDegrees))°)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundColor(ThemeColors.accentGreen)
                        Text("Bortle \(cosmosVM.stargazingConditions.bortleClass) · NELM \(String(format: "%.1f", cosmosVM.stargazingConditions.limitingMagnitude))")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large (2x2) Executive Observatory Card
    @ViewBuilder
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cosmos & Night Sky Observatory", systemImage: "moon.stars.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                HStack(spacing: 5) {
                    Text(cosmosLive.spaceWeather?.provenance.badgeLabel ?? "OFFLINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ThemeColors.accentCyan.opacity(0.14), in: Capsule())

                    Text(cosmosVM.observerLocationName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }

            HStack(spacing: 14) {
                // Live Zenith Sky Dome
                CosmosMiniSkyDomeView(
                    latitude: cosmosVM.observerLatitude,
                    longitude: cosmosVM.observerLongitude,
                    diameter: 108
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("STARGAZING QUALITY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(cosmosVM.stargazingScore)")
                            .font(.system(size: 42, weight: .thin, design: .rounded))
                            .foregroundColor(.white)
                        Text("/100")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }

                    Text(cosmosVM.stargazingVerdict)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(scoreColor(cosmosVM.stargazingScore))

                    Text("\(cosmosVM.currentMoonPhase.quarter.displayName) · \(cosmosVM.currentMoonPhase.illuminationPercent)% Moon · Bortle \(cosmosVM.stargazingConditions.bortleClass)")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 10) {
                metricCell(
                    title: "PLANETS",
                    value: "\(cosmosVM.visiblePlanetsCount) Visible",
                    icon: "sparkles",
                    tint: ThemeColors.accentCyan
                )

                metricCell(
                    title: "ISS PASS",
                    value: cosmosLive.upcomingIssPasses.first.map {
                        "\($0.startTime.formatted(date: .omitted, time: .shortened)) (\(Int($0.maxAltitudeDegrees))°)"
                    } ?? "No Pass",
                    icon: "satellite.fill",
                    tint: ThemeColors.accentPink
                )

                metricCell(
                    title: "AURORA (KP)",
                    value: kpSummaryText,
                    icon: "waveform.path.ecg",
                    tint: ThemeColors.accentGreen
                )
            }

            Spacer(minLength: 2)

            HStack {
                if let window = cosmosVM.stargazingConditions.bestWindowDescription {
                    Text("Best dark window: \(window)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                } else {
                    Text("Open interactive 120Hz Sky Observatory")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                Spacer()
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(ThemeColors.accentCyan)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var kpSummaryText: String {
        if let kp = cosmosLive.spaceWeather?.kpIndex {
            return String(format: "Kp %.1f", kp)
        }
        return "Offline"
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
