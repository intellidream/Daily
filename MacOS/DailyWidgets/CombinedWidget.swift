import WidgetKit
import SwiftUI
import AppIntents
import DailyCore

// MARK: - Timeline Entry
public struct CombinedEntry: TimelineEntry {
    public let date: Date
    public let snapshot: CombinedWidgetSnapshot

    public init(date: Date, snapshot: CombinedWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

// MARK: - Timeline Provider
public struct CombinedTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> CombinedEntry {
        CombinedEntry(
            date: Date(),
            snapshot: CombinedWidgetSnapshot(
                bubbles: BubblesWidgetSnapshot(
                    todayMl: 1250,
                    goalMl: 2000,
                    progressPercent: 0.625,
                    waterMl: 1150,
                    coffeeMl: 100
                ),
                smokes: SmokesWidgetSnapshot(
                    todayTotal: 3,
                    baseline: 20,
                    cigsCount: 3,
                    heatedCount: 0
                ),
                money: MoneyWidgetSnapshot(
                    netWorthLei: 12500,
                    netWorthEUR: 2500,
                    formattedNetWorth: "12.500 Lei",
                    formattedNetWorthEUR: "~2.500 €",
                    incomingTotal: 2500,
                    outgoingTotal: 650,
                    depositsTotal: 10000,
                    cardAmount: 1500,
                    cashAmount: 1000,
                    topOutgoingAllocations: []
                ),
                sleep: SleepWidgetSnapshot(
                    hasData: true,
                    sleepScore: 88,
                    sleepQualityRating: "Restorative",
                    totalAsleepFormatted: "7h 42m",
                    asleepSeconds: 27720,
                    durationSeconds: 29800,
                    timeInBedFormatted: "8h 16m",
                    efficiencyPercent: 93,
                    deepSeconds: 5400,
                    remSeconds: 6120,
                    lightSeconds: 16200,
                    awakeSeconds: 2080,
                    deepPercent: 20,
                    remPercent: 22,
                    lightPercent: 58,
                    awakePercent: 7,
                    deepFormatted: "1h 30m",
                    remFormatted: "1h 42m",
                    lightFormatted: "4h 30m",
                    awakeFormatted: "34m",
                    bedtimeFormatted: "23:18",
                    wakeTimeFormatted: "07:34",
                    restorativePercent: 42
                ),
                tagdos: TagdosWidgetSnapshot(
                    streams: [
                        TagdosWidgetSnapshotStream(
                            id: "1",
                            title: "Stream 1",
                            drivingPillText: "Fix brief auto-open",
                            drivingPillType: "standard",
                            activePillsCount: 4,
                            reminderTimeFormatted: nil,
                            pills: [
                                TagdosWidgetSnapshotPill(text: "Fix brief auto-open", typeRaw: "standard", isCompleted: false),
                                TagdosWidgetSnapshotPill(text: "Sync widgets", typeRaw: "standard", isCompleted: false),
                                TagdosWidgetSnapshotPill(text: "Review PR", typeRaw: "standard", isCompleted: false)
                            ]
                        )
                    ],
                    totalActivePills: 4,
                    nextReminderFormatted: nil
                ),
                stress: .placeholder,
                cosmos: .placeholder,
                morningSummary: BriefingSummarySnippet(
                    greeting: "Good Morning, Mihai",
                    weatherTemp: 18.0,
                    weatherCondition: "Clear",
                    weatherIcon: "01d",
                    sleepDurationFormatted: "7h 42m",
                    sleepScore: 88,
                    topFocusText: "Focus on Fix brief auto-open & morning hydration"
                ),
                isMorningSlot: true
            )
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (CombinedEntry) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchCombinedSnapshot()
        completion(CombinedEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<CombinedEntry>) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchCombinedSnapshot()
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let entry = CombinedEntry(date: currentDate, snapshot: snapshot)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Main Combined Widget View
public struct CombinedWidgetView: View {
    public let entry: CombinedEntry
    @Environment(\.widgetFamily) var family

    private var isMorning: Bool {
        entry.snapshot.isMorningSlot
    }

    private var targetUrl: URL {
        if isMorning {
            return URL(string: "daily://summary")!
        } else {
            return URL(string: "daily://dashboard")!
        }
    }

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                if isMorning {
                    smallMorningView
                } else {
                    smallRegularView
                }
            case .systemMedium:
                if isMorning {
                    mediumMorningView
                } else {
                    mediumRegularView
                }
            case .systemLarge:
                if isMorning {
                    largeMorningView
                } else {
                    largeRegularView
                }
            default:
                mediumRegularView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(targetUrl)
        .containerBackground(WidgetColors.bgGradient, for: .widget)
    }

    // MARK: - Shared Helpers

    /// Extracts up to `limit` important distinct TagDoS focus items (driving pills first, then active pills across streams).
    private func importantTagdosItems(limit: Int = 3) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func appendIfUnique(_ raw: String?) {
            guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let key = text.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(text)
        }

        // 1. Driving pills across all streams
        for stream in entry.snapshot.tagdos.streams {
            appendIfUnique(stream.drivingPillText)
            if result.count >= limit { return result }
        }

        // 2. Remaining active pills across all streams
        for stream in entry.snapshot.tagdos.streams {
            for pill in stream.pills {
                appendIfUnique(pill.text)
                if result.count >= limit { return result }
            }
        }

        // 3. Fallback to cleaned morning focus text
        if result.isEmpty, let cleaned = cleanMorningFocusTask(
            topFocus: entry.snapshot.morningSummary?.topFocusText,
            streamDriving: nil
        ) {
            appendIfUnique(cleaned)
        }

        return result
    }

    private func cleanMorningFocusTask(topFocus: String?, streamDriving: String?) -> String? {
        if let streamDriving = streamDriving, !streamDriving.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return streamDriving
        }
        guard let raw = topFocus, !raw.isEmpty else { return nil }
        var cleaned = raw
        let prefixes = [
            "Here's what you need to focus on today:",
            "Here's what needs your focus today:",
            "Here's what needs focus today:",
            "Here's what needs your focus:",
            "Focus priority for active Tagdos pills:",
            "Focus on",
            "Focus:"
        ]
        for p in prefixes {
            if let range = cleaned.range(of: p, options: [.caseInsensitive]) {
                cleaned.removeSubrange(cleaned.startIndex..<range.upperBound)
                break
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".-: ")))
        return cleaned.isEmpty ? raw : cleaned
    }

