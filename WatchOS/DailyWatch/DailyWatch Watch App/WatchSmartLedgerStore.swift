import Foundation
import SwiftUI
import Combine
import WatchKit
import Supabase

public struct WatchSmartLedgerQuickItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var lineIndex: Int
    public var rawAmount: Double
    public var calculatedAmount: Double
    public var isScaled: Bool
    public var currency: String

    public var displayAmount: String {
        if currency == "EUR" {
            let val = rawAmount
            return val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val)) €" : String(format: "%.1f €", val)
        }
        let total = calculatedAmount
        if total.truncatingRemainder(dividingBy: 1) == 0 {
            let val = Int(total)
            if val >= 1000 {
                return "\(val / 1000)k Lei"
            }
            return "\(val) Lei"
        }
        return String(format: "%.1f Lei", total)
    }

    public var displaySubtitle: String {
        if isScaled {
            let countStr = rawAmount.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(rawAmount))" : String(format: "%.1f", rawAmount)
            return "\(countStr) × 100 Lei"
        }
        return "Direct / Unscaled"
    }
}

@MainActor
public final class WatchSmartLedgerStore: ObservableObject {
    public static let shared = WatchSmartLedgerStore()

    @Published public var netWorth: String = "127.156 Lei"
    @Published public var netWorthEUR: String = "~25.431 €"
    @Published public var deposits: String = "127.156 Lei"
    @Published public var sold: String = "0 Lei"
    @Published public var incoming: String = "16.000 Lei"
    @Published public var outgoing: String = "16.000 Lei"
    @Published public var items: [WatchSmartLedgerQuickItem] = []
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncDate: Date? = nil

    private let cacheKey = "watch_smart_ledger_cache_v2"
    private let rawTextKey1 = "daily_smart_ledger_raw_text_v1"
    private let rawTextKey2 = "smart_ledger_raw_text"
    private let lastSyncTimestampKey = "watch_smart_ledger_last_sync_ts_v1"
    private let groupSuiteName = "group.com.intellidream.daily"

    // Default template matching iOS Gold Standard
    public static let defaultLedgerText: String = """
    **Incoming**

    ---

    Card = 151 (Rz/141/Ing/10/Rev/0/Mom/9/!!!!/9)

    Cash = 9 (SG-1/A/3M)

    ---

    Total = 160

    ---

    **Outgoing**

    Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27 = 0

    V/N/Y/O/AI/M/W/E/I/Ap/Am/Sy/Ad/Sp = 9

    Rata/Rds/Gaz/Înt/Hid/(45)/Mom/(4) = 49

    Cora/Mega/Bringo/Fresh (Edn/3) = 10

    Tigari (40/45) = 10

    Car/Benzina/Honda (1/4) = 3 (SPL!/CER?)

    Serviciu/(0/*100)/Outs/(0*200) = 0

    Acasa/Tuns/Cadouri = 10 (M&T=5/!!!!!/5)

    Vacante/Noi/Iesiri/Other = 68 (C$40/B$20)

    Subs (APL-21.01-$5/RED-14.03-$1/CSP-29.05-$5)(PRL-11.08-$6/365-25.08-$7/NSK-29.8-$2)(MRG-31.8-$2/STRS-22.09-$1)(EMG-13.12-$1) = 1

    ---

    Total = 160

    ---

    **Balance** 

    ---

    Total = 0

    ---

    **Dentist**

    ---

    (Total = 106)

    ---

    **Deposit**

    ---

    ECO/ME! = 44.000L(//~8.400€)

    ECO/B!A = 30.000L(//~5.600€)

    EUR = 0€

    ERO = 0€

    DEP = 0

    BIA = 0€

    ---

    INT = 53.156,47 (-IMP-VER)//(~10.200€)

    ---

    (Concediu = 14/23 (SEE/+5!))

    ---

    (Chirie x7y ~ 37.000€ // Plati x7y ~ 9.000€)

    (Mașini x8y~(x7-27.000€)+(x8+-27.000€)$
    """

    private var defaults: UserDefaults {
        UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
    }

    private init() {
        loadCachedData()
    }

    // MARK: - Local Cache (< 1ms load, Zero Network)

