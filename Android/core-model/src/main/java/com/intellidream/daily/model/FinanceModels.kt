package com.intellidream.daily.model

import kotlinx.serialization.Serializable
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import java.util.UUID

/**
 * Sub-tabs within the Finance Hub.
 */
@Serializable
enum class FinanceSubTab(val id: String, val title: String) {
    Money("money", "Money"),
    Stocks("stocks", "Stocks"),
    World("world", "World");

    companion object {
        fun fromId(id: String): FinanceSubTab = entries.firstOrNull { it.id.equals(id, ignoreCase = true) } ?: Money
    }
}

/**
 * Financial asset class classification.
 */
@Serializable
enum class MarketType(val displayName: String) {
    Stock("Stocks"),
    Crypto("Crypto"),
    Forex("Forex")
}

/**
 * Type of financial ledger account.
 */
@Serializable
enum class AccountType(val displayName: String) {
    Checking("Checking"),
    Savings("Savings"),
    Credit("Credit Card"),
    Investment("Investment")
}

/**
 * A bank, savings, credit, or investment account.
 */
@Serializable
data class FinanceAccount(
    val id: String = UUID.randomUUID().toString(),
    val userId: String? = null,
    val name: String,
    val type: AccountType,
    val currency: String = "USD",
    val currentBalance: Double = 0.0,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long? = null
) {
    val formattedBalance: String
        get() {
            val symbols = DecimalFormatSymbols(Locale.US)
            val formatter = DecimalFormat("$#,##0.00", symbols)
            return formatter.format(currentBalance)
        }
}

/**
 * A financial income, expense, or transfer transaction.
 */
@Serializable
data class FinanceTransaction(
    val id: String = UUID.randomUUID().toString(),
    val accountId: String,
    val date: Long = System.currentTimeMillis(),
    val amount: Double,
    val category: String? = null,
    val description: String? = null
) {
    val isIncome: Boolean get() = amount > 0

    val formattedAmount: String
        get() {
            val symbols = DecimalFormatSymbols(Locale.US)
            val formatter = DecimalFormat("$#,##0.00", symbols)
            val prefix = if (amount >= 0) "+" else "-"
            return "$prefix${formatter.format(Math.abs(amount))}"
        }
}

/**
 * Real-time and cached security market quote.
 */
@Serializable
data class StockQuote(
    val symbol: String,
    val companyName: String,
    val currentPrice: Double,
    val change: Double,
    val percentChange: Double,
    val marketType: MarketType = MarketType.Stock,
    val currency: String = "USD",
    val logoUrl: String? = null,
    val dayHigh: Double? = null,
    val dayLow: Double? = null,
    val volume: Long? = null,
    val marketCap: Long? = null,
    val exchange: String? = null
) {
    val id: String get() = symbol
    val isPositive: Boolean get() = change >= 0

    val currencySymbol: String
        get() = when (currency.uppercase(Locale.ROOT)) {
            "USD" -> "$"
            "EUR" -> "€"
            "RON" -> "lei"
            "GBP" -> "£"
            "JPY" -> "¥"
            else -> currency
        }

    val formattedPrice: String
        get() {
            val symbols = DecimalFormatSymbols(Locale.US)
            val pattern = if (currentPrice < 1.0) "$#,##0.0000" else "$#,##0.00"
            val formatter = DecimalFormat(pattern, symbols)
            formatter.positivePrefix = currencySymbol
            formatter.negativePrefix = "-$currencySymbol"
            return formatter.format(currentPrice)
        }

    val formattedChangePercent: String
        get() {
            val prefix = if (percentChange >= 0) "+" else ""
            return String.format(Locale.US, "%s%.2f%%", prefix, percentChange)
        }
}

/**
 * Global macroeconomic indicator matching the 6 Core Pillars in WinUI / iOS DailyCore.
 */
