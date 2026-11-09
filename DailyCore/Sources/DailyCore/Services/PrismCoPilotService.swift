import Foundation

/// Hybrid AI & Deterministic Assisted Web Exploration engine for Prism (`gemini-2.5-flash` + offline extractive fallback).
public final class PrismCoPilotService: @unchecked Sendable {
    public static let shared = PrismCoPilotService()

    private let primaryModel = "gemini-2.5-flash"
    private let fallbackModel = "gemini-1.5-flash"
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12.0
        config.timeoutIntervalForResource = 14.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - Preset 1-Tap Actions & Freeform Page Q&A

    public func runAction(
        _ action: PrismCoPilotAction,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String = "",
        apiKey: String?
    ) async -> PrismCoPilotTurn {
        let promptLabel: String
        switch action {
        case .tldr:
            promptLabel = "✨ TL;DR Summary"
        case .extractTasks:
            promptLabel = "🎯 Extract Actionable Tasks"
        case .keyFacts:
            promptLabel = "📊 Key Facts & Numbers"
        case .explainSelection:
            promptLabel = selectedText.isEmpty ? "🔍 Explain Key Concepts" : "🔍 Explain: \"\(String(selectedText.prefix(80)))\""
        }

        let instruction: String
        switch action {
        case .tldr:
            instruction = "Provide a crisp executive summary of this web page in 2-3 sentences, followed by up to 5 high-signal bullet takeaways."
        case .extractTasks:
            instruction = "Identify concrete, actionable next steps, checklists, or follow-ups from this page. Return concise bullets AND short 3-6 word task items suitable for a personal task manager."
        case .keyFacts:
            instruction = "Extract the most important quantitative metrics, prices, dates, benchmarks, specs, or factual claims from this page."
        case .explainSelection:
            if !selectedText.isEmpty {
                instruction = "Explain the selected passage clearly and concisely in the context of the page, highlighting why it matters: \"\(selectedText)\""
            } else {
                instruction = "Explain the core technical or conceptual ideas on this page in clear, accessible language."
            }
        }

        return await executeAssistedTurn(
            displayPrompt: promptLabel,
            instruction: instruction,
            pageTitle: pageTitle,
            pageUrl: pageUrl,
            bodyText: bodyText,
            selectedText: selectedText,
            apiKey: apiKey
        )
    }

    public func askQuestion(
        question: String,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String = "",
        apiKey: String?
    ) async -> PrismCoPilotTurn {
        let cleanQ = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQ.isEmpty else {
            return buildDeterministicTurn(
                displayPrompt: "Overview",
                pageTitle: pageTitle,
                pageUrl: pageUrl,
                bodyText: bodyText,
                selectedText: selectedText
            )
        }

        return await executeAssistedTurn(
            displayPrompt: cleanQ,
            instruction: "Answer the user's question accurately grounded in the provided web page content. User Question: \(cleanQ)",
            pageTitle: pageTitle,
            pageUrl: pageUrl,
            bodyText: bodyText,
            selectedText: selectedText,
            apiKey: apiKey
        )
    }

    // MARK: - Gemini 2.5 Flash Execution + Deterministic Fallback

    private func executeAssistedTurn(
        displayPrompt: String,
        instruction: String,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String,
        apiKey: String?
    ) async -> PrismCoPilotTurn {
        let trimmedKey = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            do {
                return try await requestGeminiTurn(
                    model: primaryModel,
                    apiKey: trimmedKey,
                    displayPrompt: displayPrompt,
                    instruction: instruction,
                    pageTitle: pageTitle,
                    pageUrl: pageUrl,
                    bodyText: bodyText,
                    selectedText: selectedText
                )
            } catch {
                if let fallbackTurn = try? await requestGeminiTurn(
                    model: fallbackModel,
                    apiKey: trimmedKey,
                    displayPrompt: displayPrompt,
                    instruction: instruction,
                    pageTitle: pageTitle,
                    pageUrl: pageUrl,
                    bodyText: bodyText,
                    selectedText: selectedText
                ) {
                    return fallbackTurn
                }
            }
        }

