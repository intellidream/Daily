import Foundation

/// Type of financial ledger account.
public enum AccountType: String, Codable, CaseIterable, Sendable {
    case checking
    case savings
    case credit
    case investment
    
    public var displayName: String {
        switch self {
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .credit: return "Credit Card"
        case .investment: return "Investment"
        }
    }
    
    public var iconName: String {
        switch self {
        case .checking: return "banknote"
        case .savings: return "tray.and.arrow.down.fill"
        case .credit: return "creditcard.fill"
        case .investment: return "chart.pie.fill"
        }
    }
}

/// A bank, savings, credit, or investment account.
public struct FinanceAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var userId: String?
    public var name: String
    public var type: AccountType
    public var currency: String
    public var currentBalance: Double
    public var createdAt: Date
    public var updatedAt: Date?
    
    public init(
        id: String = UUID().uuidString,
        userId: String? = nil,
        name: String,
        type: AccountType,
        currency: String = "USD",
        currentBalance: Double = 0.0,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.currency = currency
        self.currentBalance = currentBalance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    public var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: currentBalance)) ?? String(format: "$%.2f", currentBalance)
    }
}

/// A financial income, expense, or transfer transaction.
public struct FinanceTransaction: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var accountId: String
    public var date: Date
    public var amount: Double
    public var category: String?
    public var description: String?
    
    public init(
        id: String = UUID().uuidString,
        accountId: String,
        date: Date = Date(),
        amount: Double,
        category: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.amount = amount
        self.category = category
        self.description = description
    }
    
    public var isIncome: Bool {
        amount > 0
    }
    
    public var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        let prefix = amount >= 0 ? "+" : ""
        let formatted = formatter.string(from: NSNumber(value: abs(amount))) ?? String(format: "$%.2f", abs(amount))
        return amount < 0 ? "-\(formatted)" : "\(prefix)\(formatted)"
    }
}

/// Financial asset class classification.
public enum MarketType: String, Codable, CaseIterable, Sendable {
    case stock
    case crypto
    case forex
    
    public var displayName: String {
        switch self {
        case .stock: return "Stocks"
        case .crypto: return "Crypto"
        case .forex: return "Forex"
        }
    }
    
    public var iconName: String {
        switch self {
        case .stock: return "chart.bar.xaxis"
        case .crypto: return "bitcoinsign.circle.fill"
        case .forex: return "dollarsign.arrow.circlepath"
        }
    }
}

/// Real-time and cached security market quote.
public struct StockQuote: Identifiable, Codable, Equatable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public var companyName: String
    public var currentPrice: Double
    public var change: Double
    public var percentChange: Double
    public var marketType: MarketType
    public var currency: String
    public var logoUrl: String?
    public var dayHigh: Double?
    public var dayLow: Double?
    public var volume: Int64?
    public var marketCap: Int64?
    public var exchange: String?
    
    public init(
        symbol: String,
        companyName: String,
        currentPrice: Double,
        change: Double,
        percentChange: Double,
        marketType: MarketType = .stock,
        currency: String = "USD",
        logoUrl: String? = nil,
        dayHigh: Double? = nil,
        dayLow: Double? = nil,
        volume: Int64? = nil,
        marketCap: Int64? = nil,
        exchange: String? = nil
    ) {
        self.symbol = symbol
        self.companyName = companyName
        self.currentPrice = currentPrice
        self.change = change
        self.percentChange = percentChange
        self.marketType = marketType
        self.currency = currency
        self.logoUrl = logoUrl
        self.dayHigh = dayHigh
        self.dayLow = dayLow
        self.volume = volume
        self.marketCap = marketCap
        self.exchange = exchange
    }
    
    public var isPositive: Bool {
        change >= 0
    }
    
    public var currencySymbol: String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "RON": return "lei"
        case "GBP": return "£"
        case "JPY": return "¥"
        default: return currency
        }
    }
    
    public var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.maximumFractionDigits = currentPrice < 1.0 ? 4 : 2
        return formatter.string(from: NSNumber(value: currentPrice)) ?? "\(currencySymbol)\(currentPrice)"
    }
    
    public var formattedChangePercent: String {
        let prefix = percentChange >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", prefix, percentChange)
    }
}

