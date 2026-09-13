import Foundation
import Combine

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
    
    public init() {
        let savedText = UserDefaults.standard.string(forKey: storageKey)
        let textToUse = (savedText != nil && !savedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? savedText! : Self.defaultLedgerText
        self.rawText = textToUse
        self.parsedLedger = SmartLedgerParser.shared.parse(textToUse)
    }
    
    /// Updates the raw ledger text, saves to UserDefaults, and triggers live re-parsing.
    public func saveLedgerText(_ newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textToSave = trimmed.isEmpty ? Self.defaultLedgerText : newText
        
        self.rawText = textToSave
        UserDefaults.standard.set(textToSave, forKey: storageKey)
        self.parsedLedger = SmartLedgerParser.shared.parse(textToSave)
    }
    
    /// Resets the ledger text to the baseline template.
    public func resetToDefault() {
        saveLedgerText(Self.defaultLedgerText)
    }
    
    /// Re-parses the current raw text (e.g. if exchange rate changes).
    public func recalculate(eurRate: Double = 5.0) {
        self.parsedLedger = SmartLedgerParser.shared.parse(rawText, eurRate: eurRate)
    }
}