    // =========================================================================
    // MARK: - 1. SMALL WIDGET
    // =========================================================================

    // Small - Morning Mode (With Brief)
    // Layout:
    // 1. Header: Morning + Weather
    // 2. Sleep (left) + Compact Stress with Monkey Mascot (right)
    // 3. Money line (Net Worth Lei + EUR)
    // 4. TagDoS Focus line (2-3 important TagDoS items that fit)
    // 5. Bottom 3 pills: Water, Smokes, Cosmos
    private var smallMorningView: some View {
        let stress = entry.snapshot.stress
        let hasStress = stress.hasData
        let stressColor = hasStress ? Color(hex: stress.level.hexColor) : WidgetColors.fgMuted
        let cosmos = entry.snapshot.cosmos
        let cosmosColor = Color(hex: cosmos.qualityHexColor)
        let focusItems = importantTagdosItems(limit: 3)

        return VStack(alignment: .leading, spacing: 4) {
            // Row 1: Header (Greeting + Weather)
            HStack(alignment: .center, spacing: 4) {
                HStack(spacing: 3.5) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(WidgetColors.accentAmber)
                    Text("Morning")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                if let temp = entry.snapshot.morningSummary?.weatherTemp {
                    let iconCode = entry.snapshot.morningSummary?.weatherIcon ?? "01d"
                    HStack(spacing: 2.5) {
                        Image(systemName: WeatherConditionHelper.sfSymbol(for: iconCode))
                            .font(.system(size: 9.5))
                            .foregroundColor(WidgetColors.accentCyan)
                        Text("\(Int(round(temp)))°")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }

            // Row 2: Sleep Ring & Duration (left) + Compact Stress Indicator (right)
            HStack(spacing: 5) {
                // Sleep side
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 3.0)
                            .frame(width: 28, height: 28)
                        Circle()
                            .trim(from: 0, to: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0))
                            .stroke(
                                LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 28, height: 28)
                        Text("\(entry.snapshot.sleep.sleepScore)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 0.5) {
                        Text(entry.snapshot.sleep.totalAsleepFormatted)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(entry.snapshot.sleep.sleepQualityRating)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentMint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                Spacer(minLength: 2)

                // Stress compact indicator on the right of Sleep
                HStack(spacing: 3.5) {
                    WidgetMonkeyMascotView(mood: stress.monkeyMood, size: 17)

                    VStack(alignment: .trailing, spacing: 0.5) {
                        Text(hasStress ? "\(stress.stressScore)" : "--")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(hasStress ? stress.level.displayName : "Calm")
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundColor(stressColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 5.5)
                .padding(.vertical, 3.5)
                .background(stressColor.opacity(hasStress ? 0.14 : 0.07))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            // Row 3: Money Line (above TagDoS Focus)
            HStack(spacing: 4) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 8.5))
                    .foregroundColor(WidgetColors.accentGreen)

                Text(entry.snapshot.money.formattedNetWorth)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 2)

                Text(entry.snapshot.money.formattedNetWorthEUR)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetColors.accentGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6.5)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            // Row 4: TagDoS Focus (2-3 important items that fit cleanly)
            VStack(alignment: .leading, spacing: 2.5) {
                if focusItems.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(WidgetColors.accentPurple)
                            .frame(width: 4.5, height: 4.5)
                        Text("All focus streams clear")
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                } else {
                    // Primary item + secondary items compactly arranged so 2-3 items fit
                    HStack(spacing: 3.5) {
                        ForEach(Array(focusItems.prefix(2).enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(idx == 0 ? WidgetColors.accentPurple : WidgetColors.accentCyan)
                                    .frame(width: 4, height: 4)
                                Text(item)
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                        }
                    }

                    if focusItems.count >= 3 {
                        HStack(spacing: 3.5) {
                            Circle()
                                .fill(WidgetColors.accentMint)
                                .frame(width: 4, height: 4)
                            Text(focusItems[2])
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            if entry.snapshot.tagdos.totalActivePills > 3 {
                                Text("+\(entry.snapshot.tagdos.totalActivePills - 3)")
                                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                    .foregroundColor(WidgetColors.accentPurple)
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Spacer(minLength: 0)

            // Row 5: Bottom 3 Pills (Water, Smokes, Cosmos)
            HStack(spacing: 4) {
                // 1. Water
                HStack(spacing: 2.5) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text(widgetFormatCompactNumber(entry.snapshot.bubbles.todayMl))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                // 2. Smokes
                let count = entry.snapshot.smokes.todayTotal
                let base = entry.snapshot.smokes.baseline
                HStack(spacing: 2.5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))
                        .foregroundColor(widgetSmokeRingColor(countToday: count, baseline: base))
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                // 3. Cosmos (replacing Money pill at bottom)
                HStack(spacing: 2.5) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 8))
                        .foregroundColor(cosmosColor)
                    Text("\(cosmos.stargazingScore)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Mini Progress Ring Helper for Small Executive Widget (Regular Mode)
    private func smallProgressRing(
        progress: CGFloat,
        valueText: String,
        labelText: String,
        iconName: String,
        gradientColors: [Color],
        tintColor: Color
    ) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3.2)
                    .frame(width: 34, height: 34)

                Circle()
                    .trim(from: 0, to: max(0.04, min(progress, 1.0)))
                    .stroke(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 34, height: 34)

                Text(valueText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.system(size: 6.5))
                    .foregroundColor(tintColor)
                Text(labelText)
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Small - Regular Mode (Without Brief)
    // Includes:
    // 1. 3 Liquid Progress Rings (Sleep, Water, Smokes)
    // 2. Horizontal Stress Bar with real Monkey Mascot & single-line level badge
    // 3. Money & Cosmos quick row
    // 4. TagDoS Focus row (2 important items)
    private var smallRegularView: some View {
        let stress = entry.snapshot.stress
        let hasStress = stress.hasData
        let stressColor = hasStress ? Color(hex: stress.level.hexColor) : WidgetColors.fgMuted
        let cosmos = entry.snapshot.cosmos
        let cosmosColor = Color(hex: cosmos.qualityHexColor)
        let focusItems = importantTagdosItems(limit: 2)

        return VStack(spacing: 4.5) {
            // Row 1: 3 Liquid Progress Rings (Sleep, Water, Smokes)
            HStack(spacing: 4) {
                smallProgressRing(
                    progress: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0),
                    valueText: "\(entry.snapshot.sleep.sleepScore)%",
                    labelText: entry.snapshot.sleep.totalAsleepFormatted,
                    iconName: "moon.fill",
                    gradientColors: [WidgetColors.accentCyan, WidgetColors.accentBlue],
                    tintColor: WidgetColors.accentCyan
                )

                smallProgressRing(
                    progress: entry.snapshot.bubbles.progressPercent,
                    valueText: "\(Int(entry.snapshot.bubbles.progressPercent * 100))%",
                    labelText: "\(widgetFormatCompactNumber(entry.snapshot.bubbles.todayMl)) ml",
                    iconName: "drop.fill",
                    gradientColors: [WidgetColors.accentBlue, Color(hex: "#00FFB2")],
                    tintColor: WidgetColors.accentBlue
                )

                let sCount = entry.snapshot.smokes.todayTotal
                let sBase = entry.snapshot.smokes.baseline
                let sColor = widgetSmokeRingColor(countToday: sCount, baseline: sBase)
                smallProgressRing(
                    progress: min(1.0, CGFloat(sCount) / CGFloat(max(1, sBase))),
                    valueText: "\(sCount)",
                    labelText: "of \(sBase)",
                    iconName: "flame.fill",
                    gradientColors: [sColor, sColor.opacity(0.7)],
                    tintColor: sColor
                )
            }

            // Row 2: Horizontal Stress Bar with our Monkey Mascot & strictly 1-line level badge
            HStack(spacing: 4.5) {
                WidgetMonkeyMascotView(mood: stress.monkeyMood, size: 16)

                Text(hasStress ? "\(stress.stressScore)" : "--")
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundColor(hasStress ? .white : .white.opacity(0.5))
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        if hasStress {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: stress.level.gradientHex.first ?? "#00FFB2"),
                                            Color(hex: stress.level.gradientHex.last ?? "#00B4D8")
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * CGFloat(min(100, max(0, stress.stressScore))) / 100.0))
                        }
                    }
                }
                .frame(height: 4)

                Text(hasStress ? stress.level.displayName : "No Data")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(stressColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(stressColor.opacity(hasStress ? 0.18 : 0.08))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 6.5)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))

