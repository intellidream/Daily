package com.intellidream.daily.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun testMediumOAuthRedirectUrlParsing() {
        fun parseHandle(urlString: String): Pair<String?, Boolean> {
            val uri = try { java.net.URI(urlString) } catch (_: Exception) { return Pair(null, false) }
            val host = uri.host?.lowercase() ?: return Pair(null, false)
            if (host.contains("medium.com")) {
                val path = uri.path ?: ""
                if (path.startsWith("/@")) {
                    val parts = path.removePrefix("/@").split("/")
                    val detected = parts.firstOrNull()?.trim()
                    if (!detected.isNullOrEmpty()) {
                        return Pair(detected, false)
                    }
                } else if (host != "medium.com" && host != "www.medium.com" && host != "api.medium.com" && host.endsWith(".medium.com")) {
                    val sub = host.substringBefore(".medium.com").trim()
                    if (sub.isNotEmpty()) {
                        return Pair(sub, false)
                    }
                } else if (path == "/" || path == "" || path == "/?source=logo") {
                    return Pair(null, true)
                }
            }
            return Pair(null, false)
        }

        // Direct profile URL after Facebook OAuth redirect
        val direct = parseHandle("https://medium.com/@mihai_daily")
        assertEquals("mihai_daily", direct.first)
        assertFalse(direct.second)

        // Reading list profile URL
        val readingList = parseHandle("https://medium.com/@alexandru/list/reading-list")
        assertEquals("alexandru", readingList.first)
        assertFalse(readingList.second)

        // Subdomain URL
        val subdomain = parseHandle("https://marclou.medium.com/post-title-1234")
        assertEquals("marclou", subdomain.first)
        assertFalse(subdomain.second)

        // Root homepage redirect needing /me
        val root = parseHandle("https://medium.com/")
        assertNull(root.first)
        assertTrue(root.second)

        // Root with logo param
        val rootLogo = parseHandle("https://medium.com/?source=logo")
        assertNull(rootLogo.first)
        assertTrue(rootLogo.second)

        // Intermediate OAuth callback before final redirect
        val oauthCallback = parseHandle("https://medium.com/m/callback/facebook?code=AQD123")
        assertNull(oauthCallback.first)
        assertFalse(oauthCallback.second)
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

    @Test
    fun testMediumRssFeedDateParsingWithPubDateAndAtomUpdated() {
        val sampleMediumRss = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
              <channel>
                <title>Stories by Ev Williams on Medium</title>
                <link>https://medium.com/@ev</link>
                <description>Stories by Ev Williams on Medium</description>
                <item>
                  <title><![CDATA[Making “Social” Social Again]]></title>
                  <link>https://ev.medium.com/making-social-social-again-0126fa5c6ce8</link>
                  <dc:creator><![CDATA[Ev Williams]]></dc:creator>
                  <pubDate>Thu, 12 Dec 2024 17:11:33 GMT</pubDate>
                  <atom:updated>2025-05-19T19:09:35.029Z</atom:updated>
                  <content:encoded><![CDATA[<p>Content body here...</p>]]></content:encoded>
                </item>
              </channel>
            </rss>
        """.trimIndent()

        val feed = FeedSource(
            id = "medium_ev",
            name = "Medium: Ev Williams",
            url = "https://medium.com/feed/@ev",
            category = FeedCategory.Tech
        )

        val parser = FeedParser(feed)
        val articles = parser.parse(sampleMediumRss)

        assertEquals(1, articles.size)
        val article = articles.first()
        assertEquals("Making “Social” Social Again", article.title)
        assertEquals("Ev Williams", article.author)

        // Ensure date is not current instant / System.currentTimeMillis()
        val now = System.currentTimeMillis()
        assertTrue(now - article.publishDate > 86400000L * 30L)

        // Verify year is 2024
        val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
        cal.timeInMillis = article.publishDate
        assertEquals(2024, cal.get(java.util.Calendar.YEAR))
        assertEquals(java.util.Calendar.DECEMBER, cal.get(java.util.Calendar.MONTH))
        assertEquals(12, cal.get(java.util.Calendar.DAY_OF_MONTH))
        assertEquals(17, cal.get(java.util.Calendar.HOUR_OF_DAY))
        assertEquals(11, cal.get(java.util.Calendar.MINUTE))
    }

    @Test
    fun testArticleExtractorWithUnclosedTagsAndJunkClasses() {
        // HTML containing an unclosed script tag and multiple junk classes
        val html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Test Unclosed Tag Article</title>
                <script src="bad.js">
            </head>
            <body>
                <div class="marketing">Spam Banner</div>
                <article>
                    <div class="ad-banner">Ad 1</div>
                    <p>First authentic paragraph with sufficient length to qualify as article content.</p>
                    <div class="social-share">Share this story</div>
                    <p>Second authentic paragraph providing in-depth analysis of the situation.</p>
                    <div class="newsletter-signup">Subscribe now!</div>
                </article>
            </body>
            </html>
        """.trimIndent()

        val base = NewsArticle(
            title = "Test Article",
            link = "https://example.com/test-unclosed",
            description = "Summary fallback"
        )

        val extracted = ArticleExtractor.shared.parseHtml(html, base.link, base)

        assertNotNull(extracted.content)
        assertTrue(extracted.content!!.contains("First authentic paragraph"))
        assertTrue(extracted.content!!.contains("Second authentic paragraph"))
        // Junk tags must not be present
        assertTrue(!extracted.content!!.contains("Spam Banner"))
        assertTrue(!extracted.content!!.contains("Ad 1"))
        assertTrue(!extracted.content!!.contains("Subscribe now"))

        // Verify string did NOT duplicate tail
        val count = extracted.content!!.split("Second authentic paragraph").size - 1
        assertEquals("Content should appear exactly once, no double-append tail duplication", 1, count)
    }

    @Test
    fun testArticleExtractorBlankFallback() {
        val blankHtml = "<html><head><title>Paywall Block</title></head><body><div>403 Forbidden</div></body></html>"
        val base = NewsArticle(
            title = "Paywalled Article",
            link = "https://economist.com/story",
            description = "Detailed briefing from RSS feed about global energy markets"
        )

        val extracted = ArticleExtractor.shared.parseHtml(blankHtml, base.link, base)

        // Must fall back to base article description
        assertNotNull(extracted.content)
        assertTrue(extracted.content!!.contains("Detailed briefing from RSS feed"))
    }

    @Test
    fun testZfAndEconomicaContainerExtraction() {
        val zfHtml = """
            <html>
            <head><title>ZF Financial Report</title></head>
            <body>
                <div class="overlay-content">Banner</div>
                <div class="articleContent">
                    <p>Banca Transilvania si OMV Petrom au raportat cresteri record pe bursa de la Bucuresti in trimestrul al treilea.</p>
                    <p>Investitiile masive in energie regenerabila continua conform calendarului anuntat actionarilor.</p>
                </div>
            </body>
            </html>
        """.trimIndent()

        val zfArticle = ArticleExtractor.shared.parseHtml(zfHtml, "https://zf.ro/banci/test")
        assertNotNull(zfArticle.content)
        assertTrue(zfArticle.content!!.contains("Banca Transilvania si OMV Petrom"))
        assertTrue(!zfArticle.content!!.contains("overlay-content"))

        val ecoHtml = """
            <html>
            <head><title>Economica Analysis</title></head>
            <body>
                <div class="header-nav">Nav</div>
                <div class="single__content">
                    <p>Piata de retail din Romania atinge un nou maxim istoric pe fondul consumului intern sustinut.</p>
                    <p>Comerciantii mizeaza pe promotii agresive pentru sezonul sarbatorilor de iarna.</p>
                </div>
            </body>
            </html>
        """.trimIndent()

        val ecoArticle = ArticleExtractor.shared.parseHtml(ecoHtml, "https://economica.net/retail/test")
        assertNotNull(ecoArticle.content)
        assertTrue(ecoArticle.content!!.contains("Piata de retail din Romania"))
        assertTrue(!ecoArticle.content!!.contains("header-nav"))
    }

    @Test
    fun testTechCrunchAndCnbcContainerExtraction() {
        val tcHtml = """
            <html>
            <head><title>AI Breakthrough</title></head>
            <body>
                <div class="wp-block-techcrunch-mega-menu__content">Menu</div>
                <div class="entry-content wp-block-post-content">
                    <p>European AI startup secures landmark round for open source foundation models.</p>
                    <p>The consortium includes sovereign funds and tier-one venture partners.</p>
                </div>
            </body>
            </html>
        """.trimIndent()

        val tcArticle = ArticleExtractor.shared.parseHtml(tcHtml, "https://techcrunch.com/2026/test")
        assertNotNull(tcArticle.content)
        assertTrue(tcArticle.content!!.contains("European AI startup secures landmark round"))
        assertTrue(!tcArticle.content!!.contains("wp-block-techcrunch-mega-menu"))
    }

    @Test
    fun testZfArticleWithNestedDivsAndTextContent() {
        val zfNestedHtml = """
            <html>
            <head><title>Cristian Bichi: Problematica CBDC</title></head>
            <body>
                <div class="header">Header</div>
                <div class="text-content">
                    <p>Banca centrala a Suediei a solicitat recent parlamentului national sa ia in considerare pregatirea cadrului legislativ pentru coroana digitala.</p>
                    <div style="background-color: #BD0000; color: white;"><span>Te-ar putea interesa si:</span></div>
                    <p>Moneda CBDC: a fi sau a nu fi?</p>
                    <p>In ultimii ani, datorita avansurilor tehnologice, au inceput sa apara noi forme de bani pe langa cele traditionale.</p>
                    <p>Experienta suedeza anterioara privind e-krona este una dintre cele mai avansate din lume.</p>
                </div>
                <div class="recommendations">
                    <p>Alte articole recomandate care nu trebuie incluse in corpul stirii principale.</p>
                </div>
            </body>
            </html>
        """.trimIndent()

        val article = ArticleExtractor.shared.parseHtml(zfNestedHtml, "https://www.zf.ro/zf-24/cristian-bichi-test-23273429")
        assertNotNull(article.content)
        val content = article.content!!
        assertTrue(content.contains("Banca centrala a Suediei"))
        assertTrue(content.contains("Moneda CBDC: a fi sau a nu fi?"))
        assertTrue(content.contains("Experienta suedeza anterioara"))
        assertTrue(!content.contains("Alte articole recomandate"))
    }

    @Test
    fun testZfGenZArticleWithTextContent() {
        val zfGenZHtml = """
            <html>
            <head><title>Ai scos fierul din priza?</title></head>
            <body>
                <div class="aboutArticle">About</div>
                <div class="articleIntro mainP text-content">
                    <p>Ai uitat vreodata unde ai lasat cheile, daca ai inchis usa sau daca ai scos fierul din priza?</p>
                    <p>Desi apar la varste inaintate, debutul lor este mult mai devreme in tacere.</p>
                    <p>Somnul este aliatul cel mai puternic pentru sanatatea creierului.</p>
                </div>
                <div class="crossFooterBody">Footer junk</div>
            </body>
            </html>
        """.trimIndent()

        val article = ArticleExtractor.shared.parseHtml(zfGenZHtml, "https://www.zf.ro/zf-gen-z/ai-scos-fierul-test-23272668")
        assertNotNull(article.content)
        val content = article.content!!
        assertTrue(content.contains("Ai uitat vreodata unde ai lasat cheile"))
        assertTrue(content.contains("Somnul este aliatul cel mai puternic"))
        assertTrue(!content.contains("crossFooterBody"))
    }

    @Test
    fun testRealZfArticleExtraction() {
        val fixtureHtml = """
        <!DOCTYPE html>
        <html>
        <head><title>Studiu CPAG: Următoarea etapă a convergenţei</title></head>
        <body>
            <div id="header" class="big-wrapper">
                <nav class="menu clear">
                    <ul role="menu">
                        <li itemprop="name" role="menuitem"><a href="/zf-live/">ZF Live</a></li>
                        <li itemprop="name" role="menuitem"><a href="/cec-bank/">LIVE: CEC BANK PENTRU AFACERI ROMÂNEŞTI</a></li>
                    </ul>
                </nav>
            </div>
            <div class="article">
                <h1>Studiu CPAG: Următoarea etapă a convergenţei</h1>
                <div class="text-content">
                    <p>România nu mai beneficiază de avantajul costurilor mici, care s-a disipat considerabil în perioada 2021-2024.</p>
                    <p>Productivitatea companiilor autohtone este sub productivitatea afiliatelor străine.</p>
                    <p>Atingerea a 90% din productivitatea medie a companiilor străine ar genera 6,7 miliarde euro.</p>
                </div>
                <div class="bong carousel">
                    <div class="recommendations">
                        <p>Articole recomandate</p>
                    </div>
                </div>
            </div>
        </body>
        </html>
        """.trimIndent()

        val fixtureArticle = ArticleExtractor.shared.parseHtml(fixtureHtml, "https://www.zf.ro/zf-24/studiu-cpag-test-23273461")
        assertNotNull(fixtureArticle.content)
        val fixtureContent = fixtureArticle.content!!
        assertTrue(fixtureContent.contains("România nu mai beneficiază de avantajul costurilor mici"))
        assertTrue(fixtureContent.contains("Productivitatea companiilor autohtone"))
        assertTrue(!fixtureContent.contains("LIVE: CEC BANK"))
        assertTrue(!fixtureContent.contains("role=\"menu\""))
        assertTrue(!fixtureContent.contains("id=\"header\""))
        assertTrue(!fixtureContent.contains("Articole recomandate"))

        for (i in 1..10) {
            val file = java.io.File("/tmp/zf_item_$i.html")
            if (!file.exists()) continue
            val html = file.readText()
            val article = ArticleExtractor.shared.parseHtml(html, "https://www.zf.ro/test-$i")
            assertNotNull(article.content)
            val content = article.content!!
            println("ANDROID_ZF_ITEM_$i Title: ${article.title.take(40)}... ContentLen: ${content.length}")
            assertTrue("Item $i must have content > 100", content.length > 100)
            assertTrue("Item $i must not contain menu", !content.contains("role=\"menu\""))
            assertTrue("Item $i must not contain menuitem", !content.contains("role=\"menuitem\""))
            assertTrue("Item $i must not contain header div", !content.contains("id=\"header\""))
            assertTrue("Item $i must not contain CEC", !content.contains("CEC Bank pentru afaceri româneşti"))
        }
    }

    @Test
    fun testRecorderArticleExtraction() {
        val recorderHtml = """
            <!DOCTYPE html>
            <html lang="ro-RO">
            <head>
                <title>EXPLICATIV. Alegeri în SUA: Donald Trump, în fața testului de la jumătatea mandatului - Recorder</title>
                <meta property="og:title" content="EXPLICATIV. Alegeri în SUA: Donald Trump, în fața testului de la jumătatea mandatului" />
                <meta property="og:image" content="https://recorder.ro/wp-content/uploads/2026/10/Thumb_Explicativ_Alegeri_SUA_CLEAN.jpg" />
                <meta property="og:description" content="Explicăm ce sunt aceste alegeri și de ce rezultatul lor ar putea determina cursul ultimilor doi ani." />
                <meta name="author" content="Teodora Preda" />
            </head>
            <body>
                <header id="header">
                    <nav class="nav">Navigation</nav>
                </header>
                <main class="single-post-wrapper">
                    <article class="single-content post-54895">
                        <div class="single-content-content">
                            <p class="wp-block-paragraph">Pe 3 noiembrie, în Statele Unite ale Americii au loc alegerile de la jumătatea mandatului prezidențial, cunoscute sub numele de „midterms.”</p>
                            <p class="wp-block-paragraph">Cetățenii americani din toate cele 50 de state vor decide o parte importantă a membrilor Congresului, care reprezintă puterea legislativă la nivel federal.</p>
                            <p class="wp-block-paragraph">Ultimele sondaje arată că Partidul Democrat ar putea recâștiga majoritatea în Camera Reprezentanților, în timp ce cursa pentru Senat rămâne strânsă.</p>
                        </div>
                    </article>
                </main>
                <div class="related-posts">Recomandari</div>
            </body>
            </html>
        """.trimIndent()

        val article = ArticleExtractor.shared.parseHtml(recorderHtml, "https://recorder.ro/explicativ-alegeri-in-sua-donald-trump-in-fata-testului-de-la-jumatatea-mandatului/")
        assertNotNull(article.content)
        val content = article.content!!
        assertTrue(content.contains("Pe 3 noiembrie, în Statele Unite"))
        assertTrue(content.contains("puterea legislativă la nivel federal"))
        assertTrue(!content.contains("Recomandari"))
        assertTrue(!content.contains("Navigation"))
        assertEquals("Teodora Preda", article.author)
        assertEquals("https://recorder.ro/wp-content/uploads/2026/10/Thumb_Explicativ_Alegeri_SUA_CLEAN.jpg", article.imageUrl)
    }

    @Test
    fun testMediumImageOptimizationAndScrapedItemParsing() {
        val sampleMiroUrl = "https://miro.medium.com/v2/resize:fill:160:112/1*AbCdEf12345.jpeg"
        val optimized = optimizeMediumImageUrl(sampleMiroUrl)
        assertEquals("https://miro.medium.com/v2/resize:fit:800/1*AbCdEf12345.jpeg", optimized)

        val scraped = ScrapedMediumArticle(
            title = "How to Build a Micro-SaaS in 2026",
            url = "https://medium.com/@marclou/how-to-build-micro-saas-2026-12345",
            author = "Marc Lou in Entrepreneurship",
            authorUrl = "https://medium.com/@marclou",
            imageUrl = "https://miro.medium.com/v2/resize:fill:200:150/1*test.jpg",
            description = "Step by step guide to launching quickly."
        )

        var author = scraped.author
        var pubName = "Medium"
        val inIdx = author.indexOf(" in ")
        if (inIdx > 0) {
            pubName = author.substring(inIdx + 4).trim()
            author = author.substring(0, inIdx).trim()
        }

        assertEquals("Marc Lou", author)
        assertEquals("Entrepreneurship", pubName)
        assertEquals("https://miro.medium.com/v2/resize:fit:800/1*test.jpg", optimizeMediumImageUrl(scraped.imageUrl))
    }
}


