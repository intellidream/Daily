import XCTest
@testable import DailyCore

final class SmartLedgerParserTests: XCTestCase {
    
    let sampleLedger = """
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

    func testParseSampleLedgerTotals() {
        let parser = SmartLedgerParser()
        let result = parser.parse(sampleLedger, eurRate: 5.0)
        
        // Incoming total: 160 x 100 = 16.000 Lei
        XCTAssertEqual(result.incomingTotal, 16000.0, accuracy: 0.01)
        
        // Outgoing total: 160 x 100 = 16.000 Lei
        XCTAssertEqual(result.outgoingTotal, 16000.0, accuracy: 0.01)
        
        // Balance total: 0 Lei
        XCTAssertEqual(result.balanceTotal, 0.0, accuracy: 0.01)
        
        // Dentist total: 106 x 100 = 10.600 Lei
        XCTAssertEqual(result.dentistTotal, 10600.0, accuracy: 0.01)
        
        // Deposits: 44.000 + 30.000 + 53.156,47 = 127.156,47 Lei
        XCTAssertEqual(result.depositTotal, 127156.47, accuracy: 0.01)
        
        // Net Worth = Deposits + Balance = 127.156,47 + 0 = 127.156,47 Lei
        XCTAssertEqual(result.netWorth, 127156.47, accuracy: 0.01)
    }
    
    func testIncomingItemsBreakdown() {
        let parser = SmartLedgerParser()
        let result = parser.parse(sampleLedger)
        
        guard let incomingSec = result.sections.first(where: { $0.name == "Incoming" }) else {
            XCTFail("Incoming section not found")
            return
        }
        
        XCTAssertEqual(incomingSec.items.count, 2)
        
        let cardItem = incomingSec.items[0]
        XCTAssertEqual(cardItem.key, "Card")
        XCTAssertEqual(cardItem.rawAmount, 151.0, accuracy: 0.01)
        XCTAssertEqual(cardItem.calculatedAmount, 15100.0, accuracy: 0.01)
        XCTAssertEqual(cardItem.notes.first, "Rz/141/Ing/10/Rev/0/Mom/9/!!!!/9")
        
        let cashItem = incomingSec.items[1]
        XCTAssertEqual(cashItem.key, "Cash")
        XCTAssertEqual(cashItem.rawAmount, 9.0, accuracy: 0.01)
        XCTAssertEqual(cashItem.calculatedAmount, 900.0, accuracy: 0.01)
        XCTAssertEqual(cashItem.notes.first, "SG-1/A/3M")
    }
    
    func testOutgoingItemsBreakdown() {
        let parser = SmartLedgerParser()
        let result = parser.parse(sampleLedger)
        
        guard let outgoingSec = result.sections.first(where: { $0.name == "Outgoing" }) else {
            XCTFail("Outgoing section not found")
            return
        }
        
        // Look up Vacante
        let vacante = outgoingSec.items.first { $0.key.contains("Vacante") }
        XCTAssertNotNil(vacante)
        XCTAssertEqual(vacante?.rawAmount ?? 0, 68.0, accuracy: 0.01)
        XCTAssertEqual(vacante?.calculatedAmount ?? 0, 6800.0, accuracy: 0.01)
        XCTAssertEqual(vacante?.percentageOfSection ?? 0, 6800.0 / 16000.0, accuracy: 0.001)
        
        // Look up Rata
        let rata = outgoingSec.items.first { $0.key.contains("Rata") }
        XCTAssertNotNil(rata)
        XCTAssertEqual(rata?.rawAmount ?? 0, 49.0, accuracy: 0.01)
        XCTAssertEqual(rata?.calculatedAmount ?? 0, 4900.0, accuracy: 0.01)
    }
    
    func testNetWorthWithPositiveBalance() {
        let textWithSurplus = """
        **Incoming**
        Card = 170
        Total = 170

        **Outgoing**
        Rata = 50
        Total = 50

        **Balance**
        Total = 120

