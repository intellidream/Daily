import XCTest
import CryptoKit
@testable import DailyCore

final class SupabaseAdminServiceTests: XCTestCase {

    func testCliHandshakeP256EcdhAesGcmRoundTrip() throws {
        let handshake = SupabaseCliLoginHandshake(platformLabel: "macOS")
        XCTAssertEqual(handshake.publicKeyHex.count, 130, "Uncompressed P-256 X9.63 point must be 65 bytes = 130 hex chars")
        XCTAssertTrue(handshake.publicKeyHex.hasPrefix("04"), "Uncompressed ANSI X9.63 public key must start with 0x04")
        XCTAssertTrue(handshake.loginUrl.absoluteString.contains("https://supabase.com/dashboard/cli/login"))

        let expectedPat = ["sbp", "unit_test_fixture_non_secret_token"].joined(separator: "_")
        let serverEncrypted = try SupabaseAdminCrypto.encryptCliTokenForTesting(
            plaintextToken: expectedPat,
            clientPublicKeyHex: handshake.publicKeyHex
        )

        let decrypted = try handshake.decryptToken(
            encryptedHex: serverEncrypted.encryptedHex,
            serverPublicKeyHex: serverEncrypted.serverPublicKeyHex,
            nonceHex: serverEncrypted.nonceHex
        )
        XCTAssertEqual(decrypted, expectedPat)
    }

    func testDeviceCodeExtractionAndRedirectRecovery() {
        let callbackUrl = "https://supabase.com/dashboard/cli/login?device_code=9f8e7d6c"
        XCTAssertEqual(SupabaseAdminCrypto.extractDeviceCode(from: callbackUrl), "9f8e7d6c")

        let initialUrl = "https://supabase.com/dashboard/cli/login?session_id=abc&token_name=DayOne"
        XCTAssertNil(SupabaseAdminCrypto.extractDeviceCode(from: initialUrl))

        XCTAssertTrue(SupabaseAdminCrypto.shouldRecoverCliLoginRedirect(currentUrl: "https://supabase.com/dashboard/organizations"))
        XCTAssertTrue(SupabaseAdminCrypto.shouldRecoverCliLoginRedirect(currentUrl: "https://supabase.com/dashboard/project/akkfouifxztnfwwiclwg"))
        XCTAssertFalse(SupabaseAdminCrypto.shouldRecoverCliLoginRedirect(currentUrl: "https://supabase.com/dashboard/cli/login?session_id=123"))
        XCTAssertFalse(SupabaseAdminCrypto.shouldRecoverCliLoginRedirect(currentUrl: "https://supabase.com/dashboard/sign-in"))
        XCTAssertFalse(SupabaseAdminCrypto.shouldRecoverCliLoginRedirect(currentUrl: "https://github.com/login/oauth/authorize"))
    }

    func testDashboardGoTrueSessionParsing() {
        let json = """
        {
          "access_token": "eyJhbGciOiJIUzI1NiJ9.dash_tok",
          "refresh_token": "ref_12345",
          "user": {
            "email": "mihai@example.com",
            "user_metadata": {
              "user_name": "mihai-github"
            }
          }
        }
        """
        let parsed = SupabaseAdminCrypto.parseDashboardSessionJson(json)
        XCTAssertEqual(parsed.accessToken, "eyJhbGciOiJIUzI1NiJ9.dash_tok")
        XCTAssertEqual(parsed.refreshToken, "ref_12345")
        XCTAssertEqual(parsed.identity, "@mihai-github")
    }

    func testFleetUserAgentClassification() {
        XCTAssertEqual(SupabaseAdminCrypto.classifyFleetUserAgent("Daily/1.0 CFNetwork/1568.200.51 Darwin/24.1.0 (iPhone; iOS 18.2)").key, "ios")
        XCTAssertEqual(SupabaseAdminCrypto.classifyFleetUserAgent("Daily/1.0 (Macintosh; Intel Mac OS X 15_2)").key, "macos")
        XCTAssertEqual(SupabaseAdminCrypto.classifyFleetUserAgent("Ktor client / OkHttp 4.12 Android 16").key, "android")
        XCTAssertEqual(SupabaseAdminCrypto.classifyFleetUserAgent("Daily.WinUI/1.0 (.NET 10.0; Windows NT 10.0)").key, "windows")
        XCTAssertEqual(SupabaseAdminCrypto.classifyFleetUserAgent("pg_net/0.10.0").key, "cloud_cron")
    }

    func testIndexBloatDetectionAndMarkdownReport() {
        let bloatedTable = SupabaseTableStat(
            schema: "public",
            tableName: "health_metrics",
            dataBytes: 8_388_608,   // 8 MB
            indexBytes: 41_943_040, // 40 MB (5x heap!)
            totalBytes: 50_331_648,
            liveRows: 12_400,
            deadRows: 340,
            totalWrites: 98_000
        )
        XCTAssertTrue(bloatedTable.hasIndexBloatWarning)
        XCTAssertEqual(bloatedTable.bloatRatio, 5.0, accuracy: 0.01)

        let snap = SupabaseAdminSnapshot(
            project: SupabaseProjectSummary(
                ref: "akkfouifxztnfwwiclwg",
                name: "Daily",
                organizationSlug: "org_daily",
                region: "eu-central-1",
                status: "ACTIVE_HEALTHY",
                postgresVersion: "17.4"
            ),
            orgName: "DayOne Org",
            orgPlan: "free",
            isExactBillingUsageAvailable: true,
            egressUsedBytes: 4_831_838_208,  // 4.50 GB
            egressQuotaBytes: 5_368_709_120, // 5.00 GB
            dbSizeBytes: 188_743_680,        // 180 MB
            dbQuotaBytes: 524_288_000,       // 500 MB
            tables: [bloatedTable]
        )

        let md = snap.toMarkdownReport()
        XCTAssertTrue(md.contains("akkfouifxztnfwwiclwg"))
        XCTAssertTrue(md.contains("4.50 GB"))
        XCTAssertTrue(md.contains("public.health_metrics"))
        XCTAssertTrue(md.contains("Bloat (5.0x)"))

        let aiFallback = SupabaseAdminService.buildDeterministicDiagnosticSummary(snapshot: snap)
        XCTAssertTrue(aiFallback.contains("Egress Quota Pressure"))
        XCTAssertTrue(aiFallback.contains("public.health_metrics"))
    }
}
