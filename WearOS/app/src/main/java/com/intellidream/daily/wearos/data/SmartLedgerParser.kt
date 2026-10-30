package com.intellidream.daily.wearos.data

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import java.util.regex.Pattern

data class ParsedLedgerResult(
    val netWorth: Double,
    val netWorthEUR: Double,
    val deposits: Double,
    val balance: Double,
    val incoming: Double,
    val outgoing: Double,
    val items: List<WearLedgerItemData>
)

data class WearLedgerItemData(
    val id: String,
    val name: String,
    val lineIndex: Int,
    val rawAmount: Double,
    val calculatedAmount: Double,
    val isScaled: Boolean,
    val currency: String = "Lei"
)

object SmartLedgerParser {

    const val DEFAULT_LEDGER_TEXT: String = """**Incoming**

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

(Mașini x8y~(x7-27.000€)+(x8+-27.000€)$"""

    fun parse(text: String, eurRate: Double = 5.0): ParsedLedgerResult {
        val lines = text.lines()
        var currentSection = "Overview"
        var hasEncounteredDeposit = false

        var incomingTotal = 0.0
        var outgoingTotal = 0.0
        var balanceTotal = 0.0
        var depositTotal = 0.0

        val extractedItems = mutableListOf<WearLedgerItemData>()

        for ((lineIndex, rawLine) in lines.withIndex()) {
            val line = rawLine.trim()
            if (line.isEmpty() || line == "---" || line == "- - -") continue

            if (line.startsWith("**") && line.endsWith("**") && line.length > 4) {
                val secName = line.substring(2, line.length - 2).trim()
                currentSection = secName
                if (secName.equals("Deposit", ignoreCase = true)) {
                    hasEncounteredDeposit = true
                }
                continue
            }

            if (line.contains("=")) {
                val parts = line.split("=", limit = 2)
                val keyPart = parts[0].trim()
                val valPart = parts[1].trim()

                val isScaled = !hasEncounteredDeposit
                val parsedVal = parseNumericString(valPart, isScaled = isScaled, eurRate = eurRate)

                if (keyPart.equals("Total", ignoreCase = true)) {
                    when {
                        currentSection.equals("Incoming", ignoreCase = true) -> incomingTotal = parsedVal.calculated
                        currentSection.equals("Outgoing", ignoreCase = true) -> outgoingTotal = parsedVal.calculated
                        currentSection.equals("Balance", ignoreCase = true) -> balanceTotal = parsedVal.calculated
                    }
                    continue
                }

                if (currentSection.equals("Deposit", ignoreCase = true)) {
                    depositTotal += parsedVal.calculated
                }

                val cleanKey = cleanKeyName(keyPart)
                if (shouldIncludeInWatchQuickAdjust(cleanKey, currentSection)) {
                    extractedItems.add(
                        WearLedgerItemData(
                            id = "${lineIndex}_$cleanKey",
                            name = cleanKey,
                            lineIndex = lineIndex,
                            rawAmount = parsedVal.raw,
                            calculatedAmount = parsedVal.calculated,
                            isScaled = isScaled,
                            currency = if (parsedVal.isEUR) "EUR" else "Lei"
                        )
                    )
                }
            }
        }

        if (balanceTotal == 0.0 && (incomingTotal > 0 || outgoingTotal > 0)) {
            balanceTotal = (incomingTotal - outgoingTotal).coerceAtLeast(0.0)
        }

        val nw = depositTotal + balanceTotal
        val nwEUR = if (eurRate > 0) nw / eurRate else 0.0

        return ParsedLedgerResult(
            netWorth = nw,
            netWorthEUR = nwEUR,
            deposits = depositTotal,
            balance = balanceTotal,
            incoming = incomingTotal,
            outgoing = outgoingTotal,
            items = extractedItems
        )
    }

    private fun shouldIncludeInWatchQuickAdjust(cleanKey: String, section: String): Boolean {
        if (section.equals("Outgoing", ignoreCase = true)) {
            val lower = cleanKey.lowercase(Locale.ROOT)
            return lower.contains("tigar") || lower.contains("cora") || lower.contains("car") || lower.contains("vacant") || lower.contains("rata") || lower.contains("mega")
        }
        return false
    }

    data class ParsedNumeric(val raw: Double, val calculated: Double, val isEUR: Boolean = false)

    fun parseNumericString(valStr: String, isScaled: Boolean, eurRate: Double = 5.0): ParsedNumeric {
        var clean = valStr.replace(Regex("\\(.*?\\)"), "")
        val commentIdx = clean.indexOf("//")
        if (commentIdx >= 0) {
            clean = clean.substring(0, commentIdx)
        }

        val isEUR = clean.contains("€") || clean.contains("EUR", ignoreCase = true)
        clean = clean.replace(Regex("[L€$~$% ]"), "").replace(Regex("EUR", RegexOption.IGNORE_CASE), "").trim()

        if (clean.isEmpty()) return ParsedNumeric(0.0, 0.0, isEUR)

        var normalized = clean
        if (normalized.contains(",")) {
            normalized = normalized.replace(".", "").replace(",", ".")
        } else if (normalized.contains(".")) {
            val parts = normalized.split(".")
            if (parts.size == 2 && parts[1].length == 3) {
                normalized = normalized.replace(".", "")
            }
        }

        val num = normalized.toDoubleOrNull() ?: return ParsedNumeric(0.0, 0.0, isEUR)
        val baseCalculated = if (isScaled) num * 100.0 else num
        val calculated = if (isEUR) baseCalculated * eurRate else baseCalculated
        return ParsedNumeric(num, calculated, isEUR)
    }