        **Deposit**
        ECO = 40.000L
        """
        
        let parser = SmartLedgerParser()
        let result = parser.parse(textWithSurplus)
        
        // Deposits = 40.000 Lei
        // Balance = 120 x 100 = 12.000 Lei
        // Net Worth = 40.000 + 12.000 = 52.000 Lei
        XCTAssertEqual(result.depositTotal, 40000.0, accuracy: 0.01)
        XCTAssertEqual(result.balanceTotal, 12000.0, accuracy: 0.01)
        XCTAssertEqual(result.netWorth, 52000.0, accuracy: 0.01)
    }
    
    // MARK: - Mutation Engine Tests
    
    func testAdjustItemAmountIncrementAndRecalculate() {
        let parser = SmartLedgerParser()
        let parsed = parser.parse(sampleLedger)
        
        // Find Tigari item
        let outgoing = parsed.sections.first { $0.name == "Outgoing" }
        guard let tigari = outgoing?.items.first(where: { $0.key.contains("Tigari") }) else {
            XCTFail("Tigari item not found")
            return
        }
        
        XCTAssertEqual(tigari.rawAmount, 10.0)
        XCTAssertTrue(tigari.lineIndex >= 0)
        
        // Increment Tigari by +1
        let updatedText = parser.adjustItemAmount(in: sampleLedger, lineIndex: tigari.lineIndex, deltaRaw: 1)
        
        // Tigari line must have value 11
        XCTAssertTrue(updatedText.contains("Tigari (40/45) = 11"))
        
        // Re-parse and verify totals
        let reParsed = parser.parse(updatedText)
        let newOutgoing = reParsed.sections.first { $0.name == "Outgoing" }
        let newTigari = newOutgoing?.items.first(where: { $0.key.contains("Tigari") })
        
        XCTAssertEqual(newTigari?.rawAmount, 11.0)
        XCTAssertEqual(reParsed.outgoingTotal, 16100.0, accuracy: 0.01)
        // Balance was 160 - 161 = -1
        XCTAssertTrue(updatedText.contains("Total = -1"))
    }
    
    func testAdjustItemPreservesNotesAndComments() {
        let parser = SmartLedgerParser()
        let parsed = parser.parse(sampleLedger)
        
        let incoming = parsed.sections.first { $0.name == "Incoming" }
        guard let card = incoming?.items.first(where: { $0.key == "Card" }) else {
            XCTFail("Card item not found")
            return
        }
        
        // Increment Card by +1
        let updatedText = parser.adjustItemAmount(in: sampleLedger, lineIndex: card.lineIndex, deltaRaw: 1)
        
        // Check that the parenthesized note was fully preserved
        XCTAssertTrue(updatedText.contains("Card = 152 (Rz/141/Ing/10/Rev/0/Mom/9/!!!!/9)"))
        
        let reParsed = parser.parse(updatedText)
        XCTAssertEqual(reParsed.incomingTotal, 16100.0, accuracy: 0.01)
    }
    
    func testAddItemAndRecalculate() {
        let parser = SmartLedgerParser()
        let updatedText = parser.addItem(to: sampleLedger, sectionName: "Outgoing", key: "Sala", rawAmount: 4, note: "Gym")
        
        XCTAssertTrue(updatedText.contains("Sala = 4 (Gym)"))
        
        let reParsed = parser.parse(updatedText)
        XCTAssertEqual(reParsed.outgoingTotal, 16400.0, accuracy: 0.01)
    }
    
    func testDeleteItemAndRecalculate() {
        let parser = SmartLedgerParser()
        let parsed = parser.parse(sampleLedger)
        
        let outgoing = parsed.sections.first { $0.name == "Outgoing" }
        guard let tigari = outgoing?.items.first(where: { $0.key.contains("Tigari") }) else {
            XCTFail("Tigari item not found")
            return
        }
        
        let updatedText = parser.deleteItem(from: sampleLedger, lineIndex: tigari.lineIndex)
        XCTAssertFalse(updatedText.contains("Tigari (40/45) = 10"))
        
        let reParsed = parser.parse(updatedText)
        XCTAssertEqual(reParsed.outgoingTotal, 15000.0, accuracy: 0.01)
    }
    
    func testPreserveDoubleSlashInKey() {
        let parser = SmartLedgerParser()
        let parsed = parser.parse(sampleLedger)
        
        let outgoing = parsed.sections.first { $0.name == "Outgoing" }
        let itpItem = outgoing?.items.first { $0.key.contains("Itp") }
        XCTAssertNotNil(itpItem)
        XCTAssertEqual(itpItem?.key, "Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27")
        XCTAssertEqual(itpItem?.displayName, "Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27")
    }
    
    func testCleanKeyWithEmbeddedParenthesesAndTrailingSlash() {
        let parser = SmartLedgerParser()
        let parsed = parser.parse(sampleLedger)
        
        let outgoing = parsed.sections.first { $0.name == "Outgoing" }
        let serviciuItem = outgoing?.items.first { $0.key.contains("Serviciu") }
        XCTAssertNotNil(serviciuItem)
        XCTAssertEqual(serviciuItem?.key, "Serviciu//Outs")
        XCTAssertEqual(serviciuItem?.displayName, "Serviciu//Outs")
        XCTAssertEqual(serviciuItem?.notes.count, 2)
        XCTAssertEqual(serviciuItem?.notes[0], "0/*100")
        XCTAssertEqual(serviciuItem?.notes[1], "0*200")
    }
    
    func testEURParsingAndNetWorthContribution() {
        let parser = SmartLedgerParser()
        let ledgerText = """
        **Incoming**
        Salariu = 100

