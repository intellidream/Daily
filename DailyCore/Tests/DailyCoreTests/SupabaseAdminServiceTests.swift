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
            egressUsedBytes: 4_500_000_000,  // 4.50 GB (SI decimal matching Supabase Portal)
            egressQuotaBytes: 5_000_000_000, // 5.00 GB
            dbSizeBytes: 180_000_000,        // 180 MB
            dbQuotaBytes: 500_000_000,       // 500 MB (0.5 GB)
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

    func testSupabasePortalExactSiDecimalQuotaParityAndJwtExpiry() {
        // Real Supabase Portal usage_original = 3,169,916,695 bytes vs 5 GB Free quota = 3.170 GB / 5 GB (63.4% -> 63%)
        let snap = SupabaseAdminSnapshot(
            project: SupabaseProjectSummary(
                ref: "akkfouifxztnfwwiclwg",
                name: "Daily",
                organizationSlug: "ysecyyonrhezcfmqfbhg",
                region: "eu-central-1",
                status: "ACTIVE_HEALTHY",
                postgresVersion: "17"
            ),
            isExactBillingUsageAvailable: true,
            egressUsedBytes: 3_169_916_695,
            egressQuotaBytes: 5_000_000_000,
            egress24hBytes: 38_400_000, // 38.4 MB 24h gateway payload
            dbSizeBytes: 43_580_213,
            dbQuotaBytes: 500_000_000
        )
        XCTAssertEqual(SupabaseAdminSnapshot.formatGigabytesPrecise(snap.egressUsedBytes, decimals: 3), "3.170 GB")
        XCTAssertEqual(snap.egressCycleQuotaPercent, 63.398, accuracy: 0.01)
        XCTAssertEqual(Int(snap.egressCycleQuotaPercent.rounded()), 63)
        XCTAssertEqual(SupabaseAdminSnapshot.formatBytes(snap.egress24hBytes), "38.4 MB")
        XCTAssertNotEqual(snap.egress24hBytes, snap.egressUsedBytes)
        // 24h budget is (5,000,000,000 / 30) = 166.66 MB -> 38.4 / 166.66 = ~23%
        XCTAssertEqual(Int(snap.egress24hQuotaPercent.rounded()), 23)
        XCTAssertEqual(SupabaseAdminSnapshot.formatGigabytesPrecise(snap.dbSizeBytes, decimals: 3), "0.044 GB")
        XCTAssertEqual(Int(snap.dbQuotaPercent.rounded()), 9)

        // Credentials must prefer GoTrue dashboardAccessToken for /platform/ endpoints
        let creds = SupabaseAdminCredentials(
            managementAccessToken: "sbp_pat_token",
            dashboardAccessToken: "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5OTk5OTk5OTl9.sig",
            dashboardRefreshToken: "refresh_abc"
        )
        XCTAssertEqual(creds.primaryManagementBearer, "sbp_pat_token")
        XCTAssertEqual(creds.primaryPlatformBearer, "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5OTk5OTk5OTl9.sig")
        XCTAssertEqual(SupabaseAdminCrypto.jwtExpirationEpochSeconds(creds.dashboardAccessToken), 1_999_999_999)
        XCTAssertFalse(SupabaseAdminCrypto.isJwtExpiredOrExpiringSoon(creds.dashboardAccessToken, nowEpochSeconds: 1_900_000_000))
        XCTAssertTrue(SupabaseAdminCrypto.isJwtExpiredOrExpiringSoon(creds.dashboardAccessToken, nowEpochSeconds: 1_999_999_950))
    }

    func testBillingCyclePeriodFormattingAndCreationDateAnchorCalculation() {
        // Direct timestamp formatting
        let startEpoch: Int64 = 1760832000 // 2025-10-19 00:00:00 UTC
        let endEpoch: Int64 = 1763510400   // 2025-11-19 00:00:00 UTC
        let formatted = SupabaseAdminSnapshot.formatBillingCyclePeriod(startEpochSeconds: startEpoch, endEpochSeconds: endEpoch)
        XCTAssertEqual(formatted, "19 Oct 2025 - 19 Nov 2025")

        // Anchor day calculation from ISO creation string ("...-19...")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let nov7_2026 = cal.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        let cycleNov7 = SupabaseAdminSnapshot.computeBillingCyclePeriodFromCreation(dateString: "2024-10-19T14:32:00Z", referenceDate: nov7_2026)
        XCTAssertEqual(cycleNov7, "19 Oct 2026 - 19 Nov 2026")

        let nov25_2026 = cal.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let cycleNov25 = SupabaseAdminSnapshot.computeBillingCyclePeriodFromCreation(dateString: "2024-10-19T14:32:00Z", referenceDate: nov25_2026)
        XCTAssertEqual(cycleNov25, "19 Nov 2026 - 19 Dec 2026")
    }

    func testZeroLogQueryDefaultsSinglePassClickHouseScannerAndLegacySnapshotDecode() throws {
        XCTAssertEqual(SupabaseAdminService.cacheTtlSeconds, 1800)

        let sql = SupabaseAdminService.buildSinglePassGatewayClickHouseSql()
        XCTAssertTrue(sql.contains("WHERE source = 'edge_logs'"))
        XCTAssertFalse(sql.contains("event_message"), "Single-pass ClickHouse SQL must never scan event_message")
        XCTAssertTrue(sql.contains("GROUP BY method, path, ua"))

        let sampleRows: [[String: Any]] = [
            [
                "method": "GET",
                "path": "/rest/v1/health_metrics",
                "ua": "Daily/1.0 CFNetwork/1568 Darwin/24 (iPhone; iOS 18.2)",
                "req_count": 40,
                "resp_bytes": 120_000,
                "avg_ms": 18.0,
                "ok_cnt": 39,
                "err_4xx": 1,
                "err_5xx": 0,
                "max_status": 401,
                "last_ts": "2026-11-08T21:10:00Z"
            ],
            [
                "method": "GET",
                "path": "/rest/v1/health_metrics",
                "ua": "Ktor client / OkHttp 4.12 Android 16",
                "req_count": 10,
                "resp_bytes": 30_000,
                "avg_ms": 28.0,
                "ok_cnt": 10,
                "err_4xx": 0,
                "err_5xx": 0,
                "max_status": 200,
                "last_ts": "2026-11-08T21:12:00Z"
            ],
            [
                "method": "POST",
                "path": "/functions/v1/gemini-proxy",
                "ua": "Daily.WinUI/1.0 (.NET 10.0; Windows NT 10.0)",
                "req_count": 4,
                "resp_bytes": 0, // chunked-encoding fallback -> 4 * 1150 = 4600
                "avg_ms": 420.0,
                "ok_cnt": 3,
                "err_4xx": 0,
                "err_5xx": 1,
                "max_status": 502,
                "last_ts": "2026-11-08T21:14:00Z"
            ]
        ]

        let parsed = SupabaseAdminService.parseSinglePassClickHouseRows(sampleRows, windowHours: 1)
        XCTAssertEqual(parsed.http2xxCount, 52)
        XCTAssertEqual(parsed.http4xxCount, 1)
        XCTAssertEqual(parsed.http5xxCount, 1)
        XCTAssertEqual(parsed.topRoutes.count, 2)
        XCTAssertEqual(parsed.topRoutes.first?.path, "/rest/v1/health_metrics")
        XCTAssertEqual(parsed.topRoutes.first?.requests24h, 50)
        XCTAssertEqual(parsed.topRoutes.first?.responseBytes24h, 150_000)
        // Weighted latency: (40*18 + 10*28) / 50 = (720 + 280) / 50 = 20.0 ms
        XCTAssertEqual(parsed.topRoutes.first?.avgLatencyMs ?? 0, 20.0, accuracy: 0.01)
        XCTAssertEqual(parsed.topRoutes.last?.responseBytes24h, 4600)
        XCTAssertEqual(parsed.fleetBuckets.count, 3)
        XCTAssertEqual(parsed.recentErrors.count, 2)
        XCTAssertTrue(parsed.recentErrors.contains(where: { $0.statusCode == 502 && $0.message.contains("1h") }))

        // Unscanned snapshot defaults to 0 B Log Query mode
        let unscanned = SupabaseAdminSnapshot(
            project: SupabaseProjectSummary(
                ref: "akkfouifxztnfwwiclwg",
                name: "Daily",
                organizationSlug: "ysecyyonrhezcfmqfbhg",
                region: "eu-central-1",
                status: "ACTIVE_HEALTHY",
                postgresVersion: "17"
            ),
            logQueryBytes: 98_500_000_000,
            logQueryQuotaBytes: 100_000_000_000
        )
        XCTAssertFalse(unscanned.hasScannedGatewayLogs)
        XCTAssertTrue(unscanned.toMarkdownReport().contains("On-Demand Zero-Log-Query Mode"))
        let summary = SupabaseAdminService.buildDeterministicDiagnosticSummary(snapshot: unscanned)
        XCTAssertTrue(summary.contains("ClickHouse Log Query Guard"))

        // Backward-compatible decode when gatewayLogsScannedAt & gatewayScanWindowHours keys are absent in cached v3 JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let rawData = try encoder.encode(unscanned)
        var jsonObj = try XCTUnwrap(JSONSerialization.jsonObject(with: rawData) as? [String: Any])
        jsonObj.removeValue(forKey: "gatewayLogsScannedAt")
        jsonObj.removeValue(forKey: "gatewayScanWindowHours")
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObj)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SupabaseAdminSnapshot.self, from: legacyData)
        XCTAssertFalse(decoded.hasScannedGatewayLogs)
        XCTAssertNil(decoded.gatewayLogsScannedAt)
        XCTAssertNil(decoded.gatewayScanWindowHours)
    }
}
