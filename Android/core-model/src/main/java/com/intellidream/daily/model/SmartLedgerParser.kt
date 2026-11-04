package com.intellidream.daily.model

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import java.util.regex.Pattern

/**
 * Robust parser for the text-based Smart Ledger DSL.
 * Adheres strictly to the user-defined rules:
 * 1. Parentheses `(...)` are purely informative annotations and are completely ignored for value calculations.
 * 2. Shorthand scale: values from `**Incoming**` up to `**Deposit**` have a 100x multiplier (e.g. 151 = 15.100 Lei).
 * 3. Values in `**Deposit**` and afterwards are full, unscaled values (e.g. 44.000L = 44.000 Lei, 53.156,47 = 53.156,47 Lei).
 * 4. Net Worth = Deposits Total + Balance Total.
 */
object SmartLedgerParser {

    fun normalizeLineEndings(text: String): String {
        return text.replace("\r\n", "\n").replace("\r", "\n")
    }

    fun normalizeLedgerText(text: String): String {
        val unified = normalizeLineEndings(text)
        return unified.split("\n").joinToString("\n") { rawLine ->
            val trimmed = rawLine.trim()
            val secName = extractSectionHeader(trimmed)
            if (secName != null) "**$secName**" else rawLine
        }
    }

    private fun isDividerLine(trimmed: String): Boolean {
        return trimmed.isEmpty()
            || trimmed == "---" || trimmed == "- - -"
            || trimmed == "***" || trimmed == "* * *"
            || trimmed == "___" || trimmed == "_ _ _"
    }

    private fun canonicalizeSectionName(rawName: String): String {
        val clean = rawName.trim()
        return when (clean.lowercase(Locale.ROOT)) {
            "incoming" -> "Incoming"
            "outgoing" -> "Outgoing"
            "balance" -> "Balance"
            "dentist" -> "Dentist"
            "deposit" -> "Deposit"
            "investments" -> "Investments"
            else -> clean
        }
    }

    fun extractSectionHeader(trimmed: String): String? {
        if (isDividerLine(trimmed)) return null
        if (trimmed.startsWith("(") || trimmed.startsWith("//") || trimmed.contains("=")) {
            return null
        }

        // 1. **Section** or __Section__
        if ((trimmed.startsWith("**") && trimmed.endsWith("**") && trimmed.length > 4)
            || (trimmed.startsWith("__") && trimmed.endsWith("__") && trimmed.length > 4)
        ) {
            val inner = trimmed.substring(2, trimmed.length - 2).trim()
            return if (inner.isNotEmpty()) canonicalizeSectionName(inner) else null
        }

        // 2. *Section* or _Section_ (Notion Mobile clipboard format)
        if (trimmed.startsWith("*") && trimmed.endsWith("*") && !trimmed.startsWith("**") && trimmed.length > 2) {
            val inner = trimmed.substring(1, trimmed.length - 1).trim()
            return if (inner.isNotEmpty() && !inner.contains("*")) canonicalizeSectionName(inner) else null
        }
        if (trimmed.startsWith("_") && trimmed.endsWith("_") && !trimmed.startsWith("__") && trimmed.length > 2) {
            val inner = trimmed.substring(1, trimmed.length - 1).trim()
            return if (inner.isNotEmpty() && !inner.contains("_")) canonicalizeSectionName(inner) else null
        }

        // 3. ATX Markdown headings: # Section, ## Section, ### Section
        if (trimmed.startsWith("#")) {
            val rest = trimmed.dropWhile { it == '#' }
            if (rest.startsWith(" ") || rest.startsWith("\t")) {
                val inner = rest.trim()
                if (inner.isNotEmpty()) return canonicalizeSectionName(inner)
            }
        }

        // 4. Plain-text Desktop Notion canonical section headers (optional trailing ':')
        val candidate = if (trimmed.endsWith(":")) trimmed.dropLast(1).trim() else trimmed
        return when (candidate.lowercase(Locale.ROOT)) {
            "incoming" -> "Incoming"
            "outgoing" -> "Outgoing"
            "balance" -> "Balance"
            "dentist" -> "Dentist"
            "deposit" -> "Deposit"
            "investments" -> "Investments"
            else -> null
        }
    }

