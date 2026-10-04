package com.intellidream.daily.model

import java.util.Locale
import java.util.regex.Pattern

class ArticleExtractor {

    fun parseHtml(html: String, url: String, baseArticle: NewsArticle? = null): NewsArticle {
        return try {
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

            NewsArticle(
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
        } catch (t: Throwable) {
            android.util.Log.e("ArticleExtractor", "Failed to safely extract article for $url", t)
            baseArticle ?: NewsArticle(
                id = url,
                title = "Untitled Article",
                link = url,
                publishDate = System.currentTimeMillis()
            )
        }
    }

    private fun extractMainContent(html: String): String {
        // Step 1: Remove heavy noise tags safely using linear iterative scanning (no backtracking regex)
        val stripTags = listOf("script", "style", "noscript", "iframe", "svg", "nav", "header", "footer", "form", "aside")
        val cleaned = stripTagBlocks(html, stripTags)

        // Step 2: Evaluate candidate semantic containers
        val candidates = findContainerCandidates(cleaned)

        var bestCandidate = ""
        var bestScore = 0

        for (containerHtml in candidates) {
            val cleanContainer = sanitizeBodyHtml(containerHtml)
            val charCount = cleanContainer.length
            val pCount = countOccurrences("<p>", cleanContainer)
            val commaCount = countOccurrences(",", cleanContainer)
            val score = charCount + (pCount * 60) + (commaCount * 5)

            if (score > bestScore && (charCount > 80 || pCount >= 1)) {
                bestScore = score
                bestCandidate = cleanContainer
            }
        }

        if (bestCandidate.isNotEmpty()) {
            return bestCandidate
        }

        // Step 3: Extract paragraphs fallback
        return extractParagraphBlocks(cleaned)
    }

    private fun stripTagBlocks(html: String, tags: List<String>): String {
        var current = html
        for (tag in tags) {
            val openPrefix = "<$tag"
            val closeTag = "</$tag>"
            var searchIndex = 0
            val sb = StringBuilder(current.length)
            var lastCopied = 0

            while (searchIndex < current.length) {
                val openIdx = current.indexOf(openPrefix, searchIndex, ignoreCase = true)
                if (openIdx == -1) {
                    sb.append(current, lastCopied, current.length)
                    break
                }
                val charAfter = current.getOrNull(openIdx + openPrefix.length)
                if (charAfter != null && !charAfter.isWhitespace() && charAfter != '>' && charAfter != '/') {
                    searchIndex = openIdx + openPrefix.length
                    continue
                }
                val openCloseIdx = current.indexOf('>', openIdx)
                if (openCloseIdx == -1) {
                    sb.append(current, lastCopied, current.length)
                    break
                }
                if (openCloseIdx > openIdx && current[openCloseIdx - 1] == '/') {
                    sb.append(current, lastCopied, openIdx)
                    lastCopied = openCloseIdx + 1
                    searchIndex = lastCopied
                    continue
                }
                val closeIdx = current.indexOf(closeTag, openCloseIdx + 1, ignoreCase = true)
                if (closeIdx == -1) {
                    // Tag is unclosed; discard just this opening tag and keep the rest of document
                    sb.append(current, lastCopied, openIdx)
                    lastCopied = openCloseIdx + 1
                    searchIndex = lastCopied
                    continue
                }
                sb.append(current, lastCopied, openIdx)
                lastCopied = closeIdx + closeTag.length
                searchIndex = lastCopied
            }
            current = sb.toString()
        }
        return current
    }

    private fun stripComments(html: String): String {
        var lastCopied = 0
        val sb = StringBuilder(html.length)
        while (true) {
            val openIdx = html.indexOf("<!--", lastCopied)
            if (openIdx == -1) {
                sb.append(html, lastCopied, html.length)
                break
            }
            val closeIdx = html.indexOf("-->", openIdx + 4)
            if (closeIdx == -1) {
                sb.append(html, lastCopied, openIdx)
                break
            }
            sb.append(html, lastCopied, openIdx)
            lastCopied = closeIdx + 3
        }
        return sb.toString()
    }

    private fun findMatchingClosingTag(html: String, openTagStart: Int, tagName: String): Int {
        val openPrefix = "<$tagName"
        val closePrefix = "</$tagName>"
        var depth = 1
        var idx = html.indexOf('>', openTagStart)
        if (idx == -1) return -1
        idx += 1

        while (idx < html.length && depth > 0) {
            val nextOpen = html.indexOf(openPrefix, idx, ignoreCase = true)
            val nextClose = html.indexOf(closePrefix, idx, ignoreCase = true)

            if (nextClose == -1) return -1

            if (nextOpen != -1 && nextOpen < nextClose) {
                val charAfter = html.getOrNull(nextOpen + openPrefix.length)
                if (charAfter == null || charAfter.isWhitespace() || charAfter == '>') {
                    val closeBracket = html.indexOf('>', nextOpen)
                    if (closeBracket != -1 && html[closeBracket - 1] != '/') {
                        depth++
                    }
                    idx = if (closeBracket != -1) closeBracket + 1 else nextOpen + openPrefix.length
                    continue
                } else {
                    idx = nextOpen + openPrefix.length
                    continue
                }
            } else {
                depth--
                if (depth == 0) {
                    return nextClose
                }
                idx = nextClose + closePrefix.length
            }
        }
        return -1
    }

    private fun findContainerCandidates(html: String): List<String> {
        val candidates = mutableListOf<String>()
        val junkClasses = listOf(
            "marketing", "upnext", "up-next", "card-marketing", "teaser", "related",
            "recommendation", "social", "ad-", "advertisement", "newsletter", "promo", "comment"
        )

        // 1. Check <article> tags
        var idx = 0
        while (idx < html.length) {
            val openIdx = html.indexOf("<article", idx, ignoreCase = true)
            if (openIdx == -1) break
            val charAfter = html.getOrNull(openIdx + 8)
            if (charAfter != null && !charAfter.isWhitespace() && charAfter != '>') {
                idx = openIdx + 8
                continue
            }
            val openCloseIdx = html.indexOf('>', openIdx)
            if (openCloseIdx == -1) break
            val closeIdx = findMatchingClosingTag(html, openIdx, "article")
            if (closeIdx != -1) {
                candidates.add(html.substring(openCloseIdx + 1, closeIdx))
                idx = closeIdx + 10
            } else {
                idx = openCloseIdx + 1
            }
        }

        // 2. Check <main> tags
        idx = 0
        while (idx < html.length) {
            val openIdx = html.indexOf("<main", idx, ignoreCase = true)
            if (openIdx == -1) break
            val charAfter = html.getOrNull(openIdx + 5)
            if (charAfter != null && !charAfter.isWhitespace() && charAfter != '>') {
                idx = openIdx + 5
                continue
            }
            val openCloseIdx = html.indexOf('>', openIdx)
            if (openCloseIdx == -1) break
            val closeIdx = findMatchingClosingTag(html, openIdx, "main")
            if (closeIdx != -1) {
                candidates.add(html.substring(openCloseIdx + 1, closeIdx))
                idx = closeIdx + 7
            } else {
                idx = openCloseIdx + 1
            }
        }

        // 3. Check <div itemprop="articleBody" or class="...article..."
        idx = 0
        while (idx < html.length) {
            val openIdx = html.indexOf("<div", idx, ignoreCase = true)
            if (openIdx == -1) break
            val openCloseIdx = html.indexOf('>', openIdx)
            if (openCloseIdx == -1) break

            val tagHeader = html.substring(openIdx, openCloseIdx).lowercase(Locale.ROOT)
            val isCandidate = tagHeader.contains("articlebody") ||
                    tagHeader.contains("article-body") ||
                    tagHeader.contains("article_body") ||
                    tagHeader.contains("entry-content") ||
                    tagHeader.contains("post-content") ||
                    tagHeader.contains("story-body") ||
                    tagHeader.contains("article__content") ||
                    tagHeader.contains("article-text")

            val isJunk = junkClasses.any { tagHeader.contains(it) }

            if (isCandidate && !isJunk) {
                val closeIdx = findMatchingClosingTag(html, openIdx, "div")
                if (closeIdx != -1) {
                    candidates.add(html.substring(openCloseIdx + 1, closeIdx))
                    idx = closeIdx + 6
                    continue
                }
            }
            idx = openCloseIdx + 1
        }

        return candidates
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
        val paragraphs = mutableListOf<String>()
        var searchIdx = 0
        while (searchIdx < html.length) {
            val pOpen = html.indexOf("<p", searchIdx, ignoreCase = true)
            if (pOpen == -1) break
            val charAfter = html.getOrNull(pOpen + 2)
            if (charAfter != null && !charAfter.isWhitespace() && charAfter != '>') {
                searchIdx = pOpen + 2
                continue
            }
            val pOpenClose = html.indexOf('>', pOpen)
            if (pOpenClose == -1) break
            val pEnd = html.indexOf("</p>", pOpenClose, ignoreCase = true)
            if (pEnd == -1) break
            val pText = html.substring(pOpenClose + 1, pEnd)
            val stripped = pText.replace(Regex("<[^>]+>"), "").trim()
            if (stripped.length > 30) {
                paragraphs.add("<p>$pText</p>")
            }
            searchIdx = pEnd + 4
        }
        return paragraphs.joinToString("\n")
    }

    private fun sanitizeBodyHtml(html: String): String {
        var clean = stripComments(html)
        val junkClasses = listOf(
            "marketing", "upnext", "up-next", "card-marketing", "teaser", "related",
            "recommendation", "social", "ad-", "advertisement", "newsletter", "promo", "comment"
        )
        for (junk in junkClasses) {
            clean = stripTagsWithClass(clean, junk)
        }
        // Remove style, class, and inline script attributes safely
        clean = clean.replace(Regex("\\s*(?:class|style|id|onclick|onload|data-[\\w-]+)=[\"'][^\"']*[\"']"), "")
        // Strip empty tags
        clean = clean.replace(Regex("<(div|span|p|section)[^>]*>\\s*</\\1>", RegexOption.IGNORE_CASE), "")
        return clean.trim()
    }

    private fun stripTagsWithClass(html: String, className: String): String {
        val targetTags = listOf("div", "aside", "span", "p", "section")
        var result = html
        for (tag in targetTags) {
            var searchIdx = 0
            val sb = StringBuilder(result.length)
            var lastCopied = 0
            var modified = false
            while (searchIdx < result.length) {
                val openIdx = result.indexOf("<$tag", searchIdx, ignoreCase = true)
                if (openIdx == -1) {
                    if (modified) {
                        sb.append(result, lastCopied, result.length)
                    }
                    break
                }
                val charAfter = result.getOrNull(openIdx + 1 + tag.length)
                if (charAfter != null && !charAfter.isWhitespace()) {
                    searchIdx = openIdx + 1 + tag.length
                    continue
                }
                val openCloseIdx = result.indexOf('>', openIdx)
                if (openCloseIdx == -1) {
                    if (modified) {
                        sb.append(result, lastCopied, result.length)
                    }
                    break
                }
                val tagHeader = result.substring(openIdx, openCloseIdx)
                if (tagHeader.contains("class=", ignoreCase = true) && tagHeader.contains(className, ignoreCase = true)) {
                    val matchingEnd = findMatchingClosingTag(result, openIdx, tag)
                    if (matchingEnd != -1) {
                        sb.append(result, lastCopied, openIdx)
                        lastCopied = matchingEnd + "</$tag>".length
                        searchIdx = lastCopied
                        modified = true
                        continue
                    }
                }
                searchIdx = openCloseIdx + 1
            }
            if (modified) {
                result = sb.toString()
            }
        }
        return result
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
