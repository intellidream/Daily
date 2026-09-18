package com.intellidream.daily.model

import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import java.io.StringReader
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.regex.Pattern

class FeedParser(private val feed: FeedSource) {

    fun parse(xmlString: String): List<NewsArticle> {
        val articles = mutableListOf<NewsArticle>()
        val sanitized = sanitizeXml(xmlString)

        try {
            val factory = XmlPullParserFactory.newInstance().apply {
                isNamespaceAware = true
            }
            val parser = factory.newPullParser()
            parser.setInput(StringReader(sanitized))

            var eventType = parser.eventType
            var isInsideItem = false
            var isInsideChannelImage = false

            var currentTitle = ""
            var currentLink = ""
            var currentDescription = ""
            var currentContentEncoded = ""
            var currentAuthor = ""
            var currentPubDateStr = ""
            var currentImageUrl: String? = null
            var channelImageUrl: String? = null

            var currentTag = ""

            while (eventType != XmlPullParser.END_DOCUMENT) {
                when (eventType) {
                    XmlPullParser.START_TAG -> {
                        val name = parser.name.lowercase(Locale.ROOT)
                        currentTag = name

                        if (name == "item" || name == "entry") {
                            isInsideItem = true
                            currentTitle = ""
                            currentLink = ""
                            currentDescription = ""
                            currentContentEncoded = ""
                            currentAuthor = ""
                            currentPubDateStr = ""
                            currentImageUrl = null
                        } else if (!isInsideItem) {
                            if (name == "image" || name == "logo" || name == "icon") {
                                isInsideChannelImage = true
                            }
                        } else {
                            // Atom link: <link href="..." rel="alternate"/>
                            if (name == "link") {
                                val href = parser.getAttributeValue(null, "href")
                                val rel = parser.getAttributeValue(null, "rel")?.lowercase(Locale.ROOT)
                                val type = parser.getAttributeValue(null, "type")?.lowercase(Locale.ROOT)

                                if (rel == "enclosure" && type?.startsWith("image/") == true && href != null) {
                                    currentImageUrl = href
                                } else if (href != null && (rel == "alternate" || rel == null || currentLink.isEmpty())) {
                                    currentLink = href
                                }
                            }

                            // Media content or thumbnail: <media:content url="...">
                            if (name == "content" || name == "thumbnail") {
                                val url = parser.getAttributeValue(null, "url")
                                if (url != null && isLikelyImage(url) && currentImageUrl == null) {
                                    currentImageUrl = url
                                }
                            }

                            // RSS enclosure: <enclosure url="..." type="image/..."/>
                            if (name == "enclosure") {
                                val url = parser.getAttributeValue(null, "url")
                                val type = parser.getAttributeValue(null, "type")?.lowercase(Locale.ROOT) ?: ""
                                if (url != null && (type.isEmpty() || type.startsWith("image/") || isLikelyImage(url))) {
                                    if (currentImageUrl == null) {
                                        currentImageUrl = url
                                    }
                                }
                            }
                        }
                    }

                    XmlPullParser.TEXT -> {
                        val text = parser.text ?: ""
                        if (isInsideChannelImage && channelImageUrl == null && currentTag == "url") {
                            channelImageUrl = (channelImageUrl ?: "") + text
                        } else if (isInsideItem) {
                            when (currentTag) {
                                "title" -> currentTitle += text
                                "link" -> if (currentLink.isEmpty()) currentLink += text.trim()
                                "description", "summary" -> currentDescription += text
                                "encoded", "content" -> currentContentEncoded += text
                                "pubdate", "published", "updated", "date" -> currentPubDateStr += text
                                "creator", "author", "name" -> currentAuthor += text
                            }
                        }
                    }

                    XmlPullParser.END_TAG -> {
                        val name = parser.name.lowercase(Locale.ROOT)
                        if (name == "image" || name == "logo" || name == "icon") {
                            isInsideChannelImage = false
                        } else if (name == "item" || name == "entry") {
                            isInsideItem = false

                            val title = decodeHtmlEntities(currentTitle.trim())
                            val link = currentLink.trim()
                            val date = parseDate(currentPubDateStr.trim())

                            // Extract image from description or content if missing
                            if (currentImageUrl == null) {
                                currentImageUrl = extractFirstImage(currentContentEncoded)
                                    ?: extractFirstImage(currentDescription)
                            }

                            val finalImageUrl = optimizeMediumImageUrl(
                                currentImageUrl ?: channelImageUrl ?: feed.iconUrl
                            )

                            // Clean description snippet
                            var cleanDesc = stripHtmlTags(currentDescription)
                            if (cleanDesc.isEmpty() && currentContentEncoded.isNotEmpty()) {
                                val contentClean = stripHtmlTags(currentContentEncoded)
                                cleanDesc = if (contentClean.length > 280) {
                                    contentClean.take(280) + "..."
                                } else {
                                    contentClean
                                }
                            }

                            // Author in Publication splitting (WinUI / iOS parity)
                            var authorName = currentAuthor.trim()
                            var pubName = feed.name
                            if (authorName.contains(" in ")) {
                                val parts = authorName.split(" in ", limit = 2)
                                authorName = parts[0].trim()
                                pubName = parts[1].trim()
                            }

                            articles.add(
                                NewsArticle(
                                    id = if (link.isNotBlank()) link else UUID.randomUUID().toString(),
                                    title = if (title.isNotBlank()) title else "No Title",
                                    link = link,
                                    publishDate = date,
                                    imageUrl = finalImageUrl,
                                    description = cleanDesc,
                                    content = if (currentContentEncoded.isNotEmpty()) currentContentEncoded else currentDescription,
                                    author = authorName.ifBlank { null },
                                    publicationName = pubName,
                                    publicationIconUrl = feed.iconUrl,
                                    category = feed.category
                                )
                            )
                        }
                        currentTag = ""
                    }
                }
                eventType = parser.next()
            }
        } catch (_: Exception) {
            // Fallback to regex parser on malformed XML
        }

        if (articles.isEmpty()) {
            return parseUsingRegex(xmlString)
        }

        return articles
    }