    fun parse(text: String, eurRate: Double = 5.0): ParsedSmartLedger {
        val sections = mutableListOf<SmartLedgerSection>()
        val lines = normalizeLineEndings(text).split("\n")

        var currentSectionName = "Overview"
        val currentItems = mutableListOf<SmartLedgerItem>()
        var currentSectionScaled = true
        var currentSectionExplicitTotal: Double? = null
        var currentSectionRawTotal: Double? = null
        var hasEncounteredDeposit = false

        fun finishCurrentSection() {
            if (currentItems.isEmpty() && currentSectionExplicitTotal == null) return

            val itemsCalculatedSum = currentItems.sumOf { if (it.isPureNote) 0.0 else it.calculatedAmount }
            val itemsRawSum = currentItems.sumOf { if (it.isPureNote) 0.0 else it.rawAmount }

            val finalCalculatedTotal = currentSectionExplicitTotal ?: itemsCalculatedSum
            val finalRawTotal = currentSectionRawTotal ?: itemsRawSum

            val updatedItems = currentItems.toMutableList()
            if (finalCalculatedTotal > 0) {
                for (i in updatedItems.indices) {
                    if (!updatedItems[i].isPureNote) {
                        updatedItems[i] = updatedItems[i].copy(
                            percentageOfSection = updatedItems[i].calculatedAmount / finalCalculatedTotal
                        )
                    }
                }
            }

            val section = SmartLedgerSection(
                name = currentSectionName,
                items = updatedItems,
                totalCalculated = finalCalculatedTotal,
                totalRaw = finalRawTotal,
                isScaled = currentSectionScaled
            )
            sections.add(section)

            currentItems.clear()
            currentSectionExplicitTotal = null
            currentSectionRawTotal = null
        }

        for ((lineIndex, rawLine) in lines.withIndex()) {
            val line = rawLine.trim()

            if (isDividerLine(line)) {
                continue
            }

            // Check for section header (**Section**, *Section*, # Section, or canonical plain-text Section)
            val secName = extractSectionHeader(line)
            if (secName != null) {
                finishCurrentSection()
                currentSectionName = secName

                if (secName.equals("Deposit", ignoreCase = true)) {
                    hasEncounteredDeposit = true
                }

                currentSectionScaled = !hasEncounteredDeposit
                continue
            }

            // Handle lines enclosed in parentheses, e.g. (Total = 106)
            if (line.startsWith("(") && line.endsWith(")")) {
                val inner = line.substring(1, line.length - 1).trim()

                if (inner.startsWith("Total =", ignoreCase = true) || inner.startsWith("Total=", ignoreCase = true)) {
                    val parts = inner.split("=")
                    if (parts.size >= 2) {
                        val parsedVal = parseNumericString(parts[1], isScaled = currentSectionScaled, eurRate = eurRate)
                        currentSectionExplicitTotal = parsedVal.calculated
                        currentSectionRawTotal = parsedVal.raw
                    }
                    continue
                } else {
                    val item = SmartLedgerItem(
                        sectionName = currentSectionName,
                        lineIndex = lineIndex,
                        rawLine = rawLine,
                        key = inner,
                        rawAmount = 0.0,
                        calculatedAmount = 0.0,
                        currency = "Lei",
                        isScaled = currentSectionScaled,
                        notes = listOf(inner),
                        isPureNote = true
                    )
                    currentItems.add(item)
                    continue
                }
            }

            // Check if line contains assignment: Key = Value
            if (line.contains("=")) {
                val parts = line.split("=", limit = 2)
                val keyPart = parts[0].trim()
                val valuePart = parts[1].trim()

                if (keyPart.equals("Total", ignoreCase = true)) {
                    val parsedVal = parseNumericString(valuePart, isScaled = currentSectionScaled, eurRate = eurRate)
                    currentSectionExplicitTotal = parsedVal.calculated
                    currentSectionRawTotal = parsedVal.raw
                    continue
                }

                val notes = extractParenthesesNotes(line)
                val parsedVal = parseNumericString(valuePart, isScaled = currentSectionScaled, eurRate = eurRate)
                val cleanKey = cleanKeyName(keyPart)

                val item = SmartLedgerItem(
                    sectionName = currentSectionName,
                    lineIndex = lineIndex,
                    rawLine = rawLine,
                    key = cleanKey,
                    rawAmount = parsedVal.raw,
                    calculatedAmount = parsedVal.calculated,
                    currency = if (parsedVal.isEUR) "EUR" else "Lei",
                    isScaled = currentSectionScaled,
                    notes = notes,
                    isPureNote = false
                )
                currentItems.add(item)
            } else {
                val item = SmartLedgerItem(
                    sectionName = currentSectionName,
                    lineIndex = lineIndex,
                    rawLine = rawLine,
                    key = line,
                    rawAmount = 0.0,
                    calculatedAmount = 0.0,
                    isScaled = currentSectionScaled,
                    notes = listOf(line),
                    isPureNote = true
                )
                currentItems.add(item)
            }
        }

        finishCurrentSection()

        val incomingSec = sections.firstOrNull { it.name.equals("Incoming", ignoreCase = true) }
        val outgoingSec = sections.firstOrNull { it.name.equals("Outgoing", ignoreCase = true) }
        val balanceSec = sections.firstOrNull { it.name.equals("Balance", ignoreCase = true) }
        val dentistSec = sections.firstOrNull { it.name.equals("Dentist", ignoreCase = true) }
        val depositSec = sections.firstOrNull { it.name.equals("Deposit", ignoreCase = true) }

        val inTotal = incomingSec?.totalCalculated ?: 0.0
        val outTotal = outgoingSec?.totalCalculated ?: 0.0
        val balTotal = balanceSec?.totalCalculated ?: (inTotal - outTotal).coerceAtLeast(0.0)
        val dentTotal = dentistSec?.totalCalculated ?: 0.0
        val depTotal = depositSec?.totalCalculated ?: 0.0

        val nw = depTotal + balTotal
        val nwEUR = if (eurRate > 0) nw / eurRate else 0.0

        return ParsedSmartLedger(
            sections = sections,
            incomingTotal = inTotal,
            outgoingTotal = outTotal,
            balanceTotal = balTotal,
            dentistTotal = dentTotal,
            depositTotal = depTotal,
            netWorth = nw,
            netWorthEUR = nwEUR,
            rawText = text
        )
    }

