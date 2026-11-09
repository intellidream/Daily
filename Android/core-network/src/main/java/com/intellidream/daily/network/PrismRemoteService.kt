package com.intellidream.daily.network

import com.intellidream.daily.model.PrismClip
import com.intellidream.daily.model.PrismCoPilotAction
import com.intellidream.daily.model.PrismCoPilotTurn
import com.intellidream.daily.model.PrismPinnedSite
import com.intellidream.daily.model.PrismSearchEngine
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsBytes
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

class PrismRemoteService(
    private val clientManager: SupabaseClientManager = SupabaseClientManager
) {
    private val httpClient by lazy {
        HttpClient(CIO) {
            install(HttpTimeout) {
                requestTimeoutMillis = 14000L
                connectTimeoutMillis = 10000L
                socketTimeoutMillis = 14000L
            }
        }
    }

    private val primaryModel = "gemini-2.5-flash"
    private val fallbackModel = "gemini-1.5-flash"
    private val bucketName = "prism-clips"

    // MARK: - Lean PostgREST Sync (`updated_at` Watermark + Minimal Representation)

    suspend fun fetchClipsDelta(userId: String, watermarkIso: String?): List<PrismClip> = withContext(Dispatchers.IO) {
        try {
            val table = clientManager.client.postgrest["prism_clips"]
            table.select {
                filter {
                    eq("user_id", userId)
                    if (!watermarkIso.isNullOrBlank()) {
                        gt("updated_at", watermarkIso)
                    } else {
                        eq("is_deleted", false)
                    }
                }
                order("updated_at", Order.DESCENDING)
                limit(200)
            }.decodeList<PrismClip>()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun upsertClip(clip: PrismClip): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["prism_clips"].upsert(clip) {
                onConflict = "id"
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun fetchPinnedSitesDelta(userId: String, watermarkIso: String?): List<PrismPinnedSite> = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["prism_pinned_sites"].select {
                filter {
                    eq("user_id", userId)
                    if (!watermarkIso.isNullOrBlank()) {
                        gt("updated_at", watermarkIso)
                    } else {
                        eq("is_deleted", false)
                    }
                }
                order("display_order", Order.ASCENDING)
            }.decodeList<PrismPinnedSite>()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun upsertPinnedSite(pin: PrismPinnedSite): Boolean = withContext(Dispatchers.IO) {
        try {
            clientManager.client.postgrest["prism_pinned_sites"].upsert(pin) {
                onConflict = "id"
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    // MARK: - Supabase Storage `prism-clips` REST Operations (Zero Extra SDK Bloat)

    suspend fun uploadClipImage(
        userId: String,
        clipId: String,
        jpegBytes: ByteArray
    ): String? = withContext(Dispatchers.IO) {
        try {
            val token = clientManager.client.auth.currentAccessTokenOrNull() ?: return@withContext null
            val remotePath = "${userId.lowercase()}/${clipId.lowercase()}.jpg"
            val url = "${SupabaseClientManager.SUPABASE_URL}/storage/v1/object/$bucketName/$remotePath"
            val resp = httpClient.post(url) {
                header("Authorization", "Bearer $token")
                header("apikey", SupabaseClientManager.SUPABASE_ANON_KEY)
                header("x-upsert", "true")
                contentType(ContentType.Image.JPEG)
                setBody(jpegBytes)
            }
            if (resp.status.isSuccess()) remotePath else null
        } catch (_: Exception) {
            null
        }
    }

    suspend fun downloadClipImage(storagePath: String?, fallbackUrl: String?): ByteArray? = withContext(Dispatchers.IO) {
        try {
            if (!storagePath.isNullOrBlank()) {
                val token = clientManager.client.auth.currentAccessTokenOrNull()
                if (!token.isNullOrBlank()) {
                    val url = "${SupabaseClientManager.SUPABASE_URL}/storage/v1/object/authenticated/$bucketName/$storagePath"
                    val resp = httpClient.get(url) {
                        header("Authorization", "Bearer $token")
                        header("apikey", SupabaseClientManager.SUPABASE_ANON_KEY)
                    }
                    if (resp.status.isSuccess()) {
                        return@withContext resp.bodyAsBytes()
                    }
                }
            }
            if (!fallbackUrl.isNullOrBlank()) {
                val resp = httpClient.get(fallbackUrl)
                if (resp.status.isSuccess()) {
                    return@withContext resp.bodyAsBytes()
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    suspend fun deleteRemoteClipImage(storagePath: String?) = withContext(Dispatchers.IO) {
        if (storagePath.isNullOrBlank()) return@withContext
        try {
            val token = clientManager.client.auth.currentAccessTokenOrNull() ?: return@withContext
            val url = "${SupabaseClientManager.SUPABASE_URL}/storage/v1/object/$bucketName/$storagePath"
            httpClient.delete(url) {
                header("Authorization", "Bearer $token")
                header("apikey", SupabaseClientManager.SUPABASE_ANON_KEY)
            }
        } catch (_: Exception) {}
    }

    // MARK: - Prism Co-Pilot (Gemini 2.5 Flash + Deterministic Offline Fallback)

    suspend fun runCoPilotAction(
        action: PrismCoPilotAction,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String = "",
        apiKey: String?
    ): PrismCoPilotTurn {
        val displayPrompt = when (action) {
            PrismCoPilotAction.Tldr -> "✨ TL;DR Summary"
            PrismCoPilotAction.ExtractTasks -> "🎯 Extract Actionable Tasks"
            PrismCoPilotAction.KeyFacts -> "📊 Key Facts & Numbers"
            PrismCoPilotAction.ExplainSelection -> if (selectedText.isBlank()) "🔍 Explain Key Concepts" else "🔍 Explain: \"${selectedText.take(70)}\""
        }
        val instruction = when (action) {
            PrismCoPilotAction.Tldr -> "Provide a crisp executive summary of this web page in 2-3 sentences, followed by up to 5 high-signal bullet takeaways."
            PrismCoPilotAction.ExtractTasks -> "Identify concrete actionable next steps or checklists from this page. Return concise bullets AND short 3-6 word task items."
            PrismCoPilotAction.KeyFacts -> "Extract the most important quantitative metrics, prices, dates, benchmarks, or factual claims from this page."
            PrismCoPilotAction.ExplainSelection -> if (selectedText.isNotBlank()) "Explain this selected passage clearly in context: \"$selectedText\"" else "Explain the core ideas on this page clearly."
        }
        return executeTurn(displayPrompt, instruction, pageTitle, pageUrl, bodyText, selectedText, apiKey)
    }

    suspend fun askCoPilotQuestion(
        question: String,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String = "",
        apiKey: String?
    ): PrismCoPilotTurn {
        val clean = question.trim()
        if (clean.isEmpty()) return buildDeterministicTurn("Overview", pageTitle, pageUrl, bodyText, selectedText)
        return executeTurn(
            displayPrompt = clean,
            instruction = "Answer the user's question accurately grounded in the provided web page content. Question: $clean",
            pageTitle = pageTitle,
            pageUrl = pageUrl,
            bodyText = bodyText,
            selectedText = selectedText,
            apiKey = apiKey
        )
    }

    private suspend fun executeTurn(
        displayPrompt: String,
        instruction: String,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String,
        apiKey: String?
    ): PrismCoPilotTurn = withContext(Dispatchers.IO) {
        val key = apiKey?.trim().orEmpty()
        if (key.isNotEmpty()) {
            requestGemini(primaryModel, key, displayPrompt, instruction, pageTitle, pageUrl, bodyText, selectedText)?.let { return@withContext it }
            requestGemini(fallbackModel, key, displayPrompt, instruction, pageTitle, pageUrl, bodyText, selectedText)?.let { return@withContext it }
        }
        buildDeterministicTurn(displayPrompt, pageTitle, pageUrl, bodyText, selectedText)
    }

    private suspend fun requestGemini(
        model: String,
        apiKey: String,
        displayPrompt: String,
        instruction: String,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String
    ): PrismCoPilotTurn? {
        return try {
            val endpoint = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey"
            val sys = """
                You are Prism Co-Pilot inside DayOne. Respond in the language of the user's question or page naturally.
                Return strictly a valid JSON object:
                {"summary":"2-4 sentence synthesis","bullets":["up to 5 bullets"],"tasks":["0-4 short actionable tasks"]}
            """.trimIndent()
            val userCtx = """
                Task: $instruction
                Page Title: $pageTitle
                URL: $pageUrl
                Selected Text: ${selectedText.ifBlank { "(none)" }.take(2500)}
                Page Content:
                ${bodyText.take(15000)}
            """.trimIndent()

            val payload = JSONObject().apply {
                put("system_instruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", sys))))
                put("contents", JSONArray().put(JSONObject().put("role", "user").put("parts", JSONArray().put(JSONObject().put("text", userCtx)))))
                put("generationConfig", JSONObject().put("temperature", 0.3).put("responseMimeType", "application/json"))
            }

            val resp = httpClient.post(endpoint) {
                contentType(ContentType.Application.Json)
                setBody(payload.toString())
            }
            if (!resp.status.isSuccess()) return null
            val env = JSONObject(resp.bodyAsText())
            var text = env.optJSONArray("candidates")
                ?.optJSONObject(0)
                ?.optJSONObject("content")
                ?.optJSONArray("parts")
                ?.optJSONObject(0)
                ?.optString("text", "")
                ?.trim()
                .orEmpty()
            if (text.isEmpty()) return null
            if (text.startsWith("```")) {
                text = text.removePrefix("```json").removePrefix("```").removeSuffix("```").trim()
            }
            val parsed = JSONObject(text)
            val bulletsArr = parsed.optJSONArray("bullets")
            val bullets = buildList {
                if (bulletsArr != null) {
                    for (i in 0 until bulletsArr.length()) add(bulletsArr.optString(i))
                }
            }.filter { it.isNotBlank() }

            val tasksArr = parsed.optJSONArray("tasks")
            val tasks = buildList {
                if (tasksArr != null) {
                    for (i in 0 until tasksArr.length()) add(tasksArr.optString(i))
                }
            }.filter { it.isNotBlank() }

            PrismCoPilotTurn(
                prompt = displayPrompt,
                responseMarkdown = parsed.optString("summary", ""),
                keyBullets = bullets,
                extractedTasks = tasks,
                sourceUrl = pageUrl,
                pageTitle = pageTitle,
                isAiGenerated = true
            )
        } catch (_: Exception) {
            null
        }
    }

    fun buildDeterministicTurn(
        displayPrompt: String,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String
    ): PrismCoPilotTurn {
        val src = if (selectedText.isNotBlank()) selectedText else bodyText
        val paras = src.lines().map { it.trim() }.filter { it.length >= 45 }
        val summary = paras.firstOrNull()?.take(320)
            ?: selectedText.ifBlank { "Captured context from ${pageTitle.ifBlank { PrismSearchEngine.extractCleanDomain(pageUrl) }}." }
        val bullets = paras.drop(1)
            .sortedByDescending { p -> (if (p.any { it.isDigit() }) 1000 else 0) + p.length }
            .take(4)
            .map { it.take(180) }
        val task = "Review ${(pageTitle.ifBlank { PrismSearchEngine.extractCleanDomain(pageUrl) }).take(34)}"
        return PrismCoPilotTurn(
            prompt = displayPrompt,
            responseMarkdown = summary,
            keyBullets = bullets,
            extractedTasks = listOf(task),
            sourceUrl = pageUrl,
            pageTitle = pageTitle,
            isAiGenerated = false
        )
    }
}