    public func loadCachedData() {
        let storedTs = defaults.double(forKey: lastSyncTimestampKey)
        if storedTs > 0 {
            self.lastSyncDate = Date(timeIntervalSince1970: storedTs)
        }

        let rawText = defaults.string(forKey: rawTextKey1)
            ?? defaults.string(forKey: rawTextKey2)
            ?? Self.defaultLedgerText

        parseDocument(rawText)
    }

    private func saveLocalRawText(_ text: String) {
        defaults.set(text, forKey: rawTextKey1)
        defaults.set(text, forKey: rawTextKey2)
        UserDefaults.standard.set(text, forKey: rawTextKey1)
        UserDefaults.standard.set(text, forKey: rawTextKey2)
    }

    // MARK: - Quick Stepper Adjustments (0ms Local + Background Push)

    public func adjustItem(id: String, delta: Double) {
        if let item = items.first(where: { $0.id == id }) {
            adjustItem(lineIndex: item.lineIndex, deltaRaw: delta)
        }
    }

    public func adjustItem(lineIndex: Int, deltaRaw: Double) {
        guard lineIndex >= 0 else { return }
        WKInterfaceDevice.current().play(.click)

        let currentText = defaults.string(forKey: rawTextKey1)
            ?? defaults.string(forKey: rawTextKey2)
            ?? Self.defaultLedgerText

        let updatedText = adjustItemAmountInText(currentText, lineIndex: lineIndex, deltaRaw: deltaRaw)
        saveLocalRawText(updatedText)
        parseDocument(updatedText)

        // Push update to Supabase in background
        Task {
            await pushFullLedgerToSupabase(updatedText)
        }
    }

    // MARK: - Supabase Cloud Sync (Throttled 10m TTL to protect Battery & Network)

    public func fetchLedgerData(force: Bool = false) async {
        // Battery and network conservation: throttle to 10 minutes (600s) unless explicitly forced
        if !force, let last = lastSyncDate, Date().timeIntervalSince(last) < 600 {
            return
        }

        guard let client = WatchSessionManager.shared.supabaseClient,
              let userId = WatchSessionManager.shared.currentUserId else {
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
        }

        do {
            struct RemoteLedgerDTO: Codable {
                let id: UUID
                let user_id: UUID
                let ledger_text: String
                let updated_at: Date
            }

            let res = try await client
                .from("smart_ledgers")
                .select("id, user_id, ledger_text, updated_at")
                .eq("user_id", value: userId.uuidString)
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([RemoteLedgerDTO].self, from: res.data)

            if let first = records.first {
                saveLocalRawText(first.ledger_text)
                parseDocument(first.ledger_text)
                self.lastSyncDate = first.updated_at
                defaults.set(first.updated_at.timeIntervalSince1970, forKey: lastSyncTimestampKey)
            }
        } catch {
            print("[WatchSmartLedgerStore] Fetch error: \(error)")
        }
    }

    private func pushFullLedgerToSupabase(_ text: String) async {
        guard let client = WatchSessionManager.shared.supabaseClient,
              let userId = WatchSessionManager.shared.currentUserId else {
            return
        }

        do {
            struct UpdateDTO: Encodable {
                let ledger_text: String
                let updated_at: String
            }
            let now = Date()
            let nowISO = ISO8601DateFormatter().string(from: now)
            let payload = UpdateDTO(ledger_text: text, updated_at: nowISO)

            _ = try await client
                .from("smart_ledgers")
                .update(payload)
                .eq("user_id", value: userId.uuidString)
                .execute()

            self.lastSyncDate = now
            defaults.set(now.timeIntervalSince1970, forKey: lastSyncTimestampKey)
        } catch {
            print("[WatchSmartLedgerStore] Push update error: \(error)")
        }
    }

    // MARK: - Robust Smart Ledger DSL Parser Engine