    data class ParsedNumeric(val raw: Double, val calculated: Double, val isEUR: Boolean = false)

    fun parseNumericString(valStr: String, isScaled: Boolean, eurRate: Double = 5.0): ParsedNumeric {
        var clean = valStr

        // 1. Remove all content inside parentheses (...) first
        clean = clean.replace(Regex("\\(.*?\\)"), "")

        // 2. Drop inline comments after //
        val commentIdx = clean.indexOf("//")
        if (commentIdx >= 0) {
            clean = clean.substring(0, commentIdx)
        }

        // Detect EUR symbol or letters outside parentheses and comments
        val isEUR = clean.contains("€") || clean.contains("EUR", ignoreCase = true)

        // 3. Remove letters and unwanted characters (L, €, $, ~, %, etc.)
        clean = clean.replace(Regex("[L€$~$% ]"), "").replace(Regex("EUR", RegexOption.IGNORE_CASE), "").trim()

        if (clean.isEmpty()) return ParsedNumeric(0.0, 0.0, isEUR)

        // 4. Parse Romanian / European decimal format
        var normalized = clean
        if (normalized.contains(",")) {
            // e.g. "53.156,47" -> remove dot, replace comma with dot
            normalized = normalized.replace(".", "").replace(",", ".")
        } else if (normalized.contains(".")) {
            val parts = normalized.split(".")
            if (parts.size == 2 && parts[1].length == 3) {
                // e.g. "44.000" -> dot is thousands separator
                normalized = normalized.replace(".", "")
            }
        }

        val num = normalized.toDoubleOrNull() ?: return ParsedNumeric(0.0, 0.0, isEUR)
        val baseCalculated = if (isScaled) num * 100.0 else num
        val calculated = if (isEUR) baseCalculated * eurRate else baseCalculated
        return ParsedNumeric(num, calculated, isEUR)
    }

    private fun extractParenthesesNotes(line: String): List<String> {
        val notes = mutableListOf<String>()
        val matcher = Pattern.compile("\\((.*?)\\)").matcher(line)
        while (matcher.find()) {
            val note = matcher.group(1)?.trim() ?: ""
            if (note.isNotEmpty() && !note.startsWith("Total =", ignoreCase = true)) {
                notes.add(note)
            }
        }
        return notes
    }

    private fun cleanKeyName(key: String): String {
        var k = key.trim()
        k = k.replace(Regex("\\(.*?\\)"), "").trim()
        while (k.endsWith("/")) {
            k = k.dropLast(1).trim()
        }
        return k
    }

    fun adjustItemAmount(text: String, lineIndex: Int, deltaRaw: Double): String {
        val normalizedText = normalizeLineEndings(text)
        val lines = normalizedText.split("\n")
        if (lineIndex !in lines.indices) return normalizedText
        val line = lines[lineIndex]
        if (!line.contains("=")) return normalizedText
        val parts = line.split("=", limit = 2)
        val valuePart = parts[1].trim()
        val parsed = parseNumericString(valuePart, isScaled = false)
        val newRaw = (parsed.raw + deltaRaw).coerceAtLeast(0.0)
        return setItemAmount(normalizedText, lineIndex, newRaw)
    }

    fun setItemAmount(text: String, lineIndex: Int, newRaw: Double): String {
        val normalizedText = normalizeLineEndings(text)
        val lines = normalizedText.split("\n").toMutableList()
        if (lineIndex !in lines.indices) return normalizedText

        val oldLine = lines[lineIndex]
        val eqIdx = oldLine.indexOf("=")
        if (eqIdx < 0) return normalizedText

        val keyPart = oldLine.substring(0, eqIdx + 1) // e.g. "Card ="
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

        val formattedNum = formatNumberForDsl(newRaw, numRegion)
        val spaceBeforeRest = if (restOfLine.isEmpty() || restOfLine.startsWith(" ")) "" else " "

        lines[lineIndex] = "$keyPart $formattedNum$suffix$spaceBeforeRest$restOfLine"
        val updated = recalculateTotalsInLines(lines)
        return updated.joinToString("\n")
    }

