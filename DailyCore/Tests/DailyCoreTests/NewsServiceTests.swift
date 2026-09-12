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
}
