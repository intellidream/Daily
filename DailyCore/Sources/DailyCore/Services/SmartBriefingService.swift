import Foundation
import Combine
import CryptoKit
import Supabase

/// Central multiplatform service orchestrating Smart Periodic Briefings across 4 daily slots.
/// Implements aggressive 0ms caching, local deterministic rule synthesis (Tier 1),
/// asynchronous Gemini Flash AI enhancement (Tier 2), and Supabase cloud sync.
@MainActor
public final class SmartBriefingService: ObservableObject {
    public static let shared = SmartBriefingService()

    // MARK: - Published State
    @Published public private(set) var activeBriefing: SmartBriefingRecord? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastGeneratedAt: Date? = nil
    @Published public private(set) var isAiGenerated: Bool = false
    @Published public var shouldPresentMorningAutomatically: Bool = false

    // MARK: - Storage Keys
    private let cacheStorageKey = "daily_smart_summary_cache_v2"
    private let lastAutoShownDateKey = "daily_briefing_last_auto_shown_date_v2"

    private var inMemoryCache: [BriefingTimeSlot: SmartBriefingRecord] = [:]
    private let supabase = SupabaseService.shared.client

    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? UserDefaults.standard
    }

    private init() {
        loadCachedBriefing()
    }

    // MARK: - Cache Management

    private func loadCachedBriefing() {
        guard let data = groupDefaults.data(forKey: cacheStorageKey),
              let record = try? JSONDecoder().decode(SmartBriefingRecord.self, from: data) else {
            return
        }
        self.inMemoryCache[record.slot] = record
        self.activeBriefing = record
        self.isAiGenerated = record.isAiGenerated
        self.lastGeneratedAt = record.updatedAt
    }

    private func saveCachedBriefing(_ record: SmartBriefingRecord) {
        self.inMemoryCache[record.slot] = record
        self.activeBriefing = record
        self.isAiGenerated = record.isAiGenerated
        self.lastGeneratedAt = record.updatedAt

        if let data = try? JSONEncoder().encode(record) {
            groupDefaults.set(data, forKey: cacheStorageKey)
        }
    }

    // MARK: - Public API

    /// Retrieves or generates a Smart Briefing.
    /// Fast-path returns in 0ms if cached metrics match current data and slot.
    public func getOrGenerateBriefing(forceRefresh: Bool = false) async -> SmartBriefingRecord {
        let currentSlot = BriefingTimeSlot.current()
        let metrics = collectCurrentMetrics()
        let activeStreams = TagdosStore.shared.streams.map(\.title)
        let hash = computeDataHash(slot: currentSlot, metrics: metrics, streamCount: activeStreams.count)

        // 1. Check local cache if not force refreshing
        if !forceRefresh, let cached = inMemoryCache[currentSlot], cached.dataHash == hash {
            self.activeBriefing = cached
            return cached
        }

        self.isLoading = true
        defer { self.isLoading = false }

        let firstName = AuthService.shared.currentUser?.firstName ?? "Friend"

        // 2. Tier 1: Instant Local Deterministic Synthesis (<5ms)
        let localNarrative = synthesizeLocalNarrative(
            slot: currentSlot,
            userName: firstName,
            metrics: metrics,
            activeStreams: activeStreams
        )

        var finalRecord = SmartBriefingRecord(
            id: UUID().uuidString,
            userId: AuthService.shared.currentUser?.id ?? "local_user",
            timeSlot: currentSlot.rawValue,
            dataHash: hash,
            narrative: localNarrative,
            metrics: metrics,
            isAiGenerated: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        // 3. Tier 2: AI Enhancement via Gemini Flash API (if key is present)
        let apiKey = SettingsService.shared.settings.geminiApiKey ?? ""
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let aiNarrative = try await GeminiApiService.shared.generateBriefing(
                    apiKey: apiKey,
                    slot: currentSlot,
                    userName: firstName,
                    metrics: metrics,
                    streamTitles: activeStreams
                )
                finalRecord.narrative = aiNarrative
                finalRecord.isAiGenerated = true
            } catch {
                // Seamlessly retain Tier 1 deterministic narrative on timeout or failure
                #if DEBUG
                print("[SmartBriefingService] Gemini enhancement failed/timed out, using Tier 1: \(error)")
                #endif
            }
        }

        // 4. Update memory and disk cache
        saveCachedBriefing(finalRecord)

        // 5. Asynchronously synchronize to Supabase
        Task { [weak self] in
            await self?.syncToSupabase(record: finalRecord)
        }

        return finalRecord
    }

    /// Evaluates whether the automatic morning briefing should be presented on app launch.
    /// Strictly executed after all 6 hub data sources have finished loading.
    public func checkAutomaticMorningPresentation() -> Bool {
        let settings = SettingsService.shared.settings
        guard settings.smartBriefingEnabled && settings.smartBriefingAutoMorning else {
            return false
        }

        let slot = BriefingTimeSlot.current()
        guard slot == .morning else {
            return false
        }

        let todayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        let lastShownDay = groupDefaults.string(forKey: lastAutoShownDateKey)

        let metrics = collectCurrentMetrics()
        let activeStreams = TagdosStore.shared.streams.map(\.title)
        let hash = computeDataHash(slot: slot, metrics: metrics, streamCount: activeStreams.count)

        // Show if not shown today, or if data hash changed since last show
        if lastShownDay != todayKey || (activeBriefing?.dataHash != hash) {
            groupDefaults.set(todayKey, forKey: lastAutoShownDateKey)
            self.shouldPresentMorningAutomatically = true
            return true
        }

        return false
    }

    // MARK: - Metrics Collection & Hashing

    public func collectCurrentMetrics() -> SmartBriefingMetrics {
        let weather = WeatherService.shared.currentWeather
        let health = HealthDataService.shared
        let habits = HabitsService.shared
        let finance = FinanceService.shared
        let tagdos = TagdosStore.shared
        let news = NewsService.shared

        let sleepDurationHours: Double? = {
            guard let session = health.primarySleepSession else { return nil }
            return Double(session.durationSeconds) / 3600.0
        }()

        let activeMemoCount = tagdos.streams.reduce(0) { count, stream in
            count + (stream.activeMemos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }

        return SmartBriefingMetrics(
            weatherTemp: weather?.main.temp,
            weatherCondition: weather?.weather.first?.description.capitalized,
            weatherIcon: weather?.weather.first?.icon,
            weatherCity: weather?.name.isEmpty == false ? weather?.name : "Bucharest",
            sleepScore: health.primarySleepSession?.sleepScore,
            sleepDurationHours: sleepDurationHours,
            restingBpm: health.restingBpm > 0 ? health.restingBpm : nil,
            totalStepsToday: health.totalStepsToday,
            waterMlToday: habits.waterTotalToday,
            waterGoalMl: habits.waterGoal,
            smokesToday: habits.smokesTotalToday,
            smokesBaseline: habits.smokesBaselineCount,
            netWorth: finance.summary.netWorth,
            daySpend: finance.summary.dayChange,
            activeStreamCount: tagdos.streams.count,
            activeMemoCount: activeMemoCount,
            topNewsTitle: news.articles.first?.title
        )
    }

    public func computeDataHash(slot: BriefingTimeSlot, metrics: SmartBriefingMetrics, streamCount: Int) -> String {
        let tempRounded = Int((metrics.weatherTemp ?? 20.0).rounded())
        let sleepRounded = metrics.sleepScore ?? 0
        let stepsBucket = metrics.totalStepsToday / 500
        let waterBucket = Int(metrics.waterMlToday / 100.0)
        let smokes = metrics.smokesToday
        let netWorthBucket = Int(metrics.netWorth / 50.0)

        let composite = "\(slot.rawValue)|\(tempRounded)|\(sleepRounded)|\(stepsBucket)|\(waterBucket)|\(smokes)|\(netWorthBucket)|\(streamCount)|\(metrics.topNewsTitle ?? "")"
        let digest = SHA256.hash(data: Data(composite.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Tier 1: Local Deterministic Synthesizer

    public func synthesizeLocalNarrative(
        slot: BriefingTimeSlot,
        userName: String,
        metrics: SmartBriefingMetrics,
        activeStreams: [String]
    ) -> SmartBriefingNarrative {
        // Greeting
        let greeting = "\(slot.greetingPrefix), \(userName)! Here is your unified \(slot.displayName.lowercased())."

        // Weather
        let tempString = metrics.weatherTemp.map { "\(Int($0.rounded()))°C" } ?? "pleasant temperatures"
        let condition = metrics.weatherCondition ?? "fair skies"
        let weatherAdvice: String
        switch slot {
        case .morning:
            weatherAdvice = "Expect \(condition) with \(tempString). Great conditions to plan your day."
        case .intraday:
            weatherAdvice = "Current conditions hold at \(tempString) and \(condition)."
        case .evening:
            weatherAdvice = "The day is winding down under \(condition) at \(tempString)."
        case .nightly:
            weatherAdvice = "Night air is steady around \(tempString)."
        }

        // Health & Vitals
        let healthAdvice: String
        let sleepScore = metrics.sleepScore ?? 82
        let steps = metrics.totalStepsToday
        if let sleepHrs = metrics.sleepDurationHours {
            let formattedHrs = String(format: "%.1fh", sleepHrs)
            if sleepScore >= 80 {
                healthAdvice = "Strong recovery recorded with \(formattedHrs) of sleep (Score \(sleepScore)/100). You've accumulated \(steps) steps so far."
            } else {
                healthAdvice = "Sleep reached \(formattedHrs) (Score \(sleepScore)/100). Keep physical strain balanced today and stay hydrated. Total steps: \(steps)."
            }
        } else {
            healthAdvice = "Activity is tracking with \(steps) steps recorded today."
        }

        // Habits & Cravings (Constructive Empathy for smoking reduction)
        let waterLiters = String(format: "%.1fL", metrics.waterMlToday / 1000.0)
        let waterGoalLiters = String(format: "%.1fL", metrics.waterGoalMl / 1000.0)
        let habitAdvice: String

        let smokes = metrics.smokesToday
        let baseline = metrics.smokesBaseline
        let smokesAdvice: String
        if smokes == 0 {
            smokesAdvice = "Zero smokes logged today—fantastic discipline and clean breathing."
        } else if smokes <= baseline {
            smokesAdvice = "Currently at \(smokes) smokes, safely maintaining below your daily baseline of \(baseline). Keep hydrating through cravings."
        } else {
            smokesAdvice = "Logged \(smokes) smokes today. Take a pause, breathe deeply, and focus on clean hydration for the rest of the day."
        }
        habitAdvice = "Hydration is at \(waterLiters) / \(waterGoalLiters). \(smokesAdvice)"

        // Finance
        let financeAdvice: String
        let formattedNetWorth = String(format: "$%.0f", metrics.netWorth)
        if metrics.daySpend != 0 {
            let sign = metrics.daySpend >= 0 ? "+" : ""
            financeAdvice = "Net worth stands at \(formattedNetWorth) with a net flow of \(sign)$\(Int(metrics.daySpend)) today."
        } else {
            financeAdvice = "Portfolio assets and net worth remain steady at \(formattedNetWorth)."
        }

        // TagDoS
        let tagdosAdvice: String
        let streamCount = activeStreams.count
        if streamCount > 0 {
            let memoInfo = metrics.activeMemoCount > 0 ? " with \(metrics.activeMemoCount) active memos to tackle" : ""
            tagdosAdvice = "\(streamCount) mental streams active\(memoInfo)."
        } else {
            tagdosAdvice = "TagDoS streams are calm with no pending bottlenecks."
        }

        // News
        let newsAdvice: String
        if let topHeadline = metrics.topNewsTitle, !topHeadline.isEmpty {
            newsAdvice = "Top headline in your radar: \"\(topHeadline)\"."
        } else {
            newsAdvice = ""
        }

        // Outro
        let outro: String
        switch slot {
        case .morning:
            outro = "Set your intentions, stay focused, and make today count."
        case .intraday:
            outro = "Keep this steady pace through the afternoon."
        case .evening:
            outro = "Reflect on today's progress and enjoy a restful evening."
        case .nightly:
            outro = "Power down your screens, restore your energy, and rest well."
        }

        return SmartBriefingNarrative(
            greeting: greeting,
            weatherText: weatherAdvice,
            healthText: healthAdvice,
            habitsText: habitAdvice,
            financeText: financeAdvice,
            tagdosText: tagdosAdvice,
            newsText: newsAdvice,
            outroText: outro
        )
    }

    // MARK: - Supabase Synchronization

    public func syncToSupabase(record: SmartBriefingRecord) async {
        guard AuthService.shared.isAuthenticated,
              let currentUserId = AuthService.shared.currentUser?.id else {
            return
        }

        var remoteRecord = record
        remoteRecord.userId = currentUserId

        do {
            try await supabase
                .from("daily_smart_summaries")
                .upsert(remoteRecord)
                .execute()
        } catch {
            #if DEBUG
            print("[SmartBriefingService] Cloud sync to daily_smart_summaries bypassed: \(error)")
            #endif
        }
    }
}