    private func parseDocument(_ text: String) {
        let lines = text.components(separatedBy: CharacterSet.newlines)
        var currentSection = "Overview"
        var hasEncounteredDeposit = false

        var incomingTotal: Double = 0
        var outgoingTotal: Double = 0
        var balanceTotal: Double = 0
        var depositTotal: Double = 0

        var extractedQuickItems: [WatchSmartLedgerQuickItem] = []

        for (lineIndex, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "---" || line == "- - -" { continue }

            if line.hasPrefix("**") && line.hasSuffix("**") && line.count > 4 {
                let secName = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                currentSection = secName
                if secName.caseInsensitiveCompare("Deposit") == .orderedSame {
                    hasEncounteredDeposit = true
                }
                continue
            }

            if line.contains("=") {
                let parts = line.components(separatedBy: "=")
                let keyPart = parts[0].trimmingCharacters(in: .whitespaces)
                let valPart = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)

                let isDepositOrAfter = hasEncounteredDeposit
                let isScaled = !isDepositOrAfter

                let parsedVal = parseNumericValue(valPart, isScaled: isScaled)

                if keyPart.caseInsensitiveCompare("Total") == .orderedSame {
                    if currentSection.caseInsensitiveCompare("Incoming") == .orderedSame {
                        incomingTotal = parsedVal.calculated
                    } else if currentSection.caseInsensitiveCompare("Outgoing") == .orderedSame {
                        outgoingTotal = parsedVal.calculated
                    } else if currentSection.caseInsensitiveCompare("Balance") == .orderedSame {
                        balanceTotal = parsedVal.calculated
                    }
                    continue
                }

                // If in Deposit section, accumulate unscaled items
                if currentSection.caseInsensitiveCompare("Deposit") == .orderedSame {
                    depositTotal += parsedVal.calculated
                }

                // Check for primary quick-adjust items in Outgoing / Incoming
                let cleanKey = cleanKeyName(keyPart)
                if shouldIncludeInQuickAdjust(cleanKey: cleanKey, section: currentSection) {
                    let item = WatchSmartLedgerQuickItem(
                        id: "\(lineIndex)_\(cleanKey)",
                        name: cleanKey,
                        lineIndex: lineIndex,
                        rawAmount: parsedVal.raw,
                        calculatedAmount: parsedVal.calculated,
                        isScaled: isScaled,
                        currency: parsedVal.isEUR ? "EUR" : "Lei"
                    )
                    extractedQuickItems.append(item)
                }
            }
        }

        // If balance wasn't explicit, calculate from incoming - outgoing
        if balanceTotal == 0 && (incomingTotal > 0 || outgoingTotal > 0) {
            balanceTotal = max(0, incomingTotal - outgoingTotal)
        }

        let nw = depositTotal + balanceTotal
        let eur = nw / 5.0

        self.netWorth = formatLei(nw)
        self.netWorthEUR = String(format: "~%@ €", formatEUR(eur))
        self.deposits = formatLei(depositTotal)
        self.sold = formatLei(balanceTotal)
        self.incoming = formatLei(incomingTotal)
        self.outgoing = formatLei(outgoingTotal)

