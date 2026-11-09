import SwiftUI
import DailyCore

/// Modular Prism & Assisted Web Studio Card on the iOS & Foldable Dashboard.
public struct PrismDashboardCard: View {
    @ObservedObject private var prismStore = PrismStore.shared

    public let size: DashboardWidgetSize
    private let onTap: () -> Void

    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
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

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "safari.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                Text("\(prismStore.clips.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ThemeColors.accentCyan.opacity(0.15), in: Capsule())
            }

            Spacer(minLength: 2)

            if let latest = prismStore.clips.first {
                Text(latest.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(latest.domain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineLimit(1)
            } else {
                Text("Prism Web")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Browse & clip")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var wideContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Prism & Web Studio", systemImage: "safari.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(prismStore.clips.count) Saved")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(prismStore.pinnedSites.prefix(6)) { pin in
                        Button {
                            prismStore.requestOpenInPrism(url: pin.url, title: pin.title)
                            onTap()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(ThemeColors.accentCyan)
                                Text(pin.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let latest = prismStore.clips.first {
                HStack(spacing: 8) {
                    Image(systemName: latest.clipType.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: latest.clipType.accentHex))
                    Text(latest.clipType == .quote && !latest.contentText.isEmpty ? "\"\(latest.contentText)\"" : latest.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text(latest.domain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Prism", systemImage: "safari.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                Text("\(prismStore.clips.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(prismStore.clips.prefix(4)) { clip in
                    HStack(spacing: 8) {
                        Image(systemName: clip.clipType.iconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: clip.clipType.accentHex))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clip.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(clip.domain)
                                .font(.system(size: 10))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if prismStore.clips.isEmpty {
                Spacer()
                Text("Browse with persistent logins & clip quotes or images.")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            wideContent
            Divider().background(Color.white.opacity(0.1))
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Vault Captures")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)

                if prismStore.clips.isEmpty {
                    Text("Select text or long-press any image in Prism to capture into your Vault.")
                        .font(.system(size: 12.5))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .padding(.top, 8)
                } else {
                    ForEach(prismStore.clips.prefix(3)) { clip in
                        HStack(spacing: 10) {
                            Image(systemName: clip.clipType.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: clip.clipType.accentHex))
                                .frame(width: 26, height: 26)
                                .background(Color(hex: clip.clipType.accentHex).opacity(0.15), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(clip.contentText.isEmpty ? clip.domain : clip.contentText)
                                    .font(.system(size: 11))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension PrismDashboardCard: Equatable {
    public static func == (lhs: PrismDashboardCard, rhs: PrismDashboardCard) -> Bool {
        lhs.size == rhs.size &&
        lhs.prismStore.clips.count == rhs.prismStore.clips.count &&
        lhs.prismStore.clips.first?.id == rhs.prismStore.clips.first?.id &&
        lhs.prismStore.pinnedSites.count == rhs.prismStore.pinnedSites.count
    }
}
