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

// MARK: - Money Widget View
public struct MoneyWidgetView: View {
    public let entry: MoneyEntry
    @Environment(\.widgetFamily) var family

    private func formatCompactLei(_ amount: Double) -> String {
        widgetFormatCompactNumber(amount)
    }

    private func formatCompactEUR(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "%.1fM €", amount / 1_000_000)
        } else if amount >= 10_000 {
            let thousands = amount / 1_000
            if thousands.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0fK €", thousands)
            } else {
                return String(format: "%.1fK €", thousands)
            }
        } else if amount >= 1_000 {
            return String(format: "%.1fK €", amount / 1_000)
        } else {
            return String(format: "%.0f €", amount)
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
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(URL(string: "daily://finances/money"))
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Section: Net Worth on Left, EUR pill in Top-Right
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(formatCompactLei(entry.snapshot.netWorthLei)) Lei")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text("NET WORTH")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.45))
                }

                Spacer(minLength: 4)

                // Top-Right: EUR conversion badge in a pill
                Text(formatCompactEUR(entry.snapshot.netWorthEUR))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2.5)
                    .background(WidgetColors.accentCyan.opacity(0.18))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 2)

            // Liquid balances: Card and Cash one below the other, centered between top and buttons
            VStack(alignment: .leading, spacing: 2) {
                Text("Card \(formatCompactLei(entry.snapshot.cardAmount))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)
                Text("Cash \(formatCompactLei(entry.snapshot.cashAmount))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetColors.accentGreen)
            }

            Spacer(minLength: 2)

            // 2 Compact Adjust Buttons: -100 Crd & +100 Crd
            HStack(spacing: 4) {
                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaReal: -100)) {
                    Text("-100 Crd")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(WidgetColors.accentPink)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentPink.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaReal: 100)) {
                    Text("+100 Crd")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(WidgetColors.accentGreen)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentGreen.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentGreen.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(alignment: .trailing) {
            // Stylized Watermark Wallet Icon (scaled down: 59pt, opacity: 0.14, inward offset x: 16)
            Image(systemName: "wallet.bifold.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 59)
                .foregroundColor(WidgetColors.accentGreen)
                .opacity(0.14)
                .offset(x: 16)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Wallet icon on left, EUR badge on right (No text title)
            HStack {
                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(WidgetColors.accentGreen)

                Spacer()

                Text(entry.snapshot.formattedNetWorthEUR)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)
            }

            // 3 Columns: NET WORTH | FLOW | LIQUID
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NET WORTH")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                    Text("\(formatCompactLei(entry.snapshot.netWorthLei)) Lei")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 28).background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("FLOW (IN/OUT)")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                    Text("\(formatCompactLei(entry.snapshot.incomingTotal)) / \(formatCompactLei(entry.snapshot.outgoingTotal))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 28).background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("LIQUID")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                    Text("Crd \(formatCompactLei(entry.snapshot.cardAmount)) · Csh \(formatCompactLei(entry.snapshot.cashAmount))")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.accentCyan)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 2)

            // 3 Smart Interactive Adjust Buttons
            HStack(spacing: 6) {
                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaReal: -100)) {
                    Text("-100 Crd")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(WidgetColors.accentPink)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentPink.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Cash", deltaReal: -100)) {
                    Text("-100 Csh")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(WidgetColors.accentPink)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentPink.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaReal: 100)) {
                    Text("+100 Crd")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundColor(WidgetColors.accentGreen)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentGreen.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentGreen.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Large Animated Wallet Icon + Live EUR Badge
            HStack {
                if #available(iOS 17.0, *) {
                    Image(systemName: "wallet.bifold.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(WidgetColors.accentGreen)
                        .symbolEffect(.pulse)
                } else {
                    Image(systemName: "wallet.bifold.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(WidgetColors.accentGreen)
                }

                Spacer()

                Text(entry.snapshot.formattedNetWorthEUR)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)
            }

            // Upper Panel: Net Worth Hero + Deposits/Liquid
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
                            .foregroundColor(WidgetColors.accentPurple)
                    }
                    HStack(spacing: 4) {
                        Text("Liquid:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.5))
                        Text("\(formatCompactLei(entry.snapshot.cardAmount)) / \(formatCompactLei(entry.snapshot.cashAmount)) Lei")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentCyan)
                    }
                }
            }

            Divider().background(Color.white.opacity(0.12))

            // Key Outgoing Allocations Capsules
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
                                .foregroundColor(WidgetColors.accentPink)
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

            // Quick Adjust Action Grid
            HStack(spacing: 6) {
                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaReal: -100)) {
                    Text("-100 Card")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .foregroundColor(WidgetColors.accentPink)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentPink.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Cash", deltaReal: -100)) {
                    Text("-100 Cash")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .foregroundColor(WidgetColors.accentPink)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentPink.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentPink.opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button(intent: AdjustLedgerIntent(accountName: "Card", deltaReal: 100)) {
                    Text("+100 Card")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .foregroundColor(WidgetColors.accentGreen)
                        .background(
                            Capsule()
                                .fill(WidgetColors.accentGreen.opacity(0.14))
                                .overlay(Capsule().strokeBorder(WidgetColors.accentGreen.opacity(0.25), lineWidth: 1))
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
