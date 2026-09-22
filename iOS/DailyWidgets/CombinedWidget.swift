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
                            pills: []
                        )
                    ],
                    totalActivePills: 4,
                    nextReminderFormatted: nil
                ),
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
        .widgetURL(targetUrl)
        .containerBackground(WidgetColors.bgGradient, for: .widget)
    }

    // =========================================================================
    // MARK: - 1. SMALL WIDGET
    // =========================================================================

    // Small - Morning Mode
    private var smallMorningView: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header: Greeting + Weather
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(WidgetColors.accentAmber)
                    Text("Morning")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                if let temp = entry.snapshot.morningSummary?.weatherTemp {
                    let iconCode = entry.snapshot.morningSummary?.weatherIcon ?? "01d"
                    HStack(spacing: 3) {
                        Image(systemName: WeatherConditionHelper.sfSymbol(for: iconCode))
                            .font(.system(size: 9))
                            .foregroundColor(WidgetColors.accentCyan)
                        Text("\(Int(round(temp)))°")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }

            // Sleep Hero Progress Ring & Recovery
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 3.5)
                        .frame(width: 36, height: 36)
                    Circle()
                        .trim(from: 0, to: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0))
                        .stroke(
                            LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                    Text("\(entry.snapshot.sleep.sleepScore)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.snapshot.sleep.totalAsleepFormatted)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(entry.snapshot.sleep.sleepQualityRating)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(WidgetColors.accentMint)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            // Focus snippet or driving pill
            if let focus = cleanMorningFocusTask(
                topFocus: entry.snapshot.morningSummary?.topFocusText,
                streamDriving: entry.snapshot.tagdos.streams.first?.drivingPillText
            ) {
                HStack(spacing: 4) {
                    Text("Focus")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(WidgetColors.accentPurple.opacity(0.2))
                        .clipShape(Capsule())

                    Text(focus)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Spacer(minLength: 0)

            // Bottom 3-metric quick status
            HStack(spacing: 4) {
                // Water
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text(widgetFormatCompactNumber(entry.snapshot.bubbles.todayMl))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                // Smokes
                let count = entry.snapshot.smokes.todayTotal
                let base = entry.snapshot.smokes.baseline
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))
                        .foregroundColor(widgetSmokeRingColor(countToday: count, baseline: base))
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                // Net worth in EUR, compact integer format (e.g. 55k) without decimals
                HStack(spacing: 2) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 8))
                        .foregroundColor(WidgetColors.accentGreen)
                    Text(widgetFormatCompactIntegerEUR(entry.snapshot.money.netWorthEUR))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
        }
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

    // Mini Progress Ring Helper for Small Executive Widget
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
                    .frame(width: 36, height: 36)

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
                    .frame(width: 36, height: 36)

                Text(valueText)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.system(size: 7))
                    .foregroundColor(tintColor)
                Text(labelText)
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Small - Regular Mode (Executive 3-Ring Gauges + Horizontal Stress Bar + Combined Money & TagDoS)
    private var smallRegularView: some View {
        VStack(spacing: 7.5) {
            // Row 1: 3 Liquid Progress Rings (Sleep, Water, Smokes)
            HStack(spacing: 4) {
                // Sleep Ring
                smallProgressRing(
                    progress: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0),
                    valueText: "\(entry.snapshot.sleep.sleepScore)%",
                    labelText: entry.snapshot.sleep.totalAsleepFormatted,
                    iconName: "moon.fill",
                    gradientColors: [WidgetColors.accentCyan, WidgetColors.accentBlue],
                    tintColor: WidgetColors.accentCyan
                )

                // Water Ring
                smallProgressRing(
                    progress: entry.snapshot.bubbles.progressPercent,
                    valueText: "\(Int(entry.snapshot.bubbles.progressPercent * 100))%",
                    labelText: "\(widgetFormatCompactNumber(entry.snapshot.bubbles.todayMl)) ml",
                    iconName: "drop.fill",
                    gradientColors: [WidgetColors.accentBlue, Color(hex: "#00FFB2")],
                    tintColor: WidgetColors.accentBlue
                )

                // Smokes Ring
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

            // Row 2: Horizontal Stress Bar with Monkey Mascot (no word "STRESS" for extra room)
            let stress = entry.snapshot.stress
            let stressColor = Color(hex: stress.level.hexColor)
            HStack(spacing: 5) {
                Text(stress.monkeyMood.emoji)
                    .font(.system(size: 11.5))

                Text("\(stress.stressScore)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                // Mini horizontal gauge
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
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
                .frame(height: 4)

                Text(stress.level.displayName)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(stressColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(stressColor.opacity(0.18))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Row 3: Combined Money (EUR) & TagDoS Row (No S1 badge to maximize task text)
            let driving = entry.snapshot.tagdos.streams.first?.drivingPillText ?? "Clear"
            HStack(spacing: 5) {
                // Left: Money in EUR
                HStack(spacing: 3.5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 8.5))
                        .foregroundColor(WidgetColors.accentGreen)

                    Text(entry.snapshot.money.formattedNetWorthEUR)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Right: TagDoS Focus
                HStack(spacing: 4) {
                    Circle()
                        .fill(WidgetColors.accentPurple)
                        .frame(width: 4.5, height: 4.5)

                    Text(driving)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // =========================================================================
    // MARK: - 2. MEDIUM WIDGET
    // =========================================================================

    // Medium - Morning Mode (Split: Spotlight Summary + 4 Metric Tiles)
    private var mediumMorningView: some View {
        HStack(spacing: 10) {
            // Left Card (48%): Morning Mini-Summary Spotlight
            VStack(alignment: .leading, spacing: 6) {
                // Greeting Header
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("Morning Brief")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                if let temp = entry.snapshot.morningSummary?.weatherTemp {
                    let iconCode = entry.snapshot.morningSummary?.weatherIcon ?? "01d"
                    HStack(spacing: 4) {
                        Image(systemName: WeatherConditionHelper.sfSymbol(for: iconCode))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: WeatherConditionHelper.conditionColorHex(for: iconCode)))
                        Text("\(Int(round(temp)))° · \(entry.snapshot.morningSummary?.weatherCondition ?? "Clear")")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

                // Sleep Recap
                HStack(spacing: 5) {
                    Text("\(entry.snapshot.sleep.sleepScore)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("· \(entry.snapshot.sleep.totalAsleepFormatted)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }

                // Focus item
                if let focus = entry.snapshot.morningSummary?.topFocusText ?? entry.snapshot.tagdos.streams.first?.drivingPillText {
                    Text(focus)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // Tap to view prompt
                HStack(spacing: 4) {
                    Text("Tap for full Briefing")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "#061020").opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(WidgetColors.accentCyan.opacity(0.3), lineWidth: 1)
                    )
            )

            // Right Column (52%): 4 Compact Metric Tiles
            VStack(spacing: 5) {
                // Tile 1: Water
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 10))
                            .foregroundColor(WidgetColors.accentBlue)
                        Text("Water")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("\(Int(entry.snapshot.bubbles.todayMl)) ml")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                // Tile 2: Smokes
                let sCount = entry.snapshot.smokes.todayTotal
                let sBase = entry.snapshot.smokes.baseline
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(widgetSmokeRingColor(countToday: sCount, baseline: sBase))
                        Text("Smokes")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("\(sCount) / \(sBase)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                // Tile 3: Money (Net Worth)
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 10))
                            .foregroundColor(WidgetColors.accentGreen)
                        Text("Net Worth")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text(entry.snapshot.money.formattedNetWorth)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                // Tile 4: TagDoS
                let pill = entry.snapshot.tagdos.streams.first?.drivingPillText ?? "All clear"
                HStack {
                    HStack(spacing: 5) {
                        Text("S1")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundColor(WidgetColors.accentPurple)
                        Text(pill)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(11)
    }

    // Medium - Regular Mode (Sleep & Money Hero + 3-Row Metrics)
    private var mediumRegularView: some View {
        HStack(spacing: 12) {
            // Left Hero Column: Sleep Arc + Net Worth + Stress
            VStack(alignment: .center, spacing: 5) {
                // Sleep Arc Gauge
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 5.5)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0))
                        .stroke(
                            LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 52, height: 52)
                    VStack(spacing: 0) {
                        Text("\(entry.snapshot.sleep.sleepScore)")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text(entry.snapshot.sleep.totalAsleepFormatted)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(WidgetColors.accentMint)
                    }
                }

                // Net Worth Pill
                VStack(spacing: 1) {
                    Text(entry.snapshot.money.formattedNetWorth)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentGreen)
                        .lineLimit(1)
                    Text(entry.snapshot.money.formattedNetWorthEUR)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                // Stress Pill with Monkey Mascot
                let stress = entry.snapshot.stress
                let sColor = Color(hex: stress.level.hexColor)
                HStack(spacing: 3) {
                    Text(stress.monkeyMood.emoji)
                        .font(.system(size: 9))
                    Text("\(stress.stressScore)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(sColor)
                    Text(stress.level.displayName)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(sColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(sColor.opacity(0.15))
                .clipShape(Capsule())
            }
            .frame(width: 104)

            // Right Column: 3 Metric Cards (Water, Smokes, TagDoS)
            VStack(spacing: 7) {
                // 1. Water Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 10))
                                .foregroundColor(WidgetColors.accentBlue)
                            Text("Water")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Text("\(Int(entry.snapshot.bubbles.todayMl)) / \(Int(entry.snapshot.bubbles.goalMl)) ml")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [WidgetColors.accentBlue, WidgetColors.accentCyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, entry.snapshot.bubbles.progressPercent))))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                // 2. Smokes Counter
                let count = entry.snapshot.smokes.todayTotal
                let base = entry.snapshot.smokes.baseline
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(widgetSmokeRingColor(countToday: count, baseline: base))
                        Text("Smokes")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("\(count) / \(base) cigs")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(widgetSmokeRingColor(countToday: count, baseline: base))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                // 3. TagDoS Active Pill
                let pill = entry.snapshot.tagdos.streams.first?.drivingPillText ?? "No pending focus"
                HStack(spacing: 6) {
                    Text("S1")
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetColors.accentPurple)
                    Text(pill)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(11)
    }

    // =========================================================================
    // MARK: - 3. LARGE WIDGET
    // =========================================================================

    // Large - Morning Mode (Executive Morning Summary Card + 5 Modular Tiles)
    private var largeMorningView: some View {
        VStack(spacing: 10) {
            largeMorningHeaderCard
            largeMorningHabitsRow
            largeMorningTagdosRow
        }
        .padding(14)
    }

    private var largeMorningHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text(entry.snapshot.morningSummary?.greeting ?? "Good Morning, Mihai")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                if let temp = entry.snapshot.morningSummary?.weatherTemp {
                    let iconCode = entry.snapshot.morningSummary?.weatherIcon ?? "01d"
                    HStack(spacing: 5) {
                        Image(systemName: WeatherConditionHelper.sfSymbol(for: iconCode))
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: WeatherConditionHelper.conditionColorHex(for: iconCode)))
                        Text("\(Int(round(temp)))° · \(entry.snapshot.morningSummary?.weatherCondition ?? "Clear")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }

            Divider().background(Color.white.opacity(0.12))

            if let focus = entry.snapshot.morningSummary?.topFocusText {
                Text(focus)
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.92))
                    .lineLimit(2)
                    .lineSpacing(2)
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 10))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("Sleep: \(entry.snapshot.sleep.sleepScore)% (\(entry.snapshot.sleep.totalAsleepFormatted))")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                HStack(spacing: 4) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 10))
                        .foregroundColor(WidgetColors.accentGreen)
                    Text("Net Worth: \(entry.snapshot.money.formattedNetWorth)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(WidgetColors.accentGreen)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Open Briefing")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(WidgetColors.accentCyan)
                }
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#061020").opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [WidgetColors.accentCyan.opacity(0.5), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private var largeMorningHabitsRow: some View {
        HStack(spacing: 10) {
            // Card 1: Hydration
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 12))
                        .foregroundColor(WidgetColors.accentBlue)
                    Text("Bubbles")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Text("\(Int(entry.snapshot.bubbles.todayMl)) ml")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Goal: \(Int(entry.snapshot.bubbles.goalMl)) ml")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Card 2: Smokes
            let sCount = entry.snapshot.smokes.todayTotal
            let sBase = entry.snapshot.smokes.baseline
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(widgetSmokeRingColor(countToday: sCount, baseline: sBase))
                    Text("Smokes")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Text("\(sCount) / \(sBase)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(widgetSmokeRingColor(countToday: sCount, baseline: sBase))
                Text(sCount == 0 ? "Clean today" : "\(entry.snapshot.smokes.cigsCount) cigs")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func tagdosStreamRow(index: Int, stream: TagdosWidgetSnapshotStream) -> some View {
        HStack(spacing: 6) {
            Text("S\(index + 1)")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(WidgetColors.accentPurple)
            Text(stream.drivingPillText ?? stream.title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }

    private var largeMorningTagdosRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TAGDOS ACTIVE FOCUS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentPurple)
                Spacer()
                Text("\(entry.snapshot.tagdos.streams.count) streams")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }
            ForEach(Array(entry.snapshot.tagdos.streams.prefix(2).enumerated()), id: \.offset) { index, stream in
                tagdosStreamRow(index: index, stream: stream)
            }
        }
        .padding(11)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Large - Regular Mode (Full Executive Command Center)
    private var largeRegularView: some View {
        VStack(spacing: 12) {
            largeRegularHeaderBar
            largeRegularSleepCard
            largeRegularHabitsRow
            largeRegularTagdosRow
        }
        .padding(14)
    }

    private var largeRegularHeaderBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Daily Executive")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 11))
                    .foregroundColor(WidgetColors.accentGreen)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(entry.snapshot.money.formattedNetWorth)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentGreen)
                    Text(entry.snapshot.money.formattedNetWorthEUR)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                }
            }
        }
    }

    private var largeRegularSleepCard: some View {
        HStack(spacing: 14) {
            // Sleep Arc
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: min(1.0, CGFloat(entry.snapshot.sleep.sleepScore) / 100.0))
                    .stroke(
                        LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
                Text("\(entry.snapshot.sleep.sleepScore)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Sleep Studio")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text(entry.snapshot.sleep.totalAsleepFormatted)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                largeSleepStagesBar

                HStack {
                    Text("Deep \(entry.snapshot.sleep.deepFormatted)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "#6366F1"))
                    Text("REM \(entry.snapshot.sleep.remFormatted)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "#8B5CF6"))
                    Spacer()
                    Text("Eff \(entry.snapshot.sleep.efficiencyPercent)%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentMint)
                }
            }
        }
        .padding(11)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var largeSleepStagesBar: some View {
        GeometryReader { geo in
            let total = max(1.0, entry.snapshot.sleep.durationSeconds)
            let dW = CGFloat((entry.snapshot.sleep.deepSeconds / total)) * geo.size.width
            let rW = CGFloat((entry.snapshot.sleep.remSeconds / total)) * geo.size.width
            let lW = CGFloat((entry.snapshot.sleep.lightSeconds / total)) * geo.size.width
            let aW = CGFloat((entry.snapshot.sleep.awakeSeconds / total)) * geo.size.width

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#6366F1")).frame(width: max(2, dW))
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#8B5CF6")).frame(width: max(2, rW))
                RoundedRectangle(cornerRadius: 2).fill(WidgetColors.accentCyan).frame(width: max(2, lW))
                RoundedRectangle(cornerRadius: 2).fill(WidgetColors.accentRed.opacity(0.7)).frame(width: max(2, aW))
            }
        }
        .frame(height: 5)
    }

    private var largeRegularHabitsRow: some View {
        HStack(spacing: 8) {
            // 1. Water
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 10))
                        .foregroundColor(WidgetColors.accentBlue)
                    Text("Hydration")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text(widgetFormatCompactNumber(entry.snapshot.bubbles.todayMl))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [WidgetColors.accentBlue, WidgetColors.accentCyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(3, geo.size.width * CGFloat(min(1.0, entry.snapshot.bubbles.progressPercent))))
                    }
                }
                .frame(height: 4)

                Text("\(Int(entry.snapshot.bubbles.progressPercent * 100))% of goal")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 2. Smokes
            let count = entry.snapshot.smokes.todayTotal
            let base = entry.snapshot.smokes.baseline
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(widgetSmokeRingColor(countToday: count, baseline: base))
                    Text("Smokes")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(widgetSmokeRingColor(countToday: count, baseline: base))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(widgetSmokeRingColor(countToday: count, baseline: base))
                            .frame(width: max(3, geo.size.width * CGFloat(min(1.0, Double(count) / Double(max(1, base))))))
                    }
                }
                .frame(height: 4)

                Text("Limit \(base)")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 3. Stress
            let stress = entry.snapshot.stress
            let stressColor = Color(hex: stress.level.hexColor)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stress.monkeyMood.emoji)
                        .font(.system(size: 11))
                    Text("Stress")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(stress.stressScore)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(stressColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
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
                            .frame(width: max(3, geo.size.width * CGFloat(min(100, max(0, stress.stressScore))) / 100.0))
                    }
                }
                .frame(height: 4)

                Text(stress.level.displayName)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(stressColor)
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var largeRegularTagdosRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TAGDOS PIPELINE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentPurple)
                Spacer()
                Text("\(entry.snapshot.tagdos.streams.count) streams active")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
            }

            ForEach(Array(entry.snapshot.tagdos.streams.prefix(2).enumerated()), id: \.offset) { index, stream in
                tagdosStreamRow(index: index, stream: stream)
            }
        }
        .padding(11)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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
        .description("Unified executive dashboard integrating Water, Smokes, Sleep, Money, TagDoS and adaptive morning briefing.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