    private fun parseUsingRegex(xmlString: String): List<NewsArticle> {
        val results = mutableListOf<NewsArticle>()
        val itemPattern = Pattern.compile("<(?:item|entry)[^>]*>([\\s\\S]*?)</(?:item|entry)>", Pattern.CASE_INSENSITIVE)
        val matcher = itemPattern.matcher(xmlString)

        while (matcher.find()) {
            val itemContent = matcher.group(1) ?: continue

            val title = extractTagValue("title", itemContent)
            var link = extractTagValue("link", itemContent)
            if (link.isEmpty()) {
                link = extractAttribute("href", "link", itemContent)
            }
            val desc = extractTagValue("description", itemContent)
            val contentEncoded = extractTagValue("content:encoded", itemContent).ifEmpty {
                extractTagValue("content", itemContent)
            }
            val pubDate = extractTagValue("pubDate", itemContent).ifEmpty {
                extractTagValue("published", itemContent)
            }
            val author = extractTagValue("dc:creator", itemContent).ifEmpty {
                val authorBlock = extractTagValue("author", itemContent)
                val innerName = extractTagValue("name", authorBlock)
                if (innerName.isNotEmpty()) innerName else stripHtmlTags(authorBlock)
            }

            var imageUrl = extractAttribute("url", "media:content", itemContent)
            if (imageUrl.isEmpty()) {
                imageUrl = extractAttribute("url", "enclosure", itemContent)
            }
            if (imageUrl.isEmpty()) {
                imageUrl = extractFirstImage(contentEncoded) ?: extractFirstImage(desc) ?: ""
            }

            var cleanDesc = stripHtmlTags(desc)
            if (cleanDesc.isEmpty() && contentEncoded.isNotEmpty()) {
                val contentClean = stripHtmlTags(contentEncoded)
                cleanDesc = if (contentClean.length > 280) contentClean.take(280) + "..." else contentClean
            }

            results.add(
                NewsArticle(
                    id = if (link.isNotBlank()) link else UUID.randomUUID().toString(),
                    title = decodeHtmlEntities(title),
                    link = link,
                    publishDate = parseDate(pubDate),
                    imageUrl = optimizeMediumImageUrl(if (imageUrl.isNotBlank()) imageUrl else feed.iconUrl),
                    description = cleanDesc,
                    content = if (contentEncoded.isNotEmpty()) contentEncoded else desc,
                    author = author.ifBlank { null },
                    publicationName = feed.name,
                    publicationIconUrl = feed.iconUrl,
                    category = feed.category
                )
            )
        }

        return results
    }