        **Outgoing**
        Cheltuieli = 50

        **Deposit**
        Garanti = 10.000
        EUR = 2500€
        Revolut EUR = 1000 EUR
        Card Lei = 500 (100€ bonus)
        """
        
        let parsed = parser.parse(ledgerText, eurRate: 5.0)
        
        guard let depositSec = parsed.sections.first(where: { $0.name == "Deposit" }) else {
            XCTFail("Deposit section missing")
            return
        }
        
        // Garanti (Lei)
        guard let garanti = depositSec.items.first(where: { $0.key == "Garanti" }) else {
            XCTFail("Garanti missing")
            return
        }
        XCTAssertEqual(garanti.currency, "Lei")
        XCTAssertEqual(garanti.rawAmount, 10000.0)
        XCTAssertEqual(garanti.calculatedAmount, 10000.0)
        
        // EUR = 2500€
        guard let eurItem = depositSec.items.first(where: { $0.key == "EUR" }) else {
            XCTFail("EUR item missing")
            return
        }
        XCTAssertEqual(eurItem.currency, "EUR")
        XCTAssertEqual(eurItem.rawAmount, 2500.0)
        XCTAssertEqual(eurItem.calculatedAmount, 12500.0, accuracy: 0.01)
        XCTAssertEqual(eurItem.formattedCalculatedAmount, "2.500 €")
        XCTAssertEqual(eurItem.formattedLeiAmount, "12.500 Lei")
        
        // Revolut EUR = 1000 EUR
        guard let revEur = depositSec.items.first(where: { $0.key == "Revolut EUR" }) else {
            XCTFail("Revolut EUR missing")
            return
        }
        XCTAssertEqual(revEur.currency, "EUR")
        XCTAssertEqual(revEur.rawAmount, 1000.0)
        XCTAssertEqual(revEur.calculatedAmount, 5000.0, accuracy: 0.01)
        XCTAssertEqual(revEur.formattedCalculatedAmount, "1.000 €")
        
        // Card Lei = 500 (100€ bonus) -> € inside parentheses should NOT make currency EUR
        guard let cardLei = depositSec.items.first(where: { $0.key == "Card Lei" }) else {
            XCTFail("Card Lei missing")
            return
        }
        XCTAssertEqual(cardLei.currency, "Lei")
        XCTAssertEqual(cardLei.rawAmount, 500.0)
        XCTAssertEqual(cardLei.calculatedAmount, 500.0)
        
        // Deposit Total = 10,000 + 12,500 + 5,000 + 500 = 28,000 Lei
        XCTAssertEqual(parsed.depositTotal, 28000.0, accuracy: 0.01)
        
        // Incoming = 100 * 100 = 10,000; Outgoing = 50 * 100 = 5,000; Balance = 5,000 Lei
        XCTAssertEqual(parsed.balanceTotal, 5000.0, accuracy: 0.01)
        
        // Net Worth = 28,000 (Deposit) + 5,000 (Balance) = 33,000 Lei
        XCTAssertEqual(parsed.netWorth, 33000.0, accuracy: 0.01)
        // Net Worth EUR = 33,000 / 5.0 = 6,600 €
        XCTAssertEqual(parsed.netWorthEUR, 6600.0, accuracy: 0.01)
    }
    
    func testEURAdjustPreservesCurrency() {
        let parser = SmartLedgerParser()
        let ledgerText = """
        **Deposit**
        EUR = 2500€
        """
        let parsed = parser.parse(ledgerText, eurRate: 5.0)
        guard let item = parsed.sections.first?.items.first else {
            XCTFail("Item not found")
            return
        }
        
        let adjusted = parser.adjustItemAmount(in: ledgerText, lineIndex: item.lineIndex, deltaRaw: 100)
        XCTAssertTrue(adjusted.contains("EUR = 2600€"))
        
        let reParsed = parser.parse(adjusted, eurRate: 5.0)
        guard let adjustedItem = reParsed.sections.first?.items.first else {
            XCTFail("Adjusted item missing")
            return
        }
        XCTAssertEqual(adjustedItem.rawAmount, 2600.0)
        XCTAssertEqual(adjustedItem.currency, "EUR")
        XCTAssertEqual(adjustedItem.calculatedAmount, 13000.0, accuracy: 0.01)
    }
    
    // MARK: - Notion Mobile vs. Desktop (Mac/Windows) Paste Parity Tests
    
    func testNotionMobileVsDesktopPasteExactParity() {
        let mobileNotionPaste = """
        *Incoming*

