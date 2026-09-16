import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Signature Liquid Glass modal overlay presenting the streamlined Smart Briefing across Morning,
/// Intra-day, Evening, and Nightly phases with pre-arranged Samsung Galaxy AI-style progressive fading
/// typography, contextual metric pills, and diurnal action buttons.
public struct SmartBriefingOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var briefingService = SmartBriefingService.shared
    @ObservedObject private var authService = AuthService.shared

    @State private var record: SmartBriefingRecord? = nil
    @State private var isRefreshing: Bool = false
    @State private var revealedGlobalWordIndex: Int = 0
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
                                // Pre-arranged Integrated Cards with Samsung-style Fading Words
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    cardView(
                                        item: item,
                                        index: index,
                                        words: wordsPerCard[index],
                                        startIndex: offsets[index],
                                        totalWords: totalWords
                                    )
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
                                }

                                // Contextual Diurnal Bottom Action Button
                                bottomDoneButton(for: rec.slot)
                                    .id("bottom_button")
                                    .padding(.top, 8)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 36)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            completeInstantly(totalWords: totalWords)
                        }
                        .onAppear {
                            if ProcessInfo.processInfo.arguments.contains("-scrollToBottomBriefing") {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation {
                                        proxy.scrollTo("bottom_button", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            if let cached = briefingService.activeBriefing {
                self.record = cached
                startStreaming(for: buildCardItems(from: cached))
            } else {
                let rec = await briefingService.getOrGenerateBriefing()
                self.record = rec
                startStreaming(for: buildCardItems(from: rec))
            }
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }

    // MARK: - Navigation Bar with Slot Status Pill

    private var navigationActionBar: some View {
        let slot = record?.slot ?? BriefingTimeSlot.current()

        return HStack(alignment: .center) {
            // Refresh Button
            Button {
                triggerHaptic()
                Task {
                    isRefreshing = true
                    let refreshed = await briefingService.getOrGenerateBriefing(forceRefresh: true)
                    self.record = refreshed
                    startStreaming(for: buildCardItems(from: refreshed))
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
            }
            .buttonStyle(.plain)

            Spacer()

            // Diurnal Slot Status Pill (replacing "Instant Synthesis")
            HStack(spacing: 6) {
                Image(systemName: slot.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)

                Text("\(slot.displayName) · \(slot.timeRangeString)")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(
                Capsule()
                    .fill(Color(hex: "080F1E").opacity(0.82))
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

            // Close Button
            Button {
                triggerHaptic()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Pre-arranged Card View

    private func cardView(
        item: BriefingCardItem,
        index: Int,
        words: [String],
        startIndex: Int,
        totalWords: Int
    ) -> some View {
        let count = words.count
        let isCompleted = isFinished || revealedGlobalWordIndex >= startIndex + count
        let isCurrentlyTyping = !isFinished && revealedGlobalWordIndex >= startIndex && revealedGlobalWordIndex < startIndex + count

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
                        ? ThemeColors.accentCyan.opacity(0.5)
                        : Color.white.opacity(0.12),
                    lineWidth: isCurrentlyTyping ? 1.2 : 0.8
                )
        )
        .shadow(
            color: isCurrentlyTyping ? ThemeColors.accentCyan.opacity(0.15) : Color.black.opacity(0.15),
            radius: isCurrentlyTyping ? 10 : 6,
            x: 0,
            y: 3
        )
    }

    // MARK: - Contextual Diurnal Bottom Action Button

    private func bottomDoneButton(for slot: BriefingTimeSlot) -> some View {
        let firstName = authService.currentUser?.firstName ?? "Friend"
        let greeting = "\(slot.greetingPrefix), \(firstName)"
        let icon = slot.actionButtonIcon

        return Button {
            triggerHaptic()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)

                Text(greeting)
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
        isFinished = false

        let wordsPerCard = items.map {
            $0.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        }
        let total = wordsPerCard.reduce(0) { $0 + $1.count }

        guard total > 0 else {
            isFinished = true
            return
        }

        streamTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)

            for idx in 1...total {
                if Task.isCancelled { break }
                revealedGlobalWordIndex = idx
                try? await Task.sleep(nanoseconds: 32_000_000) // 32ms smooth word reveal
            }
            isFinished = true
        }
    }

    private func completeInstantly(totalWords: Int) {
        streamTask?.cancel()
        revealedGlobalWordIndex = totalWords
        isFinished = true
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
        if !n.weatherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let badge: String? = m.weatherTemp != nil ? "\(Int(round(m.weatherTemp!)))° · \(m.weatherCondition ?? "Clear")" : nil
            items.append(
                BriefingCardItem(
                    id: "weather",
                    icon: m.weatherIcon ?? "cloud.sun.fill",
                    iconColor: ThemeColors.accentCyan,
                    title: "Weather & Atmosphere",
                    badgeText: badge,
                    badgeColor: ThemeColors.accentCyan,
                    text: n.weatherText
                )
            )
        }

        // 2. Health & Sleep
        if !n.healthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let isSleepHour = rec.slot == .nightly || rec.slot == .morning
            let badge: String? = {
                if let score = m.sleepScore {
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
            let badge: String = {
                if m.daySpend != 0 {
                    return "\(m.daySpend >= 0 ? "+" : "")$\(Int(m.daySpend)) today"
                } else {
                    return String(format: "$%.0f Net", m.netWorth)
                }
            }()

            items.append(
                BriefingCardItem(
                    id: "finances",
                    icon: "creditcard.fill",
                    iconColor: ThemeColors.success,
                    title: "Financial Snapshot",
                    badgeText: badge,
                    badgeColor: ThemeColors.success,
                    text: n.financeText
                )
            )
        }

        // 5. TagDoS Focus
        if !n.tagdosText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let badge = "\(m.activeStreamCount) Streams · \(m.activeMemoCount) Memos"
            items.append(
                BriefingCardItem(
                    id: "tagdos",
                    icon: "tag.fill",
                    iconColor: ThemeColors.warning,
                    title: "TagDoS Focus",
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
}