    fun addItem(text: String, sectionName: String, key: String, rawAmount: Double, note: String?): String {
        val normalizedText = normalizeLineEndings(text)
        val lines = normalizedText.split("\n").toMutableList()

        var sectionHeaderIndex = -1
        for ((idx, line) in lines.withIndex()) {
            val trimmed = line.trim()
            val name = extractSectionHeader(trimmed)
            if (name != null && name.equals(sectionName, ignoreCase = true)) {
                sectionHeaderIndex = idx
                break
            }
        }

        if (sectionHeaderIndex < 0) return normalizedText

        var insertIndex = lines.size
        for (idx in (sectionHeaderIndex + 1) until lines.size) {
            val trimmed = lines[idx].trim()
            if (extractSectionHeader(trimmed) != null) {
                insertIndex = idx
                break
            }
            if (trimmed.isNotEmpty() && isDividerLine(trimmed)) {
                var isBeforeTotal = false
                for (nextIdx in (idx + 1) until minOf(idx + 5, lines.size)) {
                    val nextTrimmed = lines[nextIdx].trim()
                    if (nextTrimmed.startsWith("Total =", ignoreCase = true)
                        || nextTrimmed.startsWith("Total=", ignoreCase = true)
                        || nextTrimmed.startsWith("(Total", ignoreCase = true)
                    ) {
                        isBeforeTotal = true
                        break
                    }
                }
                if (isBeforeTotal) {
                    insertIndex = idx
                    break
                }
            } else if (trimmed.startsWith("Total =", ignoreCase = true)
                || trimmed.startsWith("Total=", ignoreCase = true)
                || trimmed.startsWith("(Total", ignoreCase = true)
            ) {
                insertIndex = idx
                break
            }
        }

        val formattedNum = if ((rawAmount % 1.0) == 0.0) "${rawAmount.toLong()}" else String.format(Locale.US, "%.2f", rawAmount)
        val trimmedNote = (note ?: "").trim()
        val notePart = if (trimmedNote.isEmpty()) "" else " ($trimmedNote)"
        val newLine = "$key = $formattedNum$notePart"

        lines.add(insertIndex, newLine)
        lines.add(insertIndex + 1, "")

        val updated = recalculateTotalsInLines(lines)
        return updated.joinToString("\n")
    }

    fun deleteItem(text: String, lineIndex: Int): String {
        val normalizedText = normalizeLineEndings(text)
        val lines = normalizedText.split("\n").toMutableList()
        if (lineIndex !in lines.indices) return normalizedText

        lines.removeAt(lineIndex)

        if (lineIndex < lines.size && lines[lineIndex].trim().isEmpty()) {
            if (lineIndex - 1 >= 0 && lines[lineIndex - 1].trim().isEmpty()) {
                lines.removeAt(lineIndex)
            }
        }

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
            val secName = extractSectionHeader(trimmed)
            if (secName != null) {
                currentSection = secName
                continue
            }
            if (trimmed.startsWith("(") && trimmed.endsWith(")")) {
                continue
            }

            if (trimmed.contains("=")) {
                val parts = trimmed.split("=", limit = 2)
                val key = parts[0].trim()
                val valStr = parts[1].trim()

                if (key.equals("Total", ignoreCase = true)) {
                    if (currentSection.equals("Incoming", ignoreCase = true)) {
                        incomingTotalLineIndex = idx
                    } else if (currentSection.equals("Outgoing", ignoreCase = true)) {
                        outgoingTotalLineIndex = idx
                    } else if (currentSection.equals("Balance", ignoreCase = true)) {
                        balanceTotalLineIndex = idx
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

    private fun formatNumberForDsl(value: Double, originalString: String): String {
        return if (originalString.contains(",")) {
            val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
                groupingSeparator = '.'
                decimalSeparator = ','
            }
            val hasDecimals = (value % 1.0) != 0.0
            val pattern = if (hasDecimals) "#,##0.00" else "#,##0"
            DecimalFormat(pattern, symbols).format(value)
        } else if (originalString.contains(".")) {
            val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
                groupingSeparator = '.'
            }
            DecimalFormat("#,##0", symbols).format(value)
        } else {
            if ((value % 1.0) == 0.0) {
                "${value.toLong()}"
            } else {
                String.format(Locale.US, "%.2f", value)
            }
        }
    }
}
