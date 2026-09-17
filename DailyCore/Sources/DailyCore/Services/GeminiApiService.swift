import Foundation

/// High-speed client connecting to Google Gemini API (gemini-2.5-flash) for generative multi-hub briefing synthesis.
/// Features a strict 3.5s timeout guarantee and structured JSON response parsing.
public final class GeminiApiService: @unchecked Sendable {
    public static let shared = GeminiApiService()

    private let primaryModel = "gemini-2.5-flash"
    private let fallbackModel = "gemini-1.5-flash"
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3.5
        config.timeoutIntervalForResource = 3.5
        self.session = URLSession(configuration: config)
    }

    /// Generates structured narrative via Gemini Flash API, returning a typed SmartBriefingNarrative.
    public func generateBriefing(
        apiKey: String,
        slot: BriefingTimeSlot,
        userName: String,
        metrics: SmartBriefingMetrics,
        streamTitles: [String] = [],
        topPills: [String] = [],
        closingWish: String? = nil,
        closingIcon: String? = nil
    ) async throws -> SmartBriefingNarrative {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw NSError(domain: "GeminiApiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Gemini API key is empty"])
        }

        let systemInstruction = """
        You are DayOne, a refined, proactive, and deeply supportive personal intelligence companion.
        Your task is to craft a dense, inspiring, and actionable \(slot.displayName) for \(userName).

        Guidelines:
        1. Address \(userName) directly in natural, warm, second-person language.
        2. Synthesize all 6 life areas based on the provided JSON telemetry: Weather, Health/Sleep, Habits, Finances, Tagdos, and News.
        3. Habit Coaching Directive: Treat smoking/heaters as a habit to consciously reduce. If smokes count is low or below baseline, warmly congratulate the discipline. Never encourage smoking. Encourage hydration and mindful breathing during cravings.
        4. Sleep & Health: Report sleep and recovery truthfully based on provided telemetry. If sleep data is not yet recorded for today, note that vitals are syncing or focus on current activity and resting heart rate without inventing numbers.
        5. Finances: All currency is Romanian Lei ("Lei"). State net worth and flows in Lei with dot separators (e.g. "127.156 Lei"). Never output dollar signs ($).
        6. Tagdos: Provide actionable focus on the driving pills to solve today (e.g. "Uite, asta ai de rezolvat azi: [key pills]"). Do not merely count streams.
        7. Tone: Calm, encouraging, succinct. Avoid conversational filler or mentioning prompt rules.
        8. Return strictly a single JSON object matching this schema:
        {
          "greeting": "A warm, personalized 1-line greeting with date context",
          "weatherText": "Concise atmosphere & outfit recommendation based on weather",
          "healthText": "Recovery analysis correlating sleep score, resting HR, and activity",
          "habitsText": "Empathetic hydration progress and supportive craving reduction advice",
          "financeText": "Summary of monthly flow, net worth in Lei, and financial clarity",
          "tagdosText": "Focus priority for active Tagdos pills (e.g. 'Uite, asta ai de rezolvat azi: ...')",
          "newsText": "1-sentence perspective on the top headline, if present",
          "outroText": "1-line empowering closing sentence"
        }
        """

        var healthPayload: [String: Any] = [
            "stepsToday": metrics.totalStepsToday
        ]
        if let score = metrics.sleepScore { healthPayload["sleepScore"] = score }
        if let hours = metrics.sleepDurationHours { healthPayload["sleepHours"] = hours }
        if let bpm = metrics.restingBpm { healthPayload["restingBpm"] = bpm }

        let promptPayload: [String: Any] = [
            "timeSlot": slot.rawValue,
            "userName": userName,
            "weather": [
                "temp": metrics.weatherTemp ?? 20.0,
                "unit": "°C",
                "condition": metrics.weatherCondition ?? "Clear",
                "city": metrics.weatherCity ?? "Current Location"
            ],
            "health": healthPayload,
            "habits": [
                "waterMlToday": metrics.waterMlToday,
                "waterGoalMl": metrics.waterGoalMl,
                "smokesToday": metrics.smokesToday,
                "smokesBaseline": metrics.smokesBaseline
            ],
            "finances": [
                "currency": "Lei",
                "netWorth": metrics.netWorth,
                "daySpend": metrics.daySpend
            ],
            "tagdos": [
                "activeStreams": streamTitles,
                "topPillsToTackle": topPills,
                "activeMemosCount": metrics.activeMemoCount
            ],
            "newsHeadline": metrics.topNewsTitle ?? ""
        ]

        let userPromptData = try JSONSerialization.data(withJSONObject: promptPayload, options: [])
        let userPromptString = String(data: userPromptData, encoding: .utf8) ?? "{}"

        do {
            var result = try await executeGenerateContent(
                model: primaryModel,
                apiKey: trimmedKey,
                systemInstruction: systemInstruction,
                userPrompt: userPromptString
            )
            result.closingWish = closingWish
            result.closingIcon = closingIcon
            return result
        } catch {
            // Fallback to secondary model if primary encounters model version mismatch
            var result = try await executeGenerateContent(
                model: fallbackModel,
                apiKey: trimmedKey,
                systemInstruction: systemInstruction,
                userPrompt: userPromptString
            )
            result.closingWish = closingWish
            result.closingIcon = closingIcon
            return result
        }
    }

    private func executeGenerateContent(
        model: String,
        apiKey: String,
        systemInstruction: String,
        userPrompt: String
    ) async throws -> SmartBriefingNarrative {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt]]
                ]
            ],
            "systemInstruction": [
                "parts": [["text": systemInstruction]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.35,
                "maxOutputTokens": 1024
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
            throw NSError(domain: "GeminiApiService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let rawJsonText = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
            throw NSError(domain: "GeminiApiService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Empty text candidate in Gemini response"])
        }

        // Clean any accidental markdown json block delimiters
        let cleanedJson = rawJsonText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)

        guard let narrativeData = cleanedJson.data(using: .utf8) else {
            throw NSError(domain: "GeminiApiService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Failed to convert Gemini response to UTF-8 data"])
        }

        return try JSONDecoder().decode(SmartBriefingNarrative.self, from: narrativeData)
    }
}
