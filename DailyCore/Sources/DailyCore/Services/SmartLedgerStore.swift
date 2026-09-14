import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Manages local persistence, reactive publishing, and live re-calculation of the user's Smart Ledger text document.
@MainActor
public final class SmartLedgerStore: ObservableObject {
    public static let shared = SmartLedgerStore()
    
    // MARK: - Published State
    @Published public private(set) var parsedLedger: ParsedSmartLedger
    @Published public private(set) var rawText: String
    
    // MARK: - Persistence Keys
    private let storageKey = "daily_smart_ledger_raw_text_v1"
    
    // MARK: - Default Starter Ledger Template
    nonisolated public static let defaultLedgerText: String = """
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
    
    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? UserDefaults.standard
    }

    public init() {
        let savedText = UserDefaults(suiteName: GroupDefaults.suiteName)?.string(forKey: storageKey) ?? UserDefaults.standard.string(forKey: storageKey)
        let textToUse = (savedText != nil && !savedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? savedText! : Self.defaultLedgerText
        self.rawText = textToUse
        self.parsedLedger = SmartLedgerParser.shared.parse(textToUse)
    }
    
    /// Updates the raw ledger text, saves to UserDefaults, and triggers live re-parsing.
    public func saveLedgerText(_ newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textToSave = trimmed.isEmpty ? Self.defaultLedgerText : newText
        
        self.rawText = textToSave
        groupDefaults.set(textToSave, forKey: storageKey)
        UserDefaults.standard.set(textToSave, forKey: storageKey)
        self.parsedLedger = SmartLedgerParser.shared.parse(textToSave)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    /// Resets the ledger text to the baseline template.
    public func resetToDefault() {
        saveLedgerText(Self.defaultLedgerText)
    }
    
    /// Re-parses the current raw text (e.g. if exchange rate changes).
    public func recalculate(eurRate: Double = 5.0) {
        self.parsedLedger = SmartLedgerParser.shared.parse(rawText, eurRate: eurRate)
    }
    
    // MARK: - Mutation Actions
    
    /// Increments or decrements an item's raw value in the DSL text document.
    public func adjustItem(item: SmartLedgerItem, deltaRaw: Double) {
        let updatedText = SmartLedgerParser.shared.adjustItemAmount(in: rawText, lineIndex: item.lineIndex, deltaRaw: deltaRaw)
        saveLedgerText(updatedText)
    }
    
    /// Updates an item's raw value directly in the DSL text document.
    public func setItemAmount(item: SmartLedgerItem, newRaw: Double) {
        let updatedText = SmartLedgerParser.shared.setItemAmount(in: rawText, lineIndex: item.lineIndex, newRaw: newRaw)
        saveLedgerText(updatedText)
    }
    
    /// Appends a new item into a designated section and recalculates totals.
    public func addItem(sectionName: String, key: String, rawAmount: Double, note: String?) {
        let updatedText = SmartLedgerParser.shared.addItem(to: rawText, sectionName: sectionName, key: key, rawAmount: rawAmount, note: note)
        saveLedgerText(updatedText)
    }
    
    /// Removes an item line completely and recalculates totals.
    public func deleteItem(item: SmartLedgerItem) {
        let updatedText = SmartLedgerParser.shared.deleteItem(from: rawText, lineIndex: item.lineIndex)
        saveLedgerText(updatedText)
    }
}
