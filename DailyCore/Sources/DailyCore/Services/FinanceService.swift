import Foundation
import Combine

/// Core Finance Service managing accounts, transactions, live stock quotes, macro indicators, and economic heatmaps.
/// Coordinates offline-first local persistence and background market data refresh.
@MainActor
public final class FinanceService: ObservableObject {
    public static let shared = FinanceService()
    
    // MARK: - Published State
    @Published public var activeSubTab: FinanceSubTab = .money
    @Published public private(set) var accounts: [FinanceAccount] = []
    @Published public private(set) var transactions: [FinanceTransaction] = []
    @Published public private(set) var watchlistQuotes: [StockQuote] = []
    @Published public private(set) var macroIndicators: [MacroIndicator] = []
    @Published public private(set) var heatmapData: [CountryEconomicData] = []
    @Published public private(set) var summary: FinanceSummary = FinanceSummary()
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastUpdated: Date?
    
    // MARK: - Persistence Keys
    private let accountsKey = "daily_finance_accounts_v1"
    private let transactionsKey = "daily_finance_transactions_v1"
    private let watchlistKey = "daily_finance_watchlist_v1"
    
    // MARK: - 6 Core Macro Pillars Definition (Matching WinUI MacroModels.cs)
    private static let macroPillars: [(symbol: String, name: String, pillar: String, emoji: String, defaultPrice: Double, defaultChange: Double, defaultPct: Double, low: Double, high: Double)] = [
        ("CL=F",     "Crude Oil (WTI)",  "Energy",      "🛢️", 71.24,   -0.85, -1.18, 70.50, 72.80),
        ("GC=F",     "Gold",             "Safe Haven",  "🟡", 2894.60, 14.20,  0.49, 2875.0, 2905.0),
        ("DX-Y.NYB", "US Dollar Index",  "The King",    "💵", 104.15,  -0.22, -0.21, 103.90, 104.50),
        ("^NDX",     "Nasdaq 100",       "Tech/Growth", "💻", 21650.4, 185.3,  0.86, 21450.0, 21720.0),
        ("BTC-USD",  "Bitcoin",          "Risk/Future", "₿",  96450.0, 2150.0, 2.28, 93800.0, 97200.0),
        ("^VIX",     "VIX Volatility",   "Stress",      "📊", 14.85,   -0.65, -4.19, 14.20, 15.60)
    ]
    
