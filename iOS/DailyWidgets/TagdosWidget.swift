import WidgetKit
import SwiftUI
import DailyCore

public struct TagdosEntry: TimelineEntry {
    public let date: Date
    public let snapshot: TagdosWidgetSnapshot

    public init(date: Date, snapshot: TagdosWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct TagdosTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> TagdosEntry {
        TagdosEntry(
            date: Date(),
            snapshot: TagdosWidgetSnapshot(
                streams: [
                    TagdosWidgetSnapshotStream(
                        id: "s1",
                        title: "Daily Ops",
                        drivingPillText: "MG",
                        drivingPillType: "standard",
                        activePillsCount: 12,
                        reminderTimeFormatted: "17:30",
                        pills: [
                            TagdosWidgetSnapshotPill(text: "MG", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "GM", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "TG", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "FSH", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "LDL", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "C$T", typeRaw: "financial", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "DUB", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "14", typeRaw: "temporalOrMetric", isCompleted: false)
                        ]
                    ),
                    TagdosWidgetSnapshotStream(
                        id: "s2",
                        title: "Work & Code",
                        drivingPillText: "WRK",
                        drivingPillType: "standard",
                        activePillsCount: 8,
                        reminderTimeFormatted: "11:00",
                        pills: [
                            TagdosWidgetSnapshotPill(text: "WRK", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "PRJ", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "REV", typeRaw: "standard", isCompleted: false),
                            TagdosWidgetSnapshotPill(text: "MET", typeRaw: "standard", isCompleted: false)
                        ]
                    )
                ],
                totalActivePills: 20,
                nextReminderFormatted: "17:30",
                lastUpdated: Date()
            )
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (TagdosEntry) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchTagdosSnapshot()
        completion(TagdosEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<TagdosEntry>) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchTagdosSnapshot()
        let entry = TagdosEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

public struct TagdosWidgetView: View {
    @Environment(\.widgetFamily) var family
    public let entry: TagdosEntry

    public init(entry: TagdosEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .systemLarge:
                largeView
            case .accessoryCircular:
                accessoryCircularView
            case .accessoryRectangular:
                accessoryRectangularView
            case .accessoryInline:
                accessoryInlineView
            default:
                smallView
            }
        }
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(URL(string: "daily://tagdos"))
    }

    // MARK: - Color Resolver
    private func pillColor(for typeRaw: String?) -> Color {
        guard let type = typeRaw else { return WidgetColors.accentCyan }
        switch type {
        case "financial": return WidgetColors.accentGreen
        case "urgent": return WidgetColors.accentPink
        case "temporalOrMetric": return WidgetColors.accentAmber
        case "completed": return Color.white.opacity(0.35)
        default: return WidgetColors.accentCyan
        }
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        let stream1 = entry.snapshot.streams.first
        let driving = stream1?.drivingPillText ?? "--"
        let drivingType = stream1?.drivingPillType
        let pills = stream1?.pills.filter { !$0.isCompleted } ?? []
        let nextTags = pills.dropFirst().prefix(2).map { $0.text }.joined(separator: " ➔ ")

        return VStack(alignment: .leading, spacing: 6) {
            // Header Row: Icon + Title on Left, Reminder on Right
            HStack(alignment: .top) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text("TAGDOS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                Spacer()

                if let rem = stream1?.reminderTimeFormatted {
                    Text(rem)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WidgetColors.accentCyan.opacity(0.18))
                        .clipShape(Capsule())
                } else {
                    Text("\(entry.snapshot.totalActivePills)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 2)

            // Center Focus: Driving Pill Hero
            VStack(alignment: .leading, spacing: 2) {
                Text("FOCUS TAG")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.45))

                HStack(spacing: 4) {
                    Text(driving)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(pillColor(for: drivingType))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(WidgetColors.accentAmber)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(pillColor(for: drivingType).opacity(0.15))
                        .overlay(Capsule().strokeBorder(pillColor(for: drivingType).opacity(0.35), lineWidth: 1))
                )

                if !nextTags.isEmpty {
                    Text("Next: \(nextTags)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            // Footer
            HStack {
                Text("\(entry.snapshot.totalActivePills) Active")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.6))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(WidgetColors.accentCyan)
            }
        }
        .background(alignment: .trailing) {
            Image(systemName: "checklist")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 59)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.08)
                .offset(x: 16)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        let stream1 = entry.snapshot.streams.first
        let stream2 = entry.snapshot.streams.count > 1 ? entry.snapshot.streams[1] : nil

        return HStack(spacing: 12) {
            // Left Column: Driving Hero & Reminder
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text("TAGDOS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                if let driving = stream1?.drivingPillText {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(driving)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(pillColor(for: stream1?.drivingPillType))
                            .lineLimit(1)
                        Text(stream1?.title ?? "Stream 1")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(pillColor(for: stream1?.drivingPillType).opacity(0.14))
                            .overlay(Capsule().strokeBorder(pillColor(for: stream1?.drivingPillType).opacity(0.3), lineWidth: 1))
                    )
                }

                Spacer(minLength: 0)

                if let rem = stream1?.reminderTimeFormatted {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 8))
                        Text(rem)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(WidgetColors.accentCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(WidgetColors.accentCyan.opacity(0.16))
                    .clipShape(Capsule())
                }
            }
            .frame(width: 104, alignment: .leading)

            Divider().background(Color.white.opacity(0.12))

            // Right Column: Stream 1 & Stream 2 Pipelines
            VStack(alignment: .leading, spacing: 6) {
                if let s1 = stream1 {
                    widgetStreamRow(stream: s1)
                }
                if let s2 = stream2 {
                    widgetStreamRow(stream: s2)
                }
            }
        }
        .background(alignment: .trailing) {
            Image(systemName: "checklist")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 75)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.06)
                .offset(x: 20)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text("TAGDOS & NOTES")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("\(entry.snapshot.totalActivePills) Active Tags")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(WidgetColors.accentCyan.opacity(0.16))
                        .clipShape(Capsule())

                    if let nextRem = entry.snapshot.nextReminderFormatted {
                        HStack(spacing: 2) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 7))
                            Text(nextRem)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(WidgetColors.accentAmber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(WidgetColors.accentAmber.opacity(0.16))
                        .clipShape(Capsule())
                    }
                }
            }

            Divider().background(Color.white.opacity(0.12))

            // Stack of Streams (up to 5)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(entry.snapshot.streams.prefix(5), id: \.id) { stream in
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack {
                            Text(stream.title)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            if let rem = stream.reminderTimeFormatted {
                                Text(rem)
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(WidgetColors.accentCyan)
                            }
                        }

                        HStack(spacing: 4) {
                            ForEach(Array(stream.pills.prefix(6).enumerated()), id: \.offset) { _, pill in
                                widgetPillBadge(pill: pill)
                            }
                            if stream.activePillsCount > 6 {
                                Text("+\(stream.activePillsCount - 6)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Subtle Footer
            HStack {
                Text("Tap to open Tagdos & Notes")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(WidgetColors.accentCyan)
            }
        }
    }

    // MARK: - Lock Screen Accessories
    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "checklist")
                    .font(.system(size: 11))
                Text("\(entry.snapshot.totalActivePills)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
    }

    private var accessoryRectangularView: some View {
        let stream1 = entry.snapshot.streams.first
        let driving = stream1?.drivingPillText ?? "--"
        let pills = stream1?.pills.dropFirst().prefix(3).map { $0.text }.joined(separator: " ➔ ") ?? ""

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 10))
                Text("Tagdos: \(driving)")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if let rem = stream1?.reminderTimeFormatted {
                    Text(rem)
                        .font(.system(size: 9, weight: .bold))
                }
            }

            if !pills.isEmpty {
                Text("Next: \(pills)")
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }

            Text("\(entry.snapshot.totalActivePills) active tags across streams")
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
        }
    }

    private var accessoryInlineView: some View {
        let stream1 = entry.snapshot.streams.first
        let driving = stream1?.drivingPillText ?? "None"
        let rem = stream1?.reminderTimeFormatted != nil ? " (\(stream1!.reminderTimeFormatted!))" : ""
        return HStack(spacing: 3) {
            Image(systemName: "checklist")
            Text("Tag: \(driving)\(rem)")
        }
    }

    // MARK: - Subview Helpers
    @ViewBuilder
    private func widgetStreamRow(stream: TagdosWidgetSnapshotStream) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stream.title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.7))

            HStack(spacing: 3.5) {
                ForEach(Array(stream.pills.prefix(4).enumerated()), id: \.offset) { _, pill in
                    widgetPillBadge(pill: pill)
                }
                if stream.activePillsCount > 4 {
                    Text("+\(stream.activePillsCount - 4)")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }
        }
    }

    @ViewBuilder
    private func widgetPillBadge(pill: TagdosWidgetSnapshotPill) -> some View {
        Text(pill.text)
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundColor(pillColor(for: pill.typeRaw))
            .padding(.horizontal, 4.5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(pillColor(for: pill.typeRaw).opacity(0.14))
                    .overlay(Capsule().strokeBorder(pillColor(for: pill.typeRaw).opacity(0.28), lineWidth: 0.8))
            )
    }
}

public struct TagdosWidget: Widget {
    public let kind: String = "com.intellidream.daily.TagdosWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TagdosTimelineProvider()) { entry in
            TagdosWidgetView(entry: entry)
        }
        .configurationDisplayName("Tagdos & Notes")
        .description("At-a-glance obfuscated mental tags and action pipelines.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