    private fun sanitizeXml(xml: String): String {
        return xml.replace(Regex("&(?!(?:amp|lt|gt|quot|apos|#\\d+|#[xX][a-fA-F0-9]+);)"), "&amp;")
    }

    private fun isLikelyImage(url: String): Boolean {
        val lower = url.lowercase(Locale.ROOT)
        return lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") ||
                lower.contains(".webp") || lower.contains(".gif") || lower.contains("image") || lower.contains("miro.medium.com")
    }

    private fun extractFirstImage(html: String): String? {
        val pattern = Pattern.compile("<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']", Pattern.CASE_INSENSITIVE)
        val matcher = pattern.matcher(html)
        return if (matcher.find()) matcher.group(1) else null
    }

    private fun extractTagValue(tag: String, xml: String): String {
        val pattern = Pattern.compile("<$tag[^>]*>(?:<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>|([\\s\\S]*?))</$tag>", Pattern.CASE_INSENSITIVE)
        val matcher = pattern.matcher(xml)
        if (matcher.find()) {
            val cdata = matcher.group(1)
            if (cdata != null) return cdata.trim()
            val text = matcher.group(2)
            if (text != null) return text.trim()
        }
        return ""
    }

    private fun extractAttribute(attribute: String, tag: String, xml: String): String {
        val pattern = Pattern.compile("<$tag[^>]*$attribute\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>", Pattern.CASE_INSENSITIVE)
        val matcher = pattern.matcher(xml)
        return if (matcher.find()) matcher.group(1)?.trim() ?: "" else ""
    }

    private fun parseDate(str: String): Long {
        if (str.isBlank()) return System.currentTimeMillis()

        val formats = listOf(
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd HH:mm:ss",
            "EEE, dd MMM yyyy HH:mm zzz"
        )

        for (fmt in formats) {
            try {
                val sdf = SimpleDateFormat(fmt, Locale.US)
                sdf.timeZone = TimeZone.getTimeZone("UTC")
                val date = sdf.parse(str)
                if (date != null) return date.time
            } catch (_: Exception) {}
        }

        try {
            return java.time.Instant.parse(str).toEpochMilli()
        } catch (_: Exception) {}

        return System.currentTimeMillis()
    }

    companion object {
        fun stripHtmlTags(str: String): String {
            var clean = str
                .replace(Regex("</p>", RegexOption.IGNORE_CASE), " ")
                .replace(Regex("<br\\s*/?>", RegexOption.IGNORE_CASE), " ")
                .replace(Regex("<[^>]+>"), "")
            clean = decodeHtmlEntities(clean)
            clean = clean.replace(Regex("\\s+"), " ")
            return clean.trim()
        }

        fun decodeHtmlEntities(str: String): String {
            var decoded = str
            val entities = listOf(
                "&quot;" to "\"",
                "&apos;" to "'",
                "&amp;" to "&",
                "&lt;" to "<",
                "&gt;" to ">",
                "&nbsp;" to " ",
                "&#8216;" to "'",
                "&#8217;" to "'",
                "&#8220;" to "\"",
                "&#8221;" to "\"",
                "&#8211;" to "–",
                "&#8212;" to "—",
                "&hellip;" to "…"
            )
            for ((ent, repl) in entities) {
                decoded = decoded.replace(ent, repl)
            }

            // Decimal numeric entities: &#539;
            decoded = Regex("&#(\\d+);").replace(decoded) { match ->
                val code = match.groupValues[1].toIntOrNull()
                if (code != null) {
                    try {
                        String(Character.toChars(code))
                    } catch (_: Exception) {
                        match.value
                    }
                } else match.value
            }

            // Hex numeric entities: &#x21b;
            decoded = Regex("&#[xX]([0-9a-fA-F]+);").replace(decoded) { match ->
                val code = match.groupValues[1].toIntOrNull(16)
                if (code != null) {
                    try {
                        String(Character.toChars(code))
                    } catch (_: Exception) {
                        match.value
                    }
                } else match.value
            }

            return decoded
        }

        fun optimizeMediumImageUrl(url: String): String {
            if (!url.contains("miro.medium.com")) return url
            return url.replace(Regex("v2/resize:[^/]+(/format:[^/]+)?"), "v2/resize:fit:800")
        }
    }
}
