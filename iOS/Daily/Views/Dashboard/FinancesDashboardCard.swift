import SwiftUI
import DailyCore

/// Liquid Glass Finances Card on the main Dashboard.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct FinancesDashboardCard: View {
    @ObservedObject private var financeService = FinanceService.shared
    
    public let size: DashboardWidgetSize
    private let onTap: () -> Void

    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
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
            .frame(maxWidth: .infinity, maxHeight: size == .wide ? nil : .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Small (1x1) Compact Net Worth Glance
    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Label("Finances", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeColors.accentGreen)
                
                Spacer()
                
                // 24h Change Pill
                HStack(spacing: 2) {
                    Image(systemName: financeService.summary.dayChangePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%.1f%%", abs(financeService.summary.dayChangePercent)))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundColor(financeService.summary.dayChangePercent >= 0 ? ThemeColors.accentGreen : ThemeColors.accentPink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (financeService.summary.dayChangePercent >= 0 ? ThemeColors.accentGreen : ThemeColors.accentPink).opacity(0.16)
                )
                .clipShape(Capsule())
            }
            
            Spacer(minLength: 2)

            // Net Worth
            VStack(alignment: .leading, spacing: 1) {
                Text("NET WORTH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                
                Text(compactCurrency(financeService.summary.netWorth))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Spacer(minLength: 2)

            // Cash & Invested Footer
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(ThemeColors.accentCyan)
                        .frame(width: 5, height: 5)
                    Text(compactCurrency(financeService.summary.cashTotal))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                
                Text("·")
                    .foregroundColor(Color.white.opacity(0.3))
                
                HStack(spacing: 3) {
                    Circle()
                        .fill(ThemeColors.accentPurple)
                        .frame(width: 5, height: 5)
                    Text(compactCurrency(financeService.summary.investmentsTotal))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)
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
            
            // 3 Columns: Net Worth | Cash | Investments
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NET WORTH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(financeService.summary.formattedNetWorth)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 2) {
                        Image(systemName: financeService.summary.dayChangePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%@%.2f%% today", financeService.summary.dayChangePercent >= 0 ? "+" : "", financeService.summary.dayChangePercent))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(financeService.summary.dayChangePercent >= 0 ? ThemeColors.accentGreen : ThemeColors.accentPink)
                }
                
                Divider()
                    .frame(height: 38)
                    .background(Color.white.opacity(0.15))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("CASH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(financeService.summary.formattedCash)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Text("\(financeService.accounts.filter { $0.type == .checking || $0.type == .savings }.count) accounts")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                Divider()
                    .frame(height: 38)
                    .background(Color.white.opacity(0.15))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("INVESTMENTS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(financeService.summary.formattedInvestments)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPurple)
                    
                    Text("\(financeService.watchlistQuotes.count) tracked assets")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
        }
    }

    // MARK: - Tall (1x2) Vertical 50/50 Split
    @ViewBuilder
    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Finances", systemImage: "chart.line.uptrend.xyaxis")
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
                
                Text(financeService.summary.formattedNetWorth)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Cash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(compactCurrency(financeService.summary.cashTotal))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                    
                    HStack(spacing: 4) {
                        Text("Inv")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(compactCurrency(financeService.summary.investmentsTotal))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPurple)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Bottom: Top Watchlist Items
            VStack(alignment: .leading, spacing: 6) {
                Text("TOP WATCHLIST")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                
                ForEach(financeService.watchlistQuotes.prefix(3)) { quote in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(quote.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text(quote.companyName)
                                .font(.system(size: 9))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(quote.formattedPrice)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text(quote.formattedChangePercent)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(quote.isPositive ? ThemeColors.accentGreen : ThemeColors.accentPink)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large (2x2) Multi-Panel Executive Hub
    @ViewBuilder
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Finances & Markets", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentGreen)
                Spacer()
                HStack(spacing: 4) {
                    Text("Finance Hub")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentGreen)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentGreen)
                }
            }

            // Upper Panel: Net Worth + Cash + Investments
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NET WORTH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(financeService.summary.formattedNetWorth)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 3) {
                        Image(systemName: financeService.summary.dayChangePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%@%.2f%% today", financeService.summary.dayChangePercent >= 0 ? "+" : "", financeService.summary.dayChangePercent))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(financeService.summary.dayChangePercent >= 0 ? ThemeColors.accentGreen : ThemeColors.accentPink)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Cash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(financeService.summary.formattedCash)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                    
                    HStack(spacing: 6) {
                        Text("Investments")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(financeService.summary.formattedInvestments)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPurple)
                    }
                }
            }
            .padding(.bottom, 2)

            Divider()
                .background(Color.white.opacity(0.12))

            // Lower Section: 2 Columns (Top Watchlist on Left | Global Macro Pulse on Right)
            HStack(alignment: .top, spacing: 14) {
                // Watchlist column
                VStack(alignment: .leading, spacing: 6) {
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
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                    .frame(height: 90)
                    .background(Color.white.opacity(0.12))

                // Macro Pulse column
                VStack(alignment: .leading, spacing: 6) {
                    Text("GLOBAL PULSE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    ForEach(financeService.macroIndicators.prefix(3)) { indicator in
                        HStack {
                            Text(indicator.emoji)
                                .font(.system(size: 12))
                            Text(indicator.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text(indicator.formattedChangePercent)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(indicator.isPositive ? ThemeColors.accentGreen : ThemeColors.accentPink)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Helpers
    private func compactCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }
}
