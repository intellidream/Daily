package com.intellidream.daily.model

import java.util.Locale
import java.util.regex.Pattern

class ArticleExtractor {

    fun parseHtml(html: String, url: String, baseArticle: NewsArticle? = null): NewsArticle {
        val ogTitle = extractMetaContent("og:title", html) ?: extractTitleTag(html)
        val ogImage = extractMetaContent("og:image", html) ?: baseArticle?.imageUrl
        val ogDescription = extractMetaContent("og:description", html) ?: baseArticle?.description
        var author = extractMetaContentByName("author", html) ?: baseArticle?.author

        if (author != null) {
            author = sanitizeAuthor(author)
        }

        var content = extractMainContent(html)
        if (content.isBlank()) {
            content = baseArticle?.content ?: baseArticle?.description ?: ""
        }

        if (!ogImage.isNullOrBlank() && content.isNotBlank()) {
            content = deduplicateFeaturedImage(content, ogImage)
        }

        content = optimizeMediumImagesInHtml(content)

        val title = ogTitle ?: baseArticle?.title ?: "Untitled Article"

        return NewsArticle(
            id = baseArticle?.id ?: url,
            title = FeedParser.decodeHtmlEntities(title),
            link = url,
            publishDate = baseArticle?.publishDate ?: System.currentTimeMillis(),
            imageUrl = ogImage,
            description = FeedParser.decodeHtmlEntities(ogDescription ?: ""),
            content = content,
            author = author,
            publicationName = baseArticle?.publicationName,
            publicationIconUrl = baseArticle?.publicationIconUrl,
            category = baseArticle?.category
        )
    }

    private fun extractMainContent(html: String): String {
        // Step 1: Remove heavy noise tags
        var cleaned = html
        val stripTags = listOf("script", "style", "noscript", "iframe", "svg", "nav", "header", "footer", "form", "aside")
        for (tag in stripTags) {
            val pattern = Pattern.compile("<$tag[^>]*>[\\s\\S]*?</$tag>", Pattern.CASE_INSENSITIVE)
            cleaned = pattern.matcher(cleaned).replaceAll("")
        }

        // Step 2: Evaluate candidate semantic containers
        val articlePatterns = listOf(
            "<article[^>]*>([\\s\\S]*?)</article>",
            "<div[^>]+itemprop=[\"']articleBody[\"'][^>]*>([\\s\\S]*?)</div>",
            "<div[^>]+class=[\"'][^\"']*(?:article[-_]body|entry[-_]content|post[-_]content|story[-_]body|article__content|article-text)[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            "<main[^>]*>([\\s\\S]*?)</main>"
        )

        val junkClassPatterns = listOf(
            "marketing", "upnext", "up-next", "card-marketing", "teaser", "related",
            "recommendation", "social", "ad-", "advertisement", "newsletter", "promo", "comment"
        )

        var bestCandidate = ""
        var bestScore = 0

        for (regexStr in articlePatterns) {
            val pattern = Pattern.compile(regexStr, Pattern.CASE_INSENSITIVE)
            val matcher = pattern.matcher(cleaned)

            while (matcher.find()) {
                val fullTag = matcher.group(0) ?: ""
                val openingTag = fullTag.substringBefore(">").lowercase(Locale.ROOT)

                var isJunk = false
                for (junk in junkClassPatterns) {
                    if (openingTag.contains(junk)) {
                        isJunk = true
                        break
                    }
                }
                if (isJunk) continue

                val containerHtml = matcher.group(1) ?: continue
                val cleanContainer = sanitizeBodyHtml(containerHtml)

                val charCount = cleanContainer.length
                val pCount = countOccurrences("<p>", cleanContainer)
                val commaCount = countOccurrences(",", cleanContainer)
                val score = charCount + (pCount * 60) + (commaCount * 5)

                if (score > bestScore && (charCount > 100 || pCount >= 1)) {
                    bestScore = score
                    bestCandidate = cleanContainer
                }
            }
        }

        if (bestCandidate.isNotEmpty()) {
            return bestCandidate
        }

        // Step 3: Extract paragraphs fallback
        return extractParagraphBlocks(cleaned)
    }

    private fun countOccurrences(substring: String, string: String): Int {
        var count = 0
        var idx = 0
        val lowerSub = substring.lowercase(Locale.ROOT)
        val lowerStr = string.lowercase(Locale.ROOT)
        while (true) {
            idx = lowerStr.indexOf(lowerSub, idx)
            if (idx == -1) break
            count++
            idx += lowerSub.length
        }
        return count
    }

    private fun extractParagraphBlocks(html: String): String {
        val pattern = Pattern.compile("<p[^>]*>([\\s\\S]*?)</p>", Pattern.CASE_INSENSITIVE)
        val matcher = pattern.matcher(html)
        val paragraphs = mutableListOf<String>()

        while (matcher.find()) {
            val pText = matcher.group(1) ?: continue
            val stripped = pText.replace(Regex("<[^>]+>"), "").trim()
            if (stripped.length > 30) {
                paragraphs.add("<p>$pText</p>")
            }
        }

        return paragraphs.joinToString("\n")
    }

