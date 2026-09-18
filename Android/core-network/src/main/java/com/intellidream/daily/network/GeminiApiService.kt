package com.intellidream.daily.network

import com.intellidream.daily.model.BriefingTimeSlot
import com.intellidream.daily.model.SmartBriefingMetrics
import com.intellidream.daily.model.SmartBriefingNarrative
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * High-speed client connecting to Google Gemini API (gemini-2.5-flash) for generative multi-hub briefing synthesis.
 * Features a strict 3.5s timeout guarantee and structured JSON response parsing.
 * Forensic parity with iOS DailyCore GeminiApiService.
 */
class GeminiApiService {
    companion object {
        val shared = GeminiApiService()
    }

    private val primaryModel = "gemini-2.5-flash"
    private val fallbackModel = "gemini-1.5-flash"

    private val httpClient = HttpClient(CIO) {
        install(HttpTimeout) {
            requestTimeoutMillis = 3500L
            connectTimeoutMillis = 3500L
            socketTimeoutMillis = 3500L
        }
    }

    suspend fun generateBriefing(
        apiKey: String,
        slot: BriefingTimeSlot,
        userName: String,
        metrics: SmartBriefingMetrics,
        streamTitles: List<String> = emptyList(),
        topPills: List<String> = emptyList(),
        closingWish: String? = null,
        closingIcon: String? = null
    ): SmartBriefingNarrative = withContext(Dispatchers.IO) {
        val trimmedKey = apiKey.trim()
        if (trimmedKey.isEmpty()) {
            throw IllegalArgumentException("Gemini API key is empty")
        }

        val systemInstruction = """
            You are DayOne, a refined, proactive, and deeply supportive personal intelligence companion.
            Your task is to craft a dense, inspiring, and actionable ${slot.displayName} for $userName.

            Guidelines:
            1. Address $userName directly in natural, warm, second-person language. All narrative text MUST be in English.
            2. Synthesize all 6 life areas based on the provided JSON telemetry: Weather, Health/Sleep, Habits, Finances, Tagdos, and News.
            3. Habit Coaching Directive: Treat smoking/heaters as a habit to consciously reduce. If smokes count is low or below baseline, warmly congratulate the discipline. Never encourage smoking. Encourage hydration and mindful breathing during cravings.
            4. Sleep & Health: Report sleep and recovery truthfully based on provided telemetry. If sleep data is present, evaluate sleep quality and physical readiness using the actual sleep duration (e.g. "7h 30m asleep"). If sleep data is not yet recorded for today, note that vitals are syncing or focus on current activity and resting heart rate without inventing numbers.
            5. Finances: All currency is Romanian Lei ("Lei"). State net worth and flows in Lei with dot separators (e.g. "127.156 Lei"). Never output dollar signs ($).
            6. Tagdos: Provide actionable focus on the driving pills to solve today (e.g. "Here's what needs your focus today: [key pills]"). Do not merely count streams.
            7. Tone: Calm, encouraging, succinct. Avoid conversational filler or mentioning prompt rules.
            8. Language: Output strictly in natural, refined English (except keeping 'Lei' as currency).
            9. Return strictly a single JSON object matching this schema:
            {
              "greeting": "A warm, personalized 1-line greeting with date context",
              "weatherText": "Concise atmosphere & outfit recommendation based on weather",
              "healthText": "Recovery analysis correlating sleep score, resting HR, and activity",
              "habitsText": "Empathetic hydration progress and supportive craving reduction advice",
              "financeText": "Summary of monthly flow, net worth in Lei, and financial clarity",
              "tagdosText": "Focus priority for active Tagdos pills (e.g. 'Here\\'s what needs your focus today: ...')",
              "newsText": "1-sentence perspective on the top headline, if present",
              "outroText": "1-line empowering closing sentence"
            }
        """.trimIndent()

        val promptPayload = JSONObject().apply {
            put("timeSlot", slot.value)
            put("userName", userName)
            put("weather", JSONObject().apply {
                put("temp", metrics.weatherTemp ?: 20.0)
                put("unit", "°C")
                put("condition", metrics.weatherCondition ?: "Clear")
                put("city", metrics.weatherCity ?: "Current Location")
            })
            put("health", JSONObject().apply {
                put("stepsToday", metrics.totalStepsToday)
                metrics.sleepScore?.let { put("sleepScore", it) }
                metrics.sleepDurationFormatted?.let { put("sleepFormatted", it) }
                    ?: metrics.sleepDurationHours?.let { put("sleepHours", String.format("%.1fh", it)) }
                metrics.restingBpm?.let { put("restingBpm", it) }
            })
            put("habits", JSONObject().apply {
                put("waterMlToday", metrics.waterMlToday)
                put("waterGoalMl", metrics.waterGoalMl)
                put("smokesToday", metrics.smokesToday)
                put("smokesBaseline", metrics.smokesBaseline)
            })
            put("finances", JSONObject().apply {
                put("currency", "Lei")
                put("netWorth", metrics.netWorth)
                put("daySpend", metrics.daySpend)
            })
            put("tagdos", JSONObject().apply {
                put("activeStreams", JSONArray(streamTitles))
                put("topPillsToTackle", JSONArray(topPills))
                put("activeMemosCount", metrics.activeMemoCount)
            })
            put("newsHeadline", metrics.topNewsTitle ?: "")
        }

        try {
            val result = executeGenerateContent(
                model = primaryModel,
                apiKey = trimmedKey,
                systemInstruction = systemInstruction,
                userPrompt = promptPayload.toString()
            )
            result.copy(closingWish = closingWish, closingIcon = closingIcon)
        } catch (e: Exception) {
            // Fallback to secondary model if primary encounters issues
            val fallbackResult = executeGenerateContent(
                model = fallbackModel,
                apiKey = trimmedKey,
                systemInstruction = systemInstruction,
                userPrompt = promptPayload.toString()
            )
            fallbackResult.copy(closingWish = closingWish, closingIcon = closingIcon)
        }
    }