        return buildDeterministicTurn(
            displayPrompt: displayPrompt,
            pageTitle: pageTitle,
            pageUrl: pageUrl,
            bodyText: bodyText,
            selectedText: selectedText
        )
    }

    private struct GeminiTurnResponse: Decodable {
        let summary: String
        let bullets: [String]?
        let tasks: [String]?
    }

    private struct RawGeminiEnvelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    private func requestGeminiTurn(
        model: String,
        apiKey: String,
        displayPrompt: String,
        instruction: String,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String
    ) async throws -> PrismCoPilotTurn {
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw URLError(.badURL)
        }

        let systemText = """
        You are Prism Co-Pilot inside DayOne, an intelligent research assistant.
        Respond in the same language as the user's question (or clear English if using a preset chip unless the page is in Romanian, in which case match the page's language naturally).
        Return strictly a valid JSON object matching this schema:
        {
          "summary": "Concise 2-4 sentence direct response or synthesis",
          "bullets": ["Up to 5 crisp, high-signal bullet points"],
          "tasks": ["Optional 0 to 4 short actionable items (max 50 chars each) if relevant"]
        }
        """

        let truncatedBody = String(bodyText.prefix(15000))
        let userContext = """
        Task: \(instruction)
        Page Title: \(pageTitle)
        URL: \(pageUrl)
        Selected Text: \(selectedText.isEmpty ? "(none)" : String(selectedText.prefix(2500)))
        Page Content:
        \(truncatedBody)
        """

        let bodyDict: [String: Any] = [
            "system_instruction": ["parts": [["text": systemText]]],
            "contents": [["role": "user", "parts": [["text": userContext]]]],
            "generationConfig": [
                "temperature": 0.3,
                "responseMimeType": "application/json"
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let envelope = try JSONDecoder().decode(RawGeminiEnvelope.self, from: data)
        guard var rawText = envelope.candidates?.first?.content?.parts?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawText.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        if rawText.hasPrefix("```") {
            rawText = rawText
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let parsed = try JSONDecoder().decode(GeminiTurnResponse.self, from: Data(rawText.utf8))
        return PrismCoPilotTurn(
            prompt: displayPrompt,
            responseMarkdown: parsed.summary,
            keyBullets: parsed.bullets ?? [],
            extractedTasks: parsed.tasks ?? [],
            sourceUrl: pageUrl,
            pageTitle: pageTitle,
            isAiGenerated: true
        )
    }

    // MARK: - Local Deterministic Extractive Synthesizer (Zero-Latency / Offline)

    public func buildDeterministicTurn(
        displayPrompt: String,
        pageTitle: String,
        pageUrl: String,
        bodyText: String,
        selectedText: String
    ) -> PrismCoPilotTurn {
        let source = !selectedText.isEmpty ? selectedText : bodyText
        let paragraphs = source
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 45 }

        let leadSummary: String
        if let first = paragraphs.first {
            leadSummary = String(first.prefix(320))
        } else if !selectedText.isEmpty {
            leadSummary = selectedText
        } else {
            leadSummary = "Captured context from \(pageTitle.isEmpty ? PrismSearchEngine.extractCleanDomain(from: pageUrl) : pageTitle)."
        }

        // Prefer sentences with numbers/metrics or clear informative structure
        let candidateBullets = Array(
            paragraphs
                .dropFirst()
                .sorted { lhs, rhs in
                    let lHasNum = lhs.rangeOfCharacter(from: .decimalDigits) != nil ? 1 : 0
                    let rHasNum = rhs.rangeOfCharacter(from: .decimalDigits) != nil ? 1 : 0
                    if lHasNum != rHasNum { return lHasNum > rHasNum }
                    return lhs.count > rhs.count
                }
                .prefix(4)
                .map { String($0.prefix(180)) }
        )

        let domain = PrismSearchEngine.extractCleanDomain(from: pageUrl)
        let defaultTask = "Review \(pageTitle.isEmpty ? domain : String(pageTitle.prefix(34)))"

        return PrismCoPilotTurn(
            prompt: displayPrompt,
            responseMarkdown: leadSummary,
            keyBullets: candidateBullets,
            extractedTasks: [defaultTask],
            sourceUrl: pageUrl,
            pageTitle: pageTitle,
            isAiGenerated: false
        )
    }
}
