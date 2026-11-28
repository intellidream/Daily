import WidgetKit
import SwiftUI
import AppIntents
import DailyCore

public struct TagdosEntry: TimelineEntry {
    public let date: Date
    public let snapshot: TagdosWidgetSnapshot
    public let isLoreenVeiled: Bool

    public init(date: Date, snapshot: TagdosWidgetSnapshot, isLoreenVeiled: Bool = false) {
        self.date = date
        self.snapshot = snapshot
        self.isLoreenVeiled = isLoreenVeiled
    }
}

public struct TagdosTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> TagdosEntry {
        LoreenFontRegistry.registerIfNeeded()
        return TagdosEntry(
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
        LoreenFontRegistry.registerIfNeeded()
        let snapshot = WidgetDataCoordinator.shared.fetchTagdosSnapshot()
        let veiled = GroupDefaults.shared.loadSettings().isLoreenVeilActiveForWidgets
        completion(TagdosEntry(date: Date(), snapshot: snapshot, isLoreenVeiled: veiled))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<TagdosEntry>) -> Void) {
        LoreenFontRegistry.registerIfNeeded()
        let snapshot = WidgetDataCoordinator.shared.fetchTagdosSnapshot()
        let veiled = GroupDefaults.shared.loadSettings().isLoreenVeilActiveForWidgets
        let entry = TagdosEntry(date: Date(), snapshot: snapshot, isLoreenVeiled: veiled)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

public struct TagdosWidgetView: View {
    @Environment(\.widgetFamily) var family
    public let entry: TagdosEntry

    public init(entry: TagdosEntry) {
        LoreenFontRegistry.registerIfNeeded()
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
            default:
                smallView
            }
        }
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(defaultWidgetURL)
    }

    private var defaultWidgetURL: URL? {
        if family == .systemSmall,
           let s1 = entry.snapshot.streams.first,
           let dpid = resolvedDrivingPillId(for: s1),
           !s1.id.isEmpty {
            return pillEditURL(streamId: s1.id, pillId: dpid)
        }
        return URL(string: "daily://tagdos")
    }

    private func resolvedDrivingPillId(for stream: TagdosWidgetSnapshotStream) -> String? {
        if let dpid = stream.drivingPillId, !dpid.isEmpty {
            return dpid
        }
        if let firstId = stream.pills.first(where: { !$0.isCompleted })?.id, !firstId.isEmpty {
            return firstId
        }
        return nil
    }

    private func pillEditURL(streamId: String, pillId: String) -> URL {
        if !streamId.isEmpty && !pillId.isEmpty {
            return URL(string: "daily://tagdos?streamId=\(streamId)&pillId=\(pillId)&edit=1") ?? URL(string: "daily://tagdos")!
        }
        if !streamId.isEmpty {
            return URL(string: "daily://tagdos?streamId=\(streamId)") ?? URL(string: "daily://tagdos")!
        }
        return URL(string: "daily://tagdos")!
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
                    Text("Tagdos")
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

            // Center Focus: Driving Pill Hero + Quick Actions
            VStack(alignment: .leading, spacing: 3) {
                Text("FOCUS TAG")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.45))

                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Text(driving)
                            .font(entry.isLoreenVeiled ? .loreen(size: 18) : .system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(pillColor(for: drivingType))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Image(systemName: "star.fill")
                            .font(.system(size: 7.5))
                            .foregroundColor(WidgetColors.accentAmber)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(pillColor(for: drivingType).opacity(0.15))
                            .overlay(Capsule().strokeBorder(pillColor(for: drivingType).opacity(0.35), lineWidth: 1))
                    )

                    Spacer(minLength: 0)

                    if let s1 = stream1, let dpid = resolvedDrivingPillId(for: s1) {
                        widgetQuickActionPair(streamId: s1.id, pillId: dpid, size: 22, iconSize: 9.5)
                    }
                }

                if !nextTags.isEmpty {
                    HStack(spacing: 3) {
                        Text("Next:")
                            .font(.system(size: 9.5, weight: .medium))
                        Text(nextTags)
                            .font(entry.isLoreenVeiled ? .loreen(size: 9.5) : .system(size: 9.5, weight: .medium))
                    }
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

        return HStack(spacing: 10) {
            // Left Column: Driving Hero, Active Count & Reminder
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text("Tagdos")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                    Spacer(minLength: 2)
                    Text("\(entry.snapshot.totalActivePills)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(WidgetColors.accentCyan.opacity(0.16)))
                }

                Spacer(minLength: 0)

                if let s1 = stream1, let driving = s1.drivingPillText {
                    VStack(alignment: .leading, spacing: 3) {
                        Link(destination: pillEditURL(streamId: s1.id, pillId: resolvedDrivingPillId(for: s1) ?? "")) {
                            VStack(alignment: .leading, spacing: 1.5) {
                                Text(driving)
                                    .font(entry.isLoreenVeiled ? .loreen(size: 14.5) : .system(size: 14.5, weight: .bold, design: .rounded))
                                    .foregroundColor(pillColor(for: s1.drivingPillType))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(s1.title)
                                    .font(entry.isLoreenVeiled ? .loreen(size: 8.5) : .system(size: 8.5, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(pillColor(for: s1.drivingPillType).opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(pillColor(for: s1.drivingPillType).opacity(0.3), lineWidth: 1))
                            )
                        }

                        if let dpid = resolvedDrivingPillId(for: s1) {
                            HStack(spacing: 4) {
                                widgetQuickActionPair(streamId: s1.id, pillId: dpid, size: 20, iconSize: 8.5)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                if let rem = stream1?.reminderTimeFormatted ?? entry.snapshot.nextReminderFormatted {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 8))
                        Text(rem)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(WidgetColors.accentCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WidgetColors.accentCyan.opacity(0.16))
                    .clipShape(Capsule())
                } else {
                    Text("\(entry.snapshot.streams.count) active streams")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .frame(width: 98, alignment: .leading)

            Divider().background(Color.white.opacity(0.12))

            // Right Column: Up to 3 Stream Pipelines
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.snapshot.streams.prefix(3), id: \.id) { stream in
                    widgetStreamRow(stream: stream)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .trailing) {
            Image(systemName: "checklist")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 75)
                .foregroundColor(WidgetColors.accentPurple)
                .opacity(0.05)
                .offset(x: 20)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text("TAGDOS & NOTES")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    Text("\(entry.snapshot.totalActivePills) Active Tags")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2.5)
                        .background(WidgetColors.accentCyan.opacity(0.16))
                        .clipShape(Capsule())

                    if let nextRem = entry.snapshot.nextReminderFormatted {
                        HStack(spacing: 2.5) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 7.5))
                            Text(nextRem)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(WidgetColors.accentAmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(WidgetColors.accentAmber.opacity(0.16))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 0)

            // Stack of Streams (up to 5 styled stream rows)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(entry.snapshot.streams.prefix(5), id: \.id) { stream in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Link(destination: pillEditURL(streamId: stream.id, pillId: "")) {
                                Text(stream.title)
                                    .font(entry.isLoreenVeiled ? .loreen(size: 9.5) : .system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if let rem = stream.reminderTimeFormatted {
                                HStack(spacing: 2) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 7))
                                    Text(rem)
                                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(WidgetColors.accentCyan)
                            }
                        }

                        widgetPillsRowWithQuickActions(
                            stream: stream,
                            maxPills: 6,
                            buttonSize: 16,
                            iconSize: 7.5
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    )
                }
            }

            Spacer(minLength: 0)

            // Subtle Footer
            HStack {
                Text("\(entry.snapshot.streams.count) active streams · Tap to open Tagdos & Notes")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 10.5))
                    .foregroundColor(WidgetColors.accentCyan)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Subview Helpers
    @ViewBuilder
    private func widgetQuickActionPair(streamId: String, pillId: String, size: CGFloat, iconSize: CGFloat) -> some View {
        HStack(spacing: 3.5) {
            Button(intent: CompleteTagdosPillIntent(streamId: streamId, pillId: pillId)) {
                Image(systemName: "checkmark")
                    .font(.system(size: iconSize, weight: .heavy))
                    .foregroundColor(WidgetColors.accentGreen)
                    .frame(width: size, height: size)
                    .background(
                        Circle()
                            .fill(Color(hex: "0D3026"))
                            .overlay(Circle().strokeBorder(WidgetColors.accentGreen.opacity(0.58), lineWidth: 0.9))
                            .shadow(color: WidgetColors.accentGreen.opacity(0.26), radius: 2.2, x: 0, y: 0)
                            .shadow(color: Color.black.opacity(0.25), radius: 1.8, x: 0, y: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(intent: RecycleTagdosPillIntent(streamId: streamId, pillId: pillId)) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundColor(WidgetColors.accentCyan)
                    .frame(width: size, height: size)
                    .background(
                        Circle()
                            .fill(Color(hex: "0D2B3D"))
                            .overlay(Circle().strokeBorder(WidgetColors.accentCyan.opacity(0.58), lineWidth: 0.9))
                            .shadow(color: WidgetColors.accentCyan.opacity(0.26), radius: 2.2, x: 0, y: 0)
                            .shadow(color: Color.black.opacity(0.25), radius: 1.8, x: 0, y: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func widgetStreamRow(stream: TagdosWidgetSnapshotStream) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Link(destination: pillEditURL(streamId: stream.id, pillId: "")) {
                    Text(stream.title)
                        .font(entry.isLoreenVeiled ? .loreen(size: 9) : .system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let rem = stream.reminderTimeFormatted {
                    HStack(spacing: 2) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 6.5))
                        Text(rem)
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(WidgetColors.accentCyan)
                }
            }

            widgetPillsRowWithQuickActions(
                stream: stream,
                maxPills: 5,
                buttonSize: 15,
                iconSize: 7
            )
        }
    }

    @ViewBuilder
    private func widgetPillsRowWithQuickActions(
        stream: TagdosWidgetSnapshotStream,
        maxPills: Int,
        buttonSize: CGFloat,
        iconSize: CGFloat
    ) -> some View {
        let dpid = resolvedDrivingPillId(for: stream)
        ZStack(alignment: .trailing) {
            HStack(spacing: 3.5) {
                ForEach(Array(stream.pills.prefix(maxPills).enumerated()), id: \.offset) { _, pill in
                    widgetPillBadge(pill: pill, streamId: stream.id)
                }
                if stream.activePillsCount > maxPills {
                    Text("+\(stream.activePillsCount - maxPills)")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.42))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, dpid != nil ? (buttonSize * 2 + 7) : 0)
            .clipped()

            if let dpid {
                widgetQuickActionPair(streamId: stream.id, pillId: dpid, size: buttonSize, iconSize: iconSize)
                    .padding(.vertical, 1.5)
            }
        }
    }

    @ViewBuilder
    private func widgetPillBadge(pill: TagdosWidgetSnapshotPill, streamId: String) -> some View {
        let badge = Text(pill.text)
            .font(entry.isLoreenVeiled ? .loreen(size: 8.5) : .system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundColor(pillColor(for: pill.typeRaw))
            .padding(.horizontal, 4.5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(pillColor(for: pill.typeRaw).opacity(0.14))
                    .overlay(Capsule().strokeBorder(pillColor(for: pill.typeRaw).opacity(0.28), lineWidth: 0.8))
            )

        if !pill.id.isEmpty && !streamId.isEmpty {
            Link(destination: pillEditURL(streamId: streamId, pillId: pill.id)) {
                badge
            }
        } else {
            badge
        }
    }
}

public struct TagdosWidget: Widget {
    public let kind: String = "com.intellidream.daily.TagdosWidget"

    public init() {
        LoreenFontRegistry.registerIfNeeded()
    }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TagdosTimelineProvider()) { entry in
            TagdosWidgetView(entry: entry)
        }
        .configurationDisplayName("Tagdos & Notes")
        .description("At-a-glance obfuscated mental tags and action pipelines.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge
        ])
    }
}
