package com.intellidream.daily.model

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

class WpJsonParser(private val feed: FeedSource) {

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun parse(jsonString: String): List<NewsArticle> {
        val articles = mutableListOf<NewsArticle>()
        try {
            val element = json.parseToJsonElement(jsonString)
            if (element is JsonArray) {
                for (item in element) {
                    if (item is JsonObject) {
                        val article = parsePost(item)
                        if (article != null) {
                            articles.add(article)
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return articles
    }

    private fun parsePost(post: JsonObject): NewsArticle? {
        val link = post["link"]?.jsonPrimitive?.content ?: ""
        val titleObj = post["title"]?.jsonObject
        val rawTitle = titleObj?.get("rendered")?.jsonPrimitive?.content ?: "No Title"
        val title = FeedParser.decodeHtmlEntities(rawTitle)

        val dateStr = post["date"]?.jsonPrimitive?.content ?: ""
        val date = parseDate(dateStr)

        val contentObj = post["content"]?.jsonObject
        val content = contentObj?.get("rendered")?.jsonPrimitive?.content

        val excerptObj = post["excerpt"]?.jsonObject
        val excerpt = excerptObj?.get("rendered")?.jsonPrimitive?.content ?: ""

        var cleanDesc = FeedParser.stripHtmlTags(excerpt)
        if (cleanDesc.isEmpty() && !content.isNullOrEmpty()) {
            val contentClean = FeedParser.stripHtmlTags(content)
            cleanDesc = if (contentClean.length > 280) contentClean.take(280) + "..." else contentClean
        }

        var authorName: String? = null
        var imageUrl: String? = null

        val embedded = post["_embedded"]?.jsonObject
        if (embedded != null) {
            val authors = embedded["author"]?.jsonArray
            if (authors != null && authors.isNotEmpty()) {
                val firstAuthor = authors[0].jsonObject
                authorName = firstAuthor["name"]?.jsonPrimitive?.content
            }

            val mediaList = embedded["wp:featuredmedia"]?.jsonArray
            if (mediaList != null && mediaList.isNotEmpty()) {
                val firstMedia = mediaList[0].jsonObject
                imageUrl = firstMedia["source_url"]?.jsonPrimitive?.content
                val details = firstMedia["media_details"]?.jsonObject
                val sizes = details?.get("sizes")?.jsonObject
                val medium = sizes?.get("medium")?.jsonObject
                val mediumUrl = medium?.get("source_url")?.jsonPrimitive?.content
                if (!mediumUrl.isNullOrEmpty()) {
                    imageUrl = mediumUrl
                }
            }
        }

        return NewsArticle(
            id = if (link.isNotBlank()) link else UUID.randomUUID().toString(),
            title = title,
            link = link,
            publishDate = date,
            imageUrl = imageUrl ?: feed.iconUrl,
            description = cleanDesc,
            content = content,
            author = authorName,
            publicationName = feed.name,
            publicationIconUrl = feed.iconUrl,
            category = feed.category
        )
    }

    private fun parseDate(str: String): Long {
        if (str.isBlank()) return System.currentTimeMillis()

        val formats = listOf(
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXX"
        )
        for (fmt in formats) {
            try {
                val sdf = SimpleDateFormat(fmt, Locale.US)
                sdf.timeZone = TimeZone.getTimeZone("UTC")
                val d = sdf.parse(str)
                if (d != null) return d.time
            } catch (_: Exception) {}
        }

        try {
            return java.time.Instant.parse(str).toEpochMilli()
        } catch (_: Exception) {}

        return System.currentTimeMillis()
    }
}
