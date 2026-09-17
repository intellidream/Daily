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
        let currentSlot = BriefingTimeSlot.current()
        // Strictly prevent loading stale records from a previous time slot or day into activeBriefing
        if record.slot == currentSlot && Calendar.current.isDateInToday(record.createdAt) {
            self.inMemoryCache[record.slot] = record
            self.activeBriefing = record
            self.isAiGenerated = record.isAiGenerated
            self.lastGeneratedAt = record.updatedAt
        }
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
    /// Fast-path returns in 0ms if cached metrics match current data, slot, and day.
    public func getOrGenerateBriefing(forceRefresh: Bool = false) async -> SmartBriefingRecord {
        let currentSlot = BriefingTimeSlot.current()
        let metrics = collectCurrentMetrics()
        let activeStreams = TagdosStore.shared.streams.map(\.title)
        let hash = computeDataHash(slot: currentSlot, metrics: metrics, streamCount: activeStreams.count)

        // 1. Check local cache if not force refreshing, strictly matching slot and date
        if !forceRefresh,
           let cached = inMemoryCache[currentSlot],
           cached.dataHash == hash,
           cached.slot == currentSlot,
           Calendar.current.isDateInToday(cached.createdAt) {
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
                finalRecord.narrative = aiNarrative
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

        let metrics = collectCurrentMetrics()
        let activeStreams = TagdosStore.shared.streams.map(\.title)
        let hash = computeDataHash(slot: slot, metrics: metrics, streamCount: activeStreams.count)

        // Show if not shown today, or if data hash changed since last show
        if lastShownDay != todayKey || (activeBriefing?.dataHash != hash) {
            groupDefaults.set(todayKey, forKey: lastAutoShownDateKey)
            // Pre-generate the fresh morning briefing with updated hub metrics before showing
            _ = await getOrGenerateBriefing(forceRefresh: true)
            self.shouldPresentMorningAutomatically = true
            return true
        }

        return false
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

        let sleepDurationHours: Double? = {
            guard let session = health.primarySleepSession else { return nil }
            return Double(session.durationSeconds) / 3600.0
        }()

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
            sleepScore: health.primarySleepSession?.sleepScore,
            sleepDurationHours: sleepDurationHours,
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
            topNewsTitle: news.topHeadline?.title ?? news.articles.first?.title
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
        let greeting = "\(slot.diurnalGreeting(for: userName)) Iată sumarul tău integrat."

        // Weather & Rain Detection
        let tempString = metrics.weatherTemp.map { "\(Int($0.rounded()))°C" } ?? "temperaturi plăcute"
        let condition = metrics.weatherCondition ?? "cer senin"
        let condLower = condition.lowercased()
        let isRaining = condLower.contains("rain") || condLower.contains("ploaie") || condLower.contains("drizzle") || condLower.contains("thunderstorm") || condLower.contains("averse")

        let weatherAdvice: String
        if isRaining {
            weatherAdvice = "Afară sunt \(tempString) cu \(condition). Nu uita să iei o umbrelă dacă ieși azi."
        } else {
            switch slot {
            case .morning:
                weatherAdvice = "Condiții de \(condition) cu \(tempString). O atmosferă excelentă pentru a-ți planifica ziua."
            case .intraday:
                weatherAdvice = "Vremea se menține cu \(condition) la \(tempString)."
            case .evening:
                weatherAdvice = "Ziua se încheie liniștit sub \(condition) la \(tempString)."
            case .nightly:
                weatherAdvice = "Aerul nopții este constant în jurul a \(tempString)."
            }
        }

        // Contextual Closing Wish
        let closingWish: String
        let closingIcon: String
        if isRaining {
            closingWish = "Ia o umbrelă azi :))"
            closingIcon = "umbrella.fill"
        } else {
            closingWish = slot.defaultClosingWish
            closingIcon = slot.defaultClosingIcon
        }

        // Health & Vitals
        let healthAdvice: String
        let steps = metrics.totalStepsToday
        if let sleepScore = metrics.sleepScore, let sleepHrs = metrics.sleepDurationHours {
            let formattedHrs = String(format: "%.1fh", sleepHrs)
            if sleepScore >= 80 {
                if steps > 500 {
                    healthAdvice = "Recuperare excelentă cu \(formattedHrs) de somn (Scor \(sleepScore)/100). Ai acumulat deja \(steps) pași."
                } else {
                    healthAdvice = "Recuperare excelentă cu \(formattedHrs) de somn (Scor \(sleepScore)/100). Ești gata pentru o zi plină de energie."
                }
            } else {
                healthAdvice = "Ai înregistrat \(formattedHrs) de somn (Scor \(sleepScore)/100). Menține un ritm echilibrat și hidratează-te corespunzător."
            }
        } else if steps > 500 {
            let bpmInfo = (metrics.restingBpm ?? 0) > 0 ? ", cu pulsul în repaus la \(Int(metrics.restingBpm!)) bpm" : ""
            healthAdvice = "Activitatea este în plină desfășurare, cu \(steps) pași înregistrați astăzi\(bpmInfo)."
        } else {
            let bpmInfo = (metrics.restingBpm ?? 0) > 0 ? "Pulsul în repaus este la \(Int(metrics.restingBpm!)) bpm." : "Indicatorii de recuperare se sincronizează pe măsură ce începe ziua."
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
                smokesAdvice = "Începe ziua cu un pahar de apă și ține poftele la zero."
            } else {
                smokesAdvice = "Zero țigări consumate—disciplină excelentă pentru plămânii tăi."
            }
        } else if smokes <= baseline {
            smokesAdvice = "\(smokes) țigări înregistrate, menținându-te sub pragul tău zilnic (\(baseline)). Hidratează-te când simți poftă."
        } else {
            smokesAdvice = "\(smokes) țigări înregistrate azi. Respiră adânc, ia o pauză și axează-te pe hidratare pentru restul zilei."
        }

        if metrics.waterMlToday > 0 {
            habitAdvice = "Hidratarea este la \(waterLiters) / \(waterGoalLiters). \(smokesAdvice)"
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
            financeAdvice = "Net worth-ul este de \(formattedNetWorth), cu un flux lunar de \(inK) / \(outK) Lei."
        } else {
            financeAdvice = "Disponibilitățile și portofoliul se mențin stabile la \(formattedNetWorth)."
        }

        // Tagdos Actionable Directive
        let tagdosAdvice: String
        let resolvedPills = topPills.isEmpty ? extractTopPills() : topPills
        if !resolvedPills.isEmpty {
            tagdosAdvice = "Uite, asta ai de rezolvat azi: \(resolvedPills.prefix(3).joined(separator: ", "))."
        } else if activeStreams.count > 0 {
            tagdosAdvice = "Toate stream-urile Tagdos sunt la zi, fără blocaje active."
        } else {
            tagdosAdvice = "Stream-urile Tagdos sunt calme, fără sarcini active."
        }

        // News
        let newsAdvice: String
        if let topHeadline = metrics.topNewsTitle, !topHeadline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newsAdvice = "Știrea principală în radar: \"\(topHeadline)\"."
        } else {
            newsAdvice = ""
        }

        // Outro
        let outro: String
        switch slot {
        case .morning:
            outro = "Setează-ți intențiile, concentrează-te și fă ca ziua de azi să conteze."
        case .intraday:
            outro = "Menține acest ritm constant pe parcursul după-amiezii."
        case .evening:
            outro = "Reflectează la realizările de azi și bucură-te de o seară relaxantă."
        case .nightly:
            outro = "Închide ecranele, regenerează-ți energia și dormi liniștit."
        }

        return SmartBriefingNarrative(
            greeting: greeting,
            weatherText: weatherAdvice,
            healthText: healthAdvice,
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
