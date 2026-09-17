package com.intellidream.daily.network

import com.intellidream.daily.model.MarketType
import com.intellidream.daily.model.StockQuote
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.net.URLEncoder

@Serializable
data class RemoteLedgerRecord(
    val id: String = "primary_ledger",
    val user_id: String? = null,
    val raw_text: String,
    val updated_at: Long = System.currentTimeMillis()
)

class FinanceRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    private val httpClient = HttpClient(CIO) {
        install(HttpTimeout) {
            requestTimeoutMillis = 4000L
            connectTimeoutMillis = 4000L
            socketTimeoutMillis = 4000L
        }
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchYahooQuote(symbol: String, marketType: MarketType = MarketType.Stock): StockQuote? = withContext(Dispatchers.IO) {
        try {
            val encoded = URLEncoder.encode(symbol, "UTF-8")
            val url = "https://query1.finance.yahoo.com/v8/finance/chart/$encoded?interval=1d&range=1d"
            val response = httpClient.get(url) {
                header("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
                header("Accept", "application/json")
            }

            if (response.status.value != 200) return@withContext null

            val bodyText = response.bodyAsText()
            val root = json.parseToJsonElement(bodyText).jsonObject
            val chart = root["chart"]?.jsonObject ?: return@withContext null
            val result = chart["result"]?.jsonArray?.firstOrNull()?.jsonObject ?: return@withContext null
            val meta = result["meta"]?.jsonObject ?: return@withContext null

            val regularPrice = meta["regularMarketPrice"]?.jsonPrimitive?.doubleOrNull ?: return@withContext null
            val previousClose = meta["chartPreviousClose"]?.jsonPrimitive?.doubleOrNull ?: regularPrice
            val dayHigh = meta["regularMarketDayHigh"]?.jsonPrimitive?.doubleOrNull
            val dayLow = meta["regularMarketDayLow"]?.jsonPrimitive?.doubleOrNull
            val volume = meta["regularMarketVolume"]?.jsonPrimitive?.longOrNull
            val currency = meta["currency"]?.jsonPrimitive?.content ?: "USD"
            val companyName = meta["shortName"]?.jsonPrimitive?.content ?: symbol

            val change = regularPrice - previousClose
            val percentChange = if (previousClose != 0.0) (change / previousClose) * 100.0 else 0.0

            StockQuote(
                symbol = symbol,
                companyName = companyName,
                currentPrice = regularPrice,
                change = change,
                percentChange = percentChange,
                marketType = marketType,
                currency = currency,
                dayHigh = dayHigh,
                dayLow = dayLow,
                volume = volume
            )
        } catch (_: Exception) {
            null
        }
    }

    suspend fun pushLedger(rawText: String, userId: String? = null): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["smart_ledgers"].upsert(
                RemoteLedgerRecord(
                    id = "primary_ledger",
                    user_id = userId,
                    raw_text = rawText,
                    updated_at = System.currentTimeMillis()
                )
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun fetchLedger(): String? = withContext(Dispatchers.IO) {
        try {
            val record = clientManager.client.postgrest["smart_ledgers"]
                .select {
                    filter {
                        eq("id", "primary_ledger")
                    }
                }
                .decodeSingleOrNull<RemoteLedgerRecord>()
            record?.raw_text
        } catch (_: Exception) {
            null
        }
    }
}
