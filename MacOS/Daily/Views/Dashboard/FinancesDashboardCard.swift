import SwiftUI
import DailyCore

/// Liquid Glass Finances Card on the main Dashboard.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct FinancesDashboardCard: View {
    @ObservedObject private var ledgerStore = SmartLedgerStore.shared
    @ObservedObject private var financeService = FinanceService.shared
    
    public let size: DashboardWidgetSize
    private let onTap: () -> Void

    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
    }

    private var ledger: ParsedSmartLedger {
        ledgerStore.parsedLedger
    }
    
    private var cardAmount: Double {
        if let inc = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }),
           let card = inc.items.first(where: { $0.key.caseInsensitiveCompare("Card") == .orderedSame }) {
            return card.calculatedAmount
        }
        return 0
    }
    
    private var cashAmount: Double {
        if let inc = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }),
           let cash = inc.items.first(where: { $0.key.caseInsensitiveCompare("Cash") == .orderedSame }) {
            return cash.calculatedAmount
        }
        return 0
    }
    
    private var topOutgoingItems: [SmartLedgerItem] {
        guard let out = ledger.sections.first(where: { $0.name.caseInsensitiveCompare("Outgoing") == .orderedSame }) else {
            return []
        }
        return out.items
            .filter { !$0.isPureNote && $0.calculatedAmount > 0 }
            .sorted { $0.calculatedAmount > $1.calculatedAmount }
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
            .dashboardCardFrame(for: size)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Small (1x1) Compact Net Worth Glance
    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "wallet.bifold.fill")
                    Text("Money")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ThemeColors.accentGreen)
                
                Spacer()
                
                // EUR Equivalent Pill
                Text(ledger.formattedNetWorthEUR)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ThemeColors.accentCyan.opacity(0.14))
                    .clipShape(Capsule())
            }
            
            Spacer(minLength: 2)

            // Net Worth
            VStack(alignment: .leading, spacing: 1) {
                Text("NET WORTH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                
                Text(formatCompactLei(ledger.netWorth))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            
            Spacer(minLength: 2)

            // Liquidity Footer (Card & Cash)
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Circle()
                        .fill(ThemeColors.accentCyan)
                        .frame(width: 4, height: 4)
                    Text("Crd \(formatCompactNumber(cardAmount))")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                        .lineLimit(1)
                }
                
                Text("·")
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.3))
                
                HStack(spacing: 2) {
                    Circle()
                        .fill(Color(red: 0.35, green: 0.85, blue: 0.55))
                        .frame(width: 4, height: 4)
                    Text("Csh \(formatCompactNumber(cashAmount))")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.55))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Wide (2x1) Standard 3-Column Split
    @ViewBuilder
    private var wideContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Finances & Money", systemImage: "wallet.bifold.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentGreen)
                Spacer()
                HStack(spacing: 4) {
                    Text("Open Hub")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentGreen)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentGreen)
                }
            }
            
            // 3 Columns: Net Worth | Monthly Flow | Reserves
            HStack(spacing: 14) {
                // Column 1: Net Worth
                VStack(alignment: .leading, spacing: 3) {
                    Text("NET WORTH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(ledger.formattedBadge(ledger.netWorth))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text(ledger.formattedNetWorthEUR)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                    .frame(height: 38)
                    .background(Color.white.opacity(0.15))
                
                // Column 2: Monthly Flow
                VStack(alignment: .leading, spacing: 3) {
                    Text("MONTHLY FLOW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    HStack(spacing: 4) {
                        Text("In")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(formatCompactLei(ledger.incomingTotal))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentGreen)
                    }
                    
                    HStack(spacing: 4) {
                        Text("Out")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(formatCompactLei(ledger.outgoingTotal))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                    .frame(height: 38)
                    .background(Color.white.opacity(0.15))
                
                // Column 3: Deposits & Liquid
                VStack(alignment: .leading, spacing: 3) {
                    Text("DEPOSITS & LIQUID")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    Text(ledger.formattedBadge(ledger.depositTotal))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text("Crd \(formatCompactNumber(cardAmount)) · Csh \(formatCompactNumber(cashAmount))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Tall (1x2) Vertical 50/50 Split
    @ViewBuilder
    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label("Finances", systemImage: "wallet.bifold.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeColors.accentGreen)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ThemeColors.accentGreen)
            }

            // Top: Net Worth Card
            VStack(alignment: .leading, spacing: 3) {
                Text("NET WORTH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                
                Text(ledger.formattedBadge(ledger.netWorth))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Text(ledger.formattedNetWorthEUR)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Text("Dep")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(formatCompactLei(ledger.depositTotal))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPurple)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    
                    HStack(spacing: 3) {
                        Text("Crd")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(formatCompactLei(cardAmount))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .padding(.top, 2)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Middle: Top Outgoing Allocations
            VStack(alignment: .leading, spacing: 4) {
                Text("TOP OUTGOING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                
                ForEach(topOutgoingItems.prefix(2)) { item in
                    HStack {
                        Text(item.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(formatCompactLei(item.calculatedAmount))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPink)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Bottom: Global Macro Pulse (Gold, Dollar, BTC)
            VStack(alignment: .leading, spacing: 4) {
                Text("GLOBAL PULSE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                
                ForEach(financeService.macroIndicators.prefix(3)) { indicator in
                    HStack {
                        Text(indicator.emoji)
                            .font(.system(size: 10))
                        Text(indicator.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(indicator.formattedChangePercent)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(indicator.isPositive ? ThemeColors.accentGreen : ThemeColors.accentPink)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large (2x2) Multi-Panel Executive Hub
    @ViewBuilder
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Finances & Markets", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentGreen)
                Spacer()
                HStack(spacing: 4) {
                    Text("Open Hub")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentGreen)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentGreen)
                }
            }

            // Upper Panel: Net Worth + Liquid Breakdown
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NET WORTH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(ledger.formattedNetWorth)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text(ledger.formattedNetWorthEUR)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Deposits")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(ledger.formattedBadge(ledger.depositTotal))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPurple)
                    }
                    
                    HStack(spacing: 6) {
                        Text("Flow")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text("\(formatCompactNumber(ledger.incomingTotal)) / \(formatCompactNumber(ledger.outgoingTotal)) Lei")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 6) {
                        Text("Liquid")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text("\(formatCompactNumber(cardAmount)) / \(formatCompactNumber(cashAmount)) Lei")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Middle Section: Outgoing Allocations
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("KEY OUTGOING ALLOCATIONS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Spacer()
                    Text("Total \(ledger.formattedBadge(ledger.outgoingTotal))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPink)
                }
                
                HStack(spacing: 6) {
                    ForEach(topOutgoingItems.prefix(3)) { item in
                        HStack(spacing: 4) {
                            Text(cleanPillName(item.displayName))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(formatCompactNumber(item.calculatedAmount))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentPink)
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

            Divider()
                .background(Color.white.opacity(0.12))

            // Lower Section: 2 Columns (Top Watchlist on Left | Global Macro Pulse on Right)
            HStack(alignment: .top, spacing: 14) {
                // Watchlist column
                VStack(alignment: .leading, spacing: 5) {
                    Text("WATCHLIST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    ForEach(financeService.watchlistQuotes.prefix(3)) { quote in
                        HStack {
                            Text(quote.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(quote.formattedPrice)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                Text(quote.formattedChangePercent)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundColor(quote.isPositive ? ThemeColors.accentGreen : ThemeColors.accentPink)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                    .frame(height: 80)
                    .background(Color.white.opacity(0.12))

                // Macro Pulse column
                VStack(alignment: .leading, spacing: 5) {
                    Text("GLOBAL PULSE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    ForEach(financeService.macroIndicators.prefix(3)) { indicator in
                        HStack {
                            Text(indicator.emoji)
                                .font(.system(size: 11))
                            Text(indicator.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text(indicator.formattedChangePercent)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(indicator.isPositive ? ThemeColors.accentGreen : ThemeColors.accentPink)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Helpers
    private func formatCompactLei(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "%.1fM Lei", amount / 1_000_000)
        } else if amount >= 1_000 {
            let thousands = amount / 1_000
            if thousands.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0fK Lei", thousands)
            } else {
                return String(format: "%.1fK Lei", thousands)
            }
        } else if amount == 0 {
            return "0 Lei"
        } else {
            return String(format: "%.0f Lei", amount)
        }
    }

    private func formatCompactNumber(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            let thousands = amount / 1_000
            if thousands.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0fK", thousands)
            } else {
                return String(format: "%.1fK", thousands)
            }
        } else if amount == 0 {
            return "0"
        } else {
            return String(format: "%.0f", amount)
        }
    }

    private func cleanPillName(_ name: String) -> String {
        let firstPart = name.split(separator: "/").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? name
        return firstPart.isEmpty ? name : firstPart
    }
}

extension FinancesDashboardCard: Equatable {
    public static func == (lhs: FinancesDashboardCard, rhs: FinancesDashboardCard) -> Bool {
        lhs.size == rhs.size &&
        lhs.ledgerStore.rawText == rhs.ledgerStore.rawText &&
        lhs.financeService.watchlistQuotes == rhs.financeService.watchlistQuotes &&
        lhs.financeService.macroIndicators == rhs.financeService.macroIndicators
    }
}
