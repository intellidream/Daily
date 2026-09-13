import Foundation

/// Robust parser for the text-based Smart Ledger DSL.
/// Adheres strictly to the user-defined rules:
/// 1. Parentheses `(...)` are purely informative annotations and are completely ignored for value calculations.
/// 2. Shorthand scale: values from `**Incoming**` up to `**Deposit**` have a 100x multiplier (e.g. 151 = 15.100 Lei).
/// 3. Values in `**Deposit**` and afterwards are full, unscaled values (e.g. 44.000L = 44.000 Lei, 53.156,47 = 53.156,47 Lei).
/// 4. Net Worth = Deposits Total + Balance Total.
public final class SmartLedgerParser: Sendable {
    
    public static let shared = SmartLedgerParser()
    
    public init() {}
    
    public func parse(_ text: String, eurRate: Double = 5.0) -> ParsedSmartLedger {
        var sections: [SmartLedgerSection] = []
        let lines = text.components(separatedBy: CharacterSet.newlines)
        
        var currentSectionName = "Overview"
        var currentItems: [SmartLedgerItem] = []
        var currentSectionScaled = true
        var currentSectionExplicitTotal: Double? = nil
        var currentSectionRawTotal: Double? = nil
        var hasEncounteredDeposit = false
        
        func finishCurrentSection() {
            guard !currentItems.isEmpty || currentSectionExplicitTotal != nil else { return }
            
            // Calculate sum from items
            let itemsCalculatedSum = currentItems.reduce(0.0) { $0 + ($1.isPureNote ? 0.0 : $1.calculatedAmount) }
            let itemsRawSum = currentItems.reduce(0.0) { $0 + ($1.isPureNote ? 0.0 : $1.rawAmount) }
            
            let finalCalculatedTotal = currentSectionExplicitTotal ?? itemsCalculatedSum
            let finalRawTotal = currentSectionRawTotal ?? itemsRawSum
            
            // Compute percentage of section for outgoing/breakdown items
            var updatedItems = currentItems
            if finalCalculatedTotal > 0 {
                for i in 0..<updatedItems.count {
                    if !updatedItems[i].isPureNote {
                        updatedItems[i].percentageOfSection = updatedItems[i].calculatedAmount / finalCalculatedTotal
                    }
                }
            }
            
            let section = SmartLedgerSection(
                name: currentSectionName,
                items: updatedItems,
                totalCalculated: finalCalculatedTotal,
                totalRaw: finalRawTotal,
                isScaled: currentSectionScaled
            )
            sections.append(section)
            
            currentItems.removeAll()
            currentSectionExplicitTotal = nil
            currentSectionRawTotal = nil
        }
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and divider hyphens
            if line.isEmpty || line == "---" || line == "- - -" {
                continue
            }
            
            // Check for Markdown section header: **SectionName**
            if line.hasPrefix("**") && line.hasSuffix("**") && line.count > 4 {
                finishCurrentSection()
                let secName = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                currentSectionName = secName
                
                if secName.caseInsensitiveCompare("Deposit") == .orderedSame {
                    hasEncounteredDeposit = true
                }
                
                // Everything before Deposit is scaled x100; Deposit and after is unscaled
                currentSectionScaled = !hasEncounteredDeposit
                continue
            }
            
            // Handle lines enclosed in parentheses, e.g. (Total = 106) or (Concediu = 14/23)
            if line.hasPrefix("(") && line.hasSuffix(")") {
                let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                
                if inner.hasPrefix("Total =") || inner.hasPrefix("Total=") {
                    // This is an explicit total enclosed in parentheses (e.g. under Dentist: (Total = 106))
                    let parts = inner.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let parsedVal = parseNumericString(parts[1], isScaled: currentSectionScaled)
                        currentSectionExplicitTotal = parsedVal.calculated
                        currentSectionRawTotal = parsedVal.raw
                    }
                    continue
                } else {
                    // Pure informative note line
                    let item = SmartLedgerItem(
                        key: inner,
                        rawAmount: 0,
                        calculatedAmount: 0,
                        isScaled: currentSectionScaled,
                        notes: [inner],
                        isPureNote: true
                    )
                    currentItems.append(item)
                    continue
                }
            }
            