    // MARK: - 25 Country Curated Q1 2026 Macro Heatmap (Matching WinUI HeatmapService.cs)
    private static let defaultHeatmap: [CountryEconomicData] = [
        // Americas
        CountryEconomicData(countryCode: "US", countryName: "United States", currencyCode: "USD", interestRate: 4.50, inflationRate: 2.8, region: "Americas"),
        CountryEconomicData(countryCode: "CA", countryName: "Canada", currencyCode: "CAD", interestRate: 3.25, inflationRate: 2.5, region: "Americas"),
        CountryEconomicData(countryCode: "BR", countryName: "Brazil", currencyCode: "BRL", interestRate: 14.25, inflationRate: 5.1, region: "Americas"),
        CountryEconomicData(countryCode: "MX", countryName: "Mexico", currencyCode: "MXN", interestRate: 9.50, inflationRate: 3.8, region: "Americas"),
        CountryEconomicData(countryCode: "AR", countryName: "Argentina", currencyCode: "ARS", interestRate: 29.0, inflationRate: 67.0, region: "Americas"),
        
        // Europe
        CountryEconomicData(countryCode: "DE", countryName: "Germany", currencyCode: "EUR", interestRate: 2.65, inflationRate: 2.3, region: "Europe"),
        CountryEconomicData(countryCode: "GB", countryName: "United Kingdom", currencyCode: "GBP", interestRate: 4.50, inflationRate: 3.0, region: "Europe"),
        CountryEconomicData(countryCode: "FR", countryName: "France", currencyCode: "EUR", interestRate: 2.65, inflationRate: 1.8, region: "Europe"),
        CountryEconomicData(countryCode: "CH", countryName: "Switzerland", currencyCode: "CHF", interestRate: 0.50, inflationRate: 1.1, region: "Europe"),
        CountryEconomicData(countryCode: "RO", countryName: "Romania", currencyCode: "RON", interestRate: 6.50, inflationRate: 5.0, region: "Europe"),
        CountryEconomicData(countryCode: "PL", countryName: "Poland", currencyCode: "PLN", interestRate: 5.75, inflationRate: 4.7, region: "Europe"),
        CountryEconomicData(countryCode: "TR", countryName: "Turkey", currencyCode: "TRY", interestRate: 42.50, inflationRate: 44.0, region: "Europe"),
        CountryEconomicData(countryCode: "SE", countryName: "Sweden", currencyCode: "SEK", interestRate: 2.25, inflationRate: 1.5, region: "Europe"),
        
        // Asia-Pacific
        CountryEconomicData(countryCode: "JP", countryName: "Japan", currencyCode: "JPY", interestRate: 0.50, inflationRate: 3.2, region: "Asia"),
        CountryEconomicData(countryCode: "CN", countryName: "China", currencyCode: "CNY", interestRate: 3.10, inflationRate: 0.5, region: "Asia"),
        CountryEconomicData(countryCode: "IN", countryName: "India", currencyCode: "INR", interestRate: 6.25, inflationRate: 4.5, region: "Asia"),
        CountryEconomicData(countryCode: "KR", countryName: "South Korea", currencyCode: "KRW", interestRate: 2.75, inflationRate: 2.0, region: "Asia"),
        CountryEconomicData(countryCode: "AU", countryName: "Australia", currencyCode: "AUD", interestRate: 4.10, inflationRate: 3.4, region: "Asia"),
        CountryEconomicData(countryCode: "ID", countryName: "Indonesia", currencyCode: "IDR", interestRate: 5.75, inflationRate: 3.0, region: "Asia"),
        CountryEconomicData(countryCode: "TH", countryName: "Thailand", currencyCode: "THB", interestRate: 2.00, inflationRate: 1.2, region: "Asia"),
        
        // Middle East & Africa
        CountryEconomicData(countryCode: "ZA", countryName: "South Africa", currencyCode: "ZAR", interestRate: 7.50, inflationRate: 5.3, region: "Africa"),
        CountryEconomicData(countryCode: "NG", countryName: "Nigeria", currencyCode: "NGN", interestRate: 27.50, inflationRate: 29.0, region: "Africa"),
        CountryEconomicData(countryCode: "SA", countryName: "Saudi Arabia", currencyCode: "SAR", interestRate: 5.50, inflationRate: 1.7, region: "Middle East"),
        CountryEconomicData(countryCode: "AE", countryName: "UAE", currencyCode: "AED", interestRate: 4.90, inflationRate: 2.1, region: "Middle East"),
        CountryEconomicData(countryCode: "EG", countryName: "Egypt", currencyCode: "EGP", interestRate: 27.25, inflationRate: 24.0, region: "Africa")
    ]
    
    // MARK: - Curated Baseline Watchlist
    private static let defaultWatchlist: [StockQuote] = [
        StockQuote(symbol: "AAPL", companyName: "Apple Inc.", currentPrice: 242.80, change: 3.45, percentChange: 1.44, marketType: .stock, logoUrl: "https://www.google.com/s2/favicons?domain=apple.com&sz=128", dayHigh: 244.50, dayLow: 239.80, volume: 54200000),
        StockQuote(symbol: "NVDA", companyName: "NVIDIA Corp.", currentPrice: 138.25, change: 4.12, percentChange: 3.07, marketType: .stock, logoUrl: "https://www.google.com/s2/favicons?domain=nvidia.com&sz=128", dayHigh: 140.10, dayLow: 134.50, volume: 88400000),
        StockQuote(symbol: "MSFT", companyName: "Microsoft Corp.", currentPrice: 428.60, change: 2.80, percentChange: 0.66, marketType: .stock, logoUrl: "https://www.google.com/s2/favicons?domain=microsoft.com&sz=128", dayHigh: 431.20, dayLow: 426.00, volume: 22100000),
        StockQuote(symbol: "TSLA", companyName: "Tesla, Inc.", currentPrice: 345.10, change: -5.40, percentChange: -1.54, marketType: .stock, logoUrl: "https://www.google.com/s2/favicons?domain=tesla.com&sz=128", dayHigh: 352.00, dayLow: 341.20, volume: 67300000),
        StockQuote(symbol: "BTC-USD", companyName: "Bitcoin", currentPrice: 96450.0, change: 2150.0, percentChange: 2.28, marketType: .crypto, logoUrl: "https://upload.wikimedia.org/wikipedia/commons/4/46/Bitcoin.svg", dayHigh: 97200.0, dayLow: 93800.0, volume: 38200000000),
        StockQuote(symbol: "ETH-USD", companyName: "Ethereum", currentPrice: 2780.40, change: 65.20, percentChange: 2.40, marketType: .crypto, logoUrl: "https://upload.wikimedia.org/wikipedia/commons/6/6f/Ethereum-icon-purple.svg", dayHigh: 2820.0, dayLow: 2710.0, volume: 16500000000),
        StockQuote(symbol: "EURUSD=X", companyName: "EUR / USD", currentPrice: 1.0482, change: 0.0031, percentChange: 0.30, marketType: .forex, logoUrl: "https://www.google.com/s2/favicons?domain=europa.eu&sz=128", dayHigh: 1.0510, dayLow: 1.0440, volume: nil)
    ]
    