    private fun sanitizeBodyHtml(html: String): String {
        var clean = html
        // Remove junk elements by class before stripping classes
        val junkClasses = listOf(
            "marketing", "upnext", "up-next", "card-marketing", "teaser", "related",
            "recommendation", "social", "ad-", "advertisement", "newsletter", "promo", "comment"
        )
        for (junk in junkClasses) {
            clean = clean.replace(Regex("<(?:div|aside|span|p|section)[^>]+class=[\"'][^\"']*$junk[^\"']*[\"'][^>]*>[\\s\\S]*?</(?:div|aside|span|p|section)>", RegexOption.IGNORE_CASE), "")
        }
        // Remove class, style, id, event handlers
        clean = clean.replace(Regex("\\s*(?:class|style|id|onclick|onload|data-[\\w-]+)=[\"'][^\"']*[\"']"), "")
        // Remove HTML comments
        clean = clean.replace(Regex("<!--[\\s\\S]*?-->"), "")
        // Strip empty tags
        clean = clean.replace(Regex("<(div|span|p|section)[^>]*>\\s*</\\1>", RegexOption.IGNORE_CASE), "")
        return clean.trim()
    }

    fun deduplicateFeaturedImage(content: String, featuredImage: String): String {
        if (featuredImage.isBlank()) return content

        val pattern = Pattern.compile("<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>", Pattern.CASE_INSENSITIVE)
        val matcher = pattern.matcher(content)

        if (!matcher.find()) return content

        val foundSrc = matcher.group(1) ?: return content
        val s1 = normalizeImageUrl(foundSrc)
        val s2 = normalizeImageUrl(featuredImage)

        var shouldRemove = false
        if (s1.isNotEmpty() && s2.isNotEmpty()) {
            if (s1.contains(s2) || s2.contains(s1)) {
                shouldRemove = true
            } else if (s1.length > 15 && s2.length > 15) {
                val f1 = s1.substringAfterLast("/")
                val f2 = s2.substringAfterLast("/")
                if (f1.isNotEmpty() && f1.equals(f2, ignoreCase = true)) {
                    shouldRemove = true
                }
            }
        }

        if (shouldRemove) {
            val start = matcher.start()
            val end = matcher.end()
            var modified = content.substring(0, start) + content.substring(end)
            modified = modified.replace(Regex("<(?:figure|div|p)[^>]*>\\s*</(?:figure|div|p)>", RegexOption.IGNORE_CASE), "")
            return modified.trim()
        }

        return content
    }

    private fun normalizeImageUrl(url: String): String {
        return try {
            val uri = java.net.URI(url)
            (uri.host ?: "").lowercase(Locale.ROOT) + uri.path.lowercase(Locale.ROOT)
        } catch (_: Exception) {
            url.lowercase(Locale.ROOT)
        }
    }

    fun optimizeMediumImagesInHtml(html: String): String {
        if (!html.contains("miro.medium.com")) return html
        return html.replace(Regex("https://miro\\.medium\\.com/v2/resize:[^/]+(/format:[^/]+)?"), "https://miro.medium.com/v2/resize:fit:800")
    }

    fun sanitizeAuthor(raw: String): String {
        var author = raw
        val junkPhrases = listOf("Social Links", "NavigationContributor", "Navigation", "See all articles", "By ", "De către ", "Author: ")
        for (junk in junkPhrases) {
            author = author.replace(junk, "", ignoreCase = true)
        }

        // Separate concatenated titles (e.g. "Jane DoeSenior Editor" -> "Jane Doe, Senior Editor")
        val titlePattern = Pattern.compile("(?<=[a-z])\\s*(?<!,\\s)(Senior Editor|Executive Editor|Deals Editor|Managing Editor|Editor|Contributor|Freelance Writer|Freelance|Staff Writer|Staff|Writer|Journalist)", Pattern.CASE_INSENSITIVE)
        author = titlePattern.matcher(author).replaceAll(", $1")

        author = author.trim().trim(',', '.', '-', '|')
        author = author.replace(Regex("\\s+,"), ",")
        return author.trim()
    }

    private fun extractMetaContent(property: String, html: String): String? {
        val pattern = Pattern.compile("<meta[^>]+property=[\"']$property[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>", Pattern.CASE_INSENSITIVE)
        val matcher = pattern.matcher(html)
        if (matcher.find()) return matcher.group(1)?.trim()

        val reversePattern = Pattern.compile("<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']$property[\"'][^>]*>", Pattern.CASE_INSENSITIVE)
        val reverseMatcher = reversePattern.matcher(html)
        if (reverseMatcher.find()) return reverseMatcher.group(1)?.trim()

        return null
    }

    private fun extractMetaContentByName(name: String, html: String): String? {
        val pattern = Pattern.compile("<meta[^>]+name=[\"']$name[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>", Pattern.CASE_INSENSITIVE)
        val matcher = pattern.matcher(html)
        if (matcher.find()) return matcher.group(1)?.trim()

        val reversePattern = Pattern.compile("<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+name=[\"']$name[\"'][^>]*>", Pattern.CASE_INSENSITIVE)
        val reverseMatcher = reversePattern.matcher(html)
        if (reverseMatcher.find()) return reverseMatcher.group(1)?.trim()

        return null
    }

    private fun extractTitleTag(html: String): String? {
        val pattern = Pattern.compile("<title[^>]*>([\\s\\S]*?)</title>", Pattern.CASE_INSENSITIVE)
        val matcher = pattern.matcher(html)
        if (matcher.find()) return matcher.group(1)?.trim()
        return null
    }

    companion object {
        val shared = ArticleExtractor()
    }
}
