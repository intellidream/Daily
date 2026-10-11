import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Liquid Glass Tagdos & Notes Card on the main Dashboard.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct TagdosNotesDashboardCard: View {
    @ObservedObject private var store = TagdosStore.shared
    @ObservedObject private var settingsService = SettingsService.shared

    public let size: DashboardWidgetSize
    public let onTap: () -> Void

    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
    }

    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
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
        }
        .buttonStyle(.plain)
        .dashboardCardFrame(for: size)
    }

    // MARK: - Color Resolver
    private func pillColor(for type: TagDoPillType) -> Color {
        switch type {
        case .standard: return ThemeColors.accentCyan
        case .financial: return ThemeColors.accentGreen
        case .urgent: return ThemeColors.accentPink
        case .temporalOrMetric: return ThemeColors.accentOrange
        case .completed: return Color.white.opacity(0.35)
        }
    }

    // MARK: - Small (1x1)
    @ViewBuilder
    private var smallContent: some View {
        let stream1 = store.streams.first
        let driving = stream1?.drivingPill
        let nextPill = stream1?.activePills.dropFirst().first
        let totalActive = store.streams.reduce(0) { $0 + $1.activePills.count }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentPurple)
                    Text("Tagdos")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)
                }

                Spacer()

                if let reminder = stream1?.streamReminder {
                    Text(reminderFormatted(reminder))
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ThemeColors.accentCyan.opacity(0.18))
                        .clipShape(Capsule())
                } else {
                    Text("\(totalActive) tags")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 2)

            // Center Hero: Driving Pill
            VStack(alignment: .leading, spacing: 3) {
                Text("CURRENT FOCUS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.45))

                if let driving = driving {
                    HStack(spacing: 5) {
                        Text(driving.rawText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(pillColor(for: driving.type))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(pillColor(for: driving.type).opacity(0.15))
                            .overlay(Capsule().strokeBorder(pillColor(for: driving.type).opacity(0.35), lineWidth: 1))
                    )
                } else {
                    Text("All Done! 🎉")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentGreen)
                }

                if let next = nextPill {
                    Text("Then: \(next.rawText)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            // Footer
            HStack {
                Text("Open Hub")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
            }
        }
    }

    // MARK: - Wide (2x1)
    @ViewBuilder
    private var wideContent: some View {
        let stream1 = store.streams.first
        let stream2 = store.streams.count > 1 ? store.streams[1] : nil
        let totalActive = store.streams.reduce(0) { $0 + $1.activePills.count }

        VStack(alignment: .leading, spacing: 7) {
            // Header Row
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.accentPurple)
                    Text("Tagdos & Notes")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("\(totalActive) Active")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())

                    Text("Open Hub")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }

            // Stream 1 Pill Pipeline
            if let s1 = stream1 {
                streamRow(stream: s1, maxPills: 6)
            }

            // Stream 2 Pill Pipeline
            if let s2 = stream2 {
                streamRow(stream: s2, maxPills: 6)
            }
        }
    }

    // MARK: - Tall (1x2)
    @ViewBuilder
    private var tallContent: some View {
        let totalActive = store.streams.reduce(0) { $0 + $1.activePills.count }

        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.accentPurple)
                    Text("Tagdos")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)
                }
                Spacer()
                Text("\(totalActive) active")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
            }

            Divider().background(Color.white.opacity(0.1))

            // Stack of 3 streams
            ForEach(store.streams.prefix(3)) { stream in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(stream.displayTitle)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        if let rem = stream.streamReminder {
                            Text(reminderFormatted(rem))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                    }

                    // Pills row
                    HStack(spacing: 4) {
                        ForEach(stream.activePills.prefix(4)) { pill in
                            miniPillBadge(pill: pill)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer()

            // Quick note preview if any
            if let firstNote = store.quickNotes.first {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 9))
                        .foregroundColor(ThemeColors.accentOrange)
                    Text(firstNote.title.isEmpty ? firstNote.content : firstNote.title)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Large (2x2)
    @ViewBuilder
    private var largeContent: some View {
        let totalActive = store.streams.reduce(0) { $0 + $1.activePills.count }

        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ThemeColors.accentPurple)
                    Text("Tagdos & Notes")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("\(totalActive) Tags Active")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ThemeColors.accentCyan.opacity(0.15))
                        .clipShape(Capsule())

                    Text("Open Hub >")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Render up to 4 Streams
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.streams.prefix(4)) { stream in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(stream.displayTitle)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            if let rem = stream.streamReminder {
                                HStack(spacing: 3) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 8))
                                    Text(reminderFormatted(rem))
                                        .font(.system(size: 8.5, weight: .semibold))
                                }
                                .foregroundColor(ThemeColors.accentCyan)
                            }
                        }

                        // Horizontal flow of pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(stream.activePills.prefix(8)) { pill in
                                    interactivePillBadge(pill: pill, streamId: stream.id)
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            // Bottom Notes Strip
            if !store.quickNotes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundColor(ThemeColors.accentOrange)
                        Text("Quick Notes")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    HStack(spacing: 6) {
                        ForEach(store.quickNotes.prefix(2)) { note in
                            Text(note.title.isEmpty ? note.content : note.title)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.75))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row & Pill Helpers

    @ViewBuilder
    private func streamRow(stream: TagDoStream, maxPills: Int) -> some View {
        VStack(alignment: .leading, spacing: 2.5) {
            HStack {
                Text(stream.displayTitle)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.8))
                Spacer()
                if let rem = stream.streamReminder {
                    Text(reminderFormatted(rem))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }

            HStack(spacing: 4) {
                ForEach(stream.activePills.prefix(maxPills)) { pill in
                    miniPillBadge(pill: pill)
                }
                if stream.activePills.count > maxPills {
                    Text("+\(stream.activePills.count - maxPills)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }
        }
    }

    @ViewBuilder
    private func miniPillBadge(pill: TagDoPill) -> some View {
        Text(pill.rawText)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(pillColor(for: pill.type))
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(pillColor(for: pill.type).opacity(0.14))
                    .overlay(Capsule().strokeBorder(pillColor(for: pill.type).opacity(0.28), lineWidth: 0.8))
            )
    }

    @ViewBuilder
    private func interactivePillBadge(pill: TagDoPill, streamId: UUID) -> some View {
        HStack(spacing: 3) {
            Text(pill.rawText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(pillColor(for: pill.type))
        }
        .padding(.horizontal, 6.5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(pillColor(for: pill.type).opacity(0.16))
                .overlay(Capsule().strokeBorder(pillColor(for: pill.type).opacity(0.32), lineWidth: 1))
        )
    }

    private func reminderFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

extension TagdosNotesDashboardCard: Equatable {
    public static func == (lhs: TagdosNotesDashboardCard, rhs: TagdosNotesDashboardCard) -> Bool {
        lhs.size == rhs.size
    }
}