    // MARK: - Initializer
    public init() {
        loadStoredData()
        recalculateSummary()
    }
    
    // MARK: - Data Loading & Synchronous Cache
    private func loadStoredData() {
        let defaults = UserDefaults.standard
        
        // 1. Accounts
        if let data = defaults.data(forKey: accountsKey),
           let saved = try? JSONDecoder().decode([FinanceAccount].self, from: data),
           !saved.isEmpty {
            self.accounts = saved
        } else {
            self.accounts = [
                FinanceAccount(name: "Checking Account", type: .checking, currency: "USD", currentBalance: 12450.0),
                FinanceAccount(name: "High Yield Savings", type: .savings, currency: "USD", currentBalance: 34800.0),
                FinanceAccount(name: "Active Brokerage", type: .investment, currency: "USD", currentBalance: 95330.0),
                FinanceAccount(name: "Platinum Card", type: .credit, currency: "USD", currentBalance: -1850.0)
            ]
            saveAccounts()
        }
        
        // 2. Transactions
        if let data = defaults.data(forKey: transactionsKey),
           let saved = try? JSONDecoder().decode([FinanceTransaction].self, from: data),
           !saved.isEmpty {
            self.transactions = saved
        } else {
            guard let checkingId = accounts.first(where: { $0.type == .checking })?.id,
                  let brokerageId = accounts.first(where: { $0.type == .investment })?.id else { return }
            
            let now = Date()
            self.transactions = [
                FinanceTransaction(accountId: checkingId, date: Calendar.current.date(byAdding: .hour, value: -2, to: now)!, amount: -124.50, category: "Groceries", description: "Fresh Market Organics"),
                FinanceTransaction(accountId: checkingId, date: Calendar.current.date(byAdding: .day, value: -1, to: now)!, amount: -6.50, category: "Dining", description: "Artisan Espresso"),
                FinanceTransaction(accountId: checkingId, date: Calendar.current.date(byAdding: .day, value: -2, to: now)!, amount: 4200.00, category: "Income", description: "Bi-Weekly Payroll"),
                FinanceTransaction(accountId: brokerageId, date: Calendar.current.date(byAdding: .day, value: -3, to: now)!, amount: 312.00, category: "Investment", description: "Apple Dividend Yield"),
                FinanceTransaction(accountId: checkingId, date: Calendar.current.date(byAdding: .day, value: -4, to: now)!, amount: -85.00, category: "Utilities", description: "Clean Energy Grid"),
                FinanceTransaction(accountId: checkingId, date: Calendar.current.date(byAdding: .day, value: -5, to: now)!, amount: -249.99, category: "Tech", description: "Electronics & Accessories")
            ]
            saveTransactions()
        }
        
        // 3. Watchlist
        if let data = defaults.data(forKey: watchlistKey),
           let saved = try? JSONDecoder().decode([StockQuote].self, from: data),
           !saved.isEmpty {
            self.watchlistQuotes = saved
        } else {
            self.watchlistQuotes = Self.defaultWatchlist
            saveWatchlist()
        }
        
        // 4. Macro Indicators
        self.macroIndicators = Self.macroPillars.map { p in
            MacroIndicator(
                symbol: p.symbol,
                name: p.name,
                pillar: p.pillar,
                emoji: p.emoji,
                currentPrice: p.defaultPrice,
                change: p.defaultChange,
                percentChange: p.defaultPct,
                dayHigh: p.high,
                dayLow: p.low
            )
        }
        
        // 5. Heatmap Data (Ordered by Real Rate descending)
        self.heatmapData = Self.defaultHeatmap.sorted { $0.realRate > $1.realRate }
    }
    
