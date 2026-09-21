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
        
        for (lineIndex, rawLine) in lines.enumerated() {
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
                        let parsedVal = parseNumericString(parts[1], isScaled: currentSectionScaled, eurRate: eurRate)
                        currentSectionExplicitTotal = parsedVal.calculated
                        currentSectionRawTotal = parsedVal.raw
                    }
                    continue
                } else {
                    // Pure informative note line
                    let item = SmartLedgerItem(
                        sectionName: currentSectionName,
                        lineIndex: lineIndex,
                        rawLine: rawLine,
                        key: inner,
                        rawAmount: 0,
                        calculatedAmount: 0,
                        currency: "Lei",
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
                    let parsedVal = parseNumericString(valuePart, isScaled: currentSectionScaled, eurRate: eurRate)
                    currentSectionExplicitTotal = parsedVal.calculated
                    currentSectionRawTotal = parsedVal.raw
                    continue
                }
                
                // Extract all notes inside parentheses across the line
                let notes = extractParenthesesNotes(from: line)
                
                // Parse the numerical value (ignoring parentheses content)
                let parsedVal = parseNumericString(valuePart, isScaled: currentSectionScaled, eurRate: eurRate)
                
                // Clean the key: remove leading/trailing noise
                let cleanKey = cleanKeyName(keyPart)
                
                let item = SmartLedgerItem(
                    sectionName: currentSectionName,
                    lineIndex: lineIndex,
                    rawLine: rawLine,
                    key: cleanKey,
                    rawAmount: parsedVal.raw,
                    calculatedAmount: parsedVal.calculated,
                    currency: parsedVal.isEUR ? "EUR" : "Lei",
                    isScaled: currentSectionScaled,
                    notes: notes,
                    isPureNote: false
                )
                currentItems.append(item)
            } else {
                // Standalone note or comment line
                let item = SmartLedgerItem(
                    sectionName: currentSectionName,
                    lineIndex: lineIndex,
                    rawLine: rawLine,
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
    
    /// Parses a raw value string into a tuple of (raw: Double, calculated: Double, isEUR: Bool).
    /// Ignores all content inside parentheses `(...)` and drops comments after `//`.
    /// When currency is EUR (indicated by € or EUR outside parentheses), converts calculated amount to Lei using eurRate.
    private func parseNumericString(_ valStr: String, isScaled: Bool, eurRate: Double = 5.0) -> (raw: Double, calculated: Double, isEUR: Bool) {
        var clean = valStr
        
        // 1. Remove all content inside parentheses (...) first (all parenthesized notes are ignored)
        clean = clean.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        
        // 2. Drop inline comments after //
        if let commentRange = clean.range(of: "//") {
            clean = String(clean[..<commentRange.lowerBound])
        }
        
        // Detect EUR symbol or letters outside parentheses and comments
        let isEUR = clean.contains("€") || clean.range(of: "EUR", options: .caseInsensitive) != nil
        
        // 3. Remove letters and currency symbols (L, €, $, ~, etc.)
        let unwantedChars = CharacterSet(charactersIn: "L€$~$% ")
        clean = clean.components(separatedBy: unwantedChars).joined().trimmingCharacters(in: .whitespaces)
        clean = clean.replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
        
        guard !clean.isEmpty else { return (0.0, 0.0, isEUR) }
        
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
        
        guard let num = Double(normalized) else { return (0.0, 0.0, isEUR) }
        
        let baseCalculated = isScaled ? num * 100.0 : num
        let calculated = isEUR ? baseCalculated * eurRate : baseCalculated
        return (raw: num, calculated: calculated, isEUR: isEUR)
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
    
    /// Cleans key names: strips parenthesized metadata notes (...) and trailing slashes,
    /// while strictly preserving intentional double-slashes "//" inside key categories (e.g. Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27).
    private func cleanKeyName(_ key: String) -> String {
        var k = key.trimmingCharacters(in: .whitespaces)
        
        // 1. Remove parenthesized metadata expressions (...) from the key
        k = k.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        k = k.trimmingCharacters(in: .whitespaces)
        
        // 2. If the main text ends in a trailing slash '/' (because it was followed by a parenthesized comment), strip it
        while k.hasSuffix("/") {
            k.removeLast()
            k = k.trimmingCharacters(in: .whitespaces)
        }
        
        return k
    }
    
    // MARK: - Two-Way DSL Mutation Engine
    
    /// Adjusts an existing item's raw amount by deltaRaw (e.g. +1 or -1 in scaled sections, or +100/-100 in unscaled).
    /// Preserves keys, parentheses notes, and comments, and automatically recalculates section totals and balance.
    public func adjustItemAmount(in text: String, lineIndex: Int, deltaRaw: Double) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lineIndex >= 0 && lineIndex < lines.count else { return text }
        let line = lines[lineIndex]
        guard line.contains("=") else { return text }
        let parts = line.components(separatedBy: "=")
        let valuePart = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
        let parsed = parseNumericString(valuePart, isScaled: false)
        let newRaw = max(0, parsed.raw + deltaRaw)
        return setItemAmount(in: text, lineIndex: lineIndex, newRaw: newRaw)
    }
    
    /// Sets an item's raw amount directly to newRaw at lineIndex.
    public func setItemAmount(in text: String, lineIndex: Int, newRaw: Double) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lineIndex >= 0 && lineIndex < lines.count else { return text }
        
        let oldLine = lines[lineIndex]
        guard let eqRange = oldLine.range(of: "=") else { return text }
        
        let keyPart = String(oldLine[..<eqRange.upperBound]) // e.g. "Card =" or "Tigari (40/45) ="
        let afterEq = String(oldLine[eqRange.upperBound...])
        
        // Find where notes `(` or comments `//` begin
        var noteOrCommentIndex = afterEq.endIndex
        if let parenIndex = afterEq.firstIndex(of: "(") {
            noteOrCommentIndex = min(noteOrCommentIndex, parenIndex)
        }
        if let slashRange = afterEq.range(of: "//") {
            noteOrCommentIndex = min(noteOrCommentIndex, slashRange.lowerBound)
        }
        
        let numRegion = String(afterEq[..<noteOrCommentIndex])
        let restOfLine = String(afterEq[noteOrCommentIndex...])
        
        // Preserve currency / units suffix if present
        var suffix = ""
        if numRegion.contains("€") {
            suffix = "€"
        } else if numRegion.range(of: "EUR", options: .caseInsensitive) != nil {
            suffix = " EUR"
        } else if numRegion.contains("L") {
            suffix = "L"
        } else if numRegion.contains("$") {
            suffix = "$"
        }
        
        let formattedNum = formatNumberForDsl(value: newRaw, originalString: numRegion)
        let spaceBeforeRest = (restOfLine.isEmpty || restOfLine.hasPrefix(" ")) ? "" : " "
        
        lines[lineIndex] = "\(keyPart) \(formattedNum)\(suffix)\(spaceBeforeRest)\(restOfLine)"
        lines = recalculateTotalsInLines(lines)
        return lines.joined(separator: "\n")
    }
    
    /// Adds a new category/item to a designated section.
    public func addItem(to text: String, sectionName: String, key: String, rawAmount: Double, note: String?) -> String {
        var lines = text.components(separatedBy: "\n")
        
        // Find section header index
        var sectionHeaderIndex = -1
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") {
                let name = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                if name.caseInsensitiveCompare(sectionName) == .orderedSame {
                    sectionHeaderIndex = idx
                    break
                }
            }
        }
        
        guard sectionHeaderIndex >= 0 else { return text }
        
        // Find insertion point before next section or before Total =
        var insertIndex = lines.count
        for idx in (sectionHeaderIndex + 1)..<lines.count {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") {
                insertIndex = idx
                break
            }
            if trimmed == "---" {
                // Look ahead to check if Total = follows
                var isBeforeTotal = false
                for nextIdx in (idx + 1)..<min(idx + 5, lines.count) {
                    let nextTrimmed = lines[nextIdx].trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.hasPrefix("Total =") || nextTrimmed.hasPrefix("Total=") {
                        isBeforeTotal = true
                        break
                    }
                }
                if isBeforeTotal {
                    insertIndex = idx
                    break
                }
            }
        }
        
        let formattedNum = rawAmount.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(rawAmount))" : String(format: "%.2f", rawAmount)
        let trimmedNote = (note ?? "").trimmingCharacters(in: .whitespaces)
        let notePart = trimmedNote.isEmpty ? "" : " (\(trimmedNote))"
        let newLine = "\(key) = \(formattedNum)\(notePart)"
        
        lines.insert(newLine, at: insertIndex)
        lines.insert("", at: insertIndex + 1)
        
        lines = recalculateTotalsInLines(lines)
        return lines.joined(separator: "\n")
    }
    
    /// Deletes an item from the text at lineIndex.
    public func deleteItem(from text: String, lineIndex: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lineIndex >= 0 && lineIndex < lines.count else { return text }
        
        lines.remove(at: lineIndex)
        
        // Clean up double blank lines
        if lineIndex < lines.count && lines[lineIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            if lineIndex - 1 >= 0 && lines[lineIndex - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.remove(at: lineIndex)
            }
        }
        
        lines = recalculateTotalsInLines(lines)
        return lines.joined(separator: "\n")
    }
    
    /// Recalculates `Total = ...` for Incoming, Outgoing, and Balance sections across lines.
    public func recalculateTotalsInLines(_ lines: [String]) -> [String] {
        var updated = lines
        var currentSection = ""
        var incomingSum: Double = 0
        var outgoingSum: Double = 0
        
        var incomingTotalLineIndex = -1
        var outgoingTotalLineIndex = -1
        var balanceTotalLineIndex = -1
        
        for (idx, line) in updated.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
                currentSection = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            
            if trimmed.contains("=") {
                let parts = trimmed.components(separatedBy: "=")
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let valStr = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                
                if key.caseInsensitiveCompare("Total") == .orderedSame {
                    if currentSection.caseInsensitiveCompare("Incoming") == .orderedSame {
                        incomingTotalLineIndex = idx
                    } else if currentSection.caseInsensitiveCompare("Outgoing") == .orderedSame {
                        outgoingTotalLineIndex = idx
                    } else if currentSection.caseInsensitiveCompare("Balance") == .orderedSame {
                        balanceTotalLineIndex = idx
                    }
                    continue
                }
                
                let parsed = parseNumericString(valStr, isScaled: false)
                if currentSection.caseInsensitiveCompare("Incoming") == .orderedSame {
                    incomingSum += parsed.raw
                } else if currentSection.caseInsensitiveCompare("Outgoing") == .orderedSame {
                    outgoingSum += parsed.raw
                }
            }
        }
        
        if incomingTotalLineIndex >= 0 {
            let formatted = incomingSum.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(incomingSum))" : String(format: "%.2f", incomingSum)
            updated[incomingTotalLineIndex] = "Total = \(formatted)"
        }
        
        if outgoingTotalLineIndex >= 0 {
            let formatted = outgoingSum.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(outgoingSum))" : String(format: "%.2f", outgoingSum)
            updated[outgoingTotalLineIndex] = "Total = \(formatted)"
        }
        
        if balanceTotalLineIndex >= 0 {
            let bal = incomingSum - outgoingSum
            let formatted = bal.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(bal))" : String(format: "%.2f", bal)
            updated[balanceTotalLineIndex] = "Total = \(formatted)"
        }
        
        return updated
    }
    
    private func formatNumberForDsl(value: Double, originalString: String) -> String {
        if originalString.contains(",") {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = "."
            formatter.decimalSeparator = ","
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        } else if originalString.contains(".") {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = "."
            formatter.decimalSeparator = ","
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        } else {
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(value))"
            } else {
                return String(format: "%.2f", value)
            }
        }
    }
}
