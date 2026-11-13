package com.intellidream.daily.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NewsPerspectivesTest {

    @Test
    fun `seed catalog loads 200+ Romanian European and global outlets`() {
        val registry = MediaIntelligenceRegistry.shared
        assertTrue("Expected >= 200 outlets, got ${registry.catalogCount}", registry.catalogCount >= 200)

        val recorder = registry.resolve(url = "https://recorder.ro/investigatie-noua/", publicationName = "Recorder")
        assertEquals(MediaBias.Center, recorder.bias)
        assertEquals(FactualityTier.VeryHigh, recorder.factuality)
        assertEquals("RO", recorder.countryCode)

        val zf = registry.resolve(url = "https://www.zf.ro/banci-si-asigurari/bnr-2026", publicationName = "Ziarul Financiar")
        assertEquals(MediaBias.LeanRight, zf.bias)

        val bbc = registry.resolve(url = "https://feeds.bbci.co.uk/news/world-123", publicationName = "BBC News")
        assertEquals(MediaBias.Center, bbc.bias)

        val substack = registry.resolve(
            url = "https://pragmaticengineer.substack.com/p/architecture",
            publicationName = "The Pragmatic Engineer",
            author = "Gergely Orosz",
            isSubstack = true
        )
        assertEquals(MediaBias.IndependentCreator, substack.bias)
    }

    @Test
    fun `framing analyzer classifies investigative opinion sensational and reporting`() {
        val recorderProfile = MediaIntelligenceRegistry.shared.resolve(url = "https://recorder.ro/articol")
        assertEquals(
            ArticleFramingTag.Investigation,
            ArticleFramingAnalyzer.classify(
                title = "Investigație Recorder: Cum funcționează rețeaua contractelor publice",
                link = "https://recorder.ro/investigatii/reteaua/",
                profile = recorderProfile
            )
        )
        assertEquals(
            ArticleFramingTag.Opinion,
            ArticleFramingAnalyzer.classify(
                title = "Opinion: Why Europe must reform capital markets now",
                link = "https://www.ft.com/opinion/capital-markets"
            )
        )
        assertEquals(
            ArticleFramingTag.Sensational,
            ArticleFramingAnalyzer.classify(
                title = "ȘOCANT! Nu o să-ți vină să crezi ce decizie s-a luat azi!!!"
            )
        )
        assertEquals(
            ArticleFramingTag.Reporting,
            ArticleFramingAnalyzer.classify(
                title = "BNR menține rata dobânzii de politică monetară la 6,50% pe an",
                link = "https://www.hotnews.ro/economie/bnr-dobanda"
            )
        )
    }

    @Test
    fun `bilingual story clustering merges Romanian and English ECB stories and avoids false merges`() {
        val now = System.currentTimeMillis()
        val articles = listOf(
            NewsArticle(
                id = "1",
                title = "BCE reduce dobânda cheie la 2,25% pe fondul scăderii inflației în zona euro",
                link = "https://www.hotnews.ro/economie/bce-dobanda-225",
                publishDate = now,
                publicationName = "HotNews"
            ),
            NewsArticle(
                id = "2",
                title = "European Central Bank cuts interest rates to 2.25% amid Eurozone inflation cooling",
                link = "https://www.reuters.com/markets/ecb-cuts-rates-225",
                publishDate = now - 1800_000L,
                publicationName = "Reuters"
            ),
            NewsArticle(
                id = "3",
                title = "Banca Centrală Europeană scade dobânzile la 2,25% pentru a sprijini economia din zona euro",
                link = "https://www.zf.ro/banci/bce-scade-dobanzile-225",
                publishDate = now - 2400_000L,
                publicationName = "Ziarul Financiar"
            ),
            NewsArticle(
                id = "4",
                title = "NASA launches Europa Clipper spacecraft toward Jupiter icy moon",
                link = "https://arstechnica.com/space/2026/europa-clipper/",
                publishDate = now - 900_000L,
                publicationName = "Ars Technica"
            )
        )

        val output = StoryClusterEngine.clusterArticles(articles)
        val ecbCluster = output.clusters.firstOrNull { it.uniqueOutletCount == 3 }
        assertNotNull("Expected 3-outlet bilingual ECB cluster", ecbCluster)
        assertTrue(ecbCluster!!.hasMultipleSources)
        assertEquals(2, output.clusters.size)
    }

    @Test
    fun `blindspot detection and Google News sibling unpacking work deterministically`() {
        val lowRight = StoryClusterEngine.computeBlindspot(
            distribution = BiasDistribution(leftCount = 4, centerCount = 1, rightCount = 0),
            uniqueOutlets = 5
        )
        assertEquals(BlindspotType.LowRightCoverage, lowRight)

        val sampleXml = """
            <rss version="2.0"><channel><item>
              <title>Major EU Summit Agreement - Politico Europe</title>
              <link>https://news.google.com/rss/articles/CBMi123</link>
              <pubDate>Sat, 14 Nov 2026 08:00:00 GMT</pubDate>
              <source url="https://www.politico.eu">Politico Europe</source>
              <description>&lt;ol&gt;&lt;li&gt;&lt;a href=&quot;https://www.politico.eu/article/eu-summit&quot;&gt;Major EU Summit Agreement&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color=&quot;#6f6f6f&quot;&gt;Politico Europe&lt;/font&gt;&lt;/li&gt;&lt;li&gt;&lt;a href=&quot;https://www.theguardian.com/world/eu-summit&quot;&gt;EU leaders strike landmark climate deal&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color=&quot;#6f6f6f&quot;&gt;The Guardian&lt;/font&gt;&lt;/li&gt;&lt;li&gt;&lt;a href=&quot;https://www.telegraph.co.uk/world/eu-summit&quot;&gt;Brussels budget deal sparks debate&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color=&quot;#6f6f6f&quot;&gt;The Telegraph&lt;/font&gt;&lt;/li&gt;&lt;/ol&gt;</description>
            </item></channel></rss>
        """.trimIndent()

        val feed = FeedSource(id = "gn", name = "Google News", url = "https://news.google.com/rss")
        val parsed = FeedParser(feed).parse(sampleXml)
        assertEquals(1, parsed.size)
        assertEquals("Politico Europe", parsed[0].publicationName)
        assertEquals("Major EU Summit Agreement", parsed[0].title)
        assertEquals(3, parsed[0].googleNewsSiblings?.size)

        val clustered = StoryClusterEngine.clusterArticles(parsed)
        assertEquals(3, clustered.clusters[0].uniqueOutletCount)
    }
}
