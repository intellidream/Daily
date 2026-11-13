import SwiftUI
import DailyCore

/// Personal monthly "Media Diet" dashboard for iOS & SimulaDuo.
public struct MediaDietSheet: View {
    @ObservedObject private var dietStore = MediaDietStore.shared
    public let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    private var snap: MediaDietSnapshot { dietStore.currentSnapshot }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [ThemeColors.bgStop1, ThemeColors.bgStop2, ThemeColors.bgStop3],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    HStack {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(ThemeColors.accentCyan.opacity(0.16))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "scale.3d")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(ThemeColors.accentCyan)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("My Media Diet")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Monthly Reading Balance • \(snap.yearMonth)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }

                        Spacer()

                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 23))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }

                    // Summary Banner
                    GlassCard(cornerRadius: 18, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(snap.balanceSummaryLabel)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text(snap.totalArticlesRead == 0
                                 ? "Open any article in the distraction-free reader to start calibrating your monthly Media Diet."
                                 : "Based on \(snap.totalArticlesRead) unique stories read across your feeds this month.")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(ThemeColors.fgMutedDark)

                            GeometryReader { geo in
                                let w = max(geo.size.width, 1)
                                let d = snap.distribution
                                HStack(spacing: 3) {
                                    if d.ratedPoliticalCount > 0 {
                                        if d.leftCount > 0 {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(ThemeColors.accentBlue)
                                                .frame(width: max(8, w * d.leftFraction))
                                        }
                                        if d.centerCount > 0 {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(ThemeColors.accentCyan)
                                                .frame(width: max(8, w * d.centerFraction))
                                        }
                                        if d.rightCount > 0 {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(ThemeColors.accentOrange)
                                                .frame(width: max(8, w * d.rightFraction))
                                        }
                                    } else {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.14))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .frame(height: 10)
                            .clipShape(Capsule())

                            HStack {
                                dietLegendPill(title: "L", count: snap.distribution.leftCount, pct: snap.distribution.leftPercentInt, color: ThemeColors.accentBlue)
                                Spacer()
                                dietLegendPill(title: "C", count: snap.distribution.centerCount, pct: snap.distribution.centerPercentInt, color: ThemeColors.accentCyan)
                                Spacer()
                                dietLegendPill(title: "R", count: snap.distribution.rightCount, pct: snap.distribution.rightPercentInt, color: ThemeColors.accentOrange)
                                if snap.distribution.independentCount > 0 {
                                    Spacer()
                                    dietLegendPill(title: "Indep.", count: snap.distribution.independentCount, pct: nil, color: ThemeColors.accentPurple)
                                }
                            }
                        }
                    }

                    // 3 KPI Metric Tiles
                    HStack(spacing: 10) {
                        kpiTile(
                            icon: "checkmark.shield.fill",
                            title: "Factuality",
                            value: "\(snap.highFactualityPercent)%",
                            subtitle: "High / V.High",
                            accent: ThemeColors.success
                        )

                        kpiTile(
                            icon: "person.2.badge.key.fill",
                            title: "Independent",
                            value: "\(snap.independentOwnershipPercent)%",
                            subtitle: "Non-Corporate",
                            accent: ThemeColors.accentPurple
                        )

                        kpiTile(
                            icon: "eye.trianglebadge.exclamationmark",
                            title: "Blindspots",
                            value: "\(snap.blindspotsRead)",
                            subtitle: "Explored",
                            accent: ThemeColors.accentOrange
                        )
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.accentCyan.opacity(0.85))
                        Text("Private by design: computed on-device and synced as a single compact monthly counter without storing reading history URLs in the cloud.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(ThemeColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
            }
        }
        .task {
            await dietStore.syncWithSupabaseIfNeeded()
        }
    }

    private func dietLegendPill(title: String, count: Int, pct: Int?, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            if let pct = pct {
                Text("\(pct)% (\(count))")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(ThemeColors.fgMutedDark)
            } else {
                Text("(\(count))")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
        }
    }

    private func kpiTile(icon: String, title: String, value: String, subtitle: String, accent: Color) -> some View {
        GlassCard(cornerRadius: 16, padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)

                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
