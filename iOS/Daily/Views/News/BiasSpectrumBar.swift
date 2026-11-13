import SwiftUI
import DailyCore

// MARK: - Shared Perspectives Visual Palette Helpers (iOS & SimulaDuo)

public enum PerspectivesPalette {
    public static func color(for bias: MediaBias) -> Color {
        switch bias {
        case .left:
            return Color(hex: "3B82F6")
        case .leanLeft:
            return ThemeColors.accentBlue
        case .center:
            return ThemeColors.accentCyan
        case .leanRight:
            return ThemeColors.accentOrange
        case .right:
            return ThemeColors.error
        case .independentCreator:
            return ThemeColors.accentPurple
        case .unrated:
            return Color.white.opacity(0.55)
        }
    }

    public static func color(for factuality: FactualityTier) -> Color {
        switch factuality {
        case .veryHigh:
            return ThemeColors.success
        case .high:
            return Color(hex: "34D399")
        case .mixed:
            return ThemeColors.warning
        case .low:
            return ThemeColors.error
        }
    }

    public static func color(for framing: ArticleFramingTag) -> Color {
        switch framing {
        case .reporting:
            return ThemeColors.accentCyan
        case .opinion:
            return ThemeColors.accentPurple
        case .investigation:
            return ThemeColors.success
        case .sensational:
            return ThemeColors.warning
        }
    }

    public static func color(for blindspot: BlindspotType) -> Color {
        switch blindspot {
        case .none:
            return .clear
        case .lowLeftCoverage:
            return ThemeColors.accentBlue
        case .lowRightCoverage:
            return ThemeColors.accentOrange
        case .uncoveredLocally:
            return ThemeColors.accentCyan
        case .domesticOnlyFocus:
            return ThemeColors.accentPurple
        }
    }

    public static func flagEmoji(for countryCode: String) -> String {
        let code = countryCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch code {
        case "EU": return "🇪🇺"
        case "INT", "": return "🌐"
        case "UK": return "🇬🇧"
        default:
            guard code.count == 2 else { return "🌐" }
            let base: UInt32 = 127397
            var scalars = String.UnicodeScalarView()
            for scalar in code.unicodeScalars {
                if let flagScalar = UnicodeScalar(base + scalar.value) {
                    scalars.append(flagScalar)
                }
            }
            let str = String(scalars)
            return str.isEmpty ? "🌐" : str
        }
    }
}

// MARK: - Variant A: Sleek Minimal Outlet Micro-Badge

public struct OutletMicroBadge: View {
    public let profile: MediaOutletProfile
    public let framing: ArticleFramingTag
    public var compact: Bool = false
    public var onTap: (() -> Void)? = nil

    public init(
        profile: MediaOutletProfile,
        framing: ArticleFramingTag = .reporting,
        compact: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.profile = profile
        self.framing = framing
        self.compact = compact
        self.onTap = onTap
    }

    private var biasLabel: String {
        if compact {
            return profile.bias.shortCode
        }
        switch profile.bias {
        case .independentCreator: return "Independent"
        case .unrated: return profile.countryCode == "INT" ? "Source" : profile.countryCode
        default: return profile.bias.displayName
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Button {
                onTap?()
            } label: {
                HStack(spacing: 3.5) {
                    Circle()
                        .fill(PerspectivesPalette.color(for: profile.bias))
                        .frame(width: 6, height: 6)

                    Text(biasLabel)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.88))

                    if profile.bias != .unrated {
                        Text("·")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))

                        Text(compact ? compactFactuality(profile.factuality) : profile.factuality.displayName)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(PerspectivesPalette.color(for: profile.factuality))
                    }
                }
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule()
                                .strokeBorder(PerspectivesPalette.color(for: profile.bias).opacity(0.28), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)

            if let framingLabel = framing.badgeLabel {
                let fColor = PerspectivesPalette.color(for: framing)
                Text(framingLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(fColor)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(fColor.opacity(0.13))
                            .overlay(Capsule().strokeBorder(fColor.opacity(0.30), lineWidth: 0.8))
                    )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func compactFactuality(_ tier: FactualityTier) -> String {
        switch tier {
        case .veryHigh: return "V.High"
        case .high: return "High"
        case .mixed: return "Mixed"
        case .low: return "Low"
        }
    }
}

// MARK: - Ground News–Style Segmented Bias Spectrum Bar

public struct BiasSpectrumBar: View {
    public let cluster: StoryCluster
    public var showActionPill: Bool = true
    public var onTapPerspectives: (() -> Void)? = nil

    public init(
        cluster: StoryCluster,
        showActionPill: Bool = true,
        onTapPerspectives: (() -> Void)? = nil
    ) {
        self.cluster = cluster
        self.showActionPill = showActionPill
        self.onTapPerspectives = onTapPerspectives
    }

