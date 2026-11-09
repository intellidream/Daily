package com.intellidream.daily.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PrismModelsTest {

    @Test
    fun testOmniboxResolvesSafeUrlsAndBlocksMaliciousSchemes() {
        assertEquals(
            "https://github.com/jetbrains/kotlin",
            PrismSearchEngine.resolveOmniboxInput("github.com/jetbrains/kotlin", PrismSearchEngine.Google)
        )
        val searchUrl = PrismSearchEngine.resolveOmniboxInput("compose 120hz scroll", PrismSearchEngine.Perplexity)
        assertTrue(searchUrl?.startsWith("https://www.perplexity.ai/search?q=") == true)

        assertNull(PrismSearchEngine.resolveOmniboxInput("javascript:alert(1)"))
        assertNull(PrismSearchEngine.resolveOmniboxInput("file:///sdcard/secret"))
        assertNull(PrismSearchEngine.resolveOmniboxInput("intent://evil#Intent;end"))
    }

    @Test
    fun testPrismShieldBlocksThirdPartyTrackersAndHonorsAllowlist() {
        assertTrue(
            PrismShieldRules.shouldBlockRequest(
                requestUrl = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js",
                pageUrl = "https://www.theverge.com/tech",
                shieldEnabled = true,
                allowlist = emptyList()
            )
        )
        assertFalse(
            PrismShieldRules.shouldBlockRequest(
                requestUrl = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js",
                pageUrl = "https://www.theverge.com/tech",
                shieldEnabled = true,
                allowlist = listOf("theverge.com")
            )
        )
        assertFalse(
            PrismShieldRules.shouldBlockRequest(
                requestUrl = "https://cdn.theverge.com/hero.jpg",
                pageUrl = "https://www.theverge.com/tech",
                shieldEnabled = true,
                allowlist = emptyList()
            )
        )
    }

    @Test
    fun testDeterministicPinIdStability() {
        val id1 = PrismPinnedSite.deterministicId("User-1", "https://GitHub.com/")
        val id2 = PrismPinnedSite.deterministicId("user-1", "https://github.com")
        assertEquals(id1, id2)
    }
}
