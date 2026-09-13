import Foundation

/// Represents an individual parsed line or item in a financial Smart Ledger section.
public struct SmartLedgerItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var key: String
    public var rawAmount: Double
    public var calculatedAmount: Double
    public var isScaled: Bool
    public var notes: [String]
    public var isPureNote: Bool
    public var sectionName: String
    public var lineIndex: Int
    public var rawLine: String
    public var percentageOfSection: Double
    
    /// Clean display title for UI pills (e.g. "Tigari" for "Tigari (40/45)").
    public var displayName: String {
        var clean = key
        // If key ends with a parenthesized suffix like "(40/45)", strip it for clean pill title display
        if let lastOpen = clean.lastIndex(of: "("), clean.hasSuffix(")") {
            let candidate = String(clean[..<lastOpen]).trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty {
                return candidate
            }
        }
        return key
    }
    
    public init(
        id: UUID = UUID(),
        sectionName: String = "",
        lineIndex: Int = -1,
        rawLine: String = "",
        key: String,
        rawAmount: Double = 0.0,
        calculatedAmount: Double = 0.0,
        isScaled: Bool = true,
        notes: [String] = [],
        isPureNote: Bool = false,
        percentageOfSection: Double = 0.0
    ) {
        self.id = id
        self.sectionName = sectionName
        self.lineIndex = lineIndex
        self.rawLine = rawLine
        self.key = key
        self.rawAmount = rawAmount
        self.calculatedAmount = calculatedAmount
        self.isScaled = isScaled
        self.notes = notes
        self.isPureNote = isPureNote
        self.percentageOfSection = percentageOfSection
    }
    
    /// Nicely formatted full amount in Romanian Lei (e.g. "15.100 Lei" or "53.156,47 Lei").
    public var formattedCalculatedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = calculatedAmount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.minimumFractionDigits = calculatedAmount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        let numStr = formatter.string(from: NSNumber(value: calculatedAmount)) ?? "\(calculatedAmount)"
        return "\(numStr) Lei"
    }
    
    /// User's original shorthand numeric notation (e.g. "151", "49", "10").
    public var formattedRawAmount: String {
        if rawAmount.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rawAmount))"
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: rawAmount)) ?? "\(rawAmount)"
        }
    }
}

/// Represents a distinct section within the Smart Ledger (e.g. Incoming, Outgoing, Balance, Deposit).
public struct SmartLedgerSection: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var items: [SmartLedgerItem]
    public var totalCalculated: Double
    public var totalRaw: Double
    public var isScaled: Bool
    
    public init(
        name: String,
        items: [SmartLedgerItem] = [],
        totalCalculated: Double = 0.0,
        totalRaw: Double = 0.0,
        isScaled: Bool = true
    ) {
        self.name = name
        self.items = items
        self.totalCalculated = totalCalculated
        self.totalRaw = totalRaw
        self.isScaled = isScaled
    }
    
    public var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = totalCalculated.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.minimumFractionDigits = totalCalculated.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        let numStr = formatter.string(from: NSNumber(value: totalCalculated)) ?? "\(totalCalculated)"
        return "\(numStr) Lei"
    }
    
    public var formattedRawTotal: String {
        if totalRaw.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(totalRaw))"
        } else {
            return String(format: "%.2f", totalRaw)
        }
    }
}

/// The fully parsed and computed state of the user's Smart Ledger text.
public struct ParsedSmartLedger: Codable, Equatable, Sendable {
    public var sections: [SmartLedgerSection]
    public var incomingTotal: Double
    public var outgoingTotal: Double
    public var balanceTotal: Double
    public var dentistTotal: Double
    public var depositTotal: Double
    public var netWorth: Double
    public var netWorthEUR: Double
    public var rawText: String
    
    public init(
        sections: [SmartLedgerSection] = [],
        incomingTotal: Double = 0.0,
        outgoingTotal: Double = 0.0,
        balanceTotal: Double = 0.0,
        dentistTotal: Double = 0.0,
        depositTotal: Double = 0.0,
        netWorth: Double = 0.0,
        netWorthEUR: Double = 0.0,
        rawText: String = ""
    ) {
        self.sections = sections
        self.incomingTotal = incomingTotal
        self.outgoingTotal = outgoingTotal
        self.balanceTotal = balanceTotal
        self.dentistTotal = dentistTotal
        self.depositTotal = depositTotal
        self.netWorth = netWorth
        self.netWorthEUR = netWorthEUR
        self.rawText = rawText
    }
    
    public var formattedNetWorth: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = netWorth.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.minimumFractionDigits = netWorth.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        let numStr = formatter.string(from: NSNumber(value: netWorth)) ?? "\(netWorth)"
        return "\(numStr) Lei"
    }
    
    public var formattedNetWorthEUR: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "€"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: netWorthEUR)) ?? "~\(Int(netWorthEUR)) €"
    }
    
    public var formattedIncomingTotal: String {
        formatCurrency(incomingTotal)
    }
    
    public var formattedOutgoingTotal: String {
        formatCurrency(outgoingTotal)
    }
    
    public var formattedBalanceTotal: String {
        formatCurrency(balanceTotal)
    }
    
    public var formattedDentistTotal: String {
        formatCurrency(dentistTotal)
    }
    
    public var formattedDepositTotal: String {
        formatCurrency(depositTotal)
    }
    
    /// Compact formatted string without decimal cents for small badge capsules (e.g. "127.156 Lei").
    public func formattedBadge(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        let numStr = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(numStr) Lei"
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.minimumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        let numStr = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(numStr) Lei"
    }
}
