package com.intellidream.daily.model

import kotlinx.serialization.Serializable
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import java.util.UUID

/**
 * Represents an individual parsed line or item in a financial Smart Ledger section.
 */
@Serializable
data class SmartLedgerItem(
    val id: String = UUID.randomUUID().toString(),
    val sectionName: String = "",
    val lineIndex: Int = -1,
    val rawLine: String = "",
    val key: String,
    val rawAmount: Double = 0.0,
    val calculatedAmount: Double = 0.0,
    val currency: String = "Lei",
    val isScaled: Boolean = true,
    val notes: List<String> = emptyList(),
    val isPureNote: Boolean = false,
    val percentageOfSection: Double = 0.0
) {
    /**
     * Clean display title for UI pills (e.g. "Tigari" for "Tigari (40/45)" or "Serviciu//Outs").
     */
    val displayName: String
        get() {
            if (isPureNote) return key
            var clean = key.replace(Regex("\\(.*?\\)"), "").trim()
            while (clean.endsWith("/")) {
                clean = clean.dropLast(1).trim()
            }
            return if (clean.isEmpty()) key else clean
        }

    /**
     * Nicely formatted amount in original currency (e.g. "2.500 €" or "15.100 Lei").
     */
    val formattedCalculatedAmount: String
        get() {
            val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
                groupingSeparator = '.'
                decimalSeparator = ','
            }
            if (currency == "EUR") {
                val hasDecimals = (rawAmount % 1.0) != 0.0
                val pattern = if (hasDecimals) "#,##0.00" else "#,##0"
                val formatter = DecimalFormat(pattern, symbols)
                return "${formatter.format(rawAmount)} €"
            } else {
                val hasDecimals = (calculatedAmount % 1.0) != 0.0
                val pattern = if (hasDecimals) "#,##0.00" else "#,##0"
                val formatter = DecimalFormat(pattern, symbols)
                return "${formatter.format(calculatedAmount)} Lei"
            }
        }

    /**
     * Always formats the full equivalent amount in Romanian Lei (e.g. "12.500 Lei").
     */
    val formattedLeiAmount: String
        get() {
            val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
                groupingSeparator = '.'
                decimalSeparator = ','
            }
            val hasDecimals = (calculatedAmount % 1.0) != 0.0
            val pattern = if (hasDecimals) "#,##0.00" else "#,##0"
            val formatter = DecimalFormat(pattern, symbols)
            return "${formatter.format(calculatedAmount)} Lei"
        }

    /**
     * User's original shorthand numeric notation (e.g. "151", "49", "10").
     */
    val formattedRawAmount: String
        get() {
            return if ((rawAmount % 1.0) == 0.0) {
                "${rawAmount.toLong()}"
            } else {
                val symbols = DecimalFormatSymbols(Locale.US)
                val formatter = DecimalFormat("#.##", symbols)
                formatter.format(rawAmount)
            }
        }
}

/**
 * Represents a distinct section within the Smart Ledger (e.g. Incoming, Outgoing, Balance, Deposit, Dentist).
 */
@Serializable
data class SmartLedgerSection(
    val name: String,
    val items: List<SmartLedgerItem> = emptyList(),
    val totalCalculated: Double = 0.0,
    val totalRaw: Double = 0.0,
    val isScaled: Boolean = true
) {
    val id: String get() = name

    val formattedTotal: String
        get() {
            val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
                groupingSeparator = '.'
                decimalSeparator = ','
            }
            val hasDecimals = (totalCalculated % 1.0) != 0.0
            val pattern = if (hasDecimals) "#,##0.00" else "#,##0"
            val formatter = DecimalFormat(pattern, symbols)
            return "${formatter.format(totalCalculated)} Lei"
        }

    val formattedRawTotal: String
        get() {
            return if ((totalRaw % 1.0) == 0.0) {
                "${totalRaw.toLong()}"
            } else {
                String.format(Locale.US, "%.2f", totalRaw)
            }
        }
}

/**
 * The fully parsed and computed state of the user's Smart Ledger text.
 */
@Serializable
data class ParsedSmartLedger(
    val sections: List<SmartLedgerSection> = emptyList(),
    val incomingTotal: Double = 0.0,
    val outgoingTotal: Double = 0.0,
    val balanceTotal: Double = 0.0,
    val dentistTotal: Double = 0.0,
    val depositTotal: Double = 0.0,
    val netWorth: Double = 0.0,
    val netWorthEUR: Double = 0.0,
    val rawText: String = ""
) {
    val formattedNetWorth: String
        get() = formatCurrency(netWorth)

    val formattedNetWorthEUR: String
        get() {
            val symbols = DecimalFormatSymbols(Locale.GERMANY).apply {
                groupingSeparator = '.'
            }
            val formatter = DecimalFormat("#,##0", symbols)
            return "~${formatter.format(netWorthEUR)} €"
        }

    val formattedIncomingTotal: String get() = formatCurrency(incomingTotal)
    val formattedOutgoingTotal: String get() = formatCurrency(outgoingTotal)
    val formattedBalanceTotal: String get() = formatCurrency(balanceTotal)
    val formattedDentistTotal: String get() = formatCurrency(dentistTotal)
    val formattedDepositTotal: String get() = formatCurrency(depositTotal)

    /**
     * Compact formatted string without decimal cents for small badge capsules (e.g. "127.156 Lei").
     */
    fun formattedBadge(value: Double): String {
        val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
            groupingSeparator = '.'
        }
        val formatter = DecimalFormat("#,##0", symbols)
        return "${formatter.format(value)} Lei"
    }

    private fun formatCurrency(value: Double): String {
        val symbols = DecimalFormatSymbols(Locale("ro", "RO")).apply {
            groupingSeparator = '.'
            decimalSeparator = ','
        }
        val hasDecimals = (value % 1.0) != 0.0
        val pattern = if (hasDecimals) "#,##0.00" else "#,##0"
        val formatter = DecimalFormat(pattern, symbols)
        return "${formatter.format(value)} Lei"
    }
}

val DEFAULT_LEDGER_TEXT: String = """
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

Serviciu/(0/__STAR__100)/Outs/(0*200) = 0

Acasa/Tuns/Cadouri = 10 (M&T=5/!!!!!/5)

Vacante/Noi/Iesiri/Other = 68 (C__DOLLAR__40/B__DOLLAR__20)

Subs (APL-21.01-__DOLLAR__5/RED-14.03-__DOLLAR__1/CSP-29.05-__DOLLAR__5)(PRL-11.08-__DOLLAR__6/365-25.08-__DOLLAR__7/NSK-29.8-__DOLLAR__2)(MRG-31.8-__DOLLAR__2/STRS-22.09-__DOLLAR__1)(EMG-13.12-__DOLLAR__1) = 1

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

(Mașini x8y~(x7-27.000€)+(x8+-27.000€)__DOLLAR__
""".trimIndent()
    .replace("__STAR__", "*")
    .replace("__DOLLAR__", "$")