    fun cleanKeyName(key: String): String {
        var k = key.trim()
        k = k.replace(Regex("\\(.*?\\)"), "").trim()
        while (k.endsWith("/")) {
            k = k.dropLast(1).trim()
        }
        return k
    }

    fun adjustItemAmount(text: String, lineIndex: Int, deltaRaw: Double): String {
        val lines = text.lines()
        if (lineIndex !in lines.indices) return text
        val line = lines[lineIndex]
        if (!line.contains("=")) return text
        val parts = line.split("=", limit = 2)
        val valuePart = parts[1].trim()
        val parsed = parseNumericString(valuePart, isScaled = false)
        val newRaw = (parsed.raw + deltaRaw).coerceAtLeast(0.0)
        return setItemAmount(text, lineIndex, newRaw)
    }

    fun setItemAmount(text: String, lineIndex: Int, newRaw: Double): String {
        val lines = text.lines().toMutableList()
        if (lineIndex !in lines.indices) return text

        val oldLine = lines[lineIndex]
        val eqIdx = oldLine.indexOf("=")
        if (eqIdx < 0) return text

        val keyPart = oldLine.substring(0, eqIdx + 1)
        val afterEq = oldLine.substring(eqIdx + 1)

        var noteOrCommentIndex = afterEq.length
        val parenIdx = afterEq.indexOf("(")
        if (parenIdx >= 0) {
            noteOrCommentIndex = minOf(noteOrCommentIndex, parenIdx)
        }
        val slashIdx = afterEq.indexOf("//")
        if (slashIdx >= 0) {
            noteOrCommentIndex = minOf(noteOrCommentIndex, slashIdx)
        }

        val numRegion = afterEq.substring(0, noteOrCommentIndex)
        val restOfLine = afterEq.substring(noteOrCommentIndex)

        val suffix = when {
            numRegion.contains("€") -> "€"
            numRegion.contains("EUR", ignoreCase = true) -> " EUR"
            numRegion.contains("L") -> "L"
            numRegion.contains("$") -> "$"
            else -> ""
        }

        val formattedNum = if ((newRaw % 1.0) == 0.0) "${newRaw.toLong()}" else String.format(Locale.US, "%.1f", newRaw)
        val spaceBeforeRest = if (restOfLine.isEmpty() || restOfLine.startsWith(" ")) "" else " "

        lines[lineIndex] = "$keyPart $formattedNum$suffix$spaceBeforeRest$restOfLine"
        val updated = recalculateTotalsInLines(lines)
        return updated.joinToString("\n")
    }

    fun recalculateTotalsInLines(lines: List<String>): List<String> {
        val updated = lines.toMutableList()
        var currentSection = ""
        var incomingSum = 0.0
        var outgoingSum = 0.0

        var incomingTotalLineIndex = -1
        var outgoingTotalLineIndex = -1
        var balanceTotalLineIndex = -1

        for ((idx, line) in updated.withIndex()) {
            val trimmed = line.trim()
            if (trimmed.startsWith("**") && trimmed.endsWith("**") && trimmed.length > 4) {
                currentSection = trimmed.substring(2, trimmed.length - 2).trim()
                continue
            }

            if (trimmed.contains("=")) {
                val parts = trimmed.split("=", limit = 2)
                val key = parts[0].trim()
                val valStr = parts[1].trim()

                if (key.equals("Total", ignoreCase = true)) {
                    when {
                        currentSection.equals("Incoming", ignoreCase = true) -> incomingTotalLineIndex = idx
                        currentSection.equals("Outgoing", ignoreCase = true) -> outgoingTotalLineIndex = idx
                        currentSection.equals("Balance", ignoreCase = true) -> balanceTotalLineIndex = idx
                    }
                    continue
                }

                val parsed = parseNumericString(valStr, isScaled = false)
                if (currentSection.equals("Incoming", ignoreCase = true)) {
                    incomingSum += parsed.raw
                } else if (currentSection.equals("Outgoing", ignoreCase = true)) {
                    outgoingSum += parsed.raw
                }
            }
        }

        if (incomingTotalLineIndex >= 0) {
            val formatted = if ((incomingSum % 1.0) == 0.0) "${incomingSum.toLong()}" else String.format(Locale.US, "%.2f", incomingSum)
            updated[incomingTotalLineIndex] = "Total = $formatted"
        }

        if (outgoingTotalLineIndex >= 0) {
            val formatted = if ((outgoingSum % 1.0) == 0.0) "${outgoingSum.toLong()}" else String.format(Locale.US, "%.2f", outgoingSum)
            updated[outgoingTotalLineIndex] = "Total = $formatted"
        }

        if (balanceTotalLineIndex >= 0) {
            val bal = incomingSum - outgoingSum
            val formatted = if ((bal % 1.0) == 0.0) "${bal.toLong()}" else String.format(Locale.US, "%.2f", bal)
            updated[balanceTotalLineIndex] = "Total = $formatted"
        }

        return updated
    }
}
