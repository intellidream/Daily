import XCTest
@testable import DailyCore

final class NewsServiceTests: XCTestCase {
    
    // MARK: - 1. RSS 2.0 Parsing
    
    func testRss2Parsing() {
        let sampleRss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
            <channel>
                <title>Tech News</title>
                <item>
                    <title><![CDATA[New Apple Silicon &amp; AI Breakthroughs]]></title>
                    <link>https://techcrunch.com/2026/apple-silicon</link>
                    <pubDate>Thu, 10 Sep 2026 14:30:00 +0000</pubDate>
                    <description><![CDATA[<p>Apple announces major architectural advancements in local AI inference.&nbsp;<a href="#">Read more</a></p>]]></description>
                    <content:encoded><![CDATA[<p>Full article body detailing the neural engine performance...</p>]]></content:encoded>
                    <media:content url="https://techcrunch.com/wp-content/uploads/2026/09/m5-chip.jpg" type="image/jpeg"/>
                    <author>Jane Doe</author>
                </item>
            </channel>
        </rss>
        """
        
        let feed = FeedSource(name: "TechCrunch", url: "https://techcrunch.com/feed/", category: .tech)
        let parser = FeedParser(feed: feed)
        let articles = parser.parse(xmlData: Data(sampleRss.utf8))
        
        XCTAssertEqual(articles.count, 1)
        let first = articles[0]
        XCTAssertEqual(first.title, "New Apple Silicon & AI Breakthroughs")
        XCTAssertEqual(first.link, "https://techcrunch.com/2026/apple-silicon")
        XCTAssertEqual(first.imageUrl, "https://techcrunch.com/wp-content/uploads/2026/09/m5-chip.jpg")
        XCTAssertTrue(first.description?.contains("Apple announces major architectural advancements") == true)
        XCTAssertFalse(first.description?.contains("<p>") == true) // Verified HTML tag stripping
    }
    
    // MARK: - 2. Atom Feed Parsing
    
    func testAtomParsing() {
        let sampleAtom = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Ars Technica</title>
            <entry>
                <title>Next-Gen High Performance Computing</title>
                <link href="https://arstechnica.com/science/2026/quantum" rel="alternate"/>
                <published>2026-09-10T12:00:00Z</published>
                <summary type="html">&lt;p&gt;Quantum supremacy milestone achieved in multi-qubit coherence.&lt;/p&gt;</summary>
                <link rel="enclosure" type="image/png" href="https://arstechnica.com/images/quantum.png"/>
                <author><name>Dr. Alan Turing</name></author>
            </entry>
        </feed>
        """
        
        let feed = FeedSource(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", category: .tech)
        let parser = FeedParser(feed: feed)
        let articles = parser.parse(xmlData: Data(sampleAtom.utf8))
        
        XCTAssertEqual(articles.count, 1)
        let first = articles[0]
        XCTAssertEqual(first.title, "Next-Gen High Performance Computing")
        XCTAssertEqual(first.link, "https://arstechnica.com/science/2026/quantum")
        XCTAssertEqual(first.imageUrl, "https://arstechnica.com/images/quantum.png")
        XCTAssertEqual(first.author, "Dr. Alan Turing")
    }
    
    // MARK: - 3. WordPress JSON API Parsing (e.g. ZonaIT)
    
    func testWpJsonParsing() {
        let sampleWpJson = """
        [
            {
                "id": 1042,
                "date": "2026-09-10T10:15:00",
                "link": "https://zonait.ro/review-procesor-next-gen/",
                "title": { "rendered": "Review: Procesorul Viitorului &amp; Performan&#539;a Real&#259;" },
                "excerpt": { "rendered": "<p>Am testat noua genera&#539;ie de procesoare &#537;i am r&#259;mas impresiona&#539;i de eficien&#539;&#259;.</p>" },
                "content": { "rendered": "<p>Testele sintetice demonstreaza o eficienta de neegalat...</p>" },
                "_embedded": {
                    "author": [{ "name": "Dan Cadar" }],
                    "wp:featuredmedia": [{
                        "source_url": "https://zonait.ro/wp-content/uploads/2026/09/cpu_hero.jpg",
                        "media_details": {
                            "sizes": {
                                "medium": { "source_url": "https://zonait.ro/wp-content/uploads/2026/09/cpu_hero-600x400.jpg" }
                            }
                        }
                    }]
                }
            }
        ]
        """
        
        let feed = FeedSource(name: "Zona IT", url: "https://zonait.ro/wp-json/wp/v2/posts", type: .wpJson, category: .tech)
        let parser = WpJsonParser(feed: feed)
        let articles = parser.parse(jsonData: Data(sampleWpJson.utf8))
        
        XCTAssertEqual(articles.count, 1)
        let first = articles[0]
        XCTAssertEqual(first.title, "Review: Procesorul Viitorului & Performanța Reală")
        XCTAssertEqual(first.link, "https://zonait.ro/review-procesor-next-gen/")
        XCTAssertEqual(first.author, "Dan Cadar")
        XCTAssertEqual(first.imageUrl, "https://zonait.ro/wp-content/uploads/2026/09/cpu_hero-600x400.jpg")
        XCTAssertFalse(first.description?.contains("<p>") == true)
    }
    
    // MARK: - 4. Featured Image Deduplication (WinUI Parity)
    
    func testFeaturedImageDeduplication() {
        let featImg = "https://cdn.example.com/images/hero_cover.jpg"
        let contentWithDuplicate = """
        <figure class="featured-wrap">
            <img src="https://cdn.example.com/images/hero_cover.jpg?width=1200" alt="Hero"/>
        </figure>
        <p>This is the first actual paragraph of the story detailing the event.</p>
        <p>And another paragraph.</p>
        """
        
        let deduplicated = ArticleExtractor.shared.deduplicateFeaturedImage(content: contentWithDuplicate, featuredImage: featImg)
        
        XCTAssertFalse(deduplicated.contains("<img"), "Duplicate hero image tag should be eliminated")
        XCTAssertFalse(deduplicated.contains("<figure"), "Empty wrapper figure tag should be eliminated")
        XCTAssertTrue(deduplicated.contains("This is the first actual paragraph"), "Body paragraph should remain intact")
    }
    
    // MARK: - 5. Author Sanitization (WinUI Parity)
    
    func testAuthorSanitization() {
        let rawAuthor = "Jane DoeSenior Editor Social Links"
        let sanitized = ArticleExtractor.shared.sanitizeAuthor(rawAuthor)
        
        XCTAssertEqual(sanitized, "Jane Doe, Senior Editor")
    }
    
    // MARK: - 6. Deterministic GUID Generation (Supabase Sync Parity)
    
    @MainActor
    func testDeterministicGuid() {
        let userId = "d0000000-0000-0000-0000-000000000001"
        let url = "https://techcrunch.com/2026/apple-silicon"
        
        let guid1 = SavedArticlesService.shared.generateDeterministicGuid(userId: userId, url: url, type: .readLater)
        let guid2 = SavedArticlesService.shared.generateDeterministicGuid(userId: userId, url: url, type: .readLater)
        let guidFav = SavedArticlesService.shared.generateDeterministicGuid(userId: userId, url: url, type: .favorite)
        
        XCTAssertEqual(guid1, guid2, "Deterministic GUIDs must match across calls for identical inputs")
        XCTAssertNotEqual(guid1, guidFav, "Different SavedArticleTypes must generate distinct GUIDs")
    }
    
    func testSavedArticlePostgresSerialization() throws {
        let json = """
        [
            {
                "id": "c1f77d33-40fa-40c2-9e87-0b1a03f4ce8e",
                "user_id": "99fdb600-7c28-406b-bc54-5aa8c0cfdf2b",
                "article_url": "https://theverge.com/ai/article1",
                "title": "Future of Generative Models",
                "image_url": "https://theverge.com/image.jpg",
                "description": "Comprehensive analysis",
                "author": "Tech Staff",
                "publication_name": "The Verge",
                "publication_icon_url": "https://theverge.com/icon.png",
                "article_type": "ReadLater",
                "article_date": "2026-09-12T20:15:30.123456+00:00",
                "created_at": "2026-09-12T20:15:30.123456+00:00",
                "updated_at": "2026-09-12T20:16:00.654321+00:00",
                "is_deleted": false
            }
        ]
        """
        
        let articles = try JSONDecoder().decode([SavedArticle].self, from: Data(json.utf8))
        XCTAssertEqual(articles.count, 1)
        let first = articles[0]
        XCTAssertEqual(first.id, "c1f77d33-40fa-40c2-9e87-0b1a03f4ce8e")
        XCTAssertEqual(first.title, "Future of Generative Models")
        XCTAssertEqual(first.articleType, "ReadLater")
        XCTAssertFalse(first.isDeleted)
        XCTAssertNotNil(first.updatedAt)
        
        // Test round-trip encoding
        let encodedData = try JSONEncoder().encode(articles)
        let roundTripped = try JSONDecoder().decode([SavedArticle].self, from: encodedData)
        XCTAssertEqual(roundTripped.count, 1)
        XCTAssertEqual(roundTripped[0].id, first.id)
    }
    
    // MARK: - 7. Smart Recommendations Round-Robin Fairness
    
    func testSmartRecommendations() {
        let current = NewsArticle(
            id: "current",
            title: "Apple Silicon Neural Engine Architecture and AI Performance",
            link: "https://apple.com/silicon",
            description: "Deep dive into machine learning hardware acceleration.",
            category: .tech
        )
        
        let pool = [
            NewsArticle(id: "tc1", title: "Apple AI Models on Silicon", link: "https://tc.com/1", publicationName: "TechCrunch", category: .tech),
            NewsArticle(id: "tc2", title: "Neural Engine Benchmark", link: "https://tc.com/2", publicationName: "TechCrunch", category: .tech),
            NewsArticle(id: "vg1", title: "Apple Hardware Event Recap", link: "https://verge.com/1", publicationName: "The Verge", category: .tech),
            NewsArticle(id: "ars1", title: "Architecture Analysis of Modern Chips", link: "https://ars.com/1", publicationName: "Ars Technica", category: .tech),
            NewsArticle(id: "bb1", title: "Cooking Italian Pasta", link: "https://bbc.com/pasta", publicationName: "BBC", category: .other)
        ]
        
        let recs = SmartRecommendationEngine.shared.getRecommendations(for: current, candidatePool: pool, limit: 3)
        
        XCTAssertFalse(recs.isEmpty)
        XCTAssertFalse(recs.contains(where: { $0.id == "current" }))
        
        // Check diversity: top 2 recommendations shouldn't both be from TechCrunch if other matching sources exist
        if recs.count >= 2 {
            let p1 = recs[0].publicationName
            let p2 = recs[1].publicationName
            XCTAssertNotEqual(p1, p2, "Round-robin fairness must alternate distinct publication sources")
        }
    }
    
    // MARK: - 8. Medium Feed Dual-Date Tag Parsing (pubDate + atom:updated)
    
    func testMediumRssFeedDateParsingWithPubDateAndAtomUpdated() {
        let sampleMediumRss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
            <channel>
                <title>Stories by Ev Williams on Medium</title>
                <link>https://medium.com/@ev</link>
                <description>Stories by Ev Williams on Medium</description>
                <item>
                    <title><![CDATA[Making “Social” Social Again]]></title>
                    <link>https://ev.medium.com/making-social-social-again-0126fa5c6ce8</link>
                    <guid isPermaLink="false">https://medium.com/p/0126fa5c6ce8</guid>
                    <category><![CDATA[social]]></category>
                    <dc:creator><![CDATA[Ev Williams]]></dc:creator>
                    <pubDate>Thu, 12 Dec 2024 17:11:33 GMT</pubDate>
                    <atom:updated>2025-05-19T19:09:35.029Z</atom:updated>
                    <content:encoded><![CDATA[<p>Content body here...</p>]]></content:encoded>
                </item>
            </channel>
        </rss>
        """
        
        let feed = FeedSource(name: "Medium: Ev Williams", url: "https://medium.com/feed/@ev", category: .tech)
        let parser = FeedParser(feed: feed)
        let articles = parser.parse(xmlData: Data(sampleMediumRss.utf8))
        
        XCTAssertEqual(articles.count, 1)
        let article = articles[0]
        XCTAssertEqual(article.title, "Making “Social” Social Again")
        XCTAssertEqual(article.author, "Ev Williams")
        
        // Ensure date is NOT current instant/Date.now
        let now = Date()
        XCTAssertGreaterThan(now.timeIntervalSince(article.publishDate), 86400 * 30, "Medium article should parse actual historical pubDate, not fall back to Date.now")
        
        // Exact calendar verification: 12 Dec 2024
        let calendar = Calendar(identifier: .gregorian)
        var utcCal = calendar
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = utcCal.component(.year, from: article.publishDate)
        let month = utcCal.component(.month, from: article.publishDate)
        let day = utcCal.component(.day, from: article.publishDate)
        let hour = utcCal.component(.hour, from: article.publishDate)
        let minute = utcCal.component(.minute, from: article.publishDate)
        
        XCTAssertEqual(year, 2024)
        XCTAssertEqual(month, 12)
        XCTAssertEqual(day, 12)
        XCTAssertEqual(hour, 17)
        XCTAssertEqual(minute, 11)
    }
    
    // MARK: - 8b. Medium OAuth URL Redirection & Handle Extraction
    
    func testMediumOAuthRedirectUrlParsing() {
        func parseHandle(from urlString: String) -> (handle: String?, shouldNavigateMe: Bool) {
            guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
                return (nil, false)
            }
            if host.contains("medium.com") {
                let path = url.path
                if path.hasPrefix("/@") {
                    let parts = path.dropFirst(2).split(separator: "/")
                    if let first = parts.first, !first.isEmpty {
                        return (String(first), false)
                    }
                } else if host != "medium.com" && host != "www.medium.com" && host != "api.medium.com" && host.hasSuffix(".medium.com") {
                    let sub = host.replacingOccurrences(of: ".medium.com", with: "")
                    if !sub.isEmpty {
                        return (sub, false)
                    }
                } else if path == "/" || path == "" || path == "/?source=logo" {
                    return (nil, true)
                }
            }
            return (nil, false)
        }
        
        // Direct profile URL after Facebook OAuth redirect
        let direct = parseHandle(from: "https://medium.com/@mihai_daily")
        XCTAssertEqual(direct.handle, "mihai_daily")
        XCTAssertFalse(direct.shouldNavigateMe)
        
        // Reading list profile URL
        let readingList = parseHandle(from: "https://medium.com/@alexandru/list/reading-list")
        XCTAssertEqual(readingList.handle, "alexandru")
        XCTAssertFalse(readingList.shouldNavigateMe)
        
        // Subdomain URL
        let subdomain = parseHandle(from: "https://marclou.medium.com/post-title-1234")
        XCTAssertEqual(subdomain.handle, "marclou")
        XCTAssertFalse(subdomain.shouldNavigateMe)
        
        // Root homepage redirect needing /me
        let root = parseHandle(from: "https://medium.com/")
        XCTAssertNil(root.handle)
        XCTAssertTrue(root.shouldNavigateMe)
        
        // Root with logo param
        let rootLogo = parseHandle(from: "https://medium.com/?source=logo")
        XCTAssertNil(rootLogo.handle)
        XCTAssertTrue(rootLogo.shouldNavigateMe)
        
        // Intermediate OAuth callback before final redirect
        let oauthCallback = parseHandle(from: "https://medium.com/m/callback/facebook?code=AQD123")
        XCTAssertNil(oauthCallback.handle)
        XCTAssertFalse(oauthCallback.shouldNavigateMe)
    }
    
    // MARK: - 9. Short Article Extraction & Cookie Script Pruning (Republica Parity)
    
    func testRepublicaShortArticleExtraction() async throws {
        let url = "https://republica.ro/se-pare-ca-am-murit"
        let article = try await ArticleExtractor.shared.extract(from: url)
        
        XCTAssertTrue(article.title.contains("Se pare că am murit"))
        XCTAssertEqual(article.author, "Cristian Tudor Popescu")
        XCTAssertNotNil(article.imageUrl)
        
        guard let content = article.content else {
            XCTFail("Article content should not be nil")
            return
        }
        
        // Ensure core editorial content is extracted
        XCTAssertTrue(content.contains("Circulă pe facebook un clip cu titlul: „Lumânări pentru ziaristul CTP”"))
        XCTAssertTrue(content.contains("Veșnica pomenire, veșnica pomenire!"))
        
        // Ensure third-party cookie consent tables & marketing boxes were pruned
        XCTAssertFalse(content.contains("_cc_id"))
        XCTAssertFalse(content.contains("cookie-script"))
        XCTAssertFalse(content.contains("Cookie"))
        XCTAssertFalse(content.contains("cookie"))
        XCTAssertFalse(content.contains("Îți recomandăm"))
        XCTAssertFalse(content.contains("newsletter"))
    }
    
    func testHeuristicFallbackShortArticleExtraction() {
        let shortHtml = """
        <html>
        <head><title>Short Flash News</title></head>
        <body>
            <div id="cookie-banner">Please accept cookies: table of 500 characters of cookie data...</div>
            <div class="card-marketing">Sign up for habits newsletter today!</div>
            <div itemprop="articleBody">
                <p>This is a brief breaking news announcement under 200 characters.</p>
                <p>Stay tuned for ongoing updates throughout the evening.</p>
            </div>
            <div class="recommendations">
                <article>Recommended story 1</article>
                <article>Recommended story 2</article>
            </div>
        </body>
        </html>
        """
        
        let article = ArticleExtractor.shared.parseHtml(shortHtml, url: "https://example.com/breaking")
        XCTAssertEqual(article.title, "Short Flash News")
        guard let content = article.content else {
            XCTFail("Content must not be nil")
            return
        }
        XCTAssertTrue(content.contains("This is a brief breaking news announcement under 200 characters."))
        XCTAssertFalse(content.contains("cookie-banner"))
        XCTAssertFalse(content.contains("Recommended story"))
    }
    
    // MARK: - 10. Publication Specific Container Extraction Parity
    
    func testZfAndEconomicaContainerExtraction() {
        let zfHtml = """
        <html>
        <head><title>ZF Financial Report</title></head>
        <body>
            <div class="overlay-content">Banner</div>
            <div class="articleContent">
                <p>Banca Transilvania și OMV Petrom au raportat creșteri record pe bursa de la București în trimestrul al treilea.</p>
                <p>Investițiile masive în energie regenerabilă continuă conform calendarului anunțat acționarilor.</p>
            </div>
            <div class="footer-wrap">Footer links</div>
        </body>
        </html>
        """
        
        let zfArticle = ArticleExtractor.shared.parseHtml(zfHtml, url: "https://zf.ro/banci/test")
        XCTAssertNotNil(zfArticle.content)
        XCTAssertTrue(zfArticle.content?.contains("Banca Transilvania și OMV Petrom") == true)
        XCTAssertFalse(zfArticle.content?.contains("overlay-content") == true)
        
        let economicaHtml = """
        <html>
        <head><title>Economica Analysis</title></head>
        <body>
            <div class="header-nav">Nav</div>
            <div class="single__content">
                <p>Piața de retail din România atinge un nou maxim istoric pe fondul consumului intern susținut.</p>
                <p>Comercianții mizează pe promoții agresive pentru sezonul sărbătorilor de iarnă.</p>
            </div>
        </body>
        </html>
        """
        
        let ecoArticle = ArticleExtractor.shared.parseHtml(economicaHtml, url: "https://economica.net/retail/test")
        XCTAssertNotNil(ecoArticle.content)
        XCTAssertTrue(ecoArticle.content?.contains("Piața de retail din România") == true)
        XCTAssertFalse(ecoArticle.content?.contains("header-nav") == true)
    }
    
    func testTechCrunchAndCnbcContainerExtraction() {
        let tcHtml = """
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
        """
        
        let tcArticle = ArticleExtractor.shared.parseHtml(tcHtml, url: "https://techcrunch.com/2026/test")
        XCTAssertNotNil(tcArticle.content)
        XCTAssertTrue(tcArticle.content?.contains("European AI startup secures landmark round") == true)
        XCTAssertFalse(tcArticle.content?.contains("wp-block-techcrunch-mega-menu") == true)
    }
    
    func testZfArticleWithNestedDivsAndTextContent() {
        let zfNestedHtml = """
        <html>
        <head><title>Cristian Bichi: Problematica CBDC</title></head>
        <body>
            <div class="header">Header</div>
            <div class="text-content">
                <p>Banca centrală a Suediei a solicitat recent parlamentului național să ia în considerare pregătirea cadrului legislativ pentru coroana digitală.</p>
                <div style="background-color: #BD0000; color: white;"><span>Te-ar putea interesa și:</span></div>
                <p>Moneda CBDC: a fi sau a nu fi?</p>
                <p>În ultimii ani, datorită avansurilor tehnologice, au început să apară noi forme de bani pe lângă cele tradiționale.</p>
                <p>Experiența suedeză anterioară privind e-krona este una dintre cele mai avansate din lume.</p>
            </div>
            <div class="recommendations">
                <p>Alte articole recomandate care nu trebuie incluse în corpul știrii principale.</p>
            </div>
        </body>
        </html>
        """
        
        let article = ArticleExtractor.shared.parseHtml(zfNestedHtml, url: "https://www.zf.ro/zf-24/cristian-bichi-test-23273429")
        XCTAssertNotNil(article.content)
        let content = article.content ?? ""
        XCTAssertTrue(content.contains("Banca centrală a Suediei"), "Should contain first paragraph")
        XCTAssertTrue(content.contains("Moneda CBDC: a fi sau a nu fi?"), "Should contain paragraph after nested div")
        XCTAssertTrue(content.contains("Experiența suedeză anterioară"), "Should contain subsequent paragraphs through end of text-content")
        XCTAssertFalse(content.contains("Alte articole recomandate"), "Should not leak recommendations outside container")
    }
    
    func testZfGenZArticleWithTextContent() {
        let zfGenZHtml = """
        <html>
        <head><title>Ai scos fierul din priză?</title></head>
        <body>
            <div class="aboutArticle">About</div>
            <div class="articleIntro mainP text-content">
                <p>Ai uitat vreodată unde ai lăsat cheile, dacă ai închis ușa sau dacă ai scos fierul din priză?</p>
                <p>Deși apar la vârste înaintate, debutul lor este mult mai devreme în tăcere.</p>
                <p>Somnul este aliatul cel mai puternic pentru sănătatea creierului.</p>
            </div>
            <div class="crossFooterBody">Footer junk</div>
        </body>
        </html>
        """
        
        let article = ArticleExtractor.shared.parseHtml(zfGenZHtml, url: "https://www.zf.ro/zf-gen-z/ai-scos-fierul-test-23272668")
        XCTAssertNotNil(article.content)
        let content = article.content ?? ""
        XCTAssertTrue(content.contains("Ai uitat vreodată unde ai lăsat cheile"))
        XCTAssertTrue(content.contains("Somnul este aliatul cel mai puternic"))
        XCTAssertFalse(content.contains("crossFooterBody"))
    }
    
    #if canImport(WebKit)
    func testHeadlessReadabilityOnRealZfArticle() async {
        let fixtureHtml = """
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
        """
        
        let fixtureArticle = await HeadlessReadabilityParser.shared.parse(
            html: fixtureHtml,
            urlString: "https://www.zf.ro/zf-24/studiu-cpag-test-23273461",
            baseArticle: nil,
            extractor: ArticleExtractor.shared
        )
        XCTAssertNotNil(fixtureArticle?.content)
        let fixtureContent = fixtureArticle?.content ?? ""
        XCTAssertTrue(fixtureContent.contains("România nu mai beneficiază de avantajul costurilor mici"))
        XCTAssertTrue(fixtureContent.contains("Productivitatea companiilor autohtone"))
        XCTAssertFalse(fixtureContent.contains("LIVE: CEC BANK"))
        XCTAssertFalse(fixtureContent.contains("role=\"menu\""))
        XCTAssertFalse(fixtureContent.contains("id=\"header\""))
        XCTAssertFalse(fixtureContent.contains("Articole recomandate"))

        for i in 1...10 {
            let path = "/tmp/zf_item_\(i).html"
            guard let html = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let article = await HeadlessReadabilityParser.shared.parse(
                html: html,
                urlString: "https://www.zf.ro/test-\(i)",
                baseArticle: nil,
                extractor: ArticleExtractor.shared
            )
            let content = article?.content ?? ""
            let title = article?.title ?? "nil"
            print("ZF_ITEM_\(i) Title: \(title.prefix(40))... ContentLen: \(content.count)")
            XCTAssertTrue(content.count > 100, "Item \(i) should have content > 100")
            XCTAssertFalse(content.contains("role=\"menu\""), "Item \(i) must not contain menu")
            XCTAssertFalse(content.contains("role=\"menuitem\""), "Item \(i) must not contain menuitem")
            XCTAssertFalse(content.contains("id=\"header\""), "Item \(i) must not contain header div")
            XCTAssertFalse(content.contains("Pentru afaceri românești"), "Item \(i) must not contain nav menu")
        }
    }
    #endif
    
    func testRecorderArticleExtraction() {
        let recorderHtml = """
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
        """
        
        let article = ArticleExtractor.shared.parseHtml(recorderHtml, url: "https://recorder.ro/explicativ-alegeri-in-sua-donald-trump-in-fata-testului-de-la-jumatatea-mandatului/")
        XCTAssertNotNil(article.content)
        let content = article.content ?? ""
        XCTAssertTrue(content.contains("Pe 3 noiembrie, în Statele Unite"), "Should extract article body from single-content-content")
        XCTAssertTrue(content.contains("puterea legislativă la nivel federal"), "Should extract all paragraphs")
        XCTAssertFalse(content.contains("Recomandari"), "Should exclude related posts")
        XCTAssertFalse(content.contains("Navigation"), "Should exclude header navigation")
        XCTAssertEqual(article.author, "Teodora Preda")
        XCTAssertEqual(article.imageUrl, "https://recorder.ro/wp-content/uploads/2026/10/Thumb_Explicativ_Alegeri_SUA_CLEAN.jpg")
    }
    
    @MainActor
    func testDefaultFeedsIncludeRecorder() {
        let feeds = NewsService.defaultFeeds
        let recorder = feeds.first { $0.name == "Recorder" }
        XCTAssertNotNil(recorder, "Recorder must be included in default feeds")
        XCTAssertEqual(recorder?.category, .local)
        XCTAssertEqual(recorder?.url, "https://recorder.ro/feed/")
    }
}
