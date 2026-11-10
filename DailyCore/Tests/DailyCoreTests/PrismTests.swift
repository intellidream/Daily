import XCTest
@testable import DailyCore

final class PrismTests: XCTestCase {

    func testOmniboxResolvesUrlsDomainsAndQueriesSafely() {
        // Explicit HTTPS
        let full = PrismSearchEngine.resolveOmniboxInput("https://pragmaticengineer.com/p/ai", engine: .google)
        XCTAssertEqual(full?.absoluteString, "https://pragmaticengineer.com/p/ai")

        // Bare domain -> HTTPS upgrade
        let bare = PrismSearchEngine.resolveOmniboxInput("github.com/apple/swift", engine: .google)
        XCTAssertEqual(bare?.absoluteString, "https://github.com/apple/swift")

        // Natural language query -> Search Engine URL
        let query = PrismSearchEngine.resolveOmniboxInput("swift 6 strict concurrency", engine: .perplexity)
        XCTAssertEqual(query?.host, "www.perplexity.ai")
        XCTAssertTrue(query?.absoluteString.contains("swift%206%20strict%20concurrency") == true)

        // Dangerous schemes strictly blocked
        XCTAssertNil(PrismSearchEngine.resolveOmniboxInput("javascript:alert(1)", engine: .google))
        XCTAssertNil(PrismSearchEngine.resolveOmniboxInput("file:///etc/passwd", engine: .google))
        XCTAssertNil(PrismSearchEngine.resolveOmniboxInput("data:text/html,<h1>x</h1>", engine: .google))
    }

    func testPrismClipPostgrestSnakeCaseSerialization() throws {
        let clip = PrismClip(
            userId: "00000000-0000-0000-0000-000000000001",
            clipType: .quote,
            title: "Architecture Notes",
            sourceUrl: "https://www.example.com/post",
            contentText: "Keep background tabs hibernated for 0% idle CPU.",
            userNote: "Key invariant",
            tags: ["prism", "perf"],
            isFavorite: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(clip)
        let rawJson = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(rawJson.contains("\"clip_type\":\"quote\""))
        XCTAssertTrue(rawJson.contains("\"source_url\":\"https:\\/\\/www.example.com\\/post\"") || rawJson.contains("\"source_url\":\"https://www.example.com/post\""))
        XCTAssertTrue(rawJson.contains("\"domain\":\"example.com\""))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PrismClip.self, from: data)
        XCTAssertEqual(decoded.id, clip.id)
        XCTAssertEqual(decoded.clipType, .quote)
        XCTAssertEqual(decoded.domain, "example.com")
        XCTAssertEqual(decoded.tags, ["prism", "perf"])
    }

    func testContentBlockerRulesValidJSONWithAllowlist() throws {
        let json = PrismWebScripts.contentBlockerRulesJSON(allowlistedDomains: ["github.com", "substack.com"])
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        XCTAssertNotNil(parsed)
        XCTAssertGreaterThan(parsed?.count ?? 0, 10)

        let firstTrigger = parsed?.first?["trigger"] as? [String: Any]
        let unlessDomains = firstTrigger?["unless-domain"] as? [String]
        XCTAssertEqual(unlessDomains, ["*github.com", "*substack.com"])
    }

    @MainActor
    func testTabHibernationAndMaxTabsInvariant() {
        let store = PrismStore.shared
        let first = store.openNewTab(url: "https://github.com", title: "GitHub")
        let second = store.openNewTab(url: "https://news.ycombinator.com", title: "HN")

        XCTAssertEqual(store.activeTabId, second.id)
        let firstState = store.tabs.first(where: { $0.id == first.id })
        let secondState = store.tabs.first(where: { $0.id == second.id })
        XCTAssertEqual(firstState?.isHibernated, true)
        XCTAssertEqual(secondState?.isHibernated, false)

        // Open up to beyond cap and verify cap holds
        for i in 0..<10 {
            _ = store.openNewTab(url: "https://example.com/\(i)", title: "Tab \(i)")
        }
        XCTAssertLessThanOrEqual(store.tabs.count, PrismTabState.maxOpenTabs)
        let activeTabsCount = store.tabs.filter { !$0.isHibernated }.count
        XCTAssertEqual(activeTabsCount, 1)
    }

    func testDeterministicCoPilotFallback() {
        let turn = PrismCoPilotService.shared.buildDeterministicTurn(
            displayPrompt: "✨ TL;DR Summary",
            pageTitle: "Benchmark Report",
            pageUrl: "https://example.com/bench",
            bodyText: """
            Prism reduces PostgREST egress by 92% through monotonic updated_at watermarks and client-side JPEG compression.

            Background tab hibernation keeps memory steady under 120 MB even across 8 open research tabs on macOS and iOS.
            """,
            selectedText: ""
        )
        XCTAssertFalse(turn.isAiGenerated)
        XCTAssertTrue(turn.responseMarkdown.contains("92%"))
        XCTAssertFalse(turn.keyBullets.isEmpty)
        XCTAssertFalse(turn.extractedTasks.isEmpty)
    }

    @MainActor
    func testLiveSupabaseSync() async throws {
        await PrismStore.shared.syncWithSupabase(forceFullPull: true)
        XCTAssertGreaterThanOrEqual(PrismStore.shared.allClips.count, 1)
        XCTAssertFalse(PrismStore.shared.clips.isEmpty)
    }
}
