import SwiftUI
import DailyCore

public enum FinanceSubTab: String, CaseIterable, Identifiable {
    case world = "World"
    case stocks = "Stocks"
    case money = "Money"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .world: return "globe.americas.fill"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .money: return "banknote.fill"
        }
    }
}

/// Comprehensive Finance Hub screen mirroring the WinUI FinancesDetailPage architecture.
/// Delivers real-time macroeconomic indicators, multi-asset security watchlists, and Smart Ledger account analytics.
public struct FinancesMainView: View {
    @ObservedObject private var financeService = FinanceService.shared
    @State private var activeSubTab: FinanceSubTab = .world
    @State private var selectedMarketType: MarketType? = nil // nil = All
    @State private var showingAddTransactionSheet: Bool = false
    @State private var showingAddAccountSheet: Bool = false
    
    public var onNavigateBack: (() -> Void)? = nil

    public init(onNavigateBack: (() -> Void)? = nil) {
        self.onNavigateBack = onNavigateBack
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-financeSubTabStocks") {
            self._activeSubTab = State(initialValue: .stocks)
        } else if args.contains("-financeSubTabMoney") {
            self._activeSubTab = State(initialValue: .money)
        } else if args.contains("-financeSubTabWorld") {
            self._activeSubTab = State(initialValue: .world)
        }
    }

    public var body: some View {
        LiquidGlassBackground {
            VStack(spacing: 0) {
                // Top Header Bar
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        // Sub-Tab Switcher (World, Stocks, Money)
                        subTabSwitcher
                        
                        // Active Tab Content
                        switch activeSubTab {
                        case .world:
                            worldSection
                        case .stocks:
                            stocksSection
                        case .money:
                            moneySection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110) // Clearance for floating navigation capsule
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .refreshable {
                    await financeService.loadFinanceData(forceRefresh: true)
                }
            }
        }
        .sheet(isPresented: $showingAddTransactionSheet) {
            AddTransactionSheet()
        }
        .sheet(isPresented: $showingAddAccountSheet) {
            AddAccountSheet()
        }
        .task {
            if financeService.macroIndicators.isEmpty || financeService.watchlistQuotes.isEmpty {
                await financeService.loadFinanceData()
            }
        }
    }

    // MARK: - Header Bar
    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 12) {
            if let onNavigateBack = onNavigateBack {
                Button(action: onNavigateBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            
            // Icon & Title
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(ThemeColors.accentGreen.opacity(0.20))
                        .frame(width: 38, height: 38)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ThemeColors.accentGreen)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finances")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Portfolio overview and market insights")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
            
            Spacer()
        }
    }

    // MARK: - Sub-Tab Switcher
    @ViewBuilder
    private var subTabSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(FinanceSubTab.allCases) { tab in
                let isSelected = activeSubTab == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        activeSubTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(isSelected ? .white : ThemeColors.fgMutedDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(isSelected ? ThemeColors.accentGreen.opacity(0.28) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(ThemeColors.accentGreen.opacity(0.55), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // =========================================================================
    // MARK: - 1. WORLD SECTION (Macro Indicators & Real Interest Rates Heatmap)
    // =========================================================================
    @ViewBuilder
    private var worldSection: some View {
        VStack(spacing: 20) {
            // Global Pulse (6 Core Pillars)
            GlassCard(cornerRadius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Global Pulse", systemImage: "waveform.path.ecg")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Spacer()
                        Text("6 Core Pillars")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    
                    VStack(spacing: 10) {
                        ForEach(financeService.macroIndicators) { indicator in
                            macroPillarCard(indicator)
                        }
                    }
                }
            }

            // Global Heatmap (Real Interest Rates: Rate - Inflation)
            GlassCard(cornerRadius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Global Real Rates", systemImage: "thermometer.medium")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ThemeColors.accentOrange)
                        Spacer()
                        Text("Rate - Inflation")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    
                    Text("Money flows toward higher real yields. Positive real rates attract global capital.")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)

                    // Heatmap Scale Legend
                    HStack(spacing: 6) {
                        Text("Negative")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.accentPink)
                        
                        LinearGradient(
                            colors: [ThemeColors.accentPink, ThemeColors.accentOrange, ThemeColors.accentGreen],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 6)
                        .clipShape(Capsule())
                        
                        Text("High Yield")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.accentGreen)
                    }
                    .padding(.vertical, 2)

                    // Countries Grid / List
                    VStack(spacing: 8) {
                        ForEach(financeService.heatmapData) { country in
                            countryHeatmapRow(country)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func macroPillarCard(_ indicator: MacroIndicator) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Emoji icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        }
                    Text(indicator.emoji)
                        .font(.system(size: 18))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(indicator.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(indicator.pillar)
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(indicator.formattedPrice)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 2) {
                        Image(systemName: indicator.isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(indicator.formattedChangePercent)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(indicator.isPositive ? ThemeColors.accentGreen : ThemeColors.accentPink)
                }
            }
            
            // Insight bar
            if !indicator.insight.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundColor(indicator.isPositive ? ThemeColors.accentGreen : ThemeColors.accentOrange)
                    Text(indicator.insight)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.85))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func countryHeatmapRow(_ country: CountryEconomicData) -> some View {
        HStack(spacing: 10) {
            Text(country.flagEmoji)
                .font(.system(size: 18))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(country.countryName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(country.currencyCode)
                    .font(.system(size: 10))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            
            Spacer()
            
            // Rate equation: Rate - Inflation
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Interest")
                        .font(.system(size: 9))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(String(format: "%.2f%%", country.interestRate))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text("-")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.3))
                
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Inflation")
                        .font(.system(size: 9))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(String(format: "%.2f%%", country.inflationRate))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text("=")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.3))
                
                // Real Rate Pill
                Text(country.formattedRealRate)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(country.realRate >= 0 ? ThemeColors.accentGreen : ThemeColors.accentPink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (country.realRate >= 0 ? ThemeColors.accentGreen : ThemeColors.accentPink).opacity(0.16)
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // =========================================================================
    // MARK: - 2. STOCKS SECTION (Watchlist, Filter Segments & Rich Quotes)
    // =========================================================================
    @ViewBuilder
    private var stocksSection: some View {
        VStack(spacing: 16) {
            // Market Type Filter Pills
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: selectedMarketType == nil) {
                    selectedMarketType = nil
                }
                ForEach(MarketType.allCases, id: \.self) { type in
                    filterChip(label: type.displayName, isSelected: selectedMarketType == type) {
                        selectedMarketType = type
                    }
                }
            }

            // Quotes List
            let filtered = financeService.watchlistQuotes.filter { q in
                guard let selected = selectedMarketType else { return true }
                return q.marketType == selected
            }

            if filtered.isEmpty {
                GlassCard(cornerRadius: 18, padding: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text("No items in this market category")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(filtered) { quote in
                    stockQuoteCard(quote)
                }
            }
        }
    }

    @ViewBuilder
    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : ThemeColors.fgMutedDark)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? ThemeColors.accentGreen.opacity(0.28) : Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay {
                    if isSelected {
                        Capsule().strokeBorder(ThemeColors.accentGreen.opacity(0.55), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stockQuoteCard(_ quote: StockQuote) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Logo or Avatar
                    if let logoUrl = quote.logoUrl, let url = URL(string: logoUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            default:
                                fallbackAssetIcon(quote)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .background(Color.white.opacity(0.08))
                    } else {
                        fallbackAssetIcon(quote)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(quote.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text(quote.companyName)
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(quote.formattedPrice)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 2) {
                            Image(systemName: quote.isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(quote.formattedChangePercent)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(quote.isPositive ? ThemeColors.accentGreen : ThemeColors.accentPink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((quote.isPositive ? ThemeColors.accentGreen : ThemeColors.accentPink).opacity(0.16))
                        .clipShape(Capsule())
                    }
                }

                // Day Range Bar & Volume Footer
                if let low = quote.dayLow, let high = quote.dayHigh {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DAY RANGE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text(String(format: "%.2f - %.2f", low, high))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        if let vol = quote.volume {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("VOLUME")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text(formatVolume(vol))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .overlay(alignment: .top) {
                        Divider().background(Color.white.opacity(0.08))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fallbackAssetIcon(_ quote: StockQuote) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 36, height: 36)
            Image(systemName: quote.marketType.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ThemeColors.accentGreen)
        }
    }

    // =========================================================================
    // MARK: - 3. MONEY SECTION (Net Worth, Accounts, Ledger & Transactions)
    // =========================================================================
    @ViewBuilder
    private var moneySection: some View {
        VStack(spacing: 20) {
            // Net Worth Hero Card
            GlassCard(cornerRadius: 22, padding: 22) {
                VStack(spacing: 16) {
                    Text("TOTAL NET WORTH")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .tracking(1.5)

                    Text(financeService.summary.formattedNetWorth)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    HStack(spacing: 4) {
                        Image(systemName: financeService.summary.dayChangePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(format: "%@$%.2f (%@%.2f%%)", 
                                    financeService.summary.dayChange >= 0 ? "+" : "",
                                    financeService.summary.dayChange,
                                    financeService.summary.dayChangePercent >= 0 ? "+" : "",
                                    financeService.summary.dayChangePercent))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(financeService.summary.dayChangePercent >= 0 ? ThemeColors.accentGreen : ThemeColors.accentPink)

                    // 3 Breakdown Badges: Cash, Investments, Liabilities
                    HStack(spacing: 12) {
                        metricBadge(label: "CASH", value: financeService.summary.formattedCash, color: ThemeColors.accentCyan)
                        metricBadge(label: "INVESTED", value: financeService.summary.formattedInvestments, color: ThemeColors.accentPurple)
                        if financeService.summary.liabilitiesTotal > 0 {
                            metricBadge(label: "DEBT", value: financeService.summary.formattedLiabilities, color: ThemeColors.accentPink)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Accounts Breakdown Card
            GlassCard(cornerRadius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Accounts & Balances", systemImage: "creditcard.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Spacer()
                        Button {
                            showingAddAccountSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 8) {
                        ForEach(financeService.accounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }

            // Recent Transactions Ledger
            GlassCard(cornerRadius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Recent Transactions", systemImage: "list.bullet.rectangle.portrait.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ThemeColors.accentGreen)
                        Spacer()
                        Button {
                            showingAddTransactionSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Add Entry")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(ThemeColors.accentGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ThemeColors.accentGreen.opacity(0.18))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if financeService.transactions.isEmpty {
                        Text("No recorded transactions yet.")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(financeService.transactions.prefix(8)) { tx in
                                transactionRow(tx)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metricBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(ThemeColors.fgMutedDark)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func accountRow(_ account: FinanceAccount) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 34, height: 34)
                Image(systemName: account.type.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(account.type == .credit ? ThemeColors.accentPink : ThemeColors.accentCyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(account.type.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }

            Spacer()

            Text(account.formattedBalance)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(account.currentBalance >= 0 ? .white : ThemeColors.accentPink)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func transactionRow(_ tx: FinanceTransaction) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.description ?? "Transaction")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                HStack(spacing: 6) {
                    if let cat = tx.category {
                        Text(cat)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(tx.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }

            Spacer()

            Text(tx.formattedAmount)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(tx.amount >= 0 ? ThemeColors.accentGreen : .white)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    // MARK: - Formatters
    private func formatVolume(_ v: Int64) -> String {
        if v >= 1_000_000_000 {
            return String(format: "%.1fB", Double(v) / 1_000_000_000.0)
        } else if v >= 1_000_000 {
            return String(format: "%.1fM", Double(v) / 1_000_000.0)
        } else if v >= 1_000 {
            return String(format: "%.1fK", Double(v) / 1_000.0)
        } else {
            return "\(v)"
        }
    }
}

// MARK: - Add Transaction Modal Sheet
struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var financeService = FinanceService.shared
    
    @State private var selectedAccountId: String = ""
    @State private var amountString: String = ""
    @State private var isExpense: Bool = true
    @State private var description: String = ""
    @State private var category: String = "Groceries"
    
    private let categories = ["Groceries", "Dining", "Tech", "Utilities", "Salary", "Investment", "Shopping", "Other"]

    var body: some View {
        NavigationStack {
            LiquidGlassBackground {
                VStack(spacing: 16) {
                    GlassCard(cornerRadius: 18, padding: 18) {
                        VStack(spacing: 14) {
                            // Income / Expense Toggle
                            Picker("Type", selection: $isExpense) {
                                Text("Expense").tag(true)
                                Text("Income").tag(false)
                            }
                            .pickerStyle(.segmented)

                            // Amount Field
                            HStack {
                                Text("$")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                TextField("0.00", text: $amountString)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(.white)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Account Picker
                            if !financeService.accounts.isEmpty {
                                HStack {
                                    Text("Account")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                    Spacer()
                                    Picker("Account", selection: $selectedAccountId) {
                                        ForEach(financeService.accounts) { acc in
                                            Text(acc.name).tag(acc.id)
                                        }
                                    }
                                    .tint(ThemeColors.accentGreen)
                                }
                            }

                            // Category Picker
                            HStack {
                                Text("Category")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Spacer()
                                Picker("Category", selection: $category) {
                                    ForEach(categories, id: \.self) { cat in
                                        Text(cat).tag(cat)
                                    }
                                }
                                .tint(ThemeColors.accentGreen)
                            }

                            // Description
                            TextField("Description / Merchant", text: $description)
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Spacer()
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ThemeColors.accentGreen)
                    .disabled(Double(amountString) == nil)
                }
            }
            .onAppear {
                if let first = financeService.accounts.first {
                    selectedAccountId = first.id
                }
            }
        }
    }

    private func saveTransaction() {
        guard let rawAmount = Double(amountString), !selectedAccountId.isEmpty else { return }
        let finalAmount = isExpense ? -abs(rawAmount) : abs(rawAmount)
        financeService.addTransaction(
            accountId: selectedAccountId,
            amount: finalAmount,
            category: category,
            description: description.isEmpty ? category : description
        )
        dismiss()
    }
}

// MARK: - Add Account Modal Sheet
struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var financeService = FinanceService.shared
    
    @State private var name: String = ""
    @State private var accountType: AccountType = .checking
    @State private var initialBalanceString: String = ""
    
    var body: some View {
        NavigationStack {
            LiquidGlassBackground {
                VStack(spacing: 16) {
                    GlassCard(cornerRadius: 18, padding: 18) {
                        VStack(spacing: 14) {
                            TextField("Account Name (e.g. Daily Vault)", text: $name)
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(.white)

                            HStack {
                                Text("Type")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Spacer()
                                Picker("Type", selection: $accountType) {
                                    ForEach(AccountType.allCases, id: \.self) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .tint(ThemeColors.accentCyan)
                            }

                            HStack {
                                Text("Starting Balance")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Spacer()
                                TextField("0.00", text: $initialBalanceString)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 100)
                                    .padding(8)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Spacer()
                }
            }
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let balance = Double(initialBalanceString) ?? 0.0
                        financeService.addAccount(name: name, type: accountType, balance: balance)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
