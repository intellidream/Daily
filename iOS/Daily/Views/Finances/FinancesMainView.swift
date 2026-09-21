import SwiftUI
import DailyCore

/// Comprehensive Finance Hub screen mirroring the WinUI FinancesDetailPage architecture.
/// Delivers real-time macroeconomic indicators, multi-asset security watchlists, and Smart Ledger account analytics.
public struct FinancesMainView: View {
    @ObservedObject private var financeService = FinanceService.shared
    @ObservedObject private var ledgerStore = SmartLedgerStore.shared
    @State private var selectedMarketType: MarketType? = nil // nil = All
    @State private var showingAddTransactionSheet: Bool = false
    @State private var showingAddAccountSheet: Bool = false
    @State private var showingLedgerEditorSheet: Bool = false
    @State private var selectedAdjustItem: SmartLedgerItem? = nil
    @State private var showingAddItemSheet: Bool = false
    @State private var targetSectionForNewItem: String = "Outgoing"
    
    private var activeSubTab: FinanceSubTab {
        get { financeService.activeSubTab }
        nonmutating set { financeService.activeSubTab = newValue }
    }
    
    public var onNavigateBack: (() -> Void)? = nil

    public init(onNavigateBack: (() -> Void)? = nil) {
        self.onNavigateBack = onNavigateBack
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-financeSubTabStocks") {
            FinanceService.shared.activeSubTab = .stocks
        } else if args.contains("-financeSubTabWorld") {
            FinanceService.shared.activeSubTab = .world
        } else if args.contains("-financeSubTabMoney") {
            FinanceService.shared.activeSubTab = .money
        }
        
        if args.contains("-testOpenItpAdjust") {
            if let outgoing = ledgerStore.parsedLedger.sections.first(where: { $0.name.lowercased() == "outgoing" }),
               let firstItem = outgoing.items.first {
                self._selectedAdjustItem = State(initialValue: firstItem)
            }
        } else if args.contains("-testOpenServiciuAdjust") {
            if let outgoing = ledgerStore.parsedLedger.sections.first(where: { $0.name.lowercased() == "outgoing" }),
               let servItem = outgoing.items.first(where: { $0.key.contains("Serviciu") }) {
                self._selectedAdjustItem = State(initialValue: servItem)
            }
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
                
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 18) {
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
                        .padding(.top, 6)
                        .padding(.bottom, 110) // Clearance for floating navigation capsule
                    }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .refreshable {
                        await financeService.loadFinanceData(forceRefresh: true)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddTransactionSheet) {
            AddTransactionSheet()
        }
        .sheet(isPresented: $showingAddAccountSheet) {
            AddAccountSheet()
        }
        .sheet(isPresented: $showingLedgerEditorSheet) {
            SmartLedgerEditorSheet()
        }
        .sheet(item: $selectedAdjustItem) { item in
            SmartLedgerQuickAdjustSheet(item: item)
        }
        .sheet(isPresented: $showingAddItemSheet) {
            AddLedgerItemSheet(defaultSectionName: targetSectionForNewItem)
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
        HStack(spacing: 10) {
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
            
            // Sub-Tab Switcher (World, Stocks, Money) replacing the title
            subTabSwitcher
        }
    }

    // MARK: - Sub-Tab Switcher
    @ViewBuilder
    private var subTabSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(FinanceSubTab.allCases) { tab in
                let isSelected = activeSubTab == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        activeSubTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(isSelected ? .white : ThemeColors.fgMutedDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            ThemeColors.accentGreen.opacity(0.70),
                                            ThemeColors.accentGreen.opacity(0.40)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                                }
                                .shadow(color: ThemeColors.accentGreen.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1)
        }
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
    // MARK: - 3. MONEY SECTION (Smart Ledger, Net Worth, Categorized Pills & DSL)
    // =========================================================================
    @ViewBuilder
    private var moneySection: some View {
        VStack(spacing: 20) {
            // Net Worth Hero Card
            netWorthHeroCard
            
            // Render Dynamic Categorized Sections from Parsed Ledger
            ForEach(ledgerStore.parsedLedger.sections) { section in
                ledgerSectionCard(section)
                    .id("section_\(section.name)")
            }
        }
    }
    
