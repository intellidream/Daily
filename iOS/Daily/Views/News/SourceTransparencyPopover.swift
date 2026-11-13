import SwiftUI
import DailyCore

/// Rich Liquid Glass Source Transparency card displaying an outlet's 5-step political bias,
/// European/Romanian editorial context, factuality record, and ownership/funding structure.
public struct SourceTransparencyPopover: View {
    public let profile: MediaOutletProfile
    public var onClose: (() -> Void)? = nil

    public init(profile: MediaOutletProfile, onClose: (() -> Void)? = nil) {
        self.profile = profile
        self.onClose = onClose
    }

    private let fiveSteps: [MediaBias] = [.left, .leanLeft, .center, .leanRight, .right]

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [ThemeColors.bgStop1, ThemeColors.bgStop2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Header: Flag, Publication Name, Domain & Close
                    HStack(alignment: .top, spacing: 12) {
                        Text(PerspectivesPalette.flagEmoji(for: profile.countryCode))
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(profile.name)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text(profile.countryCode)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(ThemeColors.accentCyan)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(ThemeColors.accentCyan.opacity(0.14)))
                            }

                            Text(profile.domain)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }

                        Spacer()

                        if let onClose = onClose {
                            Button(action: onClose) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider().background(Color.white.opacity(0.10))

                    // Section 1: Political & Editorial Positioning
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("Editorial Positioning", systemImage: "scale.3d")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Spacer()
                            Text(profile.bias.displayName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(PerspectivesPalette.color(for: profile.bias))
                        }

                        if fiveSteps.contains(profile.bias) {
                            HStack(spacing: 4) {
                                ForEach(fiveSteps, id: \.self) { step in
                                    let isActive = step == profile.bias
                                    let c = PerspectivesPalette.color(for: step)
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(isActive ? c : Color.white.opacity(0.08))
                                            .frame(height: isActive ? 10 : 6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .strokeBorder(isActive ? Color.white.opacity(0.75) : Color.clear, lineWidth: 1)
                                            )
                                        Text(step.shortCode)
                                            .font(.system(size: 9.5, weight: isActive ? .bold : .medium, design: .rounded))
                                            .foregroundColor(isActive ? .white : .white.opacity(0.42))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        } else {
                            let c = PerspectivesPalette.color(for: profile.bias)
                            HStack(spacing: 6) {
                                Image(systemName: profile.bias == .independentCreator ? "person.crop.circle.badge.checkmark" : "globe")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(profile.bias == .independentCreator ? "Independent Author / Creator Platform" : "Uncatalogued Specialist Outlet")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(c)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(c.opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(c.opacity(0.30), lineWidth: 1))
                            )
                        }

                        if !profile.biasContext.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(ThemeColors.accentCyan)
                                Text("Context: \(profile.biasContext)")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                            )
                        }
                    }

                    // Section 2: Factuality & Ownership Grid
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Factuality", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)

                            Text(profile.factuality.displayName)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(PerspectivesPalette.color(for: profile.factuality))

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.08))
                                    Capsule()
                                        .fill(PerspectivesPalette.color(for: profile.factuality))
                                        .frame(width: geo.size.width * profile.factuality.numericScore)
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Label("Funding Model", systemImage: "building.columns.fill")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)

                            Text(profile.ownershipType.displayName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(profile.ownershipType.isIndependentOrNonProfit ? ThemeColors.success : .white)
                                .lineLimit(1)

                            Text(profile.ownershipType.isIndependentOrNonProfit ? "Reader / Public Accountability" : "Commercial / Institutional")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(1)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        )
                    }

                    // Section 3: Owner / Publisher Entity
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OWNER / PUBLISHER")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.textMuted)

                        Text(profile.ownerLabel.isEmpty ? profile.name : profile.ownerLabel)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                    )

                    if !profile.editorialNote.isEmpty {
                        Text(profile.editorialNote)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                }
                .padding(20)
            }
        }
    }
}