            // Row 3: Money (EUR + Lei) & Cosmos Pill
            HStack(spacing: 4) {
                HStack(spacing: 3.5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 8))
                        .foregroundColor(WidgetColors.accentGreen)

                    Text(entry.snapshot.money.formattedNetWorth)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                HStack(spacing: 3) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 8))
                        .foregroundColor(cosmosColor)
                    Text("\(cosmos.stargazingScore)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(cosmos.moonIlluminationPercent)%")
                        .font(.system(size: 7.5, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Spacer(minLength: 0)

            // Row 4: TagDoS Focus (up to 2 pills)
            HStack(spacing: 4) {
                if focusItems.isEmpty {
                    Circle()
                        .fill(WidgetColors.accentPurple)
                        .frame(width: 4.5, height: 4.5)
                    Text("Clear focus")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(focusItems.prefix(2).enumerated()), id: \.offset) { idx, item in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(idx == 0 ? WidgetColors.accentPurple : WidgetColors.accentCyan)
                                .frame(width: 4, height: 4)
                            Text(item)
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 3.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // =========================================================================
    // MARK: - 2. MEDIUM WIDGET
    // =========================================================================

    // Medium - Morning Mode (With Brief)
    // Includes all info from Small Morning + richer Medium breakdowns:
    // Left Column (Morning Brief Card): Greeting + Weather, Sleep Ring + Stress with Monkey Mascot, TagDoS Focus (2-3 items)
    // Right Column (4 Metric Tiles): Bubbles (with Coffee/Water), Smokes (with Cig/Heat & elapsed), Money (Lei + EUR), Cosmos (Score + Verdict + Moon/Window)
    private var mediumMorningView: some View {
        let stress = entry.snapshot.stress
        let hasStress = stress.hasData
        let stressColor = hasStress ? Color(hex: stress.level.hexColor) : WidgetColors.fgMuted
        let cosmos = entry.snapshot.cosmos
        let cosmosColor = Color(hex: cosmos.qualityHexColor)
        let focusItems = importantTagdosItems(limit: 3)

        return HStack(spacing: 8) {
            // Left Column (50%): Morning Brief Spotlight + Sleep & Stress + TagDoS Focus
            VStack(alignment: .leading, spacing: 5) {
                // Header: Morning Brief + Weather
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(WidgetColors.accentAmber)
                    Text("Morning Brief")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if let temp = entry.snapshot.morningSummary?.weatherTemp {
                        let iconCode = entry.snapshot.morningSummary?.weatherIcon ?? "01d"
                        HStack(spacing: 3) {
                            Image(systemName: WeatherConditionHelper.sfSymbol(for: iconCode))
                                .font(.system(size: 10))
                                .foregroundColor(WidgetColors.accentCyan)
                            Text("\(Int(round(temp)))° · \(entry.snapshot.morningSummary?.weatherCondition ?? "Clear")")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                }

                // Sleep + Stress Row
                HStack(spacing: 6) {
                    // Sleep Ring + Duration
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 3.2)
                                .frame(width: 30, height: 30)
                            Circle()
                                .trim(from: 0, to: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0))
                                .stroke(
                                    LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 30, height: 30)
                            Text("\(entry.snapshot.sleep.sleepScore)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 0.5) {
                            Text(entry.snapshot.sleep.totalAsleepFormatted)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("Eff \(entry.snapshot.sleep.efficiencyPercent)%")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundColor(WidgetColors.accentMint)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 2)

                    // Stress Indicator on Right of Sleep
                    HStack(spacing: 4) {
                        WidgetMonkeyMascotView(mood: stress.monkeyMood, size: 18)
                        VStack(alignment: .trailing, spacing: 0.5) {
                            Text(hasStress ? "\(stress.stressScore)" : "--")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(hasStress ? stress.level.displayName : "Calm")
                                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                .foregroundColor(stressColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(stressColor.opacity(hasStress ? 0.15 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                // TagDoS Focus (2-3 items)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("FOCUS")
                            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.accentPurple)
                        Spacer()
                        Text("\(entry.snapshot.tagdos.totalActivePills) active")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }

                    ForEach(Array(focusItems.prefix(3).enumerated()), id: \.offset) { idx, item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(idx == 0 ? WidgetColors.accentPurple : (idx == 1 ? WidgetColors.accentCyan : WidgetColors.accentMint))
                                .frame(width: 4.5, height: 4.5)
                            Text(item)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(hex: "#061020").opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(WidgetColors.accentCyan.opacity(0.28), lineWidth: 1)
                    )
            )

            // Right Column (50%): 4 Rich Metric Rows (Water, Smokes, Money, Cosmos)
            VStack(spacing: 4.5) {
                // Tile 1: Water
                HStack(spacing: 5) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("Bubbles")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer(minLength: 2)
                    Text("\(Int(entry.snapshot.bubbles.todayMl))/\(Int(entry.snapshot.bubbles.goalMl)) ml")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("(\(Int(entry.snapshot.bubbles.progressPercent * 100))%)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Tile 2: Smokes
                let sCount = entry.snapshot.smokes.todayTotal
                let sBase = entry.snapshot.smokes.baseline
                let sColor = widgetSmokeRingColor(countToday: sCount, baseline: sBase)
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(sColor)
                    Text("Smokes")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer(minLength: 2)
                    if let last = entry.snapshot.smokes.lastSmokeDate {
                        Text(widgetFormatCompactTimeAgo(last))
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                    Text("\(sCount) / \(sBase)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(sColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Tile 3: Money (Net Worth Lei + EUR)
                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(WidgetColors.accentGreen)
                    Text(entry.snapshot.money.formattedNetWorth)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    Text(entry.snapshot.money.formattedNetWorthEUR)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(WidgetColors.accentGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Tile 4: Cosmos (Stargazing Score + Moon + Window)
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(cosmosColor)
                    Text("Cosmos")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer(minLength: 2)
                    Image(systemName: cosmos.moonSymbol)
                        .font(.system(size: 8.5))
                        .foregroundColor(Color(hex: "#FDE68A"))
                    Text("\(cosmos.moonIlluminationPercent)%")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    Text("\(cosmos.stargazingScore)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(cosmosColor)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Medium - Regular Mode (Without Brief)
    // Left Column: Sleep Ring + Deep/REM/Eff, Stress with Monkey Mascot & 1-line level, Cosmos Pill
    // Right Column: 4 Rich Metric Rows (Water with breakdown, Smokes with breakdown, Money Lei+EUR+Card/Cash, TagDoS 2-3 focus items)
    private var mediumRegularView: some View {
        let stress = entry.snapshot.stress
        let hasStress = stress.hasData
        let stressColor = hasStress ? Color(hex: stress.level.hexColor) : WidgetColors.fgMuted
        let cosmos = entry.snapshot.cosmos
        let cosmosColor = Color(hex: cosmos.qualityHexColor)
        let focusItems = importantTagdosItems(limit: 2)

        return HStack(spacing: 8) {
            // Left Hero Column: Sleep + Stress + Cosmos
            VStack(spacing: 5) {
                // 1. Sleep Card
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 4)
                            .frame(width: 38, height: 38)
                        Circle()
                            .trim(from: 0, to: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0))
                            .stroke(
                                LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 38, height: 38)
                        Text("\(entry.snapshot.sleep.sleepScore)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.snapshot.sleep.totalAsleepFormatted)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("D \(entry.snapshot.sleep.deepFormatted) · R \(entry.snapshot.sleep.remFormatted)")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("Eff \(entry.snapshot.sleep.efficiencyPercent)% · \(entry.snapshot.sleep.sleepQualityRating)")
                            .font(.system(size: 7.5, weight: .medium, design: .rounded))
                            .foregroundColor(WidgetColors.accentMint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // 2. Stress Card with our Monkey Mascot & strictly 1-line level
                HStack(spacing: 5) {
                    WidgetMonkeyMascotView(mood: stress.monkeyMood, size: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(hasStress ? "\(stress.stressScore)" : "--")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text(hasStress ? stress.level.displayName : "No Data")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundColor(stressColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        HStack(spacing: 4) {
                            if let hrv = stress.hrvMs {
                                Text("HRV \(Int(round(hrv)))")
                                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(WidgetColors.accentCyan)
                            }
                            if let rhr = stress.restingHeartRate {
                                Text("RHR \(Int(round(rhr)))")
                                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(WidgetColors.accentPink)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4.5)
                .frame(maxWidth: .infinity)
                .background(stressColor.opacity(hasStress ? 0.14 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                // 3. Cosmos Compact Bar
                HStack(spacing: 4) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 9))
                        .foregroundColor(cosmosColor)
                    Text("\(cosmos.stargazingScore)/100")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer(minLength: 2)
                    Image(systemName: cosmos.moonSymbol)
                        .font(.system(size: 8.5))
                        .foregroundColor(Color(hex: "#FDE68A"))
                    Text("\(cosmos.moonIlluminationPercent)%")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(cosmosColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(width: 132)
            .frame(maxHeight: .infinity)

            // Right Column: 4 Metric Cards (Water, Smokes, Money, TagDoS)
            VStack(spacing: 4.5) {
                // 1. Water Progress + Breakdown
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 9.5))
                                .foregroundColor(WidgetColors.accentBlue)
                            Text("Water")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Text("\(Int(entry.snapshot.bubbles.todayMl)) / \(Int(entry.snapshot.bubbles.goalMl)) ml")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [WidgetColors.accentBlue, WidgetColors.accentCyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, entry.snapshot.bubbles.progressPercent))))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))

                // 2. Smokes Counter + Breakdown
                let count = entry.snapshot.smokes.todayTotal
                let base = entry.snapshot.smokes.baseline
                let sColor = widgetSmokeRingColor(countToday: count, baseline: base)
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(sColor)
                    Text("Smokes")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    if let last = entry.snapshot.smokes.lastSmokeDate {
                        Text(widgetFormatCompactTimeAgo(last))
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                    }
                    Text("\(count) / \(base)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(sColor)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))

                // 3. Money Row (Net Worth Lei + EUR)
                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(WidgetColors.accentGreen)
                    Text(entry.snapshot.money.formattedNetWorth)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Text(entry.snapshot.money.formattedNetWorthEUR)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(WidgetColors.accentGreen)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))

                // 4. TagDoS Active Focus (up to 2 pills)
                HStack(spacing: 4) {
                    if focusItems.isEmpty {
                        Circle()
                            .fill(WidgetColors.accentPurple)
                            .frame(width: 4.5, height: 4.5)
                        Text("No pending focus")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer()
                    } else {
                        ForEach(Array(focusItems.prefix(2).enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 3.5) {
                                Circle()
                                    .fill(idx == 0 ? WidgetColors.accentPurple : WidgetColors.accentCyan)
                                    .frame(width: 4.5, height: 4.5)
                                Text(item)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // =========================================================================
    // MARK: - 3. LARGE WIDGET
    // =========================================================================

    // Large - Morning Mode (With Brief)
    // Edge-to-edge layout occupying full space with rich data across all 7 pillars:
    // 1. Morning Briefing Spotlight Card (Greeting + Weather + AI Focus + Quick Status)
    // 2. Sleep & Stress Studio Row (Sleep Score/Stages + Stress Monkey/Score/HRV/RHR)
    // 3. Habits, Money & Cosmos 2x2 Grid (Bubbles, Smokes, Money, Cosmos)
    // 4. TagDoS Active Focus Pipeline (Up to 3 streams / important pills)
    private var largeMorningView: some View {
        VStack(spacing: 7) {
            largeMorningHeaderCard
            largeSleepAndStressRow
            largeFourPillarGrid
            largeTagdosPipelineCard(title: "TAGDOS MORNING FOCUS")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var largeMorningHeaderCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(WidgetColors.accentAmber)
                    Text(entry.snapshot.morningSummary?.greeting ?? "Good Morning, Mihai")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer()

                if let temp = entry.snapshot.morningSummary?.weatherTemp {
                    let iconCode = entry.snapshot.morningSummary?.weatherIcon ?? "01d"
                    HStack(spacing: 4) {
                        Image(systemName: WeatherConditionHelper.sfSymbol(for: iconCode))
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(hex: WeatherConditionHelper.conditionColorHex(for: iconCode)))
                        Text("\(Int(round(temp)))° · \(entry.snapshot.morningSummary?.weatherCondition ?? "Clear")")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                    }
                }
            }

            if let focus = entry.snapshot.morningSummary?.topFocusText {
                Text(focus)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.9))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "#061020").opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [WidgetColors.accentCyan.opacity(0.45), Color.white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // Large - Regular Mode (Without Brief)
    // Full Executive Command Center occupying horizontal & vertical space properly:
    // 1. Header Bar (Daily Executive + Date + Cosmos Quick Pill + Net Worth)
    // 2. Sleep & Stress Studio Row (Sleep stages + Stress Monkey Mascot & 1-line level)
    // 3. Habits, Money & Cosmos 2x2 Grid
    // 4. TagDoS Active Pipeline (Up to 3 streams + active pills)
    private var largeRegularView: some View {
        VStack(spacing: 7) {
            largeRegularHeaderBar
            largeSleepAndStressRow
            largeFourPillarGrid
            largeTagdosPipelineCard(title: "TAGDOS ACTIVE PIPELINE")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var largeRegularHeaderBar: some View {
        let cosmos = entry.snapshot.cosmos
        let cosmosColor = Color(hex: cosmos.qualityHexColor)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Daily Executive")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }

            Spacer()

            // Cosmos quick pill in header
            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 9.5))
                    .foregroundColor(cosmosColor)
                Text("\(cosmos.stargazingScore)")
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Image(systemName: cosmos.moonSymbol)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(hex: "#FDE68A"))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())

            // Net Worth in Header
            HStack(spacing: 5) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 10.5))
                    .foregroundColor(WidgetColors.accentGreen)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(entry.snapshot.money.formattedNetWorth)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentGreen)
                        .lineLimit(1)
                    Text(entry.snapshot.money.formattedNetWorthEUR)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    // Shared Large Row 2: Sleep Studio (Left) + Stress Studio with Monkey Mascot (Right)
    private var largeSleepAndStressRow: some View {
        let stress = entry.snapshot.stress
        let hasStress = stress.hasData
        let stressColor = hasStress ? Color(hex: stress.level.hexColor) : WidgetColors.fgMuted

        return HStack(spacing: 7) {
            // Left: Sleep Studio Card
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4.5)
                        .frame(width: 42, height: 42)
                    Circle()
                        .trim(from: 0, to: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0))
                        .stroke(
                            LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 42, height: 42)
                    Text("\(entry.snapshot.sleep.sleepScore)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.snapshot.sleep.totalAsleepFormatted)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("Eff \(entry.snapshot.sleep.efficiencyPercent)%")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentMint)
                            .lineLimit(1)
                    }

                    largeSleepStagesBar

                    HStack(spacing: 5) {
                        Text("D \(entry.snapshot.sleep.deepFormatted)")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#6366F1"))
                            .lineLimit(1)
                        Text("R \(entry.snapshot.sleep.remFormatted)")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#8B5CF6"))
                            .lineLimit(1)
                    }
                }
            }
            .padding(8.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            // Right: Stress Studio Card with our Monkey Mascot & strictly 1-line level
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    WidgetMonkeyMascotView(mood: stress.monkeyMood, size: 22)

                    VStack(alignment: .leading, spacing: 0.5) {
                        HStack(spacing: 4) {
                            Text(hasStress ? "\(stress.stressScore)" : "--")
                                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("/100")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(WidgetColors.fgMuted)
                        }
                        Text(hasStress ? stress.level.displayName : "No Data")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(stressColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Spacer(minLength: 0)
                }

                // Autonomic Balance Bar
                GeometryReader { geo in
                    let paraW = max(6, geo.size.width * CGFloat(stress.parasympatheticPercent) / 100.0)
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(WidgetColors.accentMint)
                            .frame(width: paraW)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(stressColor)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 4)

                HStack(spacing: 6) {
                    Text("Rest \(stress.parasympatheticPercent)%")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundColor(WidgetColors.accentMint)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let hrv = stress.hrvMs {
                        Text("HRV \(Int(round(hrv)))")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                            .lineLimit(1)
                    }
                    if let rhr = stress.restingHeartRate {
                        Text("RHR \(Int(round(rhr)))")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentPink)
                            .lineLimit(1)
                    }
                }
            }
            .padding(8.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var largeSleepStagesBar: some View {
        GeometryReader { geo in
            let total = max(1.0, entry.snapshot.sleep.durationSeconds)
            let dW = CGFloat((entry.snapshot.sleep.deepSeconds / total)) * geo.size.width
            let rW = CGFloat((entry.snapshot.sleep.remSeconds / total)) * geo.size.width
            let lW = CGFloat((entry.snapshot.sleep.lightSeconds / total)) * geo.size.width
            let aW = CGFloat((entry.snapshot.sleep.awakeSeconds / total)) * geo.size.width

            HStack(spacing: 1.5) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#6366F1")).frame(width: max(2, dW))
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#8B5CF6")).frame(width: max(2, rW))
                RoundedRectangle(cornerRadius: 2).fill(WidgetColors.accentCyan).frame(width: max(2, lW))
                RoundedRectangle(cornerRadius: 2).fill(WidgetColors.accentRed.opacity(0.7)).frame(width: max(2, aW))
            }
        }
        .frame(height: 4.5)
    }

    // Shared Large Row 3: 2x2 Grid for Bubbles, Smokes, Money, and Cosmos
    private var largeFourPillarGrid: some View {
        let cosmos = entry.snapshot.cosmos
        let cosmosColor = Color(hex: cosmos.qualityHexColor)
        let sCount = entry.snapshot.smokes.todayTotal
        let sBase = entry.snapshot.smokes.baseline
        let sColor = widgetSmokeRingColor(countToday: sCount, baseline: sBase)

        return VStack(spacing: 6) {
            // Top pair: Bubbles & Smokes
            HStack(spacing: 7) {
                // 1. Bubbles
                VStack(alignment: .leading, spacing: 3.5) {
                    HStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 10))
                            .foregroundColor(WidgetColors.accentCyan)
                        Text("Bubbles")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(entry.snapshot.bubbles.todayMl)) / \(Int(entry.snapshot.bubbles.goalMl)) ml")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [WidgetColors.accentBlue, WidgetColors.accentCyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, entry.snapshot.bubbles.progressPercent))))
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Text("Water \(Int(entry.snapshot.bubbles.waterMl)) · Coffee \(Int(entry.snapshot.bubbles.coffeeMl))")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(entry.snapshot.bubbles.progressPercent * 100))%")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // 2. Smokes
                VStack(alignment: .leading, spacing: 3.5) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(sColor)
                        Text("Smokes")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(sCount) / \(sBase)")
                            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                            .foregroundColor(sColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(sColor)
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, Double(sCount) / Double(max(1, sBase))))))
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Text(sCount == 0 ? "Smoke-Free Today 🌟" : "Cig \(entry.snapshot.smokes.cigsCount) · Heat \(entry.snapshot.smokes.heatedCount)")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                            .lineLimit(1)
                        Spacer()
                        if let last = entry.snapshot.smokes.lastSmokeDate {
                            Text(widgetFormatCompactTimeAgo(last))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Bottom pair: Money & Cosmos
            HStack(spacing: 7) {
                // 3. Money
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(WidgetColors.accentGreen)
                        Text(entry.snapshot.money.formattedNetWorth)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Text(entry.snapshot.money.formattedNetWorthEUR)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentGreen)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text("Card \(widgetFormatCompactNumber(entry.snapshot.money.cardAmount))")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                            .lineLimit(1)
                        Text("Cash \(widgetFormatCompactNumber(entry.snapshot.money.cashAmount))")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentMint)
                            .lineLimit(1)
                        Spacer()
                        Text("-\(widgetFormatCompactNumber(entry.snapshot.money.outgoingTotal))")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentPink)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // 4. Cosmos
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(cosmosColor)
                        Text("Cosmos \(cosmos.stargazingScore)/100")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(cosmos.stargazingVerdict)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(cosmosColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: cosmos.moonSymbol)
                            .font(.system(size: 8))
                            .foregroundColor(Color(hex: "#FDE68A"))
                        Text("\(cosmos.moonPhaseName) (\(cosmos.moonIlluminationPercent)%)")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                            .lineLimit(1)
                        Spacer()
                        Text(cosmos.bestWindowLabel)
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // Shared Large Row 4: TagDoS Pipeline Card
    private func largeTagdosPipelineCard(title: String) -> some View {
        let streams = Array(entry.snapshot.tagdos.streams.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text(title)
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                }
                Spacer()
                if let rem = entry.snapshot.tagdos.nextReminderFormatted {
                    HStack(spacing: 2.5) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 7.5))
                        Text(rem)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(WidgetColors.accentCyan)
                }
                Text("\(entry.snapshot.tagdos.totalActivePills) active tags")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }

            if streams.isEmpty {
                Text("All streams clear — enjoy your day!")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            } else {
                ForEach(Array(streams.enumerated()), id: \.offset) { index, stream in
                    HStack(spacing: 5) {
                        Text("S\(index + 1)")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.accentPurple)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(WidgetColors.accentPurple.opacity(0.18))
                            .clipShape(Capsule())

                        Text(stream.drivingPillText ?? stream.title)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        let extraPills = Array(stream.pills.dropFirst().prefix(2))
                        ForEach(Array(extraPills.enumerated()), id: \.offset) { _, pill in
                            Text(pill.text)
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - Widget Declaration
public struct CombinedWidget: Widget {
    public let kind: String = "com.intellidream.daily.widget.combined"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: CombinedTimelineProvider()
        ) { entry in
            CombinedWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Combined")
        .description("Unified executive dashboard integrating Water, Smokes, Sleep, Stress, Money, Cosmos, TagDoS and adaptive morning briefing.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
