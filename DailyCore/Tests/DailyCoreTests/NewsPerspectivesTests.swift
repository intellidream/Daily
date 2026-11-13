import Foundation
import Testing
@testable import DailyCore

@Suite("News Perspectives, Blindspots & Media Intelligence Tests")
struct NewsPerspectivesTests {

    @Test("Canonical seed catalog loads 200+ outlets and resolves RO, Global, and Substack profiles")
    func testRegistryResolution() {
        let registry = MediaIntelligenceRegistry.shared
        #expect(registry.catalogCount >= 200)

        let recorder = registry.resolve(url: "https://recorder.ro/investigatie-noua/", publicationName: "Recorder")
        #expect(recorder.name == "Recorder")
        #expect(recorder.bias == .center)
        #expect(recorder.factuality == .veryHigh)
        #expect(recorder.ownershipType == .independent)
        #expect(recorder.countryCode == "RO")

        let g4 = registry.resolve(url: "https://www.g4media.ro/articol.html", publicationName: "G4Media")
        #expect(g4.domain == "g4media.ro")
        #expect(g4.ownerLabel.contains("Titluri Quality"))

        let bbcSubdomain = registry.resolve(url: "https://feeds.bbci.co.uk/news/world/rss.xml", publicationName: "BBC")
        #expect(bbcSubdomain.domain == "bbc.com")
        #expect(bbcSubdomain.ownershipType == .publicBroadcaster)

        // Google News opaque URL resolved via publicationName alias
        let gnewsResolved = registry.resolve(
            url: "https://news.google.com/rss/articles/CBMiWWh0dHBz",
            publicationName: "Ziarul Financiar"
        )
        #expect(gnewsResolved.domain == "zf.ro")
        #expect(gnewsResolved.bias == .leanRight)

        // Dynamic Substack newsletter creator resolution
        let customSubstack = registry.resolve(
            url: "https://yohanmalshika.substack.com/p/linq-performance",
            publicationName: "Yohan's .NET Notes",
            author: "Yohan Malshika",
            isSubstack: true
        )
        #expect(customSubstack.bias == .independentCreator)
        #expect(customSubstack.ownershipType == .independent)
    }

    @Test("ArticleFramingAnalyzer distinguishes reporting, opinion, investigation, and sensational titles")
    func testArticleFramingAnalyzer() {
        let inv = ArticleFramingAnalyzer.classify(
            title: "INVESTIGAȚIE Recorder: Cum funcționează rețeaua contractelor publice",
            link: "https://recorder.ro/investigatie"
        )
        #expect(inv == .investigation)

        let op = ArticleFramingAnalyzer.classify(
            title: "Opinie: De ce reforma fiscală nu mai poate aștepta în 2026",
            link: "https://hotnews.ro/opinii/reforma"
        )
        #expect(op == .opinion)

        let sens = ArticleFramingAnalyzer.classify(
            title: "ȘOCANT! Bombă pe scena politică, nu o să-ți vină să crezi ce a urmat!!!",
            link: "https://romaniatv.net/stire"
        )
        #expect(sens == .sensational)

        let straight = ArticleFramingAnalyzer.classify(
            title: "BNR menține rata dobânzii de politică monetară la 6,50% pe an",
            link: "https://agerpres.ro/economic/bnr"
        )
        #expect(straight == .reporting)
        #expect(straight.badgeLabel == nil)
    }