    private var dist: BiasDistribution { cluster.distribution }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                let totalW = max(geo.size.width, 1)
                let rated = dist.ratedPoliticalCount
                HStack(spacing: 2) {
                    if rated > 0 {
                        if dist.leftCount > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "3B82F6"), ThemeColors.accentBlue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, totalW * dist.leftFraction))
                        }
                        if dist.centerCount > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [ThemeColors.accentCyan.opacity(0.95), Color.white.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, totalW * dist.centerFraction))
                        }
                        if dist.rightCount > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [ThemeColors.accentOrange, ThemeColors.error],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, totalW * dist.rightFraction))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [ThemeColors.accentPurple, ThemeColors.accentCyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())
            .background(Capsule().fill(Color.white.opacity(0.08)))

            HStack(spacing: 6) {
                if dist.ratedPoliticalCount > 0 {
                    HStack(spacing: 5) {
                        spectrumStat(label: "L", pct: dist.leftPercentInt, color: ThemeColors.accentBlue, active: dist.leftCount > 0)
                        spectrumStat(label: "C", pct: dist.centerPercentInt, color: ThemeColors.accentCyan, active: dist.centerCount > 0)
                        spectrumStat(label: "R", pct: dist.rightPercentInt, color: ThemeColors.accentOrange, active: dist.rightCount > 0)
                    }
                } else if dist.independentCount > 0 {
                    Text("\(dist.independentCount) Indep.")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)
                }

                if cluster.blindspot.isBlindspot {
                    let bColor = PerspectivesPalette.color(for: cluster.blindspot)
                    HStack(spacing: 3) {
                        Image(systemName: "eye.trianglebadge.exclamationmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Blindspot")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(bColor)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(bColor.opacity(0.14))
                            .overlay(Capsule().strokeBorder(bColor.opacity(0.35), lineWidth: 0.8))
                    )
                }

                Spacer(minLength: 2)

                if showActionPill {
                    Button {
                        onTapPerspectives?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "scale.3d")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("\(cluster.uniqueOutletCount) sources • Perspectives")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(ThemeColors.accentCyan.opacity(0.12))
                                .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.30), lineWidth: 0.9))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
    }

    private func spectrumStat(label: String, pct: Int, color: Color, active: Bool) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(active ? color : .white.opacity(0.35))
            Text("\(pct)%")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(active ? .white.opacity(0.85) : .white.opacity(0.35))
        }
    }
}

// MARK: - Header Tricolor Media Diet Ring Button

public struct MediaDietHeaderButton: View {
    public let snapshot: MediaDietSnapshot
    public let action: () -> Void

    public init(snapshot: MediaDietSnapshot, action: @escaping () -> Void) {
        self.snapshot = snapshot
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))

                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                ThemeColors.accentBlue,
                                ThemeColors.accentCyan,
                                ThemeColors.accentOrange,
                                ThemeColors.accentPurple,
                                ThemeColors.accentBlue
                            ],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .padding(1)

                Image(systemName: "scale.3d")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dedicated Story Cluster Card (Perspectives & Blindspots Sub-Tab)

public struct StoryClusterCard: View {
    public let cluster: StoryCluster
    public let onOpenLeadArticle: (NewsArticle) -> Void
    public let onOpenPerspectives: (StoryCluster) -> Void
    public var onInspectProfile: ((MediaOutletProfile) -> Void)? = nil

    public init(
        cluster: StoryCluster,
        onOpenLeadArticle: @escaping (NewsArticle) -> Void,
        onOpenPerspectives: @escaping (StoryCluster) -> Void,
        onInspectProfile: ((MediaOutletProfile) -> Void)? = nil
    ) {
        self.cluster = cluster
        self.onOpenLeadArticle = onOpenLeadArticle
        self.onOpenPerspectives = onOpenPerspectives
        self.onInspectProfile = onInspectProfile
    }

    public var body: some View {
        GlassCard(cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if cluster.blindspot.isBlindspot {
                        let bColor = PerspectivesPalette.color(for: cluster.blindspot)
                        HStack(spacing: 5) {
                            Image(systemName: "eye.trianglebadge.exclamationmark")
                                .font(.system(size: 10.5, weight: .bold))
                            Text(cluster.blindspot.badgeTitle)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundColor(bColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(bColor.opacity(0.15))
                                .overlay(Capsule().strokeBorder(bColor.opacity(0.35), lineWidth: 1))
                        )
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(cluster.uniqueOutletCount) Outlets Covering")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(ThemeColors.accentCyan.opacity(0.12))
                                .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.28), lineWidth: 1))
                        )
                    }

                    Spacer()

                    Text(cluster.leadArticle.relativeTimeFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }

                Button {
                    onOpenPerspectives(cluster)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cluster.leadArticle.title)
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)

                            if cluster.blindspot.isBlindspot {
                                Text(cluster.blindspot.explanation)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            } else if let desc = cluster.leadArticle.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }

                        Spacer(minLength: 0)

                        if let imgStr = cluster.leadArticle.imageUrl, let url = URL(string: imgStr) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable()
                                        .scaledToFill()
                                        .frame(width: 78, height: 78)
                                        .clipShape(RoundedRectangle(cornerRadius: 13))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 13)
                                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        let distinctItems = deduplicatedOutletItems(cluster.items)
                        ForEach(distinctItems.prefix(5)) { item in
                            Button {
                                onInspectProfile?(item.profile)
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(PerspectivesPalette.color(for: item.profile.bias))
                                        .frame(width: 6, height: 6)
                                    Text(item.profile.name)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if distinctItems.count > 5 {
                            Text("+\(distinctItems.count - 5) more")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .padding(.horizontal, 4)
                        }
                    }
                }

                BiasSpectrumBar(cluster: cluster, showActionPill: true) {
                    onOpenPerspectives(cluster)
                }

                HStack {
                    Button {
                        onOpenLeadArticle(cluster.leadArticle)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Read \(cluster.leadArticle.publicationName ?? "Lead Story")")
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.78))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if !cluster.anchorEntities.isEmpty {
                        Text(cluster.anchorEntities.prefix(3).joined(separator: " · "))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ThemeColors.textMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func deduplicatedOutletItems(_ items: [ClusterCoverageItem]) -> [ClusterCoverageItem] {
        var seen = Set<String>()
        var result: [ClusterCoverageItem] = []
        for item in items {
            let key = item.profile.domain.isEmpty ? item.profile.name : item.profile.domain
            if seen.insert(key).inserted {
                result.append(item)
            }
        }
        return result
    }
}