            // Check if line contains assignment: Key = Value
            if line.contains("=") {
                let parts = line.components(separatedBy: "=")
                let keyPart = parts[0].trimmingCharacters(in: .whitespaces)
                let valuePart = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                
                // Check if this is an explicit Total line: Total = 160
                if keyPart.caseInsensitiveCompare("Total") == .orderedSame {
                    let parsedVal = parseNumericString(valuePart, isScaled: currentSectionScaled)
                    currentSectionExplicitTotal = parsedVal.calculated
                    currentSectionRawTotal = parsedVal.raw
                    continue
                }
                
                // Extract all notes inside parentheses across the line
                let notes = extractParenthesesNotes(from: line)
                
                // Parse the numerical value (ignoring parentheses content)
                let parsedVal = parseNumericString(valuePart, isScaled: currentSectionScaled)
                
                // Clean the key: remove leading/trailing noise
                let cleanKey = cleanKeyName(keyPart)
                
                let item = SmartLedgerItem(
                    key: cleanKey,
                    rawAmount: parsedVal.raw,
                    calculatedAmount: parsedVal.calculated,
                    isScaled: currentSectionScaled,
                    notes: notes,
                    isPureNote: false
                )
                currentItems.append(item)
            } else {
                // Standalone note or comment line
                let item = SmartLedgerItem(
                    key: line,
                    rawAmount: 0,
                    calculatedAmount: 0,
                    isScaled: currentSectionScaled,
                    notes: [line],
                    isPureNote: true
                )
                currentItems.append(item)
            }
        }
        
        finishCurrentSection()
        
        // Extract key totals across sections
        let incomingSec = sections.first { $0.name.caseInsensitiveCompare("Incoming") == .orderedSame }
        let outgoingSec = sections.first { $0.name.caseInsensitiveCompare("Outgoing") == .orderedSame }
        let balanceSec = sections.first { $0.name.caseInsensitiveCompare("Balance") == .orderedSame }
        let dentistSec = sections.first { $0.name.caseInsensitiveCompare("Dentist") == .orderedSame }
        let depositSec = sections.first { $0.name.caseInsensitiveCompare("Deposit") == .orderedSame }
        
        let inTotal = incomingSec?.totalCalculated ?? 0.0
        let outTotal = outgoingSec?.totalCalculated ?? 0.0
        
        // Balance is explicit or (Incoming - Outgoing)
        let balTotal = balanceSec?.totalCalculated ?? max(0, inTotal - outTotal)
        let dentTotal = dentistSec?.totalCalculated ?? 0.0
        let depTotal = depositSec?.totalCalculated ?? 0.0
        
        // Net Worth formula agreed: Deposits Total + Balance Total
        let nw = depTotal + balTotal
        let nwEUR = eurRate > 0 ? nw / eurRate : 0.0
        
        return ParsedSmartLedger(
            sections: sections,
            incomingTotal: inTotal,
            outgoingTotal: outTotal,
            balanceTotal: balTotal,
            dentistTotal: dentTotal,
            depositTotal: depTotal,
            netWorth: nw,
            netWorthEUR: nwEUR,
            rawText: text
        )
    }
    
    // MARK: - Helper Parsing Methods
    
    /// Parses a raw value string into a tuple of (raw: Double, calculated: Double).
    /// Ignores all content inside parentheses `(...)` and drops comments after `//`.
    private func parseNumericString(_ valStr: String, isScaled: Bool) -> (raw: Double, calculated: Double) {
        var clean = valStr
        
        // 1. Remove all content inside parentheses (...) first (all parenthesized notes are ignored)
        clean = clean.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        
        // 2. Drop inline comments after //
        if let commentRange = clean.range(of: "//") {
            clean = String(clean[..<commentRange.lowerBound])
        }
        
        // 3. Remove letters and currency symbols (L, €, $, ~, etc.)
        let unwantedChars = CharacterSet(charactersIn: "L€$~$% ")
        clean = clean.components(separatedBy: unwantedChars).joined().trimmingCharacters(in: .whitespaces)
        
        guard !clean.isEmpty else { return (0.0, 0.0) }
        
        // 4. Parse Romanian / European decimal format
        var normalized = clean
        if normalized.contains(",") {
            // e.g. "53.156,47" -> remove dot (thousands separator), replace comma with dot
            normalized = normalized.replacingOccurrences(of: ".", with: "")
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        } else if normalized.contains(".") {
            let parts = normalized.components(separatedBy: ".")
            if parts.count == 2 && parts[1].count == 3 {
                // e.g. "44.000" or "30.000" -> dot is thousands separator
                normalized = normalized.replacingOccurrences(of: ".", with: "")
            }
        }
        
        guard let num = Double(normalized) else { return (0.0, 0.0) }
        
        let calculated = isScaled ? num * 100.0 : num
        return (raw: num, calculated: calculated)
    }
    
    /// Extracts all note strings found between round parentheses `(...)`.
    private func extractParenthesesNotes(from line: String) -> [String] {
        var notes: [String] = []
        let pattern = "\\((.*?)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return notes }
        
        let nsString = line as NSString
        let results = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in results {
            if match.numberOfRanges > 1 {
                let noteRange = match.range(at: 1)
                let note = nsString.substring(with: noteRange).trimmingCharacters(in: .whitespaces)
                // Filter out if it's purely a Total assignment
                if !note.isEmpty && !note.hasPrefix("Total =") {
                    notes.append(note)
                }
            }
        }
        return notes
    }
    
    /// Cleans key names, removing dangling slashes or extra notes if needed.
    private func cleanKeyName(_ key: String) -> String {
        var k = key.trimmingCharacters(in: .whitespaces)
        // If key ends with comment or //, clean it
        if let range = k.range(of: "//") {
            k = String(k[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return k
    }
}