        ---

        Card = 23 (Rz/13/Ing/10/Rev/0/Mom/9/!!!!/9)

        Cash = 0 (SG-1/A/3M)//(MOM/50!)

        ---

        Total = 23

        ---

        *Outgoing*

        Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27 = 0

        V/N/Y/O/AI/M/W/E/I/Ap/Am/Sy/Ad/Sp = 3

        Rata/Rds/Gaz/Înt/Hid/(45)/Mom/(5) = 2

        Cora/Mega/Bringo/Fresh (Edn/0) = 0

        Tigari (00/50) = 0 (SALA/$22!)

        Car/Benzina/Honda (1/4) = 4 (SPL!/CER?)

        Serviciu/(0/*100)/Outs/(0*200) = 0

        Acasa/Tuns/Cadouri = 5 (M&T=0/!!!!!/5)

        Vacante/Noi/Iesiri/Others = 9 (MOM/50)

        Subs (APL-21.01-$5/RED-14.03-$1/CSP-29.05-$5)(PRL-11.08-$6/365-25.08-$7/NSK-29.8-$2)(MRG-31.8-$2/STRS-22.09-$1)(OURA-19.10-$4/EMG-13.12-$2/6) = 0

        ---

        Total = 23

        ---

        *Balance* 

        ---

        Total = 0

        ---

        *Dentist*

        ---

        (Total = 106)

        ---

        *Deposit*

        ---

        ECO/ME! = 0€

        ECO/B!A = 41.023 (~7.750€)

        EUR = 0€

        ERO = 0€

        DEP = 0

        BIA = 8150€

        ---

        INT = 75.419,97 (-IMP-VER)//(~14.200€)

        ---

        (Concediu = 14/23)

        ---

        (Chirie x7y ~ 37.000€ // Plati x7y ~ 9.000€)

        (Mașini x8y~(x7-27.000€)+(x8+-27.000€))
        """
        
        // Simulate Windows CRLF clipboard without asterisks, dividers, or blank lines
        let desktopNotionPasteCRLF = [
            "Incoming",
            "Card = 23 (Rz/13/Ing/10/Rev/0/Mom/9/!!!!/9)",
            "Cash = 0 (SG-1/A/3M)//(MOM/50!)",
            "Total = 23",
            "Outgoing",
            "Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27 = 0",
            "V/N/Y/O/AI/M/W/E/I/Ap/Am/Sy/Ad/Sp = 3",
            "Rata/Rds/Gaz/Înt/Hid/(45)/Mom/(5) = 2",
            "Cora/Mega/Bringo/Fresh (Edn/0) = 0",
            "Tigari (00/50) = 0 (SALA/$22!)",
            "Car/Benzina/Honda (1/4) = 4 (SPL!/CER?)",
            "Serviciu/(0/*100)/Outs/(0*200) = 0",
            "Acasa/Tuns/Cadouri = 5 (M&T=0/!!!!!/5)",
            "Vacante/Noi/Iesiri/Others = 9 (MOM/50)",
            "Subs (APL-21.01-$5/RED-14.03-$1/CSP-29.05-$5)(PRL-11.08-$6/365-25.08-$7/NSK-29.8-$2)(MRG-31.8-$2/STRS-22.09-$1)(OURA-19.10-$4/EMG-13.12-$2/6) = 0",
            "Total = 23",
            "Balance ",
            "Total = 0",
            "Dentist",
            "(Total = 106)",
            "Deposit",
            "ECO/ME! = 0€",
            "ECO/B!A = 41.023 (~7.750€)",
            "EUR = 0€",
            "ERO = 0€",
            "DEP = 0",
            "BIA = 8150€",
            "INT = 75.419,97 (-IMP-VER)//(~14.200€)",
            "(Concediu = 14/23)",
            "(Chirie x7y ~ 37.000€ // Plati x7y ~ 9.000€)",
            "(Mașini x8y~(x7-27.000€)+(x8+-27.000€))"
        ].joined(separator: "\r\n")
        
        let parser = SmartLedgerParser()
        let mobileParsed = parser.parse(mobileNotionPaste, eurRate: 5.0)
        let desktopParsed = parser.parse(desktopNotionPasteCRLF, eurRate: 5.0)
        
        // Expected totals:
        // Incoming = 23 * 100 = 2.300 Lei
        // Outgoing = 23 * 100 = 2.300 Lei
        // Balance = 0 Lei
        // Dentist = 106 * 100 = 10.600 Lei
        // Deposit = 41.023 + (8.150 * 5) + 75.419,97 = 41.023 + 40.750 + 75.419,97 = 157.192,97 Lei
        // Net Worth = 157.192,97 Lei (~31.438,594 €)
        for parsed in [mobileParsed, desktopParsed] {
            XCTAssertEqual(parsed.sections.map(\.name), ["Incoming", "Outgoing", "Balance", "Dentist", "Deposit"])
            XCTAssertEqual(parsed.incomingTotal, 2300.0, accuracy: 0.01)
            XCTAssertEqual(parsed.outgoingTotal, 2300.0, accuracy: 0.01)
            XCTAssertEqual(parsed.balanceTotal, 0.0, accuracy: 0.01)
            XCTAssertEqual(parsed.dentistTotal, 10600.0, accuracy: 0.01)
            XCTAssertEqual(parsed.depositTotal, 157192.97, accuracy: 0.01)
            XCTAssertEqual(parsed.netWorth, 157192.97, accuracy: 0.01)
            XCTAssertEqual(parsed.netWorthEUR, 31438.594, accuracy: 0.01)
        }
        
        // Verify item-by-item identity across all 5 sections
        for (secMobile, secDesktop) in zip(mobileParsed.sections, desktopParsed.sections) {
            XCTAssertEqual(secMobile.name, secDesktop.name)
            XCTAssertEqual(secMobile.isScaled, secDesktop.isScaled)
            XCTAssertEqual(secMobile.totalCalculated, secDesktop.totalCalculated, accuracy: 0.01)
            XCTAssertEqual(secMobile.items.count, secDesktop.items.count)
            for (itM, itD) in zip(secMobile.items, secDesktop.items) {
                XCTAssertEqual(itM.key, itD.key)
                XCTAssertEqual(itM.rawAmount, itD.rawAmount, accuracy: 0.01)
                XCTAssertEqual(itM.calculatedAmount, itD.calculatedAmount, accuracy: 0.01)
                XCTAssertEqual(itM.currency, itD.currency)
                XCTAssertEqual(itM.isPureNote, itD.isPureNote)
                XCTAssertEqual(itM.notes, itD.notes)
            }
        }
        
        // Verify canonical header normalization & CRLF cleanup
        let normalizedMobile = parser.normalizeLedgerText(mobileNotionPaste)
        let normalizedDesktop = parser.normalizeLedgerText(desktopNotionPasteCRLF)
        XCTAssertFalse(normalizedDesktop.contains("\r"))
        for expectedHeader in ["**Incoming**", "**Outgoing**", "**Balance**", "**Dentist**", "**Deposit**"] {
            XCTAssertTrue(normalizedMobile.contains(expectedHeader))
            XCTAssertTrue(normalizedDesktop.contains(expectedHeader))
        }
        
        // Verify mutations (+1 on Card and addItem without ---) work deterministically on CRLF desktop paste
        guard let cardDesktop = desktopParsed.sections.first?.items.first(where: { $0.key == "Card" }) else {
            XCTFail("Desktop Card item missing")
            return
        }
        let adjustedDesktop = parser.adjustItemAmount(in: desktopNotionPasteCRLF, lineIndex: cardDesktop.lineIndex, deltaRaw: 2)
        let reParsedAdjusted = parser.parse(adjustedDesktop)
        XCTAssertEqual(reParsedAdjusted.incomingTotal, 2500.0, accuracy: 0.01)
        XCTAssertEqual(reParsedAdjusted.balanceTotal, 200.0, accuracy: 0.01)
        
        let withNewItem = parser.addItem(to: desktopNotionPasteCRLF, sectionName: "Outgoing", key: "Sala", rawAmount: 2, note: "Gym")
        let reParsedAdded = parser.parse(withNewItem)
        XCTAssertEqual(reParsedAdded.outgoingTotal, 2500.0, accuracy: 0.01)
    }
}
