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
    private var lastParsedArticleDate: Long? = null

    fun parse(xmlString: String): List<NewsArticle> {
        val articles = mutableListOf<NewsArticle>()
        lastParsedArticleDate = null
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
            var currentPublishedStr = ""
            var currentDcDateStr = ""
            var currentUpdatedStr = ""
            var currentSourceName = ""
            var currentSourceUrl = ""
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
                            currentPublishedStr = ""
                            currentDcDateStr = ""
                            currentUpdatedStr = ""
                            currentSourceName = ""
                            currentSourceUrl = ""
                            currentImageUrl = null
                        } else if (!isInsideItem) {
                            if (name == "image" || name == "logo" || name == "icon") {
                                isInsideChannelImage = true
                            }
                        } else {
                            if (name == "pubdate") {
                                currentPubDateStr = ""
                            } else if (name == "published") {
                                currentPublishedStr = ""
                            } else if (name == "date" || name == "dc:date") {
                                currentDcDateStr = ""
                            } else if (name == "updated" || name == "atom:updated") {
                                currentUpdatedStr = ""
                            } else if (name == "source") {
                                currentSourceName = ""
                                currentSourceUrl = parser.getAttributeValue(null, "url") ?: ""
                            }
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
                                "pubdate" -> currentPubDateStr += text
                                "published" -> currentPublishedStr += text
                                "date" -> currentDcDateStr += text
                                "updated" -> currentUpdatedStr += text
                                "creator", "author", "name" -> currentAuthor += text
                                "source" -> currentSourceName += text
                            }
                        }
                    }

                    XmlPullParser.END_TAG -> {
                        val name = parser.name.lowercase(Locale.ROOT)
                        if (name == "image" || name == "logo" || name == "icon") {
                            isInsideChannelImage = false
                        } else if (name == "item" || name == "entry") {
                            isInsideItem = false

                            var title = decodeHtmlEntities(currentTitle.trim())
                            val link = currentLink.trim()
                            val isGoogleNews = feed.url.contains("news.google.com", ignoreCase = true) ||
                                link.contains("news.google.com", ignoreCase = true)
                            
                            // Priority resolution:
                            // 1. pubDate (RSS 2.0 original publication date)
                            // 2. published (Atom 1.0 original publication date)
                            // 3. dc:date (Dublin Core / RDF publication date)
                            // 4. atom:updated / updated (Revision date fallback)
                            val rawPubDate = currentPubDateStr.trim()
                            val rawPublished = currentPublishedStr.trim()
                            val rawDcDate = currentDcDateStr.trim()
                            val rawUpdated = currentUpdatedStr.trim()

                            val parsedDate = parseDateOrNull(rawPubDate)
                                ?: parseDateOrNull(rawPublished)
                                ?: parseDateOrNull(rawDcDate)
                                ?: parseDateOrNull(rawUpdated)

                            val date = if (parsedDate != null) {
                                lastParsedArticleDate = parsedDate
                                parsedDate
                            } else if (lastParsedArticleDate != null) {
                                lastParsedArticleDate!! - 60000L
                            } else {
                                System.currentTimeMillis()
                            }

                            // Extract image from description or content if missing
                            if (currentImageUrl == null) {
                                currentImageUrl = extractFirstImage(currentContentEncoded)
                                    ?: extractFirstImage(currentDescription)
                            }

                            // Format Author, Publication & Google News pre-clustered siblings
                            var authorName = currentAuthor.trim()
                            var pubName = feed.name
                            var pubIconUrl = feed.iconUrl
                            var unpackedSiblings: List<ClusterSibling>? = null

                            if (isGoogleNews) {
                                val srcName = decodeHtmlEntities(currentSourceName.trim())
                                if (srcName.isNotEmpty()) {
                                    pubName = srcName
                                    val suffix = " - $srcName"
                                    if (title.endsWith(suffix)) {
                                        title = title.dropLast(suffix.length).trim()
                                    }
                                }
                                if (currentSourceUrl.isNotBlank()) {
                                    val srcHost = try { java.net.URI(currentSourceUrl).host ?: "" } catch (_: Exception) { "" }
                                    if (srcHost.isNotBlank()) {
                                        pubIconUrl = "https://www.google.com/s2/favicons?domain=$srcHost&sz=64"
                                    }
                                }
                                val siblings = extractGoogleNewsSiblings(currentDescription, date)
                                if (siblings.isNotEmpty()) {
                                    unpackedSiblings = siblings
                                }
                            } else if (authorName.contains(" in ")) {
                                val parts = authorName.split(" in ", limit = 2)
                                authorName = parts[0].trim()
                                pubName = parts[1].trim()
                            }

                            val finalImageUrl = optimizeSubstackImageUrl(
                                optimizeMediumImageUrl(currentImageUrl ?: channelImageUrl ?: pubIconUrl)
                            )

                            // Clean description snippet
                            var cleanDesc = if (isGoogleNews && (unpackedSiblings?.size ?: 0) >= 2) {
                                val otherPubs = unpackedSiblings!!
                                    .map { it.publicationName }
                                    .filter { it.isNotBlank() && it != pubName }
                                    .distinct()
                                    .sorted()
                                if (otherPubs.isNotEmpty()) {
                                    "Also covered by ${otherPubs.take(4).joinToString(", ")}"
                                } else {
                                    stripHtmlTags(currentDescription)
                                }
                            } else {
                                stripHtmlTags(currentDescription)
                            }
                            if (cleanDesc.isEmpty() && currentContentEncoded.isNotEmpty()) {
                                val contentClean = stripHtmlTags(currentContentEncoded)
                                cleanDesc = if (contentClean.length > 280) {
                                    contentClean.take(280) + "..."
                                } else {
                                    contentClean
                                }
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
                                    publicationIconUrl = pubIconUrl,
                                    category = feed.category,
                                    googleNewsSiblings = unpackedSiblings
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
            var rawDate = extractTagValue("pubDate", itemContent)
            if (rawDate.isEmpty()) {
                rawDate = extractTagValue("published", itemContent)
            }
            if (rawDate.isEmpty()) {
                rawDate = extractTagValue("dc:date", itemContent)
            }
            if (rawDate.isEmpty()) {
                rawDate = extractTagValue("atom:updated", itemContent)
            }
            if (rawDate.isEmpty()) {
                rawDate = extractTagValue("updated", itemContent)
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

            val parsedDate = parseDateOrNull(rawDate)
            val date = if (parsedDate != null) {
                lastParsedArticleDate = parsedDate
                parsedDate
            } else if (lastParsedArticleDate != null) {
                lastParsedArticleDate!! - 60000L
            } else {
                System.currentTimeMillis()
            }

            var cleanTitle = decodeHtmlEntities(title)
            val isGoogleNews = feed.url.contains("news.google.com", ignoreCase = true) ||
                link.contains("news.google.com", ignoreCase = true)
            var pubName = feed.name
            var pubIconUrl = feed.iconUrl
            var unpackedSiblings: List<ClusterSibling>? = null

            if (isGoogleNews) {
                val srcName = decodeHtmlEntities(extractTagValue("source", itemContent))
                val srcUrl = extractAttribute("url", "source", itemContent)
                if (srcName.isNotBlank()) {
                    pubName = srcName
                    val suffix = " - $srcName"
                    if (cleanTitle.endsWith(suffix)) {
                        cleanTitle = cleanTitle.dropLast(suffix.length).trim()
                    }
                }
                if (srcUrl.isNotBlank()) {
                    val srcHost = try { java.net.URI(srcUrl).host ?: "" } catch (_: Exception) { "" }
                    if (srcHost.isNotBlank()) {
                        pubIconUrl = "https://www.google.com/s2/favicons?domain=$srcHost&sz=64"
                    }
                }
                val siblings = extractGoogleNewsSiblings(desc, date)
                if (siblings.isNotEmpty()) {
                    unpackedSiblings = siblings
                }
            }

            results.add(
                NewsArticle(
                    id = if (link.isNotBlank()) link else UUID.randomUUID().toString(),
                    title = cleanTitle,
                    link = link,
                    publishDate = date,
                    imageUrl = optimizeMediumImageUrl(if (imageUrl.isNotBlank()) imageUrl else pubIconUrl),
                    description = cleanDesc,
                    content = if (contentEncoded.isNotEmpty()) contentEncoded else desc,
                    author = author.ifBlank { null },
                    publicationName = pubName,
                    publicationIconUrl = pubIconUrl,
                    category = feed.category,
                    googleNewsSiblings = unpackedSiblings
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

    private fun parseDateOrNull(str: String): Long? {
        if (str.isBlank()) return null
        val cleanStr = str.trim().replace(Regex("\\s+"), " ")

        val formats = listOf(
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
            "yyyy-MM-dd HH:mm:ss",
            "EEE, dd MMM yyyy HH:mm zzz",
            "EEE, dd MMM yyyy HH:mm Z",
            "yyyy-MM-dd"
        )

        for (fmt in formats) {
            try {
                val sdf = SimpleDateFormat(fmt, Locale.US)
                sdf.timeZone = TimeZone.getTimeZone("UTC")
                val date = sdf.parse(cleanStr)
                if (date != null) return date.time
            } catch (_: Exception) {}
        }

        try {
            return java.time.Instant.parse(cleanStr).toEpochMilli()
        } catch (_: Exception) {}

        return null
    }

    private fun parseDate(str: String): Long {
        return parseDateOrNull(str) ?: System.currentTimeMillis()
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

        fun extractGoogleNewsSiblings(rawHtml: String, publishDateMillis: Long? = null): List<ClusterSibling> {
            if (!rawHtml.contains("<li", ignoreCase = true) && !rawHtml.contains("&lt;li", ignoreCase = true)) {
                return emptyList()
            }
            val html = if (rawHtml.contains("&lt;")) {
                rawHtml
                    .replace("&lt;", "<")
                    .replace("&gt;", ">")
                    .replace("&quot;", "\"")
                    .replace("&amp;", "&")
                    .replace("&nbsp;", " ")
            } else {
                rawHtml
            }

            val liMatcher = Pattern.compile("<li[^>]*>([\\s\\S]*?)</li>", Pattern.CASE_INSENSITIVE).matcher(html)
            val linkPattern = Pattern.compile("<a[^>]+href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE)
            val fontPattern = Pattern.compile("<font[^>]*>([\\s\\S]*?)</font>", Pattern.CASE_INSENSITIVE)

            val blocks = ArrayList<String>()
            while (liMatcher.find()) {
                liMatcher.group(1)?.let { blocks.add(it) }
            }
            if (blocks.size < 2) return emptyList()

            val siblings = ArrayList<ClusterSibling>()
            val seenLinks = HashSet<String>()

            for (block in blocks) {
                val aMatch = linkPattern.matcher(block)
                if (!aMatch.find()) continue
                val href = (aMatch.group(1) ?: "").trim()
                val rawTitle = (aMatch.group(2) ?: "")
                    .replace(Regex("<[^>]+>"), "")
                    .replace("&nbsp;", " ")
                    .replace("&quot;", "\"")
                    .replace("&apos;", "'")
                    .replace("&#39;", "'")
                    .replace("&amp;", "&")
                    .trim()

                if (href.isEmpty() || rawTitle.isEmpty() || !seenLinks.add(href)) continue

                val fMatch = fontPattern.matcher(block)
                val publisher = if (fMatch.find()) {
                    (fMatch.group(1) ?: "")
                        .replace(Regex("<[^>]+>"), "")
                        .replace("&nbsp;", " ")
                        .replace("&amp;", "&")
                        .trim()
                } else ""

                if (publisher.isNotEmpty() && !rawTitle.contains("view full coverage", ignoreCase = true)) {
                    siblings.add(
                        ClusterSibling(
                            title = rawTitle,
                            link = href,
                            publicationName = publisher,
                            publishDateMillis = publishDateMillis
                        )
                    )
                }
            }
            return siblings
        }
    }
}
