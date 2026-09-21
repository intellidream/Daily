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
    @Published public var isBriefingPresented: Bool = false
    @Published public private(set) var hasUnreadBrief: Bool = false

    // MARK: - Storage Keys
    private let cacheStorageKey = "daily_smart_summary_cache_v4"
    private let lastAutoShownDateKey = "daily_briefing_last_auto_shown_date_v2"
    private let lastReadDataHashKey = "daily_briefing_last_read_hash_v2"

    private var inMemoryCache: [BriefingTimeSlot: SmartBriefingRecord] = [:]
    private let supabase = SupabaseService.shared.client

    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? UserDefaults.standard
    }

    public var hasBriefingAvailable: Bool {
        activeBriefing != nil
    }

    public func markBriefingAsRead() {
        if let current = activeBriefing {
            groupDefaults.set(current.dataHash, forKey: lastReadDataHashKey)
        }
        let todayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        groupDefaults.set(todayKey, forKey: lastAutoShownDateKey)
        self.hasUnreadBrief = false
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
        let currentSlot = BriefingTimeSlot.current()
        // Strictly prevent loading stale records from a previous time slot or day into activeBriefing
        if record.slot == currentSlot && Calendar.current.isDateInToday(record.createdAt) {
            self.inMemoryCache[record.slot] = record
            self.activeBriefing = record
            self.isAiGenerated = record.isAiGenerated
            self.lastGeneratedAt = record.updatedAt
            let lastRead = groupDefaults.string(forKey: lastReadDataHashKey)
            self.hasUnreadBrief = (lastRead != record.dataHash)
        }
    }

    private func saveCachedBriefing(_ record: SmartBriefingRecord) {
        self.inMemoryCache[record.slot] = record
        self.activeBriefing = record
        self.isAiGenerated = record.isAiGenerated
        self.lastGeneratedAt = record.updatedAt
        let lastRead = groupDefaults.string(forKey: lastReadDataHashKey)
        self.hasUnreadBrief = (lastRead != record.dataHash)

        if let data = try? JSONEncoder().encode(record) {
            groupDefaults.set(data, forKey: cacheStorageKey)
        }
    }

    // MARK: - Public API

    /// Retrieves or generates a Smart Briefing.
    /// Fast-path returns in 0ms if cached metrics match current data, slot, and day.
    public func getOrGenerateBriefing(forceRefresh: Bool = false) async -> SmartBriefingRecord {
        let currentSlot = BriefingTimeSlot.current()
        if WeatherService.shared.currentWeather == nil {
            await WeatherService.shared.refreshWeather(force: false)
        }
        let metrics = collectCurrentMetrics()
        let activeStreams = TagdosStore.shared.streams.map(\.title)
        let hash = computeDataHash(slot: currentSlot, metrics: metrics, streamCount: activeStreams.count)

        // 1. Check local cache if not force refreshing, strictly matching slot and date
        if !forceRefresh,
           let cached = inMemoryCache[currentSlot],
           cached.dataHash == hash,
           cached.slot == currentSlot,
           Calendar.current.isDateInToday(cached.createdAt),
           !cached.narrative.stressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.activeBriefing = cached
            return cached
        }

        self.isLoading = true
        defer { self.isLoading = false }

        let firstName = AuthService.shared.currentUser?.firstName ?? "Friend"

        // 2. Extract leading uncompleted pills for Tagdos focus
        let topPills = extractTopPills()

        // 3. Tier 1: Instant Local Deterministic Synthesis (<5ms)
        let localNarrative = synthesizeLocalNarrative(
            slot: currentSlot,
            userName: firstName,
            metrics: metrics,
            activeStreams: activeStreams,
            topPills: topPills
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

        // 4. Tier 2: AI Enhancement via Gemini Flash API (if key is present)
        let apiKey = SettingsService.shared.settings.geminiApiKey ?? ""
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let aiNarrative = try await GeminiApiService.shared.generateBriefing(
                    apiKey: apiKey,
                    slot: currentSlot,
                    userName: firstName,
                    metrics: metrics,
                    streamTitles: activeStreams,
                    topPills: topPills,
                    closingWish: localNarrative.closingWish,
                    closingIcon: localNarrative.closingIcon
                )
                let mergedNarrative = SmartBriefingNarrative(
                    greeting: aiNarrative.greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.greeting : aiNarrative.greeting,
                    weatherText: aiNarrative.weatherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.weatherText : aiNarrative.weatherText,
                    healthText: aiNarrative.healthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.healthText : aiNarrative.healthText,
                    stressText: aiNarrative.stressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.stressText : aiNarrative.stressText,
                    habitsText: aiNarrative.habitsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.habitsText : aiNarrative.habitsText,
                    financeText: aiNarrative.financeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.financeText : aiNarrative.financeText,
                    tagdosText: aiNarrative.tagdosText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.tagdosText : aiNarrative.tagdosText,
                    newsText: aiNarrative.newsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.newsText : aiNarrative.newsText,
                    outroText: aiNarrative.outroText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localNarrative.outroText : aiNarrative.outroText,
                    closingWish: (aiNarrative.closingWish?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? localNarrative.closingWish : aiNarrative.closingWish,
                    closingIcon: (aiNarrative.closingIcon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? localNarrative.closingIcon : aiNarrative.closingIcon
                )
                finalRecord.narrative = mergedNarrative
                finalRecord.isAiGenerated = true
            } catch {
                // Seamlessly retain Tier 1 deterministic narrative on timeout or failure
                #if DEBUG
                print("[SmartBriefingService] Gemini enhancement failed/timed out, using Tier 1: \(error)")
                #endif
            }
        }

        // 5. Update memory and disk cache
        saveCachedBriefing(finalRecord)

        // 6. Asynchronously synchronize to Supabase
        Task { [weak self] in
            await self?.syncToSupabase(record: finalRecord)
        }

        return finalRecord
    }

    /// Evaluates whether the automatic morning briefing should be presented on app launch.
    /// Strictly executed after all 6 hub data sources have finished loading.
    public func checkAutomaticMorningPresentation() async -> Bool {
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

        // Strictly present automatically only once per day
        guard lastShownDay != todayKey else {
            return false
        }

        groupDefaults.set(todayKey, forKey: lastAutoShownDateKey)
        // Pre-generate the fresh morning briefing with updated hub metrics before showing
        _ = await getOrGenerateBriefing(forceRefresh: true)
        self.shouldPresentMorningAutomatically = true
        self.isBriefingPresented = true
        return true
    }

    // MARK: - Metrics Collection & Hashing

    public func collectCurrentMetrics() -> SmartBriefingMetrics {
        let weather = WeatherService.shared.currentWeather
        let locationName = WeatherService.shared.currentLocationName
        let health = HealthDataService.shared
        let habits = HabitsService.shared
        let ledger = SmartLedgerStore.shared.parsedLedger
        let tagdos = TagdosStore.shared
        let news = NewsService.shared

        let primarySession = health.primarySleepSession
        let sleepDurationHours: Double? = {
            guard let session = primarySession else { return nil }
            return Double(session.asleepSeconds) / 3600.0
        }()
        let sleepDurationFormatted: String? = primarySession?.totalAsleepFormatted

        let activeMemoCount = tagdos.streams.reduce(0) { count, stream in
            count + (stream.activeMemos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }

        let resolvedCity: String = {
            if locationName != "Detecting..." && !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return locationName
            }
            if let name = weather?.name, !name.isEmpty {
                return name
            }
            return "Bucharest"
        }()

        return SmartBriefingMetrics(
            weatherTemp: weather?.main.temp,
            weatherCondition: weather?.weather.first?.description.capitalized,
            weatherIcon: weather?.weather.first?.icon,
            weatherCity: resolvedCity,
            sleepScore: primarySession?.sleepScore,
            sleepDurationHours: sleepDurationHours,
            sleepDurationFormatted: sleepDurationFormatted,
            restingBpm: health.restingBpm > 0 ? health.restingBpm : nil,
            totalStepsToday: health.totalStepsToday,
            waterMlToday: habits.totalWaterMlToday,
            waterGoalMl: habits.waterGoalMl,
            smokesToday: habits.totalSmokesToday,
            smokesBaseline: habits.smokesBaselineCount,
            netWorth: ledger.netWorth,
            daySpend: ledger.outgoingTotal,
            activeStreamCount: tagdos.streams.count,
            activeMemoCount: activeMemoCount,
            topNewsTitle: news.topHeadline?.title ?? news.articles.first?.title,
            stressScore: health.currentStressScore,
            stressStatus: health.currentStressLevel.displayName,
            monkeyMood: health.stressAnalysis?.monkeyMood.displayName
        )
    }

    public func computeDataHash(slot: BriefingTimeSlot, metrics: SmartBriefingMetrics, streamCount: Int) -> String {
        let tempRounded = Int((metrics.weatherTemp ?? 20.0).rounded())
        let sleepRounded = metrics.sleepScore ?? 0
        let stepsBucket = metrics.totalStepsToday / 500
        let waterBucket = Int(metrics.waterMlToday / 100.0)
        let smokes = metrics.smokesToday
        let netWorthBucket = Int(metrics.netWorth / 50.0)
        let stressBucket = (metrics.stressScore ?? 35) / 5

        let composite = "\(slot.rawValue)|\(tempRounded)|\(sleepRounded)|\(stepsBucket)|\(waterBucket)|\(smokes)|\(netWorthBucket)|\(streamCount)|\(metrics.topNewsTitle ?? "")|\(stressBucket)"
        let digest = SHA256.hash(data: Data(composite.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts prioritized actionable pills across active Tagdos streams.
    public func extractTopPills() -> [String] {
        let streams = TagdosStore.shared.streams
        var pills: [String] = []

        // 1. Prioritize urgent uncompleted pills
        for stream in streams {
            for pill in stream.activePills where pill.type == .urgent {
                let trimmed = pill.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !pills.contains(trimmed) {
                    pills.append(trimmed)
                }
            }
        }

        // 2. Add driving pills from each active stream
        for stream in streams {
            if let driving = stream.drivingPill?.rawText.trimmingCharacters(in: .whitespacesAndNewlines),
               !driving.isEmpty,
               !pills.contains(driving) {
                pills.append(driving)
            }
            if pills.count >= 4 { break }
        }

        // 3. Fallback to any active uncompleted pills
        if pills.isEmpty {
            for stream in streams {
                for pill in stream.activePills {
                    let trimmed = pill.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !pills.contains(trimmed) {
                        pills.append(trimmed)
                    }
                    if pills.count >= 4 { break }
                }
                if pills.count >= 4 { break }
            }
        }

        return pills
    }

    // MARK: - Tier 1: Local Deterministic Synthesizer

    public func synthesizeLocalNarrative(
        slot: BriefingTimeSlot,
        userName: String,
        metrics: SmartBriefingMetrics,
        activeStreams: [String],
        topPills: [String] = []
    ) -> SmartBriefingNarrative {
        // Greeting
        let greeting = "\(slot.diurnalGreeting(for: userName)) Here is your integrated daily briefing."

        // Weather & Rain Detection
        let tempString = metrics.weatherTemp.map { "\(Int($0.rounded()))°C" } ?? "pleasant temperatures"
        let condition = metrics.weatherCondition ?? "clear skies"
        let condLower = condition.lowercased()
        let isRaining = condLower.contains("rain") || condLower.contains("ploaie") || condLower.contains("drizzle") || condLower.contains("thunderstorm") || condLower.contains("averse")

        let weatherAdvice: String
        if isRaining {
            weatherAdvice = "It's \(tempString) outside with \(condition). Don't forget an umbrella if you head out today."
        } else {
            switch slot {
            case .morning:
                weatherAdvice = "Conditions show \(condition) at \(tempString). Great weather to plan your day."
            case .intraday:
                weatherAdvice = "Weather holds steady with \(condition) around \(tempString)."
            case .evening:
                weatherAdvice = "The evening winds down peacefully with \(condition) at \(tempString)."
            case .nightly:
                weatherAdvice = "Night air is calm around \(tempString)."
            }
        }

        // Contextual Closing Wish
        let closingWish: String
        let closingIcon: String
        if isRaining {
            closingWish = "Grab an umbrella today! :))"
            closingIcon = "umbrella.fill"
        } else {
            closingWish = slot.defaultClosingWish
            closingIcon = slot.defaultClosingIcon
        }

        // Health & Vitals
        let healthAdvice: String
        let steps = metrics.totalStepsToday
        let formattedAsleep: String? = {
            if let f = metrics.sleepDurationFormatted, !f.isEmpty, f != "--" {
                return f
            }
            if let h = metrics.sleepDurationHours, h > 0 {
                let totalMin = Int(round(h * 60.0))
                let hrs = totalMin / 60
                let mins = totalMin % 60
                return mins > 0 ? "\(hrs)h \(mins)m" : "\(hrs)h"
            }
            return nil
        }()

        if let sleepScore = metrics.sleepScore, let sleepText = formattedAsleep {
            if sleepScore >= 80 {
                if steps > 500 {
                    healthAdvice = "Great recovery with \(sleepText) asleep (Score \(sleepScore)/100). You've already logged \(steps) steps."
                } else {
                    healthAdvice = "Great recovery with \(sleepText) asleep (Score \(sleepScore)/100). Ready for a focused, high-energy day."
                }
            } else {
                healthAdvice = "Logged \(sleepText) asleep (Score \(sleepScore)/100). Maintain a steady pace and stay well hydrated."
            }
        } else if steps > 500 {
            let bpmInfo = (metrics.restingBpm ?? 0) > 0 ? ", with resting heart rate at \(Int(metrics.restingBpm!)) bpm" : ""
            healthAdvice = "Activity in full stride with \(steps) steps logged today\(bpmInfo)."
        } else {
            let bpmInfo = (metrics.restingBpm ?? 0) > 0 ? "Resting heart rate is at \(Int(metrics.restingBpm!)) bpm." : "Recovery vitals are syncing as your day gets underway."
            healthAdvice = bpmInfo
        }

        // Habits & Cravings
        let waterLiters = String(format: "%.1fL", metrics.waterMlToday / 1000.0)
        let waterGoalLiters = String(format: "%.1fL", metrics.waterGoalMl / 1000.0)
        let habitAdvice: String

        let smokes = metrics.smokesToday
        let baseline = metrics.smokesBaseline
        let smokesAdvice: String
        if smokes == 0 {
            if slot == .morning {
                smokesAdvice = "Start the day with a glass of water and keep cravings at zero."
            } else {
                smokesAdvice = "Zero cigarettes logged—excellent discipline for your health."
            }
        } else if smokes <= baseline {
            smokesAdvice = "\(smokes) cigarettes logged, staying below your daily limit (\(baseline)). Stay hydrated whenever a craving hits."
        } else {
            smokesAdvice = "\(smokes) cigarettes logged today. Take a deep breath, pause, and focus on clean hydration for the rest of the day."
        }

        if metrics.waterMlToday > 0 {
            habitAdvice = "Hydration is at \(waterLiters) / \(waterGoalLiters). \(smokesAdvice)"
        } else {
            habitAdvice = smokesAdvice
        }

        // Finance (Romanian Lei from SmartLedgerStore)
        let financeAdvice: String
        let numFormatter = NumberFormatter()
        numFormatter.numberStyle = .decimal
        numFormatter.groupingSeparator = "."
        numFormatter.maximumFractionDigits = 0
        let formattedNetWorth = "\(numFormatter.string(from: NSNumber(value: metrics.netWorth)) ?? "\(Int(metrics.netWorth))") Lei"

        let ledger = SmartLedgerStore.shared.parsedLedger
        if ledger.incomingTotal > 0 || ledger.outgoingTotal > 0 {
            let inK = String(format: "%.1fk", ledger.incomingTotal / 1000.0)
            let outK = String(format: "%.1fk", ledger.outgoingTotal / 1000.0)
            financeAdvice = "Net worth stands at \(formattedNetWorth), with monthly flow at \(inK) / \(outK) Lei."
        } else {
            financeAdvice = "Liquid reserves and portfolio hold steady at \(formattedNetWorth)."
        }

        // Tagdos Actionable Directive
        let tagdosAdvice: String
        let resolvedPills = topPills.isEmpty ? extractTopPills() : topPills
        if !resolvedPills.isEmpty {
            tagdosAdvice = "Here's what needs your focus today: \(resolvedPills.prefix(3).joined(separator: ", "))."
        } else if activeStreams.count > 0 {
            tagdosAdvice = "All Tagdos streams are up to date with no active blockers."
        } else {
            tagdosAdvice = "Tagdos streams are clear with no pending tasks."
        }

        // News
        let newsAdvice: String
        if let topHeadline = metrics.topNewsTitle, !topHeadline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newsAdvice = "Top headline on your radar: \"\(topHeadline)\"."
        } else {
            newsAdvice = ""
        }

        // Outro
        let outro: String
        switch slot {
        case .morning:
            outro = "Set your intentions, stay focused, and make today count."
        case .intraday:
            outro = "Keep up this steady momentum through the afternoon."
        case .evening:
            outro = "Reflect on today's milestones and enjoy a restful evening."
        case .nightly:
            outro = "Power down screens, recharge your energy, and sleep peacefully."
        }

        // Stress & Autonomic Balance (voiced by Monkey Mascot)
        let stressAdvice: String
        let sScore = metrics.stressScore ?? 32
        let sMood = metrics.monkeyMood ?? "Curious Monkey"
        if sScore <= 25 {
            stressAdvice = "Stress is Restful (\(sScore)/100). Zen Monkey says: You're in peak recovery mode — wonderful flow for deep, creative tasks!"
        } else if sScore <= 50 {
            stressAdvice = "Stress is Calm (\(sScore)/100). Curious Monkey says: Autonomic tone is balanced. Keep this steady groove going with a sip of water."
        } else if sScore <= 75 {
            stressAdvice = "Stress is Moderate (\(sScore)/100). Busy Monkey says: Tension is building up. Take a 3-minute screen break and try Box Breathing."
        } else {
            stressAdvice = "Stress is High (\(sScore)/100). Overheated Monkey says: High sympathetic arousal detected! Take 3 Physiological Sighs right now (double nose inhale, long mouth exhale)."
        }

        return SmartBriefingNarrative(
            greeting: greeting,
            weatherText: weatherAdvice,
            healthText: healthAdvice,
            stressText: stressAdvice,
            habitsText: habitAdvice,
            financeText: financeAdvice,
            tagdosText: tagdosAdvice,
            newsText: newsAdvice,
            outroText: outro,
            closingWish: closingWish,
            closingIcon: closingIcon
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
