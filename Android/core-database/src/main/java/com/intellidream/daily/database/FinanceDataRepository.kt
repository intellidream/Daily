package com.intellidream.daily.database

import com.intellidream.daily.model.CountryEconomicData
import com.intellidream.daily.model.FinanceSubTab
import com.intellidream.daily.model.MacroIndicator
import com.intellidream.daily.model.MarketType
import com.intellidream.daily.model.StockQuote
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Repository managing market data feeds: 6 Macro Pillars, 25-country Real Rate Heatmap,
 * and Securities Watchlist.
 */
class FinanceDataRepository(
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {
    private val _activeSubTab = MutableStateFlow(FinanceSubTab.Money)
    val activeSubTab: StateFlow<FinanceSubTab> = _activeSubTab.asStateFlow()

    private val _macroIndicators = MutableStateFlow(defaultMacroPillars)
    val macroIndicators: StateFlow<List<MacroIndicator>> = _macroIndicators.asStateFlow()

    private val _heatmapData = MutableStateFlow(defaultHeatmap.sortedByDescending { it.realRate })
    val heatmapData: StateFlow<List<CountryEconomicData>> = _heatmapData.asStateFlow()

    private val _watchlistQuotes = MutableStateFlow(defaultWatchlist)
    val watchlistQuotes: StateFlow<List<StockQuote>> = _watchlistQuotes.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    fun setActiveSubTab(tab: FinanceSubTab) {
        _activeSubTab.value = tab
    }

    fun updateMacroIndicators(updated: List<MacroIndicator>) {
        _macroIndicators.value = updated
    }

    fun updateWatchlist(updated: List<StockQuote>) {
        _watchlistQuotes.value = updated
    }

    fun toggleWatchlistQuote(quote: StockQuote) {
        val current = _watchlistQuotes.value.toMutableList()
        val index = current.indexOfFirst { it.symbol == quote.symbol }
        if (index >= 0) {
            current.removeAt(index)
        } else {
            current.add(quote)
        }
        _watchlistQuotes.value = current
    }

    companion object {
        val defaultMacroPillars = listOf(
            MacroIndicator(
                symbol = "CL=F",
                name = "Crude Oil (WTI)",
                pillar = "Energy",
                emoji = "🛢️",
                currentPrice = 71.24,
                change = -0.85,
                percentChange = -1.18,
                dayHigh = 72.80,
                dayLow = 70.50
            ),
            MacroIndicator(
                symbol = "GC=F",
                name = "Gold",
                pillar = "Safe Haven",
                emoji = "🟡",
                currentPrice = 2894.60,
                change = 14.20,
                percentChange = 0.49,
                dayHigh = 2905.0,
                dayLow = 2875.0
            ),
            MacroIndicator(
                symbol = "DX-Y.NYB",
                name = "US Dollar Index",
                pillar = "The King",
                emoji = "💵",
                currentPrice = 104.15,
                change = -0.22,
                percentChange = -0.21,
                dayHigh = 104.50,
                dayLow = 103.90
            ),
            MacroIndicator(
                symbol = "^NDX",
                name = "Nasdaq 100",
                pillar = "Tech/Growth",
                emoji = "💻",
                currentPrice = 21650.4,
                change = 185.3,
                percentChange = 0.86,
                dayHigh = 21720.0,
                dayLow = 21450.0
            ),
            MacroIndicator(
                symbol = "BTC-USD",
                name = "Bitcoin",
                pillar = "Risk/Future",
                emoji = "₿",
                currentPrice = 96450.0,
                change = 2150.0,
                percentChange = 2.28,
                dayHigh = 97200.0,
                dayLow = 93800.0
            ),
            MacroIndicator(
                symbol = "^VIX",
                name = "VIX Volatility",
                pillar = "Stress",
                emoji = "📊",
                currentPrice = 14.85,
                change = -0.65,
                percentChange = -4.19,
                dayHigh = 15.60,
                dayLow = 14.20
            )
        )

        val defaultHeatmap = listOf(
            // Americas
            CountryEconomicData("US", "United States", "USD", 4.50, 2.8, "Americas"),
            CountryEconomicData("CA", "Canada", "CAD", 3.25, 2.5, "Americas"),
            CountryEconomicData("BR", "Brazil", "BRL", 14.25, 5.1, "Americas"),
            CountryEconomicData("MX", "Mexico", "MXN", 9.50, 3.8, "Americas"),
            CountryEconomicData("AR", "Argentina", "ARS", 29.0, 67.0, "Americas"),

            // Europe
            CountryEconomicData("DE", "Germany", "EUR", 2.65, 2.3, "Europe"),
            CountryEconomicData("GB", "United Kingdom", "GBP", 4.50, 3.0, "Europe"),
            CountryEconomicData("FR", "France", "EUR", 2.65, 1.8, "Europe"),
            CountryEconomicData("CH", "Switzerland", "CHF", 0.50, 1.1, "Europe"),
            CountryEconomicData("RO", "Romania", "RON", 6.50, 5.0, "Europe"),
            CountryEconomicData("PL", "Poland", "PLN", 5.75, 4.7, "Europe"),
            CountryEconomicData("TR", "Turkey", "TRY", 42.50, 44.0, "Europe"),
            CountryEconomicData("SE", "Sweden", "SEK", 2.25, 1.5, "Europe"),

            // Asia-Pacific
            CountryEconomicData("JP", "Japan", "JPY", 0.50, 3.2, "Asia"),
            CountryEconomicData("CN", "China", "CNY", 3.10, 0.5, "Asia"),
            CountryEconomicData("IN", "India", "INR", 6.25, 4.5, "Asia"),
            CountryEconomicData("KR", "South Korea", "KRW", 2.75, 2.0, "Asia"),
            CountryEconomicData("AU", "Australia", "AUD", 4.10, 3.4, "Asia"),
            CountryEconomicData("ID", "Indonesia", "IDR", 5.75, 3.0, "Asia"),
            CountryEconomicData("TH", "Thailand", "THB", 2.00, 1.2, "Asia"),

            // Middle East & Africa
            CountryEconomicData("ZA", "South Africa", "ZAR", 7.50, 5.3, "Africa"),
            CountryEconomicData("NG", "Nigeria", "NGN", 27.50, 29.0, "Africa"),
            CountryEconomicData("SA", "Saudi Arabia", "SAR", 5.50, 1.7, "Middle East"),
            CountryEconomicData("AE", "UAE", "AED", 4.90, 2.1, "Middle East"),
            CountryEconomicData("EG", "Egypt", "EGP", 27.25, 24.0, "Africa")
        )

        val defaultWatchlist = listOf(
            StockQuote("AAPL", "Apple Inc.", 242.80, 3.45, 1.44, MarketType.Stock, "USD", "https://www.google.com/s2/favicons?domain=apple.com&sz=128", 244.50, 239.80, 54200000),
            StockQuote("NVDA", "NVIDIA Corp.", 138.25, 4.12, 3.07, MarketType.Stock, "USD", "https://www.google.com/s2/favicons?domain=nvidia.com&sz=128", 140.10, 134.50, 88400000),
            StockQuote("MSFT", "Microsoft Corp.", 428.60, 2.80, 0.66, MarketType.Stock, "USD", "https://www.google.com/s2/favicons?domain=microsoft.com&sz=128", 431.20, 426.00, 22100000),
            StockQuote("TSLA", "Tesla, Inc.", 345.10, -5.40, -1.54, MarketType.Stock, "USD", "https://www.google.com/s2/favicons?domain=tesla.com&sz=128", 352.00, 341.20, 67300000),
            StockQuote("BTC-USD", "Bitcoin", 96450.0, 2150.0, 2.28, MarketType.Crypto, "USD", "https://upload.wikimedia.org/wikipedia/commons/4/46/Bitcoin.svg", 97200.0, 93800.0, 38200000000),
            StockQuote("ETH-USD", "Ethereum", 2780.40, 65.20, 2.40, MarketType.Crypto, "USD", "https://upload.wikimedia.org/wikipedia/commons/6/6f/Ethereum-icon-purple.svg", 2820.0, 2710.0, 16500000000),
            StockQuote("EURUSD=X", "EUR / USD", 1.0482, 0.0031, 0.30, MarketType.Forex, "USD", "https://www.google.com/s2/favicons?domain=europa.eu&sz=128", 1.0510, 1.0440, null)
        )
    }
}