/// Global macroeconomic indicator matching the 6 Core Pillars in WinUI.
public struct MacroIndicator: Identifiable, Codable, Equatable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public var name: String
    public var pillar: String // Energy, Safe Haven, The King, Tech/Growth, Risk/Future, Stress
    public var emoji: String  // 🛢️, 🟡, 💵, 💻, ₿, 📊
    public var currentPrice: Double
    public var change: Double
    public var percentChange: Double
    public var currency: String
    public var dayHigh: Double?
    public var dayLow: Double?
    public var volume: Int64?
    
    public init(
        symbol: String,
        name: String,
        pillar: String,
        emoji: String,
        currentPrice: Double,
        change: Double,
        percentChange: Double,
        currency: String = "USD",
        dayHigh: Double? = nil,
        dayLow: Double? = nil,
        volume: Int64? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.pillar = pillar
        self.emoji = emoji
        self.currentPrice = currentPrice
        self.change = change
        self.percentChange = percentChange
        self.currency = currency
        self.dayHigh = dayHigh
        self.dayLow = dayLow
        self.volume = volume
    }
    
    public var isPositive: Bool {
        change >= 0
    }
    
    public var currencySymbol: String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        default: return currency
        }
    }
    
    /// Human-friendly interpretation of indicator movement, exactly matching WinUI MacroModels.cs.
    public var insight: String {
        switch pillar {
        case "Energy":
            return isPositive ? "Energy costs rising — inflation pressure" : "Energy easing — good for consumers"
        case "Safe Haven":
            return isPositive ? "Fear rising — investors seeking safety" : "Confidence returning — risk-on"
        case "The King":
            return isPositive ? "Dollar strong — pressure on emerging markets" : "Dollar weakening — relief for EM"
        case "Tech/Growth":
            return isPositive ? "Tech optimism — growth mode" : "Tech pullback — caution in markets"
        case "Risk/Future":
            return isPositive ? "Risk appetite high — speculative mood" : "Risk-off — caution prevails"
        case "Stress":
            return currentPrice > 30.0 ? "⚠️ Markets panicking (VIX > 30)" : (currentPrice > 20.0 ? "Elevated concern" : "Markets calm")
        default:
            return ""
        }
    }
    
    public var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: currentPrice)) ?? "\(currencySymbol)\(currentPrice)"
    }
    
    public var formattedChangePercent: String {
        let prefix = percentChange >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", prefix, percentChange)
    }
}

/// Country economic rate data for the Global Heatmap (Real Rate = Interest Rate - Inflation Rate).
public struct CountryEconomicData: Identifiable, Codable, Equatable, Sendable {
    public var id: String { countryCode }
    public let countryCode: String // ISO 3166-1 alpha-2 (US, RO, DE, etc.)
    public var countryName: String
    public var currencyCode: String
    public var interestRate: Double
    public var inflationRate: Double
    public var region: String
    
    public init(
        countryCode: String,
        countryName: String,
        currencyCode: String,
        interestRate: Double,
        inflationRate: Double,
        region: String
    ) {
        self.countryCode = countryCode
        self.countryName = countryName
        self.currencyCode = currencyCode
        self.interestRate = interestRate
        self.inflationRate = inflationRate
        self.region = region
    }
    
    /// Real Rate = Central Bank Interest Rate minus Inflation Rate.
    public var realRate: Double {
        interestRate - inflationRate
    }
    
    /// Flag emoji calculated from ISO country code.
    public var flagEmoji: String {
        let base: UInt32 = 127397
        var s = ""
        for v in countryCode.uppercased().unicodeScalars {
            s.unicodeScalars.append(UnicodeScalar(base + v.value)!)
        }
        return s
    }
    
    public var formattedRealRate: String {
        let prefix = realRate >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", prefix, realRate)
    }
}

/// Aggregated financial net worth and breakdown summary.
public struct FinanceSummary: Codable, Equatable, Sendable {
    public var netWorth: Double
    public var cashTotal: Double
    public var investmentsTotal: Double
    public var liabilitiesTotal: Double
    public var dayChange: Double
    public var dayChangePercent: Double
    public var baseCurrency: String
    
    public init(
        netWorth: Double = 0.0,
        cashTotal: Double = 0.0,
        investmentsTotal: Double = 0.0,
        liabilitiesTotal: Double = 0.0,
        dayChange: Double = 0.0,
        dayChangePercent: Double = 0.0,
        baseCurrency: String = "USD"
    ) {
        self.netWorth = netWorth
        self.cashTotal = cashTotal
        self.investmentsTotal = investmentsTotal
        self.liabilitiesTotal = liabilitiesTotal
        self.dayChange = dayChange
        self.dayChangePercent = dayChangePercent
        self.baseCurrency = baseCurrency
    }
    
    public var formattedNetWorth: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: netWorth)) ?? "$\(Int(netWorth))"
    }
    
    public var formattedCash: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: cashTotal)) ?? "$\(Int(cashTotal))"
    }
    
    public var formattedInvestments: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: investmentsTotal)) ?? "$\(Int(investmentsTotal))"
    }
    
    public var formattedLiabilities: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: liabilitiesTotal)) ?? "$\(Int(liabilitiesTotal))"
    }
}