        if !extractedQuickItems.isEmpty {
            self.items = extractedQuickItems
        }
    }

    private func shouldIncludeInQuickAdjust(cleanKey: String, section: String) -> Bool {
        if section.caseInsensitiveCompare("Outgoing") == .orderedSame {
            let lower = cleanKey.lowercased()
            return lower.contains("tigar") || lower.contains("cora") || lower.contains("car") || lower.contains("vacant") || lower.contains("rata") || lower.contains("mega")
        }
        return false
    }

    private func parseNumericValue(_ valStr: String, isScaled: Bool, eurRate: Double = 5.0) -> (raw: Double, calculated: Double, isEUR: Bool) {
        var clean = valStr
        clean = clean.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        if let commentRange = clean.range(of: "//") {
            clean = String(clean[..<commentRange.lowerBound])
        }

        let isEUR = clean.contains("€") || clean.range(of: "EUR", options: .caseInsensitive) != nil

        let unwantedChars = CharacterSet(charactersIn: "L€$~$% ")
        clean = clean.components(separatedBy: unwantedChars).joined().trimmingCharacters(in: .whitespaces)
        clean = clean.replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)

        guard !clean.isEmpty else { return (0.0, 0.0, isEUR) }

        var normalized = clean
        if normalized.contains(",") {
            normalized = normalized.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if normalized.contains(".") {
            let parts = normalized.components(separatedBy: ".")
            if parts.count == 2 && parts[1].count == 3 {
                normalized = normalized.replacingOccurrences(of: ".", with: "")
            }
        }

        guard let num = Double(normalized) else { return (0.0, 0.0, isEUR) }
        let baseCalculated = isScaled ? num * 100.0 : num
        let calculated = isEUR ? baseCalculated * eurRate : baseCalculated
        return (raw: num, calculated: calculated, isEUR: isEUR)
    }

    private func cleanKeyName(_ key: String) -> String {
        var k = key.trimmingCharacters(in: .whitespaces)
        k = k.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        while k.hasSuffix("/") {
            k.removeLast()
            k = k.trimmingCharacters(in: .whitespaces)
        }
        return k
    }

    private func adjustItemAmountInText(_ text: String, lineIndex: Int, deltaRaw: Double) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lineIndex >= 0 && lineIndex < lines.count else { return text }

        let oldLine = lines[lineIndex]
        guard let eqRange = oldLine.range(of: "=") else { return text }

        let keyPart = String(oldLine[..<eqRange.upperBound])
        let afterEq = String(oldLine[eqRange.upperBound...])

        var noteOrCommentIndex = afterEq.endIndex
        if let parenIndex = afterEq.firstIndex(of: "(") {
            noteOrCommentIndex = min(noteOrCommentIndex, parenIndex)
        }
        if let slashRange = afterEq.range(of: "//") {
            noteOrCommentIndex = min(noteOrCommentIndex, slashRange.lowerBound)
        }

        let numRegion = String(afterEq[..<noteOrCommentIndex])
        let restOfLine = String(afterEq[noteOrCommentIndex...])

        let parsed = parseNumericValue(numRegion, isScaled: false)
        let newRaw = max(0, parsed.raw + deltaRaw)

        var suffix = ""
        if numRegion.contains("€") { suffix = "€" }
        else if numRegion.range(of: "EUR", options: .caseInsensitive) != nil { suffix = " EUR" }
        else if numRegion.contains("L") { suffix = "L" }
        else if numRegion.contains("$") { suffix = "$" }

        let formattedNum = newRaw.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(newRaw))" : String(format: "%.1f", newRaw)
        let spaceBeforeRest = (restOfLine.isEmpty || restOfLine.hasPrefix(" ")) ? "" : " "

        lines[lineIndex] = "\(keyPart) \(formattedNum)\(suffix)\(spaceBeforeRest)\(restOfLine)"
        lines = recalculateTotalsInLines(lines)
        return lines.joined(separator: "\n")
    }

    private func recalculateTotalsInLines(_ lines: [String]) -> [String] {
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

                let parsed = parseNumericValue(valStr, isScaled: false)
                if currentSection.caseInsensitiveCompare("Incoming") == .orderedSame {
                    incomingSum += parsed.raw
                } else if currentSection.caseInsensitiveCompare("Outgoing") == .orderedSame {
                    outgoingSum += parsed.raw
                }
            }
        }

        if incomingTotalLineIndex >= 0 {
            let formatted = incomingSum.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(incomingSum))" : String(format: "%.1f", incomingSum)
            updated[incomingTotalLineIndex] = "Total = \(formatted)"
        }

        if outgoingTotalLineIndex >= 0 {
            let formatted = outgoingSum.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(outgoingSum))" : String(format: "%.1f", outgoingSum)
            updated[outgoingTotalLineIndex] = "Total = \(formatted)"
        }

        if balanceTotalLineIndex >= 0 {
            let bal = incomingSum - outgoingSum
            let formatted = bal.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(bal))" : String(format: "%.1f", bal)
            updated[balanceTotalLineIndex] = "Total = \(formatted)"
        }

        return updated
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private func formatLei(_ val: Double) -> String {
        let str = Self.currencyFormatter.string(from: NSNumber(value: val)) ?? "\(Int(val))"
        return "\(str) Lei"
    }

    private func formatEUR(_ val: Double) -> String {
        return Self.currencyFormatter.string(from: NSNumber(value: val)) ?? "\(Int(val))"
    }
}
