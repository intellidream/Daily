import SwiftUI
import DailyCore

/// Multi-perspective framing comparison & cross-spectrum source explorer.
/// Designed to render seamlessly either as a 35% side-by-side split inside `NewsReaderView`
/// or as a standalone Liquid Glass modal sheet.
public struct PerspectivesComparisonPane: View {
    public let initialCluster: StoryCluster
    public var activeArticleLink: String? = nil
    public var isSplitPane: Bool = false
    public let onSelectArticle: (NewsArticle) -> Void
    public let onOpenInPrism: (NewsArticle) -> Void
    public var onClose: (() -> Void)? = nil

    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var newsService = NewsService.shared

    @State private var cluster: StoryCluster
    @State private var comparison: PerspectiveComparison?
    @State private var isExpandingSources = false
    @State private var isSynthesizing = false
    @State private var selectedFilter: SpectrumFilter = .all
    @State private var inspectedProfile: MediaOutletProfile?

    public enum SpectrumFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case left = "Left"
        case center = "Center"
        case right = "Right"
        case independent = "Indep."

        public var id: String { rawValue }
    }

    public init(
        cluster: StoryCluster,
        activeArticleLink: String? = nil,
        isSplitPane: Bool = false,
        onSelectArticle: @escaping (NewsArticle) -> Void,
        onOpenInPrism: @escaping (NewsArticle) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.initialCluster = cluster
        self.activeArticleLink = activeArticleLink
        self.isSplitPane = isSplitPane
        self.onSelectArticle = onSelectArticle
        self.onOpenInPrism = onOpenInPrism
        self.onClose = onClose
        self._cluster = State(initialValue: cluster)
    }

    private var filteredItems: [ClusterCoverageItem] {
        switch selectedFilter {
        case .all:
            return cluster.items
        case .left:
            return cluster.items.filter { $0.profile.bias.bucket == .left }
        case .center:
            return cluster.items.filter { $0.profile.bias.bucket == .center }
        case .right:
            return cluster.items.filter { $0.profile.bias.bucket == .right }
        case .independent:
            return cluster.items.filter {
                $0.profile.bias == .independentCreator || $0.profile.ownershipType.isIndependentOrNonProfit
            }
        }
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D1322"), Color(hex: "141D33")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                paneHeader

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // Story Lead & Spectrum Overview
                        VStack(alignment: .leading, spacing: 10) {
                            Text(cluster.leadArticle.title)
                                .font(.system(size: isSplitPane ? 14.5 : 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)

                            BiasSpectrumBar(cluster: cluster, showActionPill: false)
                        }

                        // Blindspot Alert Banner (when applicable)
                        if cluster.blindspot.isBlindspot {
                            blindspotBanner
                        }

                        // Multi-Perspective Synthesis Card (Gemini 2.5 Flash / Cached / Instant)
                        synthesisCard

                        // Spectrum Filter Tabs & Source List
                        sourcesSection
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
        }
        .popover(item: $inspectedProfile) { profile in
            SourceTransparencyPopover(profile: profile) {
                inspectedProfile = nil
            }
        }
        .task(id: initialCluster.id) {
            await loadExpandedPerspectives(force: false)
        }
    }

    // MARK: - Top Bar

    private var paneHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "scale.3d")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)

                Text("Perspectives")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if isExpandingSources || isSynthesizing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(ThemeColors.accentCyan)
                }
            }

            Spacer()

            Button {
                Task {
                    await loadExpandedPerspectives(force: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Refresh Cross-Spectrum Discovery & Framing Analysis")

            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.28))
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.10))
        }
    }

    // MARK: - Blindspot Callout

    private var blindspotBanner: some View {
        let bColor = PerspectivesPalette.color(for: cluster.blindspot)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(bColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(cluster.blindspot.badgeTitle)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(bColor)

                Text(cluster.blindspot.explanation)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(bColor.opacity(0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(bColor.opacity(0.32), lineWidth: 1)
                )
        )
    }

    // MARK: - Framing Synthesis Card

    private var synthesisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: comparison?.isAiGenerated == true ? "sparkles" : "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(comparison?.isAiGenerated == true ? ThemeColors.accentCyan : ThemeColors.accentPurple)

                    Text(comparison?.isAiGenerated == true ? "Gemini 2.5 Flash Synthesis" : "Instant Spectrum Synthesis")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                }

                Spacer()

                Text("\(cluster.uniqueOutletCount) outlets")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }

            if let comp = comparison {
                Text(comp.summaryText)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(.white.opacity(0.90))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !comp.commonFacts.isEmpty {
                    Divider().background(Color.white.opacity(0.08))
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Shared Facts Across Sources", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.success)

                        ForEach(Array(comp.commonFacts.enumerated()), id: \.offset) { _, fact in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundColor(ThemeColors.success)
                                    .font(.system(size: 12, weight: .bold))
                                Text(fact)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.86))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if !comp.framingDifferences.isEmpty {
                    Divider().background(Color.white.opacity(0.08))
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How Framing Differs", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)

                        ForEach(comp.framingDifferences) { diff in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(diff.perspectiveLabel)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(ThemeColors.accentCyan)
                                Text(diff.angle)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.86))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            )
                        }
                    }
                }

                if !comp.omissions.isEmpty {
                    Divider().background(Color.white.opacity(0.08))
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Omissions & Editorial Nuance", systemImage: "eye.fill")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.warning)

                        ForEach(Array(comp.omissions.enumerated()), id: \.offset) { _, note in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundColor(ThemeColors.warning)
                                    .font(.system(size: 12, weight: .bold))
                                Text(note)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.84))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
                )
        )
    }

    // MARK: - Filterable Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SpectrumFilter.allCases) { filter in
                        let isSelected = selectedFilter == filter
                        let count = countForFilter(filter)
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(filter.rawValue)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .opacity(0.75)
                            }
                            .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isSelected ? ThemeColors.accentCyan.opacity(0.24) : Color.white.opacity(0.06))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(isSelected ? ThemeColors.accentCyan.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if filteredItems.isEmpty {
                Text("No outlets in this spectrum segment for this story yet.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        sourceRow(item)
                    }
                }
            }
        }
    }

    private func sourceRow(_ item: ClusterCoverageItem) -> some View {
        let isCurrent = activeArticleLink == item.article.link
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(PerspectivesPalette.flagEmoji(for: item.profile.countryCode))
                    .font(.system(size: 12))

                Text(item.profile.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                    .lineLimit(1)

                OutletMicroBadge(profile: item.profile, framing: item.framing, compact: true) {
                    inspectedProfile = item.profile
                }

                Spacer(minLength: 2)

                // Open directly in Prism Web Studio
                Button {
                    onOpenInPrism(item.article)
                } label: {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan.opacity(0.9))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(ThemeColors.accentCyan.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Open in Prism Studio")
            }

            Button {
                onSelectArticle(item.article)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.article.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    HStack(spacing: 6) {
                        Text(item.article.relativeTimeFormatted)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)

                        if item.isExternalDiscovery {
                            Text("• Cross-Spectrum Discovery")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(ThemeColors.accentPurple.opacity(0.9))
                        }

                        if isCurrent {
                            Text("• Reading Now")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.success)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isCurrent ? ThemeColors.accentCyan.opacity(0.10) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            isCurrent ? ThemeColors.accentCyan.opacity(0.45) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
    }

    private func countForFilter(_ filter: SpectrumFilter) -> Int {
        switch filter {
        case .all: return cluster.items.count
        case .left: return cluster.items.filter { $0.profile.bias.bucket == .left }.count
        case .center: return cluster.items.filter { $0.profile.bias.bucket == .center }.count
        case .right: return cluster.items.filter { $0.profile.bias.bucket == .right }.count
        case .independent:
            return cluster.items.filter {
                $0.profile.bias == .independentCreator || $0.profile.ownershipType.isIndependentOrNonProfit
            }.count
        }
    }

    // MARK: - On-Demand Expansion + Synthesis Pipeline

    private func loadExpandedPerspectives(force: Bool) async {
        // 1. Instant zero-latency deterministic synthesis from existing cluster
        let isRo = StoryClusterEngine.detectRomanian(
            text: "\(cluster.leadArticle.title) \(cluster.leadArticle.description ?? "")",
            url: cluster.leadArticle.link
        )
        if comparison == nil {
            comparison = NewsPerspectiveService.shared.buildDeterministicComparison(for: cluster, isRomanian: isRo)
        }

        // 2. Expand cross-spectrum sources on-demand via Google News RSS Search + GDELT fallback
        isExpandingSources = true
        let expanded = await NewsPerspectiveService.shared.expandCoverage(for: cluster, force: force)
        cluster = expanded
        newsService.updateCluster(expanded)
        isExpandingSources = false

        // Update deterministic snapshot immediately with newly discovered outlets
        if comparison?.isAiGenerated != true || force {
            comparison = NewsPerspectiveService.shared.buildDeterministicComparison(for: expanded, isRomanian: isRo)
        }

        // 3. Upgrade to cached or fresh Gemini 2.5 Flash framing synthesis
        isSynthesizing = true
        let rich = await NewsPerspectiveService.shared.comparePerspectives(
            for: expanded,
            apiKey: settingsService.settings.geminiApiKey,
            forceRefresh: force
        )
        comparison = rich
        isSynthesizing = false
    }
}
