import WidgetKit
import SwiftUI
import AppIntents
import DailyCore

public struct MoneyEntry: TimelineEntry {
    public let date: Date
    public let snapshot: MoneyWidgetSnapshot

    public init(date: Date, snapshot: MoneyWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct MoneyTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> MoneyEntry {
        MoneyEntry(
            date: Date(),
            snapshot: MoneyWidgetSnapshot(
                netWorthLei: 127156.47,
                netWorthEUR: 25431.29,
                formattedNetWorth: "127.156,47 Lei",
                formattedNetWorthEUR: "25.431 €",
                incomingTotal: 16000,
                outgoingTotal: 16000,
                depositsTotal: 127156.47,
                cardAmount: 15100,
                cashAmount: 900,
                topOutgoingAllocations: [("Vacante", 6800), ("Rata", 4900), ("Cora", 1000)]
            )
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (MoneyEntry) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchMoneySnapshot()
        completion(MoneyEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<MoneyEntry>) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchMoneySnapshot()
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(1800)
        let entry = MoneyEntry(date: currentDate, snapshot: snapshot)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

public struct MoneyWidgetView: View {
    public let entry: MoneyEntry
    @Environment(\.widgetFamily) var family

    private let accentGreen = Color(red: 0.0, green: 0.9, blue: 0.46)
    private let accentCyan = Color(red: 0.0, green: 0.85, blue: 1.0)
    private let accentPurple = Color(red: 0.7, green: 0.53, blue: 1.0)
    private let accentPink = Color(red: 1.0, green: 0.22, blue: 0.38)
    private let bgGradient = LinearGradient(
        colors: [Color(red: 0.05, green: 0.03, blue: 0.08), Color(red: 0.10, green: 0.07, blue: 0.16)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private func formatCompactLei(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            let thousands = amount / 1_000
            if thousands.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0fK", thousands)
            } else {
                return String(format: "%.1fK", thousands)
            }
        } else {
            return String(format: "%.0f", amount)
        }
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
            case .accessoryRectangular:
                accessoryRectangularView
            default:
                mediumView
            }
        }
        .containerBackground(bgGradient, for: .widget)
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "wallet.bifold.fill")
                    Text("Money")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accentGreen)

                Spacer()

                Text(entry.snapshot.formattedNetWorthEUR)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(accentCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentCyan.opacity(0.14))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("NET WORTH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.45))

                Text("\(formatCompactLei(entry.snapshot.netWorthLei)) Lei")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 2)

            // Liquidity Footer
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Circle().fill(accentCyan).frame(width: 4, height: 4)
                    Text("Crd \(formatCompactLei(entry.snapshot.cardAmount))")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(accentCyan)
                        .lineLimit(1)
                }

                Text("·")
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.3))

                HStack(spacing: 2) {
                    Circle().fill(accentGreen).frame(width: 4, height: 4)
                    Text("Csh \(formatCompactLei(entry.snapshot.cashAmount))")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(accentGreen)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label("Finances & Money", systemImage: "wallet.bifold.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accentGreen)
                Spacer()
                Text(entry.snapshot.formattedNetWorthEUR)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(accentCyan)
            }

            // 3 Columns: Net Worth | Flow | Liquid
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NET WORTH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                    Text("\(formatCompactLei(entry.snapshot.netWorthLei)) Lei")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 30).background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("FLOW (IN/OUT)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                    Text("\(formatCompactLei(entry.snapshot.incomingTotal)) / \(formatCompactLei(entry.snapshot.outgoingTotal))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 30).background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("LIQUID")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                    Text("\(formatCompactLei(entry.snapshot.cardAmount)) · \(formatCompactLei(entry.snapshot.cashAmount))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(accentCyan)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 2)

            // Smart interactive adjust controls
            HStack(spacing: 6) {
                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaRaw: -50)) {
                    Text("-50 Crd")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(accentPink)
                        .background(
                            Capsule()
                                .fill(accentPink.opacity(0.12))
                                .overlay(Capsule().strokeBorder(accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Cash", deltaRaw: -50)) {
                    Text("-50 Csh")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(accentPink)
                        .background(
                            Capsule()
                                .fill(accentPink.opacity(0.12))
                                .overlay(Capsule().strokeBorder(accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaRaw: 100)) {
                    Text("+100 Crd")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(accentGreen)
                        .background(
                            Capsule()
                                .fill(accentGreen.opacity(0.12))
                                .overlay(Capsule().strokeBorder(accentGreen.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label("Finances & Wealth", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accentGreen)
                Spacer()
                Text(entry.snapshot.formattedNetWorthEUR)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(accentCyan)
            }

            // Upper Panel: Net Worth + Flow/Liquid
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NET WORTH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                    Text(entry.snapshot.formattedNetWorth)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Deposits:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.5))
                        Text("\(formatCompactLei(entry.snapshot.depositsTotal)) Lei")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(accentPurple)
                    }
                    HStack(spacing: 4) {
                        Text("Liquid:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.5))
                        Text("\(formatCompactLei(entry.snapshot.cardAmount)) / \(formatCompactLei(entry.snapshot.cashAmount)) Lei")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(accentCyan)
                    }
                }
            }

            Divider().background(Color.white.opacity(0.12))

            // Key Outgoing Allocations
            VStack(alignment: .leading, spacing: 5) {
                Text("TOP OUTGOING ALLOCATIONS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.45))

                HStack(spacing: 6) {
                    ForEach(entry.snapshot.topOutgoingAllocations, id: \.name) { item in
                        HStack(spacing: 3) {
                            Text(item.name.split(separator: "/").first.map(String.init) ?? item.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(formatCompactLei(item.amount))")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(accentPink)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        )
                    }
                }
            }

            Divider().background(Color.white.opacity(0.12))

            Text("SMART QUICK ADJUST")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.white.opacity(0.45))

            // Interactive Buttons
            HStack(spacing: 6) {
                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaRaw: -50)) {
                    Text("-50 Card")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .foregroundColor(accentPink)
                        .background(
                            Capsule()
                                .fill(accentPink.opacity(0.12))
                                .overlay(Capsule().strokeBorder(accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Cash", deltaRaw: -50)) {
                    Text("-50 Cash")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .foregroundColor(accentPink)
                        .background(
                            Capsule()
                                .fill(accentPink.opacity(0.12))
                                .overlay(Capsule().strokeBorder(accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaRaw: 100)) {
                    Text("+100 Card")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .foregroundColor(accentGreen)
                        .background(
                            Capsule()
                                .fill(accentGreen.opacity(0.12))
                                .overlay(Capsule().strokeBorder(accentGreen.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Lock Screen
    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("NET WORTH")
                    .font(.system(size: 9, weight: .bold))
                Spacer()
                Text(entry.snapshot.formattedNetWorthEUR)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(entry.snapshot.formattedNetWorth)
                .font(.system(size: 13, weight: .bold))
            Text("Crd \(formatCompactLei(entry.snapshot.cardAmount)) · Csh \(formatCompactLei(entry.snapshot.cashAmount))")
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.7))
        }
    }
}

public struct MoneyWidget: Widget {
    public let kind: String = "com.intellidream.daily.MoneyWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoneyTimelineProvider()) { entry in
            MoneyWidgetView(entry: entry)
        }
        .configurationDisplayName("Money & Finances")
        .description("Track Net Worth, monthly flow, liquid balances, and smart ledger adjustments.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
