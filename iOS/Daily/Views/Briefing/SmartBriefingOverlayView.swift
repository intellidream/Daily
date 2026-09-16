import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Signature Liquid Glass modal overlay presenting the unified Smart Briefing across Morning,
/// Intra-day, Evening, and Nightly phases with Samsung-style fading text and Swift Charts metrics.
public struct SmartBriefingOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var briefingService = SmartBriefingService.shared
    @ObservedObject private var authService = AuthService.shared

    @State private var record: SmartBriefingRecord? = nil
    @State private var isRefreshing: Bool = false
    @State private var showingStructuredDetails: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // 1. Ambient Dynamic Aurora Gradient Background
            auroraBackdrop
                .ignoresSafeArea()

            // 2. Main Scrollable Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Top Navigation Action Bar
                    navigationActionBar

                    // Hero Slot Title & Greeting
                    heroHeaderSection

                    if briefingService.isLoading || record == nil {
                        loadingShimmerView
                    } else if let rec = record {
                        // Narrative Section with Samsung Galaxy AI Fading Typography
                        narrativeGlassCard(for: rec)

                        // Visual Mini-Charts & Telemetry Gauges
                        metricsVisualCardsSection(for: rec.metrics)

                        // Structured Hub Details Accordion
                        structuredSectionsAccordion(for: rec.narrative)
                    }

                    // Bottom Dismiss Action Button
                    bottomDoneButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .task {
            if let cached = briefingService.activeBriefing {
                self.record = cached
            } else {
                let rec = await briefingService.getOrGenerateBriefing()
                self.record = rec
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationActionBar: some View {
        HStack {
            // Refresh Button
            Button {
                triggerHaptic()
                Task {
                    isRefreshing = true
                    let refreshed = await briefingService.getOrGenerateBriefing(forceRefresh: true)
                    self.record = refreshed
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
            }
            .buttonStyle(.plain)

            Spacer()

            // Engine Status Pill
            if let rec = record {
                HStack(spacing: 5) {
                    Image(systemName: rec.isAiGenerated ? "sparkles" : "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(rec.isAiGenerated ? ThemeColors.accentCyan : ThemeColors.accentBlue)

                    Text(rec.isAiGenerated ? "Gemini Flash AI" : "Instant Synthesis")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                        .overlay(
                            Capsule()
                                .stroke(rec.isAiGenerated ? ThemeColors.accentCyan.opacity(0.4) : Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
            }

            Spacer()

            // Close Button
            Button {
                triggerHaptic()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Hero Header Section

    private var heroHeaderSection: some View {
        let slot = record?.slot ?? BriefingTimeSlot.current()
        let firstName = authService.currentUser?.firstName ?? "Friend"

        return VStack(spacing: 8) {
            // Time Slot Badge
            HStack(spacing: 6) {
                Image(systemName: slot.systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)

                Text(slot.displayName.uppercased())
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                    .tracking(0.8)

                Text("•")
                    .foregroundColor(ThemeColors.textMuted)

                Text(slot.timeRangeString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(ThemeColors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(ThemeColors.accentCyan.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(ThemeColors.accentCyan.opacity(0.3), lineWidth: 0.8)
            )

            // Greeting
            Text("\(slot.greetingPrefix), \(firstName)!")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 2)
        }
        .padding(.top, 6)
    }

    // MARK: - Narrative Card (Samsung Fading Typewriter Text)

    private func narrativeGlassCard(for rec: SmartBriefingRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Daily Intelligence", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)

                Spacer()

                if let date = briefingService.lastGeneratedAt {
                    Text(Self.timeFormatter.string(from: date))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(ThemeColors.textMuted)
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Progressive Word-by-Word Reveal with smooth opacity & glow
            FadingTypewriterText(
                fullText: rec.narrative.fullConcatenatedText,
                wordIntervalMs: 38
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "0A1124").opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), ThemeColors.accentCyan.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
    }

    // MARK: - Mini-Charts & Visual Telemetry Section

    private func metricsVisualCardsSection(for metrics: SmartBriefingMetrics) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 1. Recovery & Sleep Mini Card
                sleepRecoveryCard(metrics: metrics)

                // 2. Habits & Hydration Mini Card
                habitsMiniCard(metrics: metrics)
            }

            HStack(spacing: 12) {
                // 3. Finance Mini Card
                financeMiniCard(metrics: metrics)

                // 4. TagDoS Mental Streams Mini Card
                tagdosMiniCard(metrics: metrics)
            }
        }
    }

    // Sleep Recovery Card
    private func sleepRecoveryCard(metrics: SmartBriefingMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(ThemeColors.accentPurple)
                    .font(.system(size: 14))
                Text("Recovery")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                if let score = metrics.sleepScore {
                    Text("\(score)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(score >= 80 ? ThemeColors.success : ThemeColors.warning)
                }
            }

            // Progress bar
            let scoreProgress = Double(metrics.sleepScore ?? 75) / 100.0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [ThemeColors.accentPurple, ThemeColors.accentCyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(min(max(scoreProgress, 0.05), 1.0)), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                if let hrs = metrics.sleepDurationHours {
                    Text(String(format: "%.1fh sleep", hrs))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(ThemeColors.textSecondary)
                }
                Spacer()
                Text("\(metrics.totalStepsToday) steps")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(ThemeColors.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "080F1E").opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // Habits & Hydration Card (with smoking reduction support)
    private func habitsMiniCard(metrics: SmartBriefingMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundColor(ThemeColors.accentCyan)
                    .font(.system(size: 14))
                Text("Habits")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                let waterLiters = String(format: "%.1fL", metrics.waterMlToday / 1000.0)
                Text(waterLiters)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
            }

            // Water Progress bar
            let waterProgress = metrics.waterGoalMl > 0 ? min(metrics.waterMlToday / metrics.waterGoalMl, 1.0) : 0.0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [ThemeColors.accentCyan, ThemeColors.accentBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(max(waterProgress, 0.05)), height: 6)
                }
            }
            .frame(height: 6)

            // Smoking reduction status
            HStack {
                Image(systemName: "smoke.fill")
                    .font(.system(size: 10))
                    .foregroundColor(metrics.smokesToday <= metrics.smokesBaseline ? ThemeColors.success : ThemeColors.warning)

                Text("\(metrics.smokesToday) / \(metrics.smokesBaseline) baseline")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(metrics.smokesToday <= metrics.smokesBaseline ? ThemeColors.success : ThemeColors.warning)

                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "080F1E").opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // Finance Mini Card
    private func financeMiniCard(metrics: SmartBriefingMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(ThemeColors.success)
                    .font(.system(size: 13))
                Text("Finance")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }

            Text(String(format: "$%.0f", metrics.netWorth))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            let sign = metrics.daySpend >= 0 ? "+" : ""
            Text("\(sign)$\(Int(metrics.daySpend)) flow today")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(metrics.daySpend >= 0 ? ThemeColors.success : ThemeColors.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "080F1E").opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // TagDoS Mini Card
    private func tagdosMiniCard(metrics: SmartBriefingMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(ThemeColors.warning)
                    .font(.system(size: 13))
                Text("TagDoS")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }

            Text("\(metrics.activeStreamCount) Streams")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("\(metrics.activeMemoCount) active memos")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(ThemeColors.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "080F1E").opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Structured Sections Accordion

    private func structuredSectionsAccordion(for narrative: SmartBriefingNarrative) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                triggerHaptic()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingStructuredDetails.toggle()
                }
            } label: {
                HStack {
                    Label("Hub Breakdown & Recommendations", systemImage: "list.bullet.rectangle.portrait")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Image(systemName: showingStructuredDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "080F1E").opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showingStructuredDetails {
                VStack(spacing: 10) {
                    ForEach(narrative.structuredSections, id: \.title) { section in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: section.icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(ThemeColors.accentCyan)
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text(section.text)
                                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                                    .foregroundColor(ThemeColors.textSecondary)
                                    .lineSpacing(3)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Done Button

    private var bottomDoneButton: some View {
        Button {
            triggerHaptic()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Text("Ready for the Day")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ThemeColors.accentBlue.opacity(0.7), ThemeColors.accentCyan.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1.2)
            )
            .shadow(color: ThemeColors.accentCyan.opacity(0.35), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
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

            // Ultra-thin blur material effect
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