    @Test("FeedParser unpacks Google News RSS <ol><li> siblings and <source> attribution")
    func testGoogleNewsRssUnpacking() {
        let sampleXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Top stories - Google News</title>
            <item>
              <title>BNR păstrează dobânda cheie la 6,5% în ședința de azi - HotNews.ro</title>
              <link>https://news.google.com/rss/articles/CBMi1</link>
              <pubDate>Fri, 13 Nov 2026 12:00:00 GMT</pubDate>
              <source url="https://www.hotnews.ro">HotNews.ro</source>
              <description>&lt;ol&gt;&lt;li&gt;&lt;a href="https://news.google.com/rss/articles/CBMi1"&gt;BNR păstrează dobânda cheie la 6,5%&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;HotNews.ro&lt;/font&gt;&lt;/li&gt;&lt;li&gt;&lt;a href="https://news.google.com/rss/articles/CBMi2"&gt;Decizie BNR privind dobânda de politică monetară și inflația&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;Ziarul Financiar&lt;/font&gt;&lt;/li&gt;&lt;li&gt;&lt;a href="https://news.google.com/rss/articles/CBMi3"&gt;Mugur Isărescu anunță decizia BNR pe dobânzi&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;Digi24&lt;/font&gt;&lt;/li&gt;&lt;/ol&gt;</description>
            </item>
          </channel>
        </rss>
        """

        let feed = FeedSource(name: "Google News", url: "https://news.google.com/rss?hl=ro&gl=RO&ceid=RO:ro", category: .local)
        let parsed = FeedParser(feed: feed).parse(xmlData: Data(sampleXml.utf8))
        #expect(parsed.count == 1)
        let first = parsed[0]
        #expect(first.publicationName == "HotNews.ro")
        #expect(!first.title.hasSuffix("- HotNews.ro"))
        #expect(first.googleNewsSiblings?.count == 3)

        let clustered = StoryClusterEngine.clusterArticles(parsed)
        #expect(clustered.clusters.count == 1)
        #expect(clustered.clusters[0].uniqueOutletCount == 3)
        #expect(clustered.clusters[0].hasMultipleSources == true)
    }

    @Test("StoryClusterEngine groups multi-outlet stories and detects ideological Blindspots")
    func testStoryClusteringAndBlindspot() {
        let now = Date()
        let articles = [
            NewsArticle(
                title: "European Central Bank cuts interest rates to 2.25% amid Eurozone inflation slowdown",
                link: "https://www.theguardian.com/business/ecb-rates",
                publishDate: now,
                publicationName: "The Guardian"
            ),
            NewsArticle(
                title: "ECB lowers Eurozone interest rates to 2.25% as Lagarde signals caution",
                link: "https://www.nytimes.com/2026/11/13/business/ecb-interest-rates.html",
                publishDate: now.addingTimeInterval(-1800),
                publicationName: "The New York Times"
            ),
            NewsArticle(
                title: "Eurozone inflation cooling prompts European Central Bank rate cut to 2.25%",
                link: "https://www.vox.com/economy/ecb-rates-cut",
                publishDate: now.addingTimeInterval(-3600),
                publicationName: "Vox"
            ),
            NewsArticle(
                title: "BCE reduce dobânda în zona euro la 2,25% pe fondul scăderii inflației",
                link: "https://www.digi24.ro/stiri/economie/bce-dobanda-225",
                publishDate: now.addingTimeInterval(-2400),
                publicationName: "Digi24"
            ),
            NewsArticle(
                title: "NASA launches Europa Clipper trajectory correction burn toward Jupiter",
                link: "https://spacenews.com/europa-clipper-burn/",
                publishDate: now.addingTimeInterval(-900),
                publicationName: "SpaceNews"
            )
        ]

        let output = StoryClusterEngine.clusterArticles(articles)
        // ECB articles should form a multi-source cluster separate from NASA Europa Clipper
        let ecbCluster = output.clusters.first { $0.uniqueOutletCount >= 3 }
        #expect(ecbCluster != nil)
        if let ecb = ecbCluster {
            #expect(ecb.distribution.leftCount == 3)
            #expect(ecb.distribution.rightCount == 0)
            #expect(ecb.blindspot == .lowRightCoverage)

            let comparison = NewsPerspectiveService.shared.buildDeterministicComparison(for: ecb, isRomanian: false)
            #expect(!comparison.summaryText.isEmpty)
            #expect(!comparison.framingDifferences.isEmpty)
        }
    }
}
