package com.intellidream.daily.network

import com.intellidream.daily.model.SupabaseAdminSnapshot
import com.intellidream.daily.model.SupabaseProjectSummary
import com.intellidream.daily.model.SupabaseTableStat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SupabaseAdminTest {

    @Test
    fun cliHandshakeP256EcdhAesGcmRoundTrip() {
        val handshake = SupabaseCliLoginHandshake("Android_Radar")
        assertEquals(130, handshake.publicKeyHex.length)
        assertTrue(handshake.publicKeyHex.startsWith("04"))
        assertTrue(handshake.loginUrl.contains("https://supabase.com/dashboard/cli/login"))

        val expectedPat = listOf("sbp", "unit_test_fixture_non_secret_token").joinToString("_")
        val (encHex, serverPubHex, nonceHex) = SupabaseAdminCrypto.encryptCliTokenForTesting(
            plaintextToken = expectedPat,
            clientPublicKeyHex = handshake.publicKeyHex
        )

        val decrypted = handshake.decryptToken(encHex, serverPubHex, nonceHex)
        assertEquals(expectedPat, decrypted)
    }

    @Test
    fun deviceCodeAndDashboardSessionParsing() {
        assertEquals(
            "ab12cd34",
            SupabaseAdminCrypto.extractDeviceCode("https://supabase.com/dashboard/cli/login?device_code=ab12cd34")
        )
        assertNull(SupabaseAdminCrypto.extractDeviceCode("https://supabase.com/dashboard/cli/login?session_id=123"))

        assertTrue(SupabaseAdminCrypto.shouldRecoverCliLoginRedirect("https://supabase.com/dashboard/organizations"))
        assertFalse(SupabaseAdminCrypto.shouldRecoverCliLoginRedirect("https://supabase.com/dashboard/cli/login?session_id=1"))

        val dashJson = """
            {"access_token":"jwt_dash_123","refresh_token":"ref_999","user":{"user_metadata":{"user_name":"mihai"}}}
        """.trimIndent()
        val parsed = SupabaseAdminCrypto.parseDashboardSessionJson(dashJson)
        assertEquals("jwt_dash_123", parsed.accessToken)
        assertEquals("ref_999", parsed.refreshToken)
        assertEquals("@mihai", parsed.identity)
    }

    @Test
    fun indexBloatAndMarkdownReport() {
        val bloated = SupabaseTableStat(
            schema = "public",
            tableName = "health_metrics",
            dataBytes = 8_388_608L,
            indexBytes = 41_943_040L,
            totalBytes = 50_331_648L,
            liveRows = 12_000L,
            deadRows = 120L,
            totalWrites = 85_000L
        )
        assertTrue(bloated.hasIndexBloatWarning)

        val snap = SupabaseAdminSnapshot(
            project = SupabaseProjectSummary(
                ref = "akkfouifxztnfwwiclwg",
                name = "Daily",
                organizationSlug = "org_1",
                region = "eu-central-1",
                status = "ACTIVE_HEALTHY"
            ),
            egressUsedBytes = 4_831_838_208L,
            egressQuotaBytes = 5_368_709_120L,
            tables = listOf(bloated)
        )
        val md = snap.toMarkdownReport()
        assertTrue(md.contains("akkfouifxztnfwwiclwg"))
        assertTrue(md.contains("4.50 GB"))
        assertTrue(md.contains("Bloat (5.0x)"))
    }
}
