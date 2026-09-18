package com.intellidream.daily.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NewsParsersTest {

    @Test
    fun testRssParsing() {
        val sampleRss = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:media="http://search.yahoo.com/mrss/">
              <channel>
                <title>Tech News Daily</title>
                <link>https://example.com</link>
                <description>Latest tech updates</description>
                <item>
                  <title>Kotlin 2.2 Released with Extreme Speed</title>
                  <link>https://example.com/kotlin-2-2</link>
                  <description><![CDATA[<p>The Kotlin team has announced 2.2 with massive compiler improvements.</p>]]></description>
                  <pubDate>Thu, 18 Sep 2026 00:00:00 GMT</pubDate>
                  <dc:creator>Roman Elizarov</dc:creator>
                  <media:content url="https://example.com/images/kotlin.jpg" medium="image" />
                </item>
              </channel>
            </rss>
        """.trimIndent()

        val feed = FeedSource(
            id = "test_feed",
            name = "Tech News Daily",
            url = "https://example.com/rss",
            category = FeedCategory.Tech
        )

        val parser = FeedParser(feed)
        val articles = parser.parse(sampleRss)

        assertEquals(1, articles.size)
        val article = articles.first()
        assertEquals("Kotlin 2.2 Released with Extreme Speed", article.title)
        assertEquals("https://example.com/kotlin-2-2", article.link)
        assertEquals("Roman Elizarov", article.author)
        assertEquals("https://example.com/images/kotlin.jpg", article.imageUrl)
        assertEquals("Tech News Daily", article.publicationName)
        assertEquals(FeedCategory.Tech, article.category)
        assertTrue(article.description?.contains("massive compiler improvements") == true)
    }

    @Test
    fun testAtomParsing() {
        val sampleAtom = """
            <?xml version="1.0" encoding="utf-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <title>Science Feed</title>
              <entry>
                <title>JWST Discovers Earliest Known Galaxy</title>
                <link rel="alternate" href="https://science.org/jwst-galaxy" />
                <id>urn:uuid:1234-5678-9012</id>
                <updated>2026-09-17T12:00:00Z</updated>
                <summary>Astronomers confirm galaxy redshift record using NIRCam.</summary>
                <author>
                  <name>Dr. Jane Doe</name>
                </author>
              </entry>
            </feed>
        """.trimIndent()

        val feed = FeedSource(
            name = "Science Wire",
            url = "https://science.org/atom",
            category = FeedCategory.Space
        )

        val parser = FeedParser(feed)
        val articles = parser.parse(sampleAtom)

        assertEquals(1, articles.size)
        val article = articles.first()
        assertEquals("JWST Discovers Earliest Known Galaxy", article.title)
        assertEquals("https://science.org/jwst-galaxy", article.link)
        assertEquals("Dr. Jane Doe", article.author)
        assertEquals(FeedCategory.Space, article.category)
    }

    @Test
    fun testWpJsonParsing() {
        val sampleJson = """
            [
              {
                "id": 1042,
                "date": "2026-09-17T15:30:00",
                "link": "https://zonait.ro/review-pixel-9-pro/",
                "title": { "rendered": "Google Pixel 9 Pro Review &#8211; Flagship Perfection" },
                "excerpt": { "rendered": "<p>Noul Google Pixel 9 Pro aduce un design redefinit cu margini plate...</p>\n" },
                "_embedded": {
                  "author": [{ "name": "Dan Cadar" }],
                  "wp:featuredmedia": [{ "source_url": "https://zonait.ro/wp-content/uploads/pixel9pro.jpg" }]
                }
              }
            ]
        """.trimIndent()

        val feed = FeedSource(
            name = "Zona IT",
            url = "https://zonait.ro/wp-json/wp/v2/posts?per_page=20&_embed",
            type = FeedType.WpJson,
            category = FeedCategory.Tech
        )

        val parser = WpJsonParser(feed)
        val articles = parser.parse(sampleJson)

        assertEquals(1, articles.size)
        val article = articles.first()
        assertEquals("Google Pixel 9 Pro Review – Flagship Perfection", article.title)
        assertEquals("https://zonait.ro/review-pixel-9-pro/", article.link)
        assertEquals("Dan Cadar", article.author)
        assertEquals("https://zonait.ro/wp-content/uploads/pixel9pro.jpg", article.imageUrl)
        assertTrue(article.description?.contains("Noul Google Pixel 9 Pro aduce un design") == true)
    }

    @Test
    fun testMediumUsernameExtraction() {
        val pathArticle = NewsArticle(
            title = "Building Micro-SaaS in 2026",
            link = "https://medium.com/@marclou/building-micro-saas-12345",
            author = "Marc Lou"
        )
        assertEquals("marclou", extractMediumUsername(pathArticle))

        val subdomainArticle = NewsArticle(
            title = "Design Systems in Jetpack Compose",
            link = "https://alexandru.medium.com/design-systems-jetpack-compose-98765",
            author = "Alexandru"
        )
        assertEquals("alexandru", extractMediumUsername(subdomainArticle))

        val authorAtArticle = NewsArticle(
            title = "Some Post",
            link = "https://medium.com/topic/post-111",
            author = "@designguru"
        )
        assertEquals("designguru", extractMediumUsername(authorAtArticle))

        val nonMediumArticle = NewsArticle(
            title = "BBC World News",
            link = "https://bbc.com/news/world-123",
            author = "BBC Correspondent"
        )
        assertNull(extractMediumUsername(nonMediumArticle))
    }

    @Test
    fun testArticleExtractorCleanup() {
        val rawHtml = """
            <!DOCTYPE html>
            <html>
            <head>
              <title>Revolutionary Battery Tech Announced</title>
              <meta property="og:title" content="Revolutionary Battery Tech Announced" />
            </head>
            <body>
              <header><nav><a href="/">Home</a></nav></header>
              <div class="ad-banner">Buy crypto now!</div>
              <article>
                <h1>Revolutionary Battery Tech Announced</h1>
                <p class="byline">By Sarah Connor</p>
                <img src="https://example.com/battery.png" alt="Battery" />
                <p>Researchers at MIT have developed a solid-state battery that charges in 3 minutes.</p>
                <div class="social-share">Share on X</div>
                <p>The breakthrough utilizes a novel ceramic electrolyte capable of handling ultra-high currents.</p>
              </article>
              <footer>&copy; 2026 Example Corp</footer>
            </body>
            </html>
        """.trimIndent()

        val baseArticle = NewsArticle(
            title = "Revolutionary Battery Tech Announced",
            link = "https://example.com/battery-tech"
        )

        val extracted = ArticleExtractor.shared.parseHtml(rawHtml, baseArticle.link, baseArticle)

        assertEquals("Revolutionary Battery Tech Announced", extracted.title)
        assertNotNull(extracted.content)
        assertTrue(extracted.content?.contains("solid-state battery") == true)
        assertTrue(extracted.content?.contains("ceramic electrolyte") == true)
        // Ads and social junk should be cleaned out
        assertTrue(extracted.content?.contains("Buy crypto now") == false)
        assertTrue(extracted.content?.contains("Share on X") == false)
    }

    @Test
    fun testSmartRecommendationEngine() {
        val current = NewsArticle(
            title = "Jetpack Compose Liquid Glass UI Guide",
            link = "https://example.com/compose-glass",
            category = FeedCategory.Tech,
            description = "How to build translucent glass cards with blur and specular highlights in Compose",
            publicationName = "Android Devs"
        )

        val relatedArticle = NewsArticle(
            title = "Advanced Compose Shaders and Blur Effects",
            link = "https://example.com/compose-shaders",
            category = FeedCategory.Tech,
            description = "Implementing runtime shaders and specular highlights in Android",
            publicationName = "Tech Insights"
        )

        val unrelatedArticle = NewsArticle(
            title = "Federal Reserve Holds Interest Rates Steady",
            link = "https://example.com/fed-rates",
            category = FeedCategory.Markets,
            description = "Central bank maintains benchmark rates as inflation cools",
            publicationName = "Bloomberg"
        )

        val recommendations = SmartRecommendationEngine.shared.getRecommendations(
            currentArticle = current,
            candidatePool = listOf(current, relatedArticle, unrelatedArticle),
            limit = 5
        )

        assertEquals(2, recommendations.size)
        // Current article must be excluded
        assertTrue(recommendations.none { it.link == current.link })
        // Related article in Tech with matching keywords should rank first
        assertEquals(relatedArticle.link, recommendations.first().link)
    }
}