    // MARK: - Net Worth Hero Card
    private var netWorthHeroCard: some View {
        GlassCard(cornerRadius: 22, padding: 20) {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TOTAL NET WORTH")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .tracking(1.5)
                        
                        Text(ledgerStore.parsedLedger.formattedNetWorth)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 6) {
                            Text("Est.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text(ledgerStore.parsedLedger.formattedNetWorthEUR)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentGreen)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        showingLedgerEditorSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 12, weight: .bold))
                            Text("Edit Ledger")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(ThemeColors.accentGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(ThemeColors.accentGreen.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(ThemeColors.accentGreen.opacity(0.40), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                
                // 4 Breakdown Badges: Deposits, Balance, Incoming, Dentist
                HStack(spacing: 8) {
                    metricBadge(label: "DEPOZITE", value: ledgerStore.parsedLedger.formattedBadge(ledgerStore.parsedLedger.depositTotal), color: ThemeColors.accentGreen)
                    metricBadge(label: "SOLD", value: ledgerStore.parsedLedger.formattedBadge(ledgerStore.parsedLedger.balanceTotal), color: ThemeColors.accentCyan)
                    metricBadge(label: "INCOMING", value: ledgerStore.parsedLedger.formattedBadge(ledgerStore.parsedLedger.incomingTotal), color: ThemeColors.accentPurple)
                    if ledgerStore.parsedLedger.dentistTotal > 0 {
                        metricBadge(label: "DENTIST", value: ledgerStore.parsedLedger.formattedBadge(ledgerStore.parsedLedger.dentistTotal), color: ThemeColors.accentPink)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Ledger Section Card
    @ViewBuilder
    private func ledgerSectionCard(_ section: SmartLedgerSection) -> some View {
        let (icon, color, title) = sectionStyle(for: section.name)
        
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Section Header
                HStack(alignment: .center) {
                    Label(title, systemImage: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(color)
                    
                    if section.name.lowercased() != "balance" && section.name.lowercased() != "dentist" {
                        Button {
                            triggerHaptic()
                            targetSectionForNewItem = section.name
                            showingAddItemSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Adaugă")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(section.formattedTotal)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        if section.isScaled && section.totalRaw > 0 {
                            Text("(\(section.formattedRawTotal))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                
                if section.items.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: section.name.lowercased() == "balance" ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(color)
                        Text(section.name.lowercased() == "balance" ? (section.totalCalculated == 0 ? "Zero-Based Budget Balanced · Toți banii au fost alocați" : "Surplus lunar nealocat") : "Sold tratament dentar / obligații planificate")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(color.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    // Section Items
                    VStack(spacing: 10) {
                        ForEach(section.items) { item in
                            ledgerItemRow(item: item, sectionColor: color)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Ledger Item Pill Row
    @ViewBuilder
    private func ledgerItemRow(item: SmartLedgerItem, sectionColor: Color) -> some View {
        if item.isPureNote {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Text(item.key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    // Horizontally scrollable title allowing left-right dragging, tap opens quick adjust
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(item.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.vertical, 2)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .onTapGesture {
                        selectedAdjustItem = item
                    }
                    
                    // Quick adjust indicator button
                    Button {
                        selectedAdjustItem = item
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ThemeColors.fgMutedDark.opacity(0.7))
                            .padding(.horizontal, 2)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer(minLength: 6)
                    
                    // Amount badges
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(item.formattedCalculatedAmount)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        if item.currency == "EUR" {
                            Text("~\(item.formattedLeiAmount)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        } else if item.isScaled && item.rawAmount > 0 {
                            Text("(\(item.formattedRawAmount))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    
                    // Inline Glass Stepper Controls [ - ] [ + ]
                    HStack(spacing: 4) {
                        Button {
                            triggerHaptic()
                            ledgerStore.adjustItem(item: item, deltaRaw: item.isScaled ? -1 : -100)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            triggerHaptic()
                            ledgerStore.adjustItem(item: item, deltaRaw: item.isScaled ? 1 : 100)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(sectionColor.opacity(0.25))
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(sectionColor.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Progress bar for percentage of section if applicable
                if item.percentageOfSection > 0 {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [sectionColor, sectionColor.opacity(0.65)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                                    .frame(width: max(4, geo.size.width * CGFloat(item.percentageOfSection)), height: 4)
                            }
                        }
                        .frame(height: 4)
                        
                        Text(String(format: "%.1f%%", item.percentageOfSection * 100))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(sectionColor)
                    }
                }
                
                // Informative notes pills underneath
                if !item.notes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(item.notes, id: \.self) { note in
                                Button {
                                    selectedAdjustItem = item
                                } label: {
                                    Text(note)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    // MARK: - Section Styling Helper
    private func sectionStyle(for name: String) -> (icon: String, color: Color, title: String) {
        switch name.lowercased() {
        case "incoming":
            return ("arrow.down.left.circle.fill", ThemeColors.accentPurple, "Incoming")
        case "outgoing":
            return ("arrow.up.right.circle.fill", ThemeColors.accentOrange, "Outgoing")
        case "balance":
            return ("equal.circle.fill", ThemeColors.accentCyan, "Balance")
        case "dentist":
            return ("cross.case.fill", ThemeColors.accentPink, "Dentist")
        case "deposit":
            return ("building.columns.fill", ThemeColors.accentGreen, "Deposits & Savings")
        default:
            return ("list.bullet.rectangle.portrait.fill", ThemeColors.accentCyan, name.capitalized)
        }
    }

    @ViewBuilder
    private func metricBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(ThemeColors.fgMutedDark)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
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
