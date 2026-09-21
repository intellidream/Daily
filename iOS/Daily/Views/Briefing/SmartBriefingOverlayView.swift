import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Signature Liquid Glass modal overlay presenting the streamlined Smart Briefing across Morning,
/// Intra-day, Evening, and Nightly phases with progressive panel fading, dynamic luminous border focus,
/// contextual metric pills, and diurnal action buttons.
public struct SmartBriefingOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var briefingService = SmartBriefingService.shared
    @ObservedObject private var authService = AuthService.shared

    @State private var record: SmartBriefingRecord? = nil
    @State private var revealedGlobalWordIndex: Int = 0
    @State private var activeCardIndex: Int = 0
    @State private var isFinished: Bool = false
    @State private var streamTask: Task<Void, Never>? = nil

    public init() {}

    public var body: some View {
        ZStack {
            // 1. Ambient Dynamic Aurora Gradient Background
            auroraBackdrop
                .ignoresSafeArea()

            // 2. Main Content
            VStack(spacing: 0) {
                // Top Navigation Action Bar with integrated Diurnal Slot Status Pill
                navigationActionBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if briefingService.isLoading || record == nil {
                    Spacer()
                    loadingShimmerView
                        .padding(.horizontal, 20)
                    Spacer()
                } else if let rec = record {
                    let items = buildCardItems(from: rec)
                    let wordsPerCard = items.map {
                        $0.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    }
                    let offsets = calculateOffsets(wordsPerCard: wordsPerCard)
                    let totalWords = wordsPerCard.reduce(0) { $0 + $1.count }

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 12) {
                                // Sequential Card Reveal: Panels fade into view as active, luminous border follows
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    if isFinished || index <= activeCardIndex {
                                        cardView(
                                            item: item,
                                            index: index,
                                            words: wordsPerCard[index],
                                            startIndex: offsets[index],
                                            totalWords: totalWords,
                                            cardCount: items.count
                                        )
                                        .id(item.id)
                                        .transition(
                                            .asymmetric(
                                                insertion: .opacity
                                                    .combined(with: .offset(y: 14))
                                                    .combined(with: .scale(scale: 0.98)),
                                                removal: .opacity
                                            )
                                        )
                                    }
                                }

                                // Tap to skip helper indicator when active
                                if !isFinished {
                                    HStack(spacing: 5) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(ThemeColors.accentCyan)

                                        Text("Tap anywhere to reveal instantly")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundColor(ThemeColors.textMuted)
                                    }
                                    .padding(.top, 4)
                                    .transition(.opacity)
                                }

                                // Contextual Diurnal Bottom Action Button (blooms in at the end)
                                if isFinished || activeCardIndex >= items.count - 1 {
                                    bottomDoneButton(for: rec.slot)
                                        .id("bottom_button")
                                        .transition(.opacity.combined(with: .offset(y: 12)))
                                        .padding(.top, 8)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 36)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            completeInstantly(totalWords: totalWords, cardCount: items.count)
                        }
                        .onChange(of: activeCardIndex) { _, newIdx in
                            if newIdx > 0 && newIdx < items.count {
                                withAnimation(.easeInOut(duration: 0.32)) {
                                    proxy.scrollTo(items[newIdx].id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: isFinished) { _, finished in
                            if finished {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo("bottom_button", anchor: .bottom)
                                }
                            }
                        }
                        .onAppear {
                            if ProcessInfo.processInfo.arguments.contains("-scrollToBottomBriefing") {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation {
                                        proxy.scrollTo("bottom_button", anchor: .bottom)
                                    }
                                }
                            } else if ProcessInfo.processInfo.arguments.contains("-scrollToTopBriefing") {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation {
                                        proxy.scrollTo(0, anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            let rec = await briefingService.getOrGenerateBriefing(forceRefresh: true)
            self.record = rec
            let items = buildCardItems(from: rec)
            print("[BriefingDebug] Card items count: \(items.count), ids: \(items.map(\.id)), weatherText: '\(rec.narrative.weatherText)'")
            startStreaming(for: items)
        }
        .onDisappear {
            briefingService.markBriefingAsRead()
            briefingService.isBriefingPresented = false
            streamTask?.cancel()
        }
    }

    // MARK: - Navigation Bar with Slot Status Pill

    private var navigationActionBar: some View {
        let slot = record?.slot ?? BriefingTimeSlot.current()
        let firstName = authService.currentUser?.firstName ?? "Mihai"

        return HStack(alignment: .center) {
            Spacer()

            // Diurnal Greeting Status Pill (Warm & Non-technical)
            HStack(spacing: 6) {
                Image(systemName: slot.systemImage)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)

                Text(slot.diurnalGreeting(for: firstName))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(hex: "080F1E").opacity(0.85))
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [ThemeColors.accentCyan.opacity(0.45), Color.white.opacity(0.18)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)

            Spacer()
        }
    }

    // MARK: - Pre-arranged Card View

    private func cardView(
        item: BriefingCardItem,
        index: Int,
        words: [String],
        startIndex: Int,
        totalWords: Int,
        cardCount: Int
    ) -> some View {
        let count = words.count
        let isCompleted = isFinished || (index < activeCardIndex) || (revealedGlobalWordIndex >= startIndex + count)
        let isCurrentlyTyping = !isFinished && (index == activeCardIndex) && (revealedGlobalWordIndex >= startIndex && revealedGlobalWordIndex < startIndex + count)

        let visibleText: String = {
            if isCompleted {
                return item.text
            } else if isCurrentlyTyping {
                let localCount = max(0, revealedGlobalWordIndex - startIndex)
                return words.prefix(localCount).joined(separator: " ")
            } else {
                return ""
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            // Card Header: Category Icon + Title + Suggestive Contextual Metric Badge
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(item.iconColor)
                    .frame(width: 26, height: 26)
                    .background(item.iconColor.opacity(0.16))
                    .clipShape(Circle())

                Text(item.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                if let badge = item.badgeText {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.badgeColor)
                            .frame(width: 4, height: 4)

                        Text(badge)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(item.badgeColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule()
                            .fill(item.badgeColor.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(item.badgeColor.opacity(0.28), lineWidth: 0.8)
                    )
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Body: Progressive Word Fading with Pre-reserved Geometry
            ZStack(alignment: .topLeading) {
                // Invisible placeholder reserving exact typography layout
                Text(item.text)
                    .font(.system(size: 14.5, weight: .regular, design: .rounded))
                    .lineSpacing(4)
                    .foregroundColor(.clear)
                    .accessibilityHidden(true)

                // Rendered animated progressive word text
                (
                    Text(visibleText)
                        .font(.system(size: 14.5, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.92))
                    +
                    Text(isCurrentlyTyping ? " ✨" : "")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                )
                .lineSpacing(4)
                .animation(.easeOut(duration: 0.12), value: revealedGlobalWordIndex)
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "080F1E").opacity(isCurrentlyTyping ? 0.88 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isCurrentlyTyping
                        ? LinearGradient(
                            colors: [
                                ThemeColors.accentCyan,
                                ThemeColors.accentBlue.opacity(0.85),
                                ThemeColors.accentCyan
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    lineWidth: isCurrentlyTyping ? 1.6 : 0.8
                )
        )
        .shadow(
            color: isCurrentlyTyping ? ThemeColors.accentCyan.opacity(0.4) : Color.black.opacity(0.16),
            radius: isCurrentlyTyping ? 12 : 6,
            x: 0,
            y: isCurrentlyTyping ? 2 : 3
        )
        .animation(.easeInOut(duration: 0.25), value: isCurrentlyTyping)
        .contentShape(Rectangle())
        .onTapGesture {
            completeInstantly(totalWords: totalWords, cardCount: cardCount)
        }
    }

    // MARK: - Contextual Diurnal Bottom Action Button

    private func bottomDoneButton(for slot: BriefingTimeSlot) -> some View {
        let wish = record?.narrative.closingWish ?? slot.defaultClosingWish
        let icon = record?.narrative.closingIcon ?? slot.defaultClosingIcon

        return Button {
            triggerHaptic()
            briefingService.markBriefingAsRead()
            briefingService.isBriefingPresented = false
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)

                Text(wish)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                ThemeColors.accentBlue.opacity(0.85),
                                ThemeColors.accentCyan.opacity(0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.6), ThemeColors.accentCyan.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: ThemeColors.accentCyan.opacity(0.35), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Streaming Animation Controller

    private func startStreaming(for items: [BriefingCardItem]) {
        streamTask?.cancel()
        revealedGlobalWordIndex = 0
        activeCardIndex = 0
        isFinished = false

        let wordsPerCard = items.map {
            $0.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        }
        let offsets = calculateOffsets(wordsPerCard: wordsPerCard)
        let total = wordsPerCard.reduce(0) { $0 + $1.count }

        guard total > 0 else {
            isFinished = true
            return
        }

        streamTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)

            for idx in 1...total {
                if Task.isCancelled { break }
                revealedGlobalWordIndex = idx

                // Check if we crossed into a subsequent card
                for (cardIdx, start) in offsets.enumerated() {
                    if idx >= start && cardIdx > activeCardIndex {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            activeCardIndex = cardIdx
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 30_000_000) // Snappy 30ms per word
            }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isFinished = true
                activeCardIndex = max(0, items.count - 1)
            }
        }
    }

    private func completeInstantly(totalWords: Int, cardCount: Int) {
        streamTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            revealedGlobalWordIndex = totalWords
            activeCardIndex = max(0, cardCount - 1)
            isFinished = true
        }
    }

    private func calculateOffsets(wordsPerCard: [[String]]) -> [Int] {
        var offsets: [Int] = []
        var running = 0
        for list in wordsPerCard {
            offsets.append(running)
            running += list.count
        }
        return offsets
    }

    // MARK: - Card Items Builder

    private func buildCardItems(from rec: SmartBriefingRecord) -> [BriefingCardItem] {
        var items: [BriefingCardItem] = []
        let n = rec.narrative
        let m = rec.metrics

        // 1. Weather
        let weatherText: String = {
            if !n.weatherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return n.weatherText
            }
            if let temp = m.weatherTemp {
                return "Conditions show \(m.weatherCondition ?? "Clear") around \(Int(round(temp)))°C in \(m.weatherCity)."
            }
            return ""
        }()

        if !weatherText.isEmpty {
            let badge: String? = m.weatherTemp != nil ? "\(Int(round(m.weatherTemp!)))° · \(m.weatherCondition ?? "Clear")" : nil
            let iconCode = m.weatherIcon ?? "01d"
            let sfSymbol = WeatherConditionHelper.sfSymbol(for: iconCode)
            let iconColor = Color(hex: WeatherConditionHelper.conditionColorHex(for: iconCode))
            items.append(
                BriefingCardItem(
                    id: "weather",
                    icon: sfSymbol,
                    iconColor: iconColor,
                    title: "Weather & Atmosphere",
                    badgeText: badge,
                    badgeColor: iconColor,
                    text: weatherText
                )
            )
        }

        // 2. Health & Sleep
        if !n.healthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let isSleepHour = rec.slot == .nightly || rec.slot == .morning
            let badge: String? = {
                if let score = m.sleepScore {
                    if let f = m.sleepDurationFormatted, !f.isEmpty, f != "--" {
                        return "\(score)% Sleep · \(f)"
                    }
                    return "\(score)% Sleep"
                } else if let hr = m.restingBpm {
                    return "\(Int(hr)) bpm Rest"
                } else if m.totalStepsToday > 0 {
                    return "\(m.totalStepsToday) steps"
                }
                return nil
            }()

            items.append(
                BriefingCardItem(
                    id: "health",
                    icon: isSleepHour ? "bed.double.fill" : "heart.fill",
                    iconColor: ThemeColors.accentPurple,
                    title: isSleepHour ? "Sleep & Recovery" : "Health & Vitals",
                    badgeText: badge,
                    badgeColor: ThemeColors.accentPurple,
                    text: n.healthText
                )
            )
        }

        // 2.5. Stress Level & Autonomic Tone (Monkey Mascot)
        if !n.stressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sScore = m.stressScore ?? 35
            let sStatus = m.stressStatus ?? "Calm"
            let badgeText = "\(sScore) · \(sStatus)"
            let statusColor = (sScore <= 25) ? Color(hex: "#00E5FF") : (sScore <= 50 ? Color(hex: "#00FFB2") : (sScore <= 75 ? Color(hex: "#FFA726") : Color(hex: "#FF5252")))

            items.append(
                BriefingCardItem(
                    id: "stress",
                    icon: "brain.head.profile",
                    iconColor: statusColor,
                    title: "Stress & Mind Balance 🐵",
                    badgeText: badgeText,
                    badgeColor: statusColor,
                    text: n.stressText
                )
            )
        }

        // 3. Habits & Balance
        if !n.habitsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let badge: String? = {
                if m.waterMlToday > 0 && m.smokesToday > 0 {
                    return "\(String(format: "%.1fL", m.waterMlToday / 1000.0)) · \(m.smokesToday) smokes"
                } else if m.waterMlToday > 0 {
                    return "\(String(format: "%.1fL", m.waterMlToday / 1000.0)) water"
                } else if m.smokesToday > 0 {
                    return "\(m.smokesToday)/\(m.smokesBaseline) smokes"
                }
                return nil
            }()

            items.append(
                BriefingCardItem(
                    id: "habits",
                    icon: "drop.fill",
                    iconColor: ThemeColors.accentBlue,
                    title: "Habits & Balance",
                    badgeText: badge,
                    badgeColor: ThemeColors.accentBlue,
                    text: n.habitsText
                )
            )
        }

        // 4. Financial Snapshot
        if !n.financeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let numFormatter = NumberFormatter()
            numFormatter.numberStyle = .decimal
            numFormatter.groupingSeparator = "."
            numFormatter.maximumFractionDigits = 0
            let formattedNet = "\(numFormatter.string(from: NSNumber(value: m.netWorth)) ?? "\(Int(m.netWorth))") Lei"

            items.append(
                BriefingCardItem(
                    id: "finances",
                    icon: "creditcard.fill",
                    iconColor: ThemeColors.success,
                    title: "Financial Snapshot",
                    badgeText: formattedNet,
                    badgeColor: ThemeColors.success,
                    text: n.financeText
                )
            )
        }

        // 5. Tagdos Focus
        if !n.tagdosText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let badge = "\(m.activeStreamCount) Streams"
            items.append(
                BriefingCardItem(
                    id: "tagdos",
                    icon: "checklist",
                    iconColor: ThemeColors.warning,
                    title: "Tagdos",
                    badgeText: badge,
                    badgeColor: ThemeColors.warning,
                    text: n.tagdosText
                )
            )
        }

        // 6. World News Headlines
        if !n.newsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(
                BriefingCardItem(
                    id: "news",
                    icon: "newspaper.fill",
                    iconColor: ThemeColors.accentCyan,
                    title: "Headlines Radar",
                    badgeText: "Daily Feed",
                    badgeColor: ThemeColors.accentCyan,
                    text: n.newsText
                )
            )
        }

        // 7. Mindful Focus / Actionable Coaching
        if !n.outroText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(
                BriefingCardItem(
                    id: "outro",
                    icon: "sparkles",
                    iconColor: ThemeColors.accentCyan,
                    title: "Mindful Focus",
                    badgeText: "Suggestion",
                    badgeColor: ThemeColors.accentCyan,
                    text: n.outroText
                )
            )
        }

        return items
    }

    // MARK: - Loading Shimmer

    private var loadingShimmerView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(ThemeColors.accentCyan)
                .scaleEffect(1.3)

            Text("Synthesizing your \(BriefingTimeSlot.current().displayName)...")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(ThemeColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "080F1E").opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Aurora Background

    private var auroraBackdrop: some View {
        let slot = record?.slot ?? BriefingTimeSlot.current()
        let colors = slot.auraGradientHex.compactMap { Color(hex: $0) }

        return ZStack {
            Color(hex: "03060C")

            RadialGradient(
                colors: [
                    (colors.first ?? ThemeColors.accentCyan).opacity(0.25),
                    (colors.count > 1 ? colors[1] : ThemeColors.accentBlue).opacity(0.12),
                    Color.clear
                ],
                center: .top,
                startRadius: 50,
                endRadius: 500
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.65)
        }
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

// MARK: - Supporting Item Model

public struct BriefingCardItem: Identifiable, Equatable {
    public let id: String
    public let icon: String
    public let iconColor: Color
    public let title: String
    public let badgeText: String?
    public let badgeColor: Color
    public let text: String

    public init(
        id: String,
        icon: String,
        iconColor: Color,
        title: String,
        badgeText: String?,
        badgeColor: Color,
        text: String
    ) {
        self.id = id
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.badgeText = badgeText
        self.badgeColor = badgeColor
        self.text = text
    }
}