@Serializable
data class MacroIndicator(
    val symbol: String,
    val name: String,
    val pillar: String, // Energy, Safe Haven, The King, Tech/Growth, Risk/Future, Stress
    val emoji: String,  // 🛢️, 🟡, 💵, 💻, ₿, 📊
    val currentPrice: Double,
    val change: Double,
    val percentChange: Double,
    val currency: String = "USD",
    val dayHigh: Double? = null,
    val dayLow: Double? = null,
    val volume: Long? = null
) {
    val id: String get() = symbol
    val isPositive: Boolean get() = change >= 0

    val currencySymbol: String
        get() = when (currency.uppercase(Locale.ROOT)) {
            "USD" -> "$"
            "EUR" -> "€"
            "GBP" -> "£"
            "JPY" -> "¥"
            else -> currency
        }

    /**
     * Human-friendly interpretation of indicator movement, matching WinUI & iOS MacroModels.
     */
    val insight: String
        get() = when (pillar) {
            "Energy" -> if (isPositive) "Energy costs rising — inflation pressure" else "Energy easing — good for consumers"
            "Safe Haven" -> if (isPositive) "Fear rising — investors seeking safety" else "Confidence returning — risk-on"
            "The King" -> if (isPositive) "Dollar strong — pressure on emerging markets" else "Dollar weakening — relief for EM"
            "Tech/Growth" -> if (isPositive) "Tech optimism — growth mode" else "Tech pullback — caution in markets"
            "Risk/Future" -> if (isPositive) "Risk appetite high — speculative mood" else "Risk-off — caution prevails"
            "Stress" -> if (currentPrice > 30.0) "⚠️ Markets panicking (VIX > 30)" else if (currentPrice > 20.0) "Elevated concern" else "Markets calm"
            else -> ""
        }

    val formattedPrice: String
        get() {
            val symbols = DecimalFormatSymbols(Locale.US)
            val formatter = DecimalFormat("#,##0.00", symbols)
            return "$currencySymbol${formatter.format(currentPrice)}"
        }

    val formattedChangePercent: String
        get() {
            val prefix = if (percentChange >= 0) "+" else ""
            return String.format(Locale.US, "%s%.2f%%", prefix, percentChange)
        }
}

/**
 * Country economic rate data for the Global Heatmap (Real Rate = Interest Rate - Inflation Rate).
 */
@Serializable
data class CountryEconomicData(
    val countryCode: String, // ISO 3166-1 alpha-2 (US, RO, DE, etc.)
    val countryName: String,
    val currencyCode: String,
    val interestRate: Double,
    val inflationRate: Double,
    val region: String
) {
    val id: String get() = countryCode

    /**
     * Real Rate = Central Bank Interest Rate minus Inflation Rate.
     */
    val realRate: Double get() = interestRate - inflationRate

    /**
     * Flag emoji dynamically calculated from ISO 3166-1 country code.
     */
    val flagEmoji: String
        get() {
            val firstChar = Character.codePointAt(countryCode.uppercase(Locale.ROOT), 0) - 0x41 + 0x1F1E6
            val secondChar = Character.codePointAt(countryCode.uppercase(Locale.ROOT), 1) - 0x41 + 0x1F1E6
            return String(Character.toChars(firstChar)) + String(Character.toChars(secondChar))
        }

    val formattedRealRate: String
        get() {
            val prefix = if (realRate >= 0) "+" else ""
            return String.format(Locale.US, "%s%.2f%%", prefix, realRate)
        }
}

/**
 * Aggregated financial net worth and breakdown summary.
 */
@Serializable
data class FinanceSummary(
    val netWorth: Double = 0.0,
    val cashTotal: Double = 0.0,
    val investmentsTotal: Double = 0.0,
    val liabilitiesTotal: Double = 0.0,
    val dayChange: Double = 0.0,
    val dayChangePercent: Double = 0.0,
    val baseCurrency: String = "USD"
) {
    val formattedNetWorth: String get() = formatDollar(netWorth)
    val formattedCash: String get() = formatDollar(cashTotal)
    val formattedInvestments: String get() = formatDollar(investmentsTotal)
    val formattedLiabilities: String get() = formatDollar(liabilitiesTotal)

    private fun formatDollar(value: Double): String {
        val symbols = DecimalFormatSymbols(Locale.US)
        val formatter = DecimalFormat("$#,##0", symbols)
        return formatter.format(value)
    }
}