    // MARK: - Public API
    public func loadFinanceData(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        // Fetch Live Market Data in Background with Safe Network Timeout
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshMacroIndicators() }
            group.addTask { await self.refreshStockQuotes() }
        }
        
        lastUpdated = Date()
        recalculateSummary()
    }
    
    public func refreshMacroIndicators() async {
        var updated = [MacroIndicator]()
        for pillar in Self.macroPillars {
            if let live = await fetchYahooQuote(symbol: pillar.symbol) {
                let indicator = MacroIndicator(
                    symbol: pillar.symbol,
                    name: pillar.name,
                    pillar: pillar.pillar,
                    emoji: pillar.emoji,
                    currentPrice: live.currentPrice,
                    change: live.change,
                    percentChange: live.percentChange,
                    currency: live.currency,
                    dayHigh: live.dayHigh,
                    dayLow: live.dayLow,
                    volume: live.volume
                )
                updated.append(indicator)
            } else if let existing = macroIndicators.first(where: { $0.symbol == pillar.symbol }) {
                updated.append(existing)
            }
        }
        if !updated.isEmpty {
            self.macroIndicators = updated
        }
    }
    
    public func refreshStockQuotes() async {
        var updated = [StockQuote]()
        for item in watchlistQuotes {
            if let live = await fetchYahooQuote(symbol: item.symbol) {
                var q = item
                q.currentPrice = live.currentPrice
                q.change = live.change
                q.percentChange = live.percentChange
                q.dayHigh = live.dayHigh
                q.dayLow = live.dayLow
                q.volume = live.volume
                updated.append(q)
            } else {
                updated.append(item)
            }
        }
        if !updated.isEmpty {
            self.watchlistQuotes = updated
            saveWatchlist()
        }
    }
    
    // MARK: - Yahoo Finance v8 JSON Query Engine
    private func fetchYahooQuote(symbol: String) async -> (currentPrice: Double, change: Double, percentChange: Double, dayHigh: Double?, dayLow: Double?, volume: Int64?, currency: String)? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 4.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let meta = result["meta"] as? [String: Any] else {
                return nil
            }
            
            let regularMarketPrice = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue ?? 0.0
            let previousClose = (meta["chartPreviousClose"] as? NSNumber)?.doubleValue ?? regularMarketPrice
            let dayHigh = (meta["regularMarketDayHigh"] as? NSNumber)?.doubleValue
            let dayLow = (meta["regularMarketDayLow"] as? NSNumber)?.doubleValue
            let volume = (meta["regularMarketVolume"] as? NSNumber)?.int64Value
            let currency = (meta["currency"] as? String) ?? "USD"
            
            let change = regularMarketPrice - previousClose
            let percentChange = previousClose != 0.0 ? (change / previousClose) * 100.0 : 0.0
            
            return (regularMarketPrice, change, percentChange, dayHigh, dayLow, volume, currency)
        } catch {
            return nil
        }
    }
    
    // MARK: - Account & Transaction Operations
    public func addAccount(name: String, type: AccountType, balance: Double, currency: String = "USD") {
        let account = FinanceAccount(name: name, type: type, currency: currency, currentBalance: balance)
        accounts.append(account)
        saveAccounts()
        recalculateSummary()
    }
    
    public func addTransaction(accountId: String, amount: Double, category: String? = nil, description: String? = nil) {
        let tx = FinanceTransaction(accountId: accountId, amount: amount, category: category, description: description)
        transactions.insert(tx, at: 0)
        
        // Recalculate linked account balance
        if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
            accounts[idx].currentBalance += amount
            accounts[idx].updatedAt = Date()
        }
        
        saveTransactions()
        saveAccounts()
        recalculateSummary()
    }
    
    public func toggleWatchlistSymbol(_ quote: StockQuote) {
        if let idx = watchlistQuotes.firstIndex(where: { $0.symbol == quote.symbol }) {
            watchlistQuotes.remove(at: idx)
        } else {
            watchlistQuotes.append(quote)
        }
        saveWatchlist()
    }
    
    // MARK: - Recalculate Summary
    public func recalculateSummary() {
        var cash: Double = 0.0
        var investments: Double = 0.0
        var liabilities: Double = 0.0
        
        for account in accounts {
            switch account.type {
            case .checking, .savings:
                cash += account.currentBalance
            case .investment:
                investments += account.currentBalance
            case .credit:
                liabilities += abs(account.currentBalance)
            }
        }
        
        let netWorth = cash + investments - liabilities
        
        // Calculate 24h day change based on weighted investment daily performance
        let avgChangePercent = watchlistQuotes.isEmpty ? 0.85 : (watchlistQuotes.map(\.percentChange).reduce(0.0, +) / Double(watchlistQuotes.count))
        let dayChange = (investments * (avgChangePercent / 100.0))
        
        self.summary = FinanceSummary(
            netWorth: netWorth,
            cashTotal: cash,
            investmentsTotal: investments,
            liabilitiesTotal: liabilities,
            dayChange: dayChange,
            dayChangePercent: avgChangePercent,
            baseCurrency: "USD"
        )
    }
    
    // MARK: - Persistence Helpers
    private func saveAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: accountsKey)
        }
    }
    
    private func saveTransactions() {
        if let encoded = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(encoded, forKey: transactionsKey)
        }
    }
    
    private func saveWatchlist() {
        if let encoded = try? JSONEncoder().encode(watchlistQuotes) {
            UserDefaults.standard.set(encoded, forKey: watchlistKey)
        }
    }
}