    private suspend fun executeGenerateContent(
        model: String,
        apiKey: String,
        systemInstruction: String,
        userPrompt: String
    ): SmartBriefingNarrative {
        val url = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey"

        val requestBody = JSONObject().apply {
            put("contents", JSONArray().apply {
                put(JSONObject().apply {
                    put("role", "user")
                    put("parts", JSONArray().apply {
                        put(JSONObject().apply { put("text", userPrompt) })
                    })
                })
            })
            put("systemInstruction", JSONObject().apply {
                put("parts", JSONArray().apply {
                    put(JSONObject().apply { put("text", systemInstruction) })
                })
            })
            put("generationConfig", JSONObject().apply {
                put("responseMimeType", "application/json")
                put("temperature", 0.35)
                put("maxOutputTokens", 1024)
            })
        }

        val response = httpClient.post(url) {
            contentType(ContentType.Application.Json)
            setBody(requestBody.toString())
        }

        if (!response.status.isSuccess()) {
            throw RuntimeException("Gemini HTTP ${response.status.value}: ${response.bodyAsText()}")
        }

        val responseText = response.bodyAsText()
        val json = JSONObject(responseText)
        val candidates = json.optJSONArray("candidates")
        val content = candidates?.optJSONObject(0)?.optJSONObject("content")
        val parts = content?.optJSONArray("parts")
        val rawJsonText = parts?.optJSONObject(0)?.optString("text")

        if (rawJsonText.isNullOrBlank()) {
            throw RuntimeException("Empty text candidate in Gemini response")
        }

        val parsed = JSONObject(rawJsonText)
        return SmartBriefingNarrative(
            greeting = parsed.optString("greeting", ""),
            weatherText = parsed.optString("weatherText", ""),
            healthText = parsed.optString("healthText", ""),
            habitsText = parsed.optString("habitsText", ""),
            financeText = parsed.optString("financeText", ""),
            tagdosText = parsed.optString("tagdosText", ""),
            newsText = parsed.optString("newsText", ""),
            outroText = parsed.optString("outroText", "")
        )
    }
}
