package com.intellidream.daily.model

import org.junit.Assert.*
import org.junit.Test

class SmartLedgerParserTest {

    private val mobileNotionPaste = """
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

Tigari (00/50) = 0 (SALA/${'$'}22!)

Car/Benzina/Honda (1/4) = 4 (SPL!/CER?)

Serviciu/(0/*100)/Outs/(0*200) = 0

Acasa/Tuns/Cadouri = 5 (M&T=0/!!!!!/5)

Vacante/Noi/Iesiri/Others = 9 (MOM/50)

Subs (APL-21.01-${'$'}5/RED-14.03-${'$'}1/CSP-29.05-${'$'}5)(PRL-11.08-${'$'}6/365-25.08-${'$'}7/NSK-29.8-${'$'}2)(MRG-31.8-${'$'}2/STRS-22.09-${'$'}1)(OURA-19.10-${'$'}4/EMG-13.12-${'$'}2/6) = 0

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
""".trimIndent()

    private val desktopNotionPasteCRLF = listOf(
        "Incoming",
        "Card = 23 (Rz/13/Ing/10/Rev/0/Mom/9/!!!!/9)",
        "Cash = 0 (SG-1/A/3M)//(MOM/50!)",
        "Total = 23",
        "Outgoing",
        "Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27 = 0",
        "V/N/Y/O/AI/M/W/E/I/Ap/Am/Sy/Ad/Sp = 3",
        "Rata/Rds/Gaz/Înt/Hid/(45)/Mom/(5) = 2",
        "Cora/Mega/Bringo/Fresh (Edn/0) = 0",
        "Tigari (00/50) = 0 (SALA/${'$'}22!)",
        "Car/Benzina/Honda (1/4) = 4 (SPL!/CER?)",
        "Serviciu/(0/*100)/Outs/(0*200) = 0",
        "Acasa/Tuns/Cadouri = 5 (M&T=0/!!!!!/5)",
        "Vacante/Noi/Iesiri/Others = 9 (MOM/50)",
        "Subs (APL-21.01-${'$'}5/RED-14.03-${'$'}1/CSP-29.05-${'$'}5)(PRL-11.08-${'$'}6/365-25.08-${'$'}7/NSK-29.8-${'$'}2)(MRG-31.8-${'$'}2/STRS-22.09-${'$'}1)(OURA-19.10-${'$'}4/EMG-13.12-${'$'}2/6) = 0",
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
    ).joinToString("\r\n")

    @Test
    fun notionMobileAndDesktopFormatsProduceIdenticalResults() {
        val mobile = SmartLedgerParser.parse(mobileNotionPaste, eurRate = 5.0)
        val desktop = SmartLedgerParser.parse(desktopNotionPasteCRLF, eurRate = 5.0)

        for (parsed in listOf(mobile, desktop)) {
            assertEquals(listOf("Incoming", "Outgoing", "Balance", "Dentist", "Deposit"), parsed.sections.map { it.name })
            assertEquals(2300.0, parsed.incomingTotal, 0.01)
            assertEquals(2300.0, parsed.outgoingTotal, 0.01)
            assertEquals(0.0, parsed.balanceTotal, 0.01)
            assertEquals(10600.0, parsed.dentistTotal, 0.01)
            assertEquals(157192.97, parsed.depositTotal, 0.01)
            assertEquals(157192.97, parsed.netWorth, 0.01)
            assertEquals(31438.594, parsed.netWorthEUR, 0.01)
        }

        for (i in mobile.sections.indices) {
            val secM = mobile.sections[i]
            val secD = desktop.sections[i]
            assertEquals(secM.name, secD.name)
            assertEquals(secM.isScaled, secD.isScaled)
            assertEquals(secM.totalCalculated, secD.totalCalculated, 0.01)
            assertEquals(secM.items.size, secD.items.size)
            for (j in secM.items.indices) {
                val itM = secM.items[j]
                val itD = secD.items[j]
                assertEquals(itM.key, itD.key)
                assertEquals(itM.rawAmount, itD.rawAmount, 0.01)
                assertEquals(itM.calculatedAmount, itD.calculatedAmount, 0.01)
                assertEquals(itM.currency, itD.currency)
                assertEquals(itM.isPureNote, itD.isPureNote)
                assertEquals(itM.notes, itD.notes)
            }
        }

        val normalizedMobile = SmartLedgerParser.normalizeLedgerText(mobileNotionPaste)
        val normalizedDesktop = SmartLedgerParser.normalizeLedgerText(desktopNotionPasteCRLF)
        assertFalse(normalizedDesktop.contains("\r"))
        for (h in listOf("**Incoming**", "**Outgoing**", "**Balance**", "**Dentist**", "**Deposit**")) {
            assertTrue(normalizedMobile.contains(h))
            assertTrue(normalizedDesktop.contains(h))
        }

        val cardDesktop = desktop.sections.first().items.first { it.key == "Card" }
        val adjusted = SmartLedgerParser.adjustItemAmount(desktopNotionPasteCRLF, cardDesktop.lineIndex, 2.0)
        val reParsed = SmartLedgerParser.parse(adjusted)
        assertEquals(2500.0, reParsed.incomingTotal, 0.01)
        assertEquals(200.0, reParsed.balanceTotal, 0.01)

        val added = SmartLedgerParser.addItem(desktopNotionPasteCRLF, "Outgoing", "Sala", 2.0, "Gym")
        val reParsedAdded = SmartLedgerParser.parse(added)
        assertEquals(2500.0, reParsedAdded.outgoingTotal, 0.01)
    }
}
