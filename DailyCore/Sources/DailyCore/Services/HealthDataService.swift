import Foundation
import Combine
import Supabase

/// Multiplatform provider protocol allowing platform-specific engines (such as iOS HealthKit)
/// to inject on-device biometric telemetry and sleep stages into HealthDataService.
@MainActor
public protocol LocalHealthDataProvider: AnyObject {
    var hostPhoneName: String { get }
    func requestAuthorization() async -> Bool
    func fetchLocalTelemetry(for date: Date) async -> [HealthTelemetryRecord]
    func fetchLocalSleepStages(for date: Date) async -> [HealthTelemetryRecord]
}

extension LocalHealthDataProvider {
    public var hostPhoneName: String { "iPhone" }
}

/// Central multiplatform service managing health telemetry, vitals, sleep analysis, and historical trends.
@MainActor
public final class HealthDataService: ObservableObject {
    public static let shared = HealthDataService()
    public weak var localDataProvider: LocalHealthDataProvider?
    
    // MARK: - Published State
    
    @Published public var activeSubTab: HealthSubTab = .overview
    @Published public var selectedDate: Date = Date()
    @Published public var selectedDeviceSource: DeviceSource? = nil
    @Published public var availableSources: [DeviceSource] = []
    @Published public var selectedDeviceFilter: String? = nil
    @Published public var availableDevices: [String] = []
    @Published public var isLoading: Bool = false
    
    // Sleep
    @Published public var primarySleepSession: SleepSession? = nil
    @Published public var allSleepSessions: [SleepSession] = []
    @Published public var daytimeNaps: [NapSession] = []
    
    // Heart Rate & Zones
    @Published public var intradayHeartRate: [IntradayHeartRatePoint] = []
    @Published public var heartRateZones: [HeartRateZone: Int] = [:]
    @Published public var averageBpm: Double = 0
    @Published public var minBpm: Double = 0
    @Published public var maxBpm: Double = 0
    @Published public var restingBpm: Double = 0
    @Published public private(set) var resolvedLatestBpm: Double? = nil
    @Published public private(set) var latestBpmAt: Date? = nil
    @Published public private(set) var latestBpmSource: String? = nil
    
    /// Most recent intraday or spot heart rate reading from the currently active wearable
    public var latestBpm: Double? {
        resolvedLatestBpm ?? intradayHeartRate.last?.bpm
    }
    
    // Unified Device Priority Configuration (`public.health_sources`)
    @Published public private(set) var configurableSources: [HealthSourceRecord] = []
    @Published public private(set) var isSavingPriorityOrder: Bool = false
    
    public var hasCustomDevicePriority: Bool {
        configurableSources.contains(where: \.isCustomPriority)
    }
    
    // Activity
    @Published public var hourlySteps: [HourlyStepBucket] = []
    @Published public var totalStepsToday: Int = 0
    @Published public var totalActiveCalories: Double = 0
    @Published public var stepsSourceDevice: String? = nil
    
    // Vitals Grid & Trends
    @Published public var currentVitals: [HealthMetricType: VitalMetricRecord] = [:]
    @Published public var historicalTrends: [HealthMetricType: [DailyMetricTrendPoint]] = [:]
    
    // Stress Level & Mascot (Autonomic Tone Model)
    @Published public var currentStressScore: Int = 0
    @Published public var currentStressLevel: StressLevel = .calm
    @Published public var intradayStress: [IntradayStressPoint] = []
    @Published public var stressAnalysis: StressAnalysisResult? = nil
    
    // Canonical Engine Daily Summary
    @Published public var canonicalSummary: DailyHealthSummaryPayload? = nil
    
    // MARK: - Private State & Dependencies
    
    private let groupSuiteName = GroupDefaults.suiteName
    private let userDefaults: UserDefaults
    private let supabase = SupabaseService.shared.client
    private let cacheTTL: TimeInterval = 300 // 5 minutes in-memory cache
    private var telemetryCache: [String: (timestamp: Date, telemetry: [HealthTelemetryRecord], vitals: [VitalMetricRecord])] = [:]
    private var summaryCache: [String: (timestamp: Date, summary: DailyHealthSummaryPayload)] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var activeLoadTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var lastEngineInvocation: [String: Date] = [:]
    private var lastEnginePayloadFingerprint: [String: String] = [:]
    private var pendingEngineDebounceTask: [String: Task<Void, Never>] = [:]
    private var lastKnownTodayStart: Date = Calendar.current.startOfDay(for: Date())
    private var isSyncingHistory: Bool = false
    private var lastPushedTelemetryEpochMs: TimeInterval = 0
    private var lastSyncedSignatureByDate: [String: (timestamp: Date, signature: String)] = [:]
    private var periodicActiveSyncTask: Task<Void, Never>?
    private var lastSuccessfulLoadTime: [String: Date] = [:]
    
    // Lean Cache for Selected Date
    private var currentLeanSleepSessions: [HealthSleepSessionRecord] = []
    private var currentLeanDailyVitals: [HealthDailyVitalsRecord] = []
    private var currentLeanIntradayHeartRate: [HealthIntradayHeartRateRecord] = []
    private var currentLeanSources: [HealthSourceRecord] = []
    
    private let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private let isoTimestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private let summaryDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: str) {
                return date
            }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            if let date = f.date(from: str) {
                return date
            }
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if let date = f.date(from: str) {
                return date
            }
            f.dateFormat = "yyyy-MM-dd"
            if let date = f.date(from: str) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(str)")
        }
        return d
    }()
    
    private let summaryEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    
    public init() {
        self.userDefaults = UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
        
        // Observe auth session state changes so that once user authentication resolves,
        // real telemetry and canonical summaries are fetched immediately.
        AuthService.shared.$sessionState
            .dropFirst()
            .sink { [weak self] state in
                if case .authenticated = state {
                    Task { [weak self] in
                        self?.setupRealtimeSubscription()
                        await self?.loadDataForSelectedDate(forceRefresh: true)
                    }
                    Task.detached(priority: .utility) { [weak self] in
                        await self?.syncMissingHistoricalDataIfNeeded()
                    }
                }
            }
            .store(in: &cancellables)
        
        if AuthService.shared.isAuthenticated {
            setupRealtimeSubscription()
            Task.detached(priority: .utility) { [weak self] in
                await self?.syncMissingHistoricalDataIfNeeded()
            }
        }
        startActiveSyncLoop()
    }
    
    // MARK: - Midnight Rollover & Active Periodic Cadence
    
    /// Automatically advances `selectedDate` to the new day across midnight if the user was viewing "Today",
    /// while flushing yesterday's final local telemetry once in the background.
    private func checkMidnightRolloverIfNeeded() {
        let cal = Calendar.current
        let currentTodayStart = cal.startOfDay(for: Date())
        guard currentTodayStart > lastKnownTodayStart else { return }
        let previousDay = lastKnownTodayStart
        lastKnownTodayStart = currentTodayStart
        
        if cal.isDate(selectedDate, inSameDayAs: previousDay) {
            selectedDate = Date()
            if let provider = localDataProvider, AuthService.shared.isAuthenticated {
                Task { [weak self] in
                    let finalTelem = await provider.fetchLocalTelemetry(for: previousDay)
                    let finalSleep = await provider.fetchLocalSleepStages(for: previousDay)
                    let combined = finalTelem + finalSleep
                    if !combined.isEmpty {
                        await self?.syncTelemetryToSupabase(telemetry: combined)
                    }
                }
            }
        }
    }
    
    public func startActiveSyncLoop() {
        periodicActiveSyncTask?.cancel()
        periodicActiveSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes periodic cadence
                guard let self = self, !Task.isCancelled else { break }
                self.checkMidnightRolloverIfNeeded()
                if AuthService.shared.isAuthenticated && self.isToday {
                    await self.loadDataForSelectedDate(forceRefresh: true)
                }
            }
        }
    }
    
    public func stopActiveSyncLoop() {
        periodicActiveSyncTask?.cancel()
        periodicActiveSyncTask = nil
    }
    
    // MARK: - Realtime Health Summary Subscription
    
    public func setupRealtimeSubscription() {
        Task { [weak self] in
            guard let self = self else { return }
            guard AuthService.shared.isAuthenticated,
                  let session = try? await self.supabase.auth.session,
                  let userId = session.user.id.uuidString.lowercased() as String? else { return }
            
            self.realtimeTask?.cancel()
            if let old = self.realtimeChannel {
                await old.unsubscribe()
            }
            
            let channel = self.supabase.channel("health-sync-\(userId)")
            self.realtimeChannel = channel
            
            self.realtimeTask = Task { [weak self] in
                let summaryChanges = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "health_daily_summary",
                    filter: .eq("user_id", value: userId)
                )
                let sleepChanges = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "health_sleep_sessions",
                    filter: .eq("user_id", value: userId)
                )
                let vitalsChanges = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "health_daily_vitals",
                    filter: .eq("user_id", value: userId)
                )
                let sourcesChanges = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "health_sources",
                    filter: .eq("user_id", value: userId)
                )
                
                try? await channel.subscribeWithError()
                
                Task { [weak self] in
                    var lastHandledTime: Date = .distantPast
                    for await _ in summaryChanges {
                        guard !Task.isCancelled else { break }
                        let now = Date()
                        guard now.timeIntervalSince(lastHandledTime) > 3.0 else { continue }
                        lastHandledTime = now
                        await self?.fetchRemoteSummarySilentlyForSelectedDate()
                    }
                }
                
                Task { [weak self] in
                    var lastHandledTime: Date = .distantPast
                    for await _ in sleepChanges {
                        guard !Task.isCancelled else { break }
                        let now = Date()
                        guard now.timeIntervalSince(lastHandledTime) > 3.0 else { continue }
                        lastHandledTime = now
                        await self?.fetchRemoteSummarySilentlyForSelectedDate()
                    }
                }
                
                Task { [weak self] in
                    var lastHandledTime: Date = .distantPast
                    for await _ in vitalsChanges {
                        guard !Task.isCancelled else { break }
                        let now = Date()
                        guard now.timeIntervalSince(lastHandledTime) > 3.0 else { continue }
                        lastHandledTime = now
                        await self?.fetchRemoteSummarySilentlyForSelectedDate()
                    }
                }
                
                Task { [weak self] in
                    var lastHandledTime: Date = .distantPast
                    for await _ in sourcesChanges {
                        guard !Task.isCancelled else { break }
                        let now = Date()
                        guard now.timeIntervalSince(lastHandledTime) > 1.5 else { continue }
                        lastHandledTime = now
                        await self?.fetchRemoteSummarySilentlyForSelectedDate()
                    }
                }
            }
        }
    }
    
    /// Silently fetches the latest canonical summary and lean health records for the selected date from Supabase
    /// without triggering local telemetry collection, uploading telemetry, or re-invoking health-engine.
    @MainActor
    public func fetchRemoteSummarySilentlyForSelectedDate() async {
        let targetDate = selectedDate
        let dateKey = isoDateFormatter.string(from: targetDate)
        
        guard let session = try? await supabase.auth.session else { return }
        let userId = session.user.id.uuidString.lowercased()
        
        do {
            async let summaryFetch: [HealthDailySummaryRecord] = {
                do {
                    return try await supabase
                        .from("health_daily_summary")
                        .select()
                        .eq("user_id", value: userId)
                        .eq("local_date", value: dateKey)
                        .limit(1)
                        .execute()
                        .value
                } catch {
                    return []
                }
            }()
            
            async let sleepFetch: [HealthSleepSessionRecord] = {
                do {
                    return try await supabase
                        .from("health_sleep_sessions")
                        .select()
                        .eq("user_id", value: userId)
                        .eq("local_date", value: dateKey)
                        .order("source_priority", ascending: true)
                        .execute()
                        .value
                } catch {
                    return []
                }
            }()
            
            async let vitalsFetch: [HealthDailyVitalsRecord] = {
                do {
                    return try await supabase
                        .from("health_daily_vitals")
                        .select()
                        .eq("user_id", value: userId)
                        .eq("local_date", value: dateKey)
                        .execute()
                        .value
                } catch {
                    return []
                }
            }()
            
            async let hrFetch: [HealthIntradayHeartRateRecord] = {
                do {
                    return try await supabase
                        .from("health_intraday_heart_rate")
                        .select()
                        .eq("user_id", value: userId)
                        .eq("local_date", value: dateKey)
                        .order("bucket_minute", ascending: true)
                        .execute()
                        .value
                } catch {
                    return []
                }
            }()
            
            async let sourcesFetch: [HealthSourceRecord] = {
                do {
                    return try await supabase
                        .from("health_sources")
                        .select()
                        .eq("user_id", value: userId)
                        .order("priority_sleep", ascending: true)
                        .execute()
                        .value
                } catch {
                    return []
                }
            }()
            
            let (summaryRows, sleepRows, vitalsRows, hrRows, sourcesRows) = await (summaryFetch, sleepFetch, vitalsFetch, hrFetch, sourcesFetch)
            guard Calendar.current.isDate(targetDate, inSameDayAs: self.selectedDate) else { return }
            
            if !sourcesRows.isEmpty {
                self.currentLeanSources = sourcesRows
            }
            
            if let row = summaryRows.first, !row.summary.isEmpty {
                let payload = row.summary
                if self.canonicalSummary != payload {
                    self.canonicalSummary = payload
                    if let encoded = try? summaryEncoder.encode(payload) {
                        userDefaults.set(encoded, forKey: "health_daily_summary_\(dateKey)")
                    }
                    summaryCache[dateKey] = (timestamp: Date(), summary: payload)
                }
            }
            
            self.currentLeanSleepSessions = Self.mergeLeanSleepSessions(remote: sleepRows, local: self.currentLeanSleepSessions.filter { $0.localDate == dateKey }, sources: self.currentLeanSources)
            self.currentLeanDailyVitals = Self.mergeLeanDailyVitals(remote: vitalsRows, local: self.currentLeanDailyVitals.filter { $0.localDate == dateKey }, sources: self.currentLeanSources)
            self.currentLeanIntradayHeartRate = Self.mergeLeanIntradayHr(remote: hrRows, local: self.currentLeanIntradayHeartRate.filter { $0.localDate == dateKey })
            
            rebuildAvailableSourcesForCurrentDate()
            rebuildConfigurableSources()
            reapplyCurrentDeviceFilter()
            await loadHistoricalTrends()
        }
    }
    
    // MARK: - Navigation Actions & Formatting
    
    public var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    public var formattedDateTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) {
            return "Today"
        } else if cal.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, d MMM"
            return formatter.string(from: selectedDate)
        }
    }
    
    public func selectDate(_ date: Date) {
        changeDate(to: date)
    }
    
    public func goToToday() {
        jumpToToday()
    }
    
    public func goToPreviousDay() {
        prevDay()
    }
    
    public func goToNextDay() {
        nextDay()
    }
    
    public func jumpToToday() {
        changeDate(to: Date())
    }
    
    public func nextDay() {
        let cal = Calendar.current
        if let next = cal.date(byAdding: .day, value: 1, to: selectedDate) {
            // Cannot navigate past today
            if cal.startOfDay(for: next) <= cal.startOfDay(for: Date()) {
                changeDate(to: next)
            }
        }
    }
    
    public func prevDay() {
        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
            changeDate(to: prev)
        }
    }
    
    public func changeDate(to newDate: Date) {
        let cal = Calendar.current
        guard !cal.isDate(newDate, inSameDayAs: selectedDate) else { return }
        selectedDate = newDate
        activeLoadTask?.cancel()
        activeLoadTask = nil
        Task {
            await loadDataForSelectedDate(forceRefresh: true)
        }
    }
    
    public func setDeviceFilter(_ source: DeviceSource?) {
        guard selectedDeviceSource != source else { return }
        selectedDeviceSource = source
        selectedDeviceFilter = source?.displayName
        reapplyCurrentDeviceFilter()
        Task {
            await loadHistoricalTrends()
        }
    }
    
    public func setDeviceFilter(_ device: String?) {
        guard selectedDeviceFilter != device else { return }
        selectedDeviceFilter = device
        selectedDeviceSource = device != nil ? DeviceSource.from(name: device) : nil
        reapplyCurrentDeviceFilter()
        Task {
            await loadHistoricalTrends()
        }
    }
    
    // MARK: - Smart Refresh
    public var lastRefreshTimestamp: Date = .distantPast
    
    public func refreshIfStale() async {
        checkMidnightRolloverIfNeeded()
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let staleThreshold: TimeInterval = isToday ? 300 : 3600 // 5 min for today, 1 hour for past
        
        if Date().timeIntervalSince(lastRefreshTimestamp) > staleThreshold {
            lastRefreshTimestamp = Date()
            await loadDataForSelectedDate(forceRefresh: true)
        } else {
            // Already fresh, just reload from memory/local cache to trigger UI updates without network load
            await loadDataForSelectedDate(forceRefresh: false)
        }
    }
    
    // MARK: - Data Fetching & Processing
    
    public func loadDataForSelectedDate(forceRefresh: Bool = false) async {
        checkMidnightRolloverIfNeeded()
        if !forceRefresh, let existing = activeLoadTask {
            await existing.value
            return
        }
        
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.performLoadDataForSelectedDate(forceRefresh: forceRefresh)
        }
        activeLoadTask = task
        await task.value
        if activeLoadTask == task {
            activeLoadTask = nil
        }
    }
    
    private func performLoadDataForSelectedDate(forceRefresh: Bool = false) async {
        let targetDate = selectedDate
        let dateKey = isoDateFormatter.string(from: targetDate)
        let isToday = Calendar.current.isDateInToday(targetDate)
        let effectiveTTL: TimeInterval = isToday ? 30 : cacheTTL
        
        // Fast throttle check: if data for targetDate was refreshed less than 15s ago and not forced, return immediately
        if !forceRefresh, let last = lastSuccessfulLoadTime[dateKey], Date().timeIntervalSince(last) < 15.0 {
            return
        }
        
        let hasCachedData = (summaryCache[dateKey] != nil && !summaryCache[dateKey]!.summary.isEmpty) ||
                            (userDefaults.data(forKey: "health_daily_summary_\(dateKey)") != nil)
        
        let shouldShowLoading = !hasCachedData && canonicalSummary == nil
        if shouldShowLoading {
            isLoading = true
        }
        defer {
            if shouldShowLoading {
                isLoading = false
            }
        }
        
        // Reset cached lean arrays if they belong to a different day
        if currentLeanDailyVitals.first?.localDate != dateKey && currentLeanSleepSessions.first?.localDate != dateKey && currentLeanIntradayHeartRate.first?.localDate != dateKey {
            currentLeanSleepSessions = []
            currentLeanDailyVitals = []
            currentLeanIntradayHeartRate = []
            canonicalSummary = nil
            resolvedLatestBpm = nil
            latestBpmAt = nil
            latestBpmSource = nil
        }

        // 1. Check in-memory canonical summary cache (only when lean arrays for this date are already in memory)
        if !forceRefresh,
           let cached = summaryCache[dateKey],
           !cached.summary.isEmpty,
           Date().timeIntervalSince(cached.timestamp) < effectiveTTL,
           (!currentLeanDailyVitals.isEmpty || !currentLeanSleepSessions.isEmpty) {
            self.canonicalSummary = cached.summary
            rebuildAvailableSourcesForCurrentDate()
            rebuildConfigurableSources()
            reapplyCurrentDeviceFilter()
            lastSuccessfulLoadTime[dateKey] = Date()
            return
        }
        
        // 2. Check persistent on-device App Group local storage for instantaneous (<300ms) startup preview
        if !forceRefresh, let summaryData = userDefaults.data(forKey: "health_daily_summary_\(dateKey)"),
           let summary = try? summaryDecoder.decode(DailyHealthSummaryPayload.self, from: summaryData) {
            if !summary.isEmpty {
                if self.canonicalSummary != summary {
                    self.canonicalSummary = summary
                    summaryCache[dateKey] = (timestamp: Date(), summary: summary)
                    applyCanonicalSummary(summary, dateKey: dateKey)
                }
            } else {
                userDefaults.removeObject(forKey: "health_daily_summary_\(dateKey)")
            }
        }
        
        // 3. Concurrently fetch Supabase lean health data & canonical summary while reading local on-device provider (HealthKit)
        let session = try? await supabase.auth.session
        let userId = session?.user.id.uuidString.lowercased()
        
        async let remoteSummaryFetch: DailyHealthSummaryPayload? = {
            guard let userId = userId else { return nil }
            do {
                let summaryRows: [HealthDailySummaryRecord] = try await supabase
                    .from("health_daily_summary")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("local_date", value: dateKey)
                    .limit(1)
                    .execute()
                    .value
                if let row = summaryRows.first, !row.summary.isEmpty {
                    return row.summary
                }
            } catch {
                print("[HealthDataService] Warning: Could not fetch health_daily_summary: \(error.localizedDescription)")
            }
            return nil
        }()
        
        async let remoteSleepFetch: [HealthSleepSessionRecord] = {
            guard let userId = userId else { return [] }
            do {
                return try await supabase
                    .from("health_sleep_sessions")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("local_date", value: dateKey)
                    .order("source_priority", ascending: true)
                    .execute()
                    .value
            } catch {
                return []
            }
        }()
        
        async let remoteVitalsFetch: [HealthDailyVitalsRecord] = {
            guard let userId = userId else { return [] }
            do {
                return try await supabase
                    .from("health_daily_vitals")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("local_date", value: dateKey)
                    .execute()
                    .value
            } catch {
                return []
            }
        }()
        
        async let remoteHrFetch: [HealthIntradayHeartRateRecord] = {
            guard let userId = userId else { return [] }
            do {
                return try await supabase
                    .from("health_intraday_heart_rate")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("local_date", value: dateKey)
                    .order("bucket_minute", ascending: true)
                    .execute()
                    .value
            } catch {
                return []
            }
        }()
        
        async let remoteSourcesFetch: [HealthSourceRecord] = {
            guard let userId = userId else { return [] }
            do {
                return try await supabase
                    .from("health_sources")
                    .select()
                    .eq("user_id", value: userId)
                    .order("priority_sleep", ascending: true)
                    .execute()
                    .value
            } catch {
                return []
            }
        }()
        
        var localTelemetry: [HealthTelemetryRecord] = []
        if let provider = localDataProvider {
            let localTelem = await provider.fetchLocalTelemetry(for: targetDate)
            let localSleep = await provider.fetchLocalSleepStages(for: targetDate)
            localTelemetry = localTelem + localSleep
            
            // Asynchronously sync real on-device telemetry to Supabase
            if !localTelemetry.isEmpty {
                Task { [weak self] in
                    await self?.syncTelemetryToSupabase(telemetry: localTelemetry)
                }
            }
        }
        
        let remotePayload = await remoteSummaryFetch
        let leanSleep = await remoteSleepFetch
        let leanVitals = await remoteVitalsFetch
        let leanHr = await remoteHrFetch
        let leanSources = await remoteSourcesFetch
        
        guard !Task.isCancelled, Calendar.current.isDate(targetDate, inSameDayAs: self.selectedDate) else { return }
        
        if !leanSources.isEmpty {
            self.currentLeanSources = leanSources
        }
        
        // Convert fresh on-device localTelemetry (if any) into canonical lean records so UI & device filter see live HealthKit data immediately
        let effectiveUid = userId ?? "local"
        let hostName = localDataProvider?.hostPhoneName ?? "Schmitz"
        var localSleepRecs: [HealthSleepSessionRecord] = []
        var localVitalsRecs: [HealthDailyVitalsRecord] = []
        var localHrRecs: [HealthIntradayHeartRateRecord] = []
        if !localTelemetry.isEmpty {
            let sleepOnly = localTelemetry.filter { $0.isSleep || $0.isSleepStage }
            if !sleepOnly.isEmpty {
                let cluster = SleepClusteringEngine.clusterSleep(
                    targetDate: targetDate,
                    telemetry: sleepOnly,
                    vitalsSummary: [:],
                    preferredDevice: nil
                )
                localSleepRecs = Self.buildLeanSleepSessionRecords(
                    primarySession: cluster.primarySession,
                    allSessions: cluster.allSessions,
                    naps: cluster.naps,
                    dateKey: dateKey,
                    userId: effectiveUid,
                    hostName: hostName
                )
            }
            localVitalsRecs = Self.buildLeanDailyVitalsRecords(
                records: localTelemetry,
                targetDate: targetDate,
                dateKey: dateKey,
                userId: effectiveUid,
                hostName: hostName
            )
            localHrRecs = Self.groupIntradayHeartRateIntoBuckets(
                records: localTelemetry,
                userId: effectiveUid,
                dateKey: dateKey
            )
        }
        
        let mergedSleep = Self.mergeLeanSleepSessions(remote: leanSleep, local: localSleepRecs, sources: self.currentLeanSources)
        let mergedVitals = Self.mergeLeanDailyVitals(remote: leanVitals, local: localVitalsRecs, sources: self.currentLeanSources)
        let mergedHr = Self.mergeLeanIntradayHr(remote: leanHr, local: localHrRecs)
        
        self.currentLeanSleepSessions = mergedSleep
        self.currentLeanDailyVitals = mergedVitals
        self.currentLeanIntradayHeartRate = mergedHr
        
        if let payload = remotePayload {
            if self.canonicalSummary != payload {
                self.canonicalSummary = payload
                if let encoded = try? summaryEncoder.encode(payload) {
                    userDefaults.set(encoded, forKey: "health_daily_summary_\(dateKey)")
                }
                summaryCache[dateKey] = (timestamp: Date(), summary: payload)
            }
        }
        
        rebuildAvailableSourcesForCurrentDate()
        rebuildConfigurableSources()
        
        // 4. Apply unified lean data + canonical summary cleanly with zero cross-device leakage
        if !mergedSleep.isEmpty || !mergedVitals.isEmpty || !mergedHr.isEmpty {
            if let payload = remotePayload, selectedDeviceFilter == nil {
                applyCanonicalSummary(payload, dateKey: dateKey)
            }
            rebuildAvailableSourcesForCurrentDate()
            rebuildConfigurableSources()
            reapplyCurrentDeviceFilter()
            lastSuccessfulLoadTime[dateKey] = Date()
            await loadHistoricalTrends()
            return
        }
        
        // 5. Historical pre-lean fallback when only canonical summary exists
        if let payload = remotePayload {
            applyCanonicalSummary(payload, dateKey: dateKey)
            rebuildAvailableSourcesForCurrentDate()
            rebuildConfigurableSources()
            lastSuccessfulLoadTime[dateKey] = Date()
            await loadHistoricalTrends()
            return
        }
        
        // 6. Demo or completely empty day fallback (zero legacy health_telemetry scan)
        if ProcessInfo.processInfo.arguments.contains("-demoHealth") {
            let demo = generateDemoData(for: targetDate)
            telemetryCache[dateKey] = (timestamp: Date(), telemetry: demo.telemetry, vitals: demo.vitals)
            await applyRecords(telemetry: demo.telemetry, vitals: demo.vitals)
            await loadHistoricalTrends()
            return
        }
        
        self.primarySleepSession = nil
        self.allSleepSessions = []
        self.daytimeNaps = []
        self.hourlySteps = []
        self.totalStepsToday = 0
        self.totalActiveCalories = 0
        self.stepsSourceDevice = nil
        self.intradayHeartRate = []
        self.heartRateZones = [:]
        self.averageBpm = 0
        self.restingBpm = 0
        self.minBpm = 0
        self.maxBpm = 0
        self.resolvedLatestBpm = nil
        self.latestBpmAt = nil
        self.latestBpmSource = nil
        self.currentVitals = [:]
        self.stressAnalysis = nil
        self.intradayStress = []
        self.currentStressScore = 0
        self.currentStressLevel = .calm
        lastSuccessfulLoadTime[dateKey] = Date()
        await loadHistoricalTrends()
    }
    
    // MARK: - Unified Device Priority & Pure Arbitration Helpers (v2.1)
    
    nonisolated public static func canonicalSourceId(for src: DeviceSource, displayName: String) -> String {
        let dLower = displayName.lowercased()
        switch src {
        case .oura: return "oura_ring"
        case .appleWatch: return "apple_watch_ultra_2"
        case .pixelWatch, .fitbit: return "pixel_watch_5"
        case .oneplus: return "oneplus_watch_3"
        default:
            if dLower.contains("schmitz") || dLower.contains("iphone") { return "schmitz_iphone" }
            if dLower.contains("trapper") || dLower.contains("pixel 9") { return "trapper_pixel9" }
            if dLower.contains("radar") || dLower.contains("fold") { return "radar_fold8" }
            return canonicalSlug(displayName)
        }
    }
    
    /// Resolves unified 1-based ascending priority rank (`1` = highest priority).
    /// Respects user-configured order in `public.health_sources`, falling back to `DeviceSource.sortPriority`.
    nonisolated public static func resolveEffectivePriorityRank(
        deviceName: String?,
        sources: [HealthSourceRecord]
    ) -> Int {
        let src = DeviceSource.from(name: deviceName)
        guard !sources.isEmpty else { return src.sortPriority }
        let expectedId = canonicalSourceId(for: src, displayName: src.displayName)
        if let matched = sources.first(where: {
            $0.id == expectedId ||
            DeviceSource.from(name: $0.displayName) == src ||
            (deviceName != nil && $0.displayName.caseInsensitiveCompare(deviceName!) == .orderedSame)
        }) {
            let dbRank = min(matched.prioritySleep, matched.priorityActivity)
            // Guard against legacy pre-v2.1 inverted priorities (e.g. 100/90/85/40)
            if dbRank > 0 && dbRank <= 30 {
                return dbRank
            }
        }
        return src.sortPriority
    }
    
    public func effectivePriorityRank(for deviceName: String?) -> Int {
        Self.resolveEffectivePriorityRank(deviceName: deviceName, sources: currentLeanSources)
    }
    
    private func rebuildConfigurableSources() {
        let uid = currentLeanSources.first?.userId ?? "local"
        var byCanonical: [DeviceSource: HealthSourceRecord] = [:]
        
        for s in currentLeanSources {
            let src = DeviceSource.from(name: s.displayName)
            if src.isVirtualEngine || src == .manual { continue }
            let cleanId = Self.canonicalSourceId(for: src, displayName: src.displayName)
            let normalizedRank = Self.resolveEffectivePriorityRank(deviceName: src.displayName, sources: [s])
            if let existing = byCanonical[src] {
                if (s.isCustomPriority && !existing.isCustomPriority) || s.id == cleanId {
                    byCanonical[src] = HealthSourceRecord(
                        id: s.id,
                        userId: s.userId,
                        platform: s.platform,
                        deviceKind: s.deviceKind,
                        vendor: s.vendor,
                        model: s.model,
                        displayName: src.displayName,
                        hostDeviceName: s.hostDeviceName ?? existing.hostDeviceName,
                        prioritySleep: normalizedRank,
                        priorityActivity: normalizedRank,
                        isCustomPriority: s.isCustomPriority || existing.isCustomPriority,
                        color: s.color ?? existing.color,
                        createdAt: s.createdAt ?? existing.createdAt
                    )
                }
            } else {
                byCanonical[src] = HealthSourceRecord(
                    id: s.id,
                    userId: s.userId,
                    platform: s.platform,
                    deviceKind: s.deviceKind,
                    vendor: s.vendor,
                    model: s.model,
                    displayName: src.displayName,
                    hostDeviceName: s.hostDeviceName,
                    prioritySleep: normalizedRank,
                    priorityActivity: normalizedRank,
                    isCustomPriority: s.isCustomPriority,
                    color: s.color ?? DeviceColorPalette.getColor(for: src.displayName),
                    createdAt: s.createdAt
                )
            }
        }
        
        // Include any active hardware on the selected date even if not yet persisted
        for src in availableSources where !src.isVirtualEngine && src != .manual {
            if byCanonical[src] == nil {
                let disp = src.displayName
                let sid = Self.canonicalSourceId(for: src, displayName: disp)
                byCanonical[src] = HealthSourceRecord(
                    id: sid,
                    userId: uid,
                    platform: (src == .appleWatch || src == .healthKit) ? "iOS" : "Android",
                    deviceKind: src == .oura ? "ring" : (src.isWearable ? "watch" : "phone"),
                    vendor: nil,
                    model: nil,
                    displayName: disp,
                    hostDeviceName: nil,
                    prioritySleep: src.sortPriority,
                    priorityActivity: src.sortPriority,
                    isCustomPriority: false,
                    color: DeviceColorPalette.getColor(for: disp),
                    createdAt: nil
                )
            }
        }
        
        self.configurableSources = Array(byCanonical.values).sorted {
            let p0 = min($0.prioritySleep, $0.priorityActivity)
            let p1 = min($1.prioritySleep, $1.priorityActivity)
            if p0 != p1 { return p0 < p1 }
            return $0.displayName < $1.displayName
        }
    }
    
    public func moveDevicePriority(from index: Int, direction: Int) async {
        let newIndex = index + direction
        guard configurableSources.indices.contains(index),
              configurableSources.indices.contains(newIndex) else { return }
        
        var reordered = configurableSources
        let moved = reordered.remove(at: index)
        reordered.insert(moved, at: newIndex)
        
        let updated: [HealthSourceRecord] = reordered.enumerated().map { idx, item in
            let rank = idx + 1
            return HealthSourceRecord(
                id: item.id,
                userId: item.userId,
                platform: item.platform,
                deviceKind: item.deviceKind,
                vendor: item.vendor,
                model: item.model,
                displayName: item.displayName,
                hostDeviceName: item.hostDeviceName,
                prioritySleep: rank,
                priorityActivity: rank,
                isCustomPriority: true,
                color: item.color,
                createdAt: item.createdAt
            )
        }
        self.configurableSources = updated
        self.currentLeanSources = updated
        reapplyCurrentDeviceFilter()
        
        await saveDevicePriorityOrder(updated.map(\.id))
    }
    
    public func saveDevicePriorityOrder(_ orderedIds: [String]) async {
        guard !orderedIds.isEmpty, AuthService.shared.isAuthenticated else { return }
        isSavingPriorityOrder = true
        defer { isSavingPriorityOrder = false }
        
        do {
            try await supabase
                .rpc("save_health_source_priorities", params: ["ordered_source_ids": orderedIds])
                .execute()
            
            if let session = try? await supabase.auth.session {
                let userId = session.user.id.uuidString.lowercased()
                let freshSources: [HealthSourceRecord] = (try? await supabase
                    .from("health_sources")
                    .select()
                    .eq("user_id", value: userId)
                    .order("priority_sleep", ascending: true)
                    .execute()
                    .value) ?? []
                if !freshSources.isEmpty {
                    self.currentLeanSources = freshSources
                    rebuildConfigurableSources()
                    reapplyCurrentDeviceFilter()
                }
                let dateKey = isoDateFormatter.string(from: selectedDate)
                triggerCanonicalEngineIfNeeded(for: dateKey, userId: userId, fingerprint: "priority_\(orderedIds.joined(separator: ","))", force: true)
            }
        } catch {
            print("[HealthDataService] Failed to save device priority order: \(error.localizedDescription)")
        }
    }
    
    public func resetDevicePriorityOrder() async {
        guard AuthService.shared.isAuthenticated else { return }
        isSavingPriorityOrder = true
        defer { isSavingPriorityOrder = false }
        
        do {
            try await supabase
                .rpc("reset_health_source_priorities")
                .execute()
            
            if let session = try? await supabase.auth.session {
                let userId = session.user.id.uuidString.lowercased()
                let freshSources: [HealthSourceRecord] = (try? await supabase
                    .from("health_sources")
                    .select()
                    .eq("user_id", value: userId)
                    .order("priority_sleep", ascending: true)
                    .execute()
                    .value) ?? []
                self.currentLeanSources = freshSources
                rebuildConfigurableSources()
                reapplyCurrentDeviceFilter()
                let dateKey = isoDateFormatter.string(from: selectedDate)
                triggerCanonicalEngineIfNeeded(for: dateKey, userId: userId, fingerprint: "priority_reset_\(Int(Date().timeIntervalSince1970))", force: true)
            }
        } catch {
            print("[HealthDataService] Failed to reset device priority order: \(error.localizedDescription)")
        }
    }
    
    public struct ArbitratedActivityResult: Sendable {
        public let totalSteps: Int
        public let activeCalories: Double
        public let hourlySteps: [HourlyStepBucket]
        public let sourceDevice: String?
    }
    
    /// Class B — Hourly Active-Wearer Envelope (`0..23`):
    /// Sums disjoint active wearable hours (e.g. morning Oura/Pixel Watch + afternoon OnePlus Watch 3)
    /// while preventing double-counting during simultaneous wear using `resolveEffectivePriorityRank` as tie-breaker.
    nonisolated public static func arbitrateHourlyActivity(
        vitals: [HealthDailyVitalsRecord],
        sources: [HealthSourceRecord]
    ) -> ArbitratedActivityResult {
        let validRows = vitals.filter { !DeviceSource.from(name: $0.sourceDeviceKey).isVirtualEngine }
        guard !validRows.isEmpty else {
            return ArbitratedActivityResult(totalSteps: 0, activeCalories: 0, hourlySteps: [], sourceDevice: nil)
        }
        
        let wearables = validRows.filter { DeviceSource.from(name: $0.sourceDeviceKey).isWearable && ($0.steps > 0 || ($0.hourlySteps?.contains(where: { $0.steps > 0 }) == true)) }
        let candidates = !wearables.isEmpty ? wearables : validRows.filter { $0.steps > 0 || ($0.hourlySteps?.contains(where: { $0.steps > 0 }) == true) }
        
        guard !candidates.isEmpty else {
            let fallback = validRows.sorted {
                resolveEffectivePriorityRank(deviceName: $0.sourceDeviceKey, sources: sources) <
                resolveEffectivePriorityRank(deviceName: $1.sourceDeviceKey, sources: sources)
            }.first!
            let canon = DeviceSource.from(name: fallback.sourceDeviceKey).displayName
            return ArbitratedActivityResult(
                totalSteps: 0,
                activeCalories: fallback.activeKcal,
                hourlySteps: [],
                sourceDevice: canon
            )
        }
        
        let anyHasHourly = candidates.contains { ($0.hourlySteps?.contains(where: { $0.steps > 0 }) == true) }
        if anyHasHourly {
            var mergedBuckets: [HourlyStepBucket] = []
            var contributedStepsByCanon: [String: Int] = [:]
            var latestActiveHourByCanon: [String: Int] = [:]
            
            for h in 0..<24 {
                var hourEntries: [(canon: String, steps: Int, rank: Int)] = []
                for row in candidates {
                    let canon = DeviceSource.from(name: row.sourceDeviceKey).displayName
                    let hSteps = row.hourlySteps?.first(where: { $0.hour == h })?.steps ?? 0
                    if hSteps > 0 {
                        let rank = resolveEffectivePriorityRank(deviceName: canon, sources: sources)
                        hourEntries.append((canon: canon, steps: hSteps, rank: rank))
                    }
                }
                if let winner = hourEntries.sorted(by: {
                    if $0.rank != $1.rank { return $0.rank < $1.rank }
                    return $0.steps > $1.steps
                }).first {
                    mergedBuckets.append(HourlyStepBucket(hour: h, steps: winner.steps))
                    contributedStepsByCanon[winner.canon, default: 0] += winner.steps
                    latestActiveHourByCanon[winner.canon] = h
                } else {
                    mergedBuckets.append(HourlyStepBucket(hour: h, steps: 0))
                }
            }
            
            let envelopeSum = mergedBuckets.reduce(0) { $0 + $1.steps }
            let maxSingleRow = candidates.max(by: { $0.steps < $1.steps })!
            let totalSteps = max(envelopeSum, maxSingleRow.steps)
            
            // Proportional active kcal across contributing wearables
            var mergedKcal: Double = 0
            for row in candidates {
                let canon = DeviceSource.from(name: row.sourceDeviceKey).displayName
                let contributed = contributedStepsByCanon[canon] ?? 0
                if contributed > 0 && row.activeKcal > 0 {
                    let ratio = min(1.0, Double(contributed) / Double(max(1, row.steps)))
                    mergedKcal += row.activeKcal * ratio
                }
            }
            let maxSingleKcal = candidates.map(\.activeKcal).max() ?? 0
            var finalKcal = round(max(mergedKcal, maxSingleKcal) * 10) / 10
            if finalKcal <= 0 && totalSteps > 0 {
                finalKcal = round(Double(totalSteps) * 0.042 * 10) / 10
            }
            
            let winnerCanon: String = {
                if let bestContributor = contributedStepsByCanon.max(by: {
                    if $0.value != $1.value { return $0.value < $1.value }
                    return (latestActiveHourByCanon[$0.key] ?? -1) < (latestActiveHourByCanon[$1.key] ?? -1)
                })?.key {
                    return bestContributor
                }
                return DeviceSource.from(name: maxSingleRow.sourceDeviceKey).displayName
            }()
            
            return ArbitratedActivityResult(
                totalSteps: totalSteps,
                activeCalories: finalKcal,
                hourlySteps: mergedBuckets,
                sourceDevice: winnerCanon
            )
        }
        
        // Fallback when no hourly buckets exist: max single wearable / device
        let best = candidates.sorted {
            if $0.steps != $1.steps { return $0.steps > $1.steps }
            return resolveEffectivePriorityRank(deviceName: $0.sourceDeviceKey, sources: sources) <
                   resolveEffectivePriorityRank(deviceName: $1.sourceDeviceKey, sources: sources)
        }.first!
        let canon = DeviceSource.from(name: best.sourceDeviceKey).displayName
        var kcal = best.activeKcal
        if kcal <= 0 {
            kcal = candidates.map(\.activeKcal).max() ?? 0
        }
        if kcal <= 0 && best.steps > 0 {
            kcal = round(Double(best.steps) * 0.042 * 10) / 10
        }
        return ArbitratedActivityResult(
            totalSteps: best.steps,
            activeCalories: kcal,
            hourlySteps: best.hourlySteps ?? [],
            sourceDevice: canon
        )
    }
    
    public struct ArbitratedLatestHeartRate: Sendable, Equatable {
        public let bpm: Double
        public let timestamp: Date
        public let sourceDevice: String
    }
    
    /// Class A — Recency-First Latest Heart Rate:
    /// Always selects the newest real reading from the currently worn sensor.
    /// Configured device priority ONLY breaks ties when >=2 sensors reported within `simultaneousWindowSeconds` (default 15m).
    nonisolated public static func arbitrateLatestHeartRate(
        vitals: [HealthDailyVitalsRecord],
        intradayBuckets: [HealthIntradayHeartRateRecord],
        targetDate: Date,
        sources: [HealthSourceRecord],
        deviceFilter: String? = nil,
        simultaneousWindowSeconds: TimeInterval = 900,
        calendar: Calendar = .current
    ) -> ArbitratedLatestHeartRate? {
        let startOfDay = calendar.startOfDay(for: targetDate)
        var byDevice: [String: ArbitratedLatestHeartRate] = [:]
        
        // 1. Intraday 5-minute buckets (baseline per-device recency if spot timestamp wasn't synced yet)
        for b in intradayBuckets where b.bpmAvg >= 30 && b.bpmAvg <= 240 {
            let src = DeviceSource.from(name: b.sourceDeviceKey)
            if src.isVirtualEngine { continue }
            let canon = src.displayName
            let bucketTs = calendar.date(byAdding: .minute, value: b.bucketMinute, to: startOfDay) ?? startOfDay
            if let existing = byDevice[canon] {
                if bucketTs >= existing.timestamp {
                    byDevice[canon] = ArbitratedLatestHeartRate(bpm: Double(b.bpmAvg), timestamp: bucketTs, sourceDevice: canon)
                }
            } else {
                byDevice[canon] = ArbitratedLatestHeartRate(bpm: Double(b.bpmAvg), timestamp: bucketTs, sourceDevice: canon)
            }
        }
        
        // 2. Exact spot `latestHeartRate` + `latestHrAt` from `health_daily_vitals` overrides older/same bucket avg
        for v in vitals {
            guard let lhr = v.latestHeartRate, lhr >= 30, lhr <= 240 else { continue }
            let src = DeviceSource.from(name: v.sourceDeviceKey)
            if src.isVirtualEngine { continue }
            let canon = src.displayName
            let spotTs = v.latestHrAt ?? v.updatedAt ?? startOfDay
            if let existing = byDevice[canon] {
                if spotTs >= existing.timestamp {
                    byDevice[canon] = ArbitratedLatestHeartRate(bpm: Double(lhr), timestamp: spotTs, sourceDevice: canon)
                }
            } else {
                byDevice[canon] = ArbitratedLatestHeartRate(bpm: Double(lhr), timestamp: spotTs, sourceDevice: canon)
            }
        }
        
        if let filter = deviceFilter, !filter.isEmpty {
            let targetCanon = DeviceSource.from(name: filter).displayName
            return byDevice[targetCanon]
        }
        
        let allCandidates = Array(byDevice.values)
        guard let newestTs = allCandidates.map(\.timestamp).max() else { return nil }
        
        let activeWindow = allCandidates.filter {
            newestTs.timeIntervalSince($0.timestamp) <= simultaneousWindowSeconds
        }
        
        return activeWindow.sorted {
            let r0 = resolveEffectivePriorityRank(deviceName: $0.sourceDevice, sources: sources)
            let r1 = resolveEffectivePriorityRank(deviceName: $1.sourceDevice, sources: sources)
            if r0 != r1 { return r0 < r1 }
            return $0.timestamp > $1.timestamp
        }.first
    }
    
    nonisolated private static func parseIsoTimestamp(_ raw: String?) -> Date? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: raw) { return d }
        let isoPlain = ISO8601DateFormatter()
        return isoPlain.date(from: raw)
    }
    
    /// Class A — Recency-First Spot Vital (`spo2`, `weight`) with 30-minute tie-break window.
    nonisolated public static func arbitrateSpotVital(
        vitals: [HealthDailyVitalsRecord],
        timestampKey: String,
        sources: [HealthSourceRecord],
        windowSeconds: TimeInterval = 1800,
        extract: (HealthDailyVitalsRecord) -> Double?
    ) -> (value: Double, sourceDevice: String, timestamp: Date?)? {
        struct SpotCandidate {
            let value: Double
            let sourceDevice: String
            let timestamp: Date?
            let rank: Int
        }
        
        var candidates: [SpotCandidate] = []
        for row in vitals {
            let src = DeviceSource.from(name: row.sourceDeviceKey)
            if src.isVirtualEngine { continue }
            guard let val = extract(row), val > 0 else { continue }
            let canon = src.displayName
            let explicitTs = parseIsoTimestamp(row.vitalsTimestamps?[timestampKey])
            let ts = explicitTs ?? row.updatedAt
            let rank = resolveEffectivePriorityRank(deviceName: canon, sources: sources)
            candidates.append(SpotCandidate(value: val, sourceDevice: canon, timestamp: ts, rank: rank))
        }
        
        guard !candidates.isEmpty else { return nil }
        
        if let newestTs = candidates.compactMap(\.timestamp).max() {
            let active = candidates.filter {
                guard let ts = $0.timestamp else { return false }
                return newestTs.timeIntervalSince(ts) <= windowSeconds
            }
            if let winner = active.sorted(by: {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
            }).first {
                return (winner.value, winner.sourceDevice, winner.timestamp)
            }
        }
        
        let fallback = candidates.sorted { $0.rank < $1.rank }.first!
        return (fallback.value, fallback.sourceDevice, fallback.timestamp)
    }
    
    // MARK: - Lean Merge & Source Helpers
    
    nonisolated private static func mergeLeanSleepSessions(
        remote: [HealthSleepSessionRecord],
        local: [HealthSleepSessionRecord],
        sources: [HealthSourceRecord] = []
    ) -> [HealthSleepSessionRecord] {
        var map: [String: HealthSleepSessionRecord] = [:]
        for r in remote {
            let canon = DeviceSource.from(name: r.sourceDeviceKey).displayName
            let key = "\(r.sessionType)|\(canon)"
            if let prev = map[key] {
                if r.stages.count > prev.stages.count || (r.stages.count == prev.stages.count && r.durationSeconds > prev.durationSeconds) {
                    map[key] = r
                }
            } else {
                map[key] = r
            }
        }
        for l in local {
            let canon = DeviceSource.from(name: l.sourceDeviceKey).displayName
            let key = "\(l.sessionType)|\(canon)"
            if let prev = map[key] {
                if prev.stages.isEmpty && !l.stages.isEmpty {
                    map[key] = l
                } else if l.durationSeconds > prev.durationSeconds && l.stages.count >= prev.stages.count {
                    map[key] = HealthSleepSessionRecord(
                        id: prev.id,
                        userId: prev.userId,
                        localDate: prev.localDate,
                        sessionType: prev.sessionType,
                        sourceDeviceKey: canon,
                        hostDeviceName: l.hostDeviceName ?? prev.hostDeviceName,
                        startTime: l.startTime,
                        endTime: l.endTime,
                        durationSeconds: l.durationSeconds,
                        timeInBedSeconds: max(prev.timeInBedSeconds, l.timeInBedSeconds),
                        efficiencyPercent: l.efficiencyPercent ?? prev.efficiencyPercent,
                        sleepScore: l.sleepScore ?? prev.sleepScore,
                        deepSeconds: l.deepSeconds,
                        remSeconds: l.remSeconds,
                        lightSeconds: l.lightSeconds,
                        awakeSeconds: l.awakeSeconds,
                        latencySeconds: prev.latencySeconds,
                        qualityRating: l.qualityRating ?? prev.qualityRating,
                        stages: l.stages,
                        sourcePriority: min(prev.sourcePriority, l.sourcePriority),
                        isUserSelected: prev.isUserSelected || l.isUserSelected
                    )
                }
            } else {
                map[key] = l
            }
        }
        return Array(map.values).sorted {
            if $0.isUserSelected != $1.isUserSelected { return $0.isUserSelected && !$1.isUserSelected }
            let p0 = resolveEffectivePriorityRank(deviceName: $0.sourceDeviceKey, sources: sources)
            let p1 = resolveEffectivePriorityRank(deviceName: $1.sourceDeviceKey, sources: sources)
            if p0 != p1 { return p0 < p1 }
            return $0.durationSeconds > $1.durationSeconds
        }
    }
    
    nonisolated private static func mergeLeanDailyVitals(
        remote: [HealthDailyVitalsRecord],
        local: [HealthDailyVitalsRecord],
        sources: [HealthSourceRecord] = []
    ) -> [HealthDailyVitalsRecord] {
        var map: [String: HealthDailyVitalsRecord] = [:]
        for r in (remote + local) {
            let src = DeviceSource.from(name: r.sourceDeviceKey)
            if src.isVirtualEngine { continue }
            let canon = src.displayName
            if let prev = map[canon] {
                let useNewSteps = r.steps >= prev.steps
                let mergedHourly: [HourlyStepBucket]? = {
                    if useNewSteps, let nh = r.hourlySteps, !nh.isEmpty { return nh }
                    if let ph = prev.hourlySteps, !ph.isEmpty { return ph }
                    return r.hourlySteps
                }()
                
                // Recency-aware merge of latestHeartRate & latestHrAt
                let (mergedLatestHr, mergedLatestHrAt): (Int?, Date?) = {
                    switch (prev.latestHeartRate, r.latestHeartRate) {
                    case let (.some(pHr), .some(rHr)):
                        let pTs = prev.latestHrAt ?? prev.updatedAt ?? .distantPast
                        let rTs = r.latestHrAt ?? r.updatedAt ?? .distantPast
                        return rTs >= pTs ? (rHr, r.latestHrAt ?? prev.latestHrAt) : (pHr, prev.latestHrAt ?? r.latestHrAt)
                    case (.none, let .some(rHr)):
                        return (rHr, r.latestHrAt)
                    case (let .some(pHr), .none):
                        return (pHr, prev.latestHrAt)
                    case (.none, .none):
                        return (nil, prev.latestHrAt ?? r.latestHrAt)
                    }
                }()
                
                var mergedTsMap = prev.vitalsTimestamps ?? [:]
                if let newTsMap = r.vitalsTimestamps {
                    for (k, v) in newTsMap {
                        if let existingIso = mergedTsMap[k],
                           let oldD = parseIsoTimestamp(existingIso),
                           let newD = parseIsoTimestamp(v) {
                            if newD >= oldD { mergedTsMap[k] = v }
                        } else {
                            mergedTsMap[k] = v
                        }
                    }
                }
                
                let mergedSpo2: Double? = {
                    if let pVal = prev.spo2, let rVal = r.spo2 {
                        let pD = parseIsoTimestamp(prev.vitalsTimestamps?["spo2"]) ?? prev.updatedAt ?? .distantPast
                        let rD = parseIsoTimestamp(r.vitalsTimestamps?["spo2"]) ?? r.updatedAt ?? .distantPast
                        return rD >= pD ? rVal : pVal
                    }
                    return r.spo2 ?? prev.spo2
                }()
                
                let mergedWeight: Double? = {
                    if let pVal = prev.weightKg, let rVal = r.weightKg {
                        let pD = parseIsoTimestamp(prev.vitalsTimestamps?["weight"]) ?? prev.updatedAt ?? .distantPast
                        let rD = parseIsoTimestamp(r.vitalsTimestamps?["weight"]) ?? r.updatedAt ?? .distantPast
                        return rD >= pD ? rVal : pVal
                    }
                    return r.weightKg ?? prev.weightKg
                }()
                
                let mergedUpdatedAt: Date? = {
                    if let pU = prev.updatedAt, let rU = r.updatedAt { return max(pU, rU) }
                    return r.updatedAt ?? prev.updatedAt
                }()
                
                map[canon] = HealthDailyVitalsRecord(
                    id: prev.id,
                    userId: prev.userId,
                    localDate: prev.localDate,
                    sourceDeviceKey: canon,
                    hostDeviceName: r.hostDeviceName ?? prev.hostDeviceName,
                    steps: max(prev.steps, r.steps),
                    activeKcal: max(prev.activeKcal, r.activeKcal),
                    restingHeartRate: r.restingHeartRate ?? prev.restingHeartRate,
                    spo2: mergedSpo2,
                    respiratoryRate: r.respiratoryRate ?? prev.respiratoryRate,
                    skinTempCelsius: r.skinTempCelsius ?? prev.skinTempCelsius,
                    weightKg: mergedWeight,
                    hrvSdnnNightly: r.hrvSdnnNightly ?? prev.hrvSdnnNightly,
                    hrvRmssdNightly: r.hrvRmssdNightly ?? prev.hrvRmssdNightly,
                    hourlySteps: mergedHourly,
                    latestHeartRate: mergedLatestHr,
                    latestHrAt: mergedLatestHrAt,
                    vitalsTimestamps: mergedTsMap.isEmpty ? nil : mergedTsMap,
                    updatedAt: mergedUpdatedAt
                )
            } else {
                map[canon] = HealthDailyVitalsRecord(
                    id: r.id,
                    userId: r.userId,
                    localDate: r.localDate,
                    sourceDeviceKey: canon,
                    hostDeviceName: r.hostDeviceName,
                    steps: r.steps,
                    activeKcal: r.activeKcal,
                    restingHeartRate: r.restingHeartRate,
                    spo2: r.spo2,
                    respiratoryRate: r.respiratoryRate,
                    skinTempCelsius: r.skinTempCelsius,
                    weightKg: r.weightKg,
                    hrvSdnnNightly: r.hrvSdnnNightly,
                    hrvRmssdNightly: r.hrvRmssdNightly,
                    hourlySteps: r.hourlySteps,
                    latestHeartRate: r.latestHeartRate,
                    latestHrAt: r.latestHrAt,
                    vitalsTimestamps: r.vitalsTimestamps,
                    updatedAt: r.updatedAt
                )
            }
        }
        return Array(map.values)
            .filter { $0.hasSignal }
            .sorted {
                resolveEffectivePriorityRank(deviceName: $0.sourceDeviceKey, sources: sources) <
                resolveEffectivePriorityRank(deviceName: $1.sourceDeviceKey, sources: sources)
            }
    }
    
    nonisolated private static func mergeLeanIntradayHr(
        remote: [HealthIntradayHeartRateRecord],
        local: [HealthIntradayHeartRateRecord]
    ) -> [HealthIntradayHeartRateRecord] {
        var map: [String: HealthIntradayHeartRateRecord] = [:]
        for r in (remote + local) {
            let src = DeviceSource.from(name: r.sourceDeviceKey)
            if src.isVirtualEngine { continue }
            let canon = src.displayName
            let key = "\(canon)|\(r.bucketMinute)"
            if let prev = map[key] {
                map[key] = HealthIntradayHeartRateRecord(
                    id: prev.id,
                    userId: prev.userId,
                    localDate: prev.localDate,
                    sourceDeviceKey: canon,
                    bucketMinute: r.bucketMinute,
                    bpmAvg: r.bpmAvg,
                    bpmMin: min(prev.bpmMin, r.bpmMin),
                    bpmMax: max(prev.bpmMax, r.bpmMax),
                    sampleCount: max(prev.sampleCount, r.sampleCount),
                    updatedAt: r.updatedAt ?? prev.updatedAt
                )
            } else {
                map[key] = HealthIntradayHeartRateRecord(
                    id: r.id,
                    userId: r.userId,
                    localDate: r.localDate,
                    sourceDeviceKey: canon,
                    bucketMinute: r.bucketMinute,
                    bpmAvg: r.bpmAvg,
                    bpmMin: r.bpmMin,
                    bpmMax: r.bpmMax,
                    sampleCount: r.sampleCount,
                    updatedAt: r.updatedAt
                )
            }
        }
        return Array(map.values).sorted { $0.bucketMinute < $1.bucketMinute }
    }
    
    /// Recomputes `availableSources` & `availableDevices` strictly from physical devices that emitted data on `selectedDate`,
    /// automatically reverting `selectedDeviceFilter` to `nil` (`All Devices`) if the selected device has no data on this date.
    private func rebuildAvailableSourcesForCurrentDate() {
        var sourcesSet = Set<DeviceSource>()
        
        for s in currentLeanSleepSessions where s.durationSeconds > 0 {
            let src = DeviceSource.from(name: s.sourceDeviceKey)
            if !src.isVirtualEngine { sourcesSet.insert(src) }
        }
        for v in currentLeanDailyVitals where v.hasSignal {
            let src = DeviceSource.from(name: v.sourceDeviceKey)
            if !src.isVirtualEngine { sourcesSet.insert(src) }
        }
        for h in currentLeanIntradayHeartRate where h.bpmAvg > 30 {
            let src = DeviceSource.from(name: h.sourceDeviceKey)
            if !src.isVirtualEngine { sourcesSet.insert(src) }
        }
        
        // Fallback to canonical summary sources ONLY for historical pre-lean days when all 3 lean arrays are empty
        if sourcesSet.isEmpty,
           currentLeanSleepSessions.isEmpty,
           currentLeanDailyVitals.isEmpty,
           currentLeanIntradayHeartRate.isEmpty,
           let summary = canonicalSummary {
            for s in summary.sources {
                let src = DeviceSource.from(name: s)
                if !src.isVirtualEngine { sourcesSet.insert(src) }
            }
        }
        
        let sortedSources = Array(sourcesSet).sorted {
            let r0 = effectivePriorityRank(for: $0.displayName)
            let r1 = effectivePriorityRank(for: $1.displayName)
            if r0 != r1 { return r0 < r1 }
            return $0.displayName < $1.displayName
        }
        self.availableSources = sortedSources
        self.availableDevices = sortedSources.map(\.displayName)
        
        // Auto-revert to All Devices if previously selected device has 0 data on this date
        if let activeSource = selectedDeviceSource, !sourcesSet.contains(activeSource) {
            selectedDeviceSource = nil
            selectedDeviceFilter = nil
        } else if let activeFilter = selectedDeviceFilter {
            let canon = DeviceSource.from(name: activeFilter)
            if !sourcesSet.contains(canon) {
                selectedDeviceSource = nil
                selectedDeviceFilter = nil
            }
        }
    }
    
    // MARK: - Lean Health Architecture Applicators
    
    /// Unpacks lean discrete sleep sessions into published UI properties.
    public func applyLeanSleepSessions(_ rows: [HealthSleepSessionRecord]) {
        self.currentLeanSleepSessions = rows
        
        let targetCanon = selectedDeviceFilter.map { DeviceSource.from(name: $0).displayName }
        let candidateRows: [HealthSleepSessionRecord] = {
            if let targetCanon = targetCanon, !targetCanon.isEmpty {
                return rows.filter { DeviceSource.from(name: $0.sourceDeviceKey).displayName == targetCanon }
            }
            return rows
        }()
        
        let nocturnalRows = candidateRows.filter { $0.sessionType != "nap" }.sorted {
            if $0.isUserSelected != $1.isUserSelected { return $0.isUserSelected && !$1.isUserSelected }
            if (!$0.stages.isEmpty) != (!$1.stages.isEmpty) { return !$0.stages.isEmpty }
            let p0 = effectivePriorityRank(for: $0.sourceDeviceKey)
            let p1 = effectivePriorityRank(for: $1.sourceDeviceKey)
            if p0 != p1 { return p0 < p1 }
            return $0.durationSeconds > $1.durationSeconds
        }
        
        let mapped = nocturnalRows.map { $0.toSleepSession() }
        let primary = mapped.first
        
        let naps = candidateRows.filter { $0.sessionType == "nap" }.map { r in
            NapSession(
                id: r.id,
                startTime: r.startTime,
                endTime: r.endTime,
                durationSeconds: Double(r.durationSeconds),
                sourceDevice: DeviceSource.from(name: r.sourceDeviceKey).displayName
            )
        }
        
        self.primarySleepSession = primary
        self.allSleepSessions = mapped
        self.daytimeNaps = naps
        
        if selectedDeviceFilter == nil && Calendar.current.isDateInToday(selectedDate) {
            WidgetDataCoordinator.shared.updateSleepSnapshot(
                from: primary,
                restingHeartRate: self.restingBpm > 0 ? self.restingBpm : nil,
                hrvMs: self.currentVitals[.hrvSdnn]?.value ?? self.currentVitals[.hrvRmssd]?.value
            )
        }
    }
    
    /// Unpacks consolidated daily vitals into published properties using 3-class physiological arbitration.
    public func applyLeanDailyVitals(_ vitals: [HealthDailyVitalsRecord]) {
        self.currentLeanDailyVitals = vitals
        let dateKey = isoDateFormatter.string(from: selectedDate)
        
        if let filter = selectedDeviceFilter, !filter.isEmpty {
            let targetCanon = DeviceSource.from(name: filter).displayName
            if let exact = vitals.first(where: { DeviceSource.from(name: $0.sourceDeviceKey).displayName == targetCanon }) {
                self.hourlySteps = exact.hourlySteps ?? []
                self.totalStepsToday = exact.steps
                self.totalActiveCalories = exact.activeKcal > 0 ? exact.activeKcal : (exact.steps > 0 ? round(Double(exact.steps) * 0.042 * 10) / 10 : 0)
                self.stepsSourceDevice = targetCanon
                self.restingBpm = Double(exact.restingHeartRate ?? 0)
                
                var updatedVitals: [HealthMetricType: VitalMetricRecord] = [:]
                populateVitalsMap(&updatedVitals, from: exact, canonicalDevice: targetCanon, overwrite: true)
                self.currentVitals = updatedVitals
            } else {
                self.hourlySteps = []
                self.totalStepsToday = 0
                self.totalActiveCalories = 0
                self.stepsSourceDevice = targetCanon
                self.restingBpm = 0
                self.currentVitals = [:]
            }
            return
        }
        
        // All Devices mode:
        // - Class B (Steps & Active Kcal): Hourly Active-Wearer Envelope across wearables
        // - Class C (RHR, HRV, Resp, Skin Temp): Configured Priority Order
        // - Class A (SpO2, Weight): Recency-First with 30m priority tie-break
        guard !vitals.isEmpty else {
            self.hourlySteps = []
            self.totalStepsToday = 0
            self.totalActiveCalories = 0
            self.stepsSourceDevice = nil
            self.restingBpm = 0
            self.currentVitals = [:]
            return
        }
        
        let activity = Self.arbitrateHourlyActivity(vitals: vitals, sources: currentLeanSources)
        self.hourlySteps = activity.hourlySteps
        self.totalStepsToday = activity.totalSteps
        self.totalActiveCalories = activity.activeCalories
        self.stepsSourceDevice = activity.sourceDevice
        
        let prioritySorted = vitals.sorted {
            let p0 = effectivePriorityRank(for: $0.sourceDeviceKey)
            let p1 = effectivePriorityRank(for: $1.sourceDeviceKey)
            if p0 != p1 { return p0 < p1 }
            return $0.steps > $1.steps
        }
        
        var mergedVitals: [HealthMetricType: VitalMetricRecord] = [:]
        for row in prioritySorted {
            let canon = DeviceSource.from(name: row.sourceDeviceKey).displayName
            populateVitalsMap(&mergedVitals, from: row, canonicalDevice: canon, overwrite: false)
        }
        
        // Override Class A spot vitals (SpO2, Weight) with Recency-First arbitration (30m simultaneous window)
        if let spo2Winner = Self.arbitrateSpotVital(vitals: vitals, timestampKey: "spo2", sources: currentLeanSources, windowSeconds: 1800, extract: \.spo2) {
            mergedVitals[.oxygenSaturation] = VitalMetricRecord(
                userId: "lean",
                type: HealthMetricType.oxygenSaturation.rawValue,
                value: spo2Winner.value,
                unit: "%",
                date: dateKey,
                sourceDevice: spo2Winner.sourceDevice,
                createdAt: spo2Winner.timestamp
            )
        }
        if let weightWinner = Self.arbitrateSpotVital(vitals: vitals, timestampKey: "weight", sources: currentLeanSources, windowSeconds: 1800, extract: \.weightKg) {
            mergedVitals[.weight] = VitalMetricRecord(
                userId: "lean",
                type: HealthMetricType.weight.rawValue,
                value: weightWinner.value,
                unit: "kg",
                date: dateKey,
                sourceDevice: weightWinner.sourceDevice,
                createdAt: weightWinner.timestamp
            )
        }
        if activity.activeCalories > 0 {
            mergedVitals[.activeEnergy] = VitalMetricRecord(
                userId: "lean",
                type: HealthMetricType.activeEnergy.rawValue,
                value: activity.activeCalories,
                unit: "kcal",
                date: dateKey,
                sourceDevice: activity.sourceDevice
            )
        }
        
        if Calendar.current.isDateInToday(selectedDate) {
            let waterMl = HabitsService.shared.totalWaterMlToday
            if waterMl > 0 {
                mergedVitals[.hydration] = VitalMetricRecord(
                    userId: "habits",
                    type: HealthMetricType.hydration.rawValue,
                    value: Double(waterMl),
                    unit: "ml",
                    date: dateKey,
                    sourceDevice: "Bubbles"
                )
            }
        }
        self.restingBpm = mergedVitals[.restingHeartRate]?.value ?? 0
        self.currentVitals = mergedVitals
    }
    
    private func populateVitalsMap(
        _ map: inout [HealthMetricType: VitalMetricRecord],
        from row: HealthDailyVitalsRecord,
        canonicalDevice: String,
        overwrite: Bool
    ) {
        let dateKey = row.localDate
        let defaultTs = row.updatedAt ?? Date()
        func tsForKey(_ key: String) -> Date {
            Self.parseIsoTimestamp(row.vitalsTimestamps?[key]) ?? defaultTs
        }
        func setMetric(_ type: HealthMetricType, _ value: Double, _ unit: String, timestamp: Date) {
            if overwrite || map[type] == nil {
                map[type] = VitalMetricRecord(
                    userId: row.userId,
                    type: type.rawValue,
                    value: value,
                    unit: unit,
                    date: dateKey,
                    sourceDevice: canonicalDevice,
                    createdAt: timestamp
                )
            }
        }
        if let lhr = row.latestHeartRate, lhr >= 30, lhr <= 240 {
            setMetric(.heartRate, Double(lhr), "bpm", timestamp: row.latestHrAt ?? defaultTs)
        }
        if let rhr = row.restingHeartRate, rhr > 0 { setMetric(.restingHeartRate, Double(rhr), "bpm", timestamp: tsForKey("rhr")) }
        if let spo2 = row.spo2, spo2 > 0 { setMetric(.oxygenSaturation, spo2, "%", timestamp: tsForKey("spo2")) }
        if let resp = row.respiratoryRate, resp > 0 { setMetric(.respiratoryRate, resp, "br/min", timestamp: tsForKey("resp")) }
        if let temp = row.skinTempCelsius { setMetric(.bodyTemperature, temp, "°C", timestamp: tsForKey("temp")) }
        if let weight = row.weightKg, weight > 0 { setMetric(.weight, weight, "kg", timestamp: tsForKey("weight")) }
        if let sdnn = row.hrvSdnnNightly, sdnn > 0 { setMetric(.hrvSdnn, sdnn, "ms", timestamp: tsForKey("hrv_sdnn")) }
        if let rmssd = row.hrvRmssdNightly, rmssd > 0 { setMetric(.hrvRmssd, rmssd, "ms", timestamp: tsForKey("hrv_rmssd")) }
        if row.activeKcal > 0 { setMetric(.activeEnergy, row.activeKcal, "kcal", timestamp: defaultTs) }
    }
    
    /// Unpacks 5-minute bucketed heart rate AND resolves Class A Recency-First `latestBpm`.
    public func applyLeanIntradayHeartRate(_ buckets: [HealthIntradayHeartRateRecord], targetDate: Date) {
        self.currentLeanIntradayHeartRate = buckets
        let dateKey = isoDateFormatter.string(from: targetDate)
        
        // Resolve Latest BPM (Recency-First with 15-min simultaneous priority tie-break)
        let leanLatest = Self.arbitrateLatestHeartRate(
            vitals: currentLeanDailyVitals,
            intradayBuckets: buckets,
            targetDate: targetDate,
            sources: currentLeanSources,
            deviceFilter: selectedDeviceFilter
        )
        
        var finalLatest = leanLatest
        if selectedDeviceFilter == nil,
           let summaryBpm = canonicalSummary?.cardiovascular.latestBpm,
           summaryBpm >= 30,
           let summarySrc = canonicalSummary?.cardiovascular.latestSourceDevice {
            let summaryTs = canonicalSummary?.cardiovascular.latestBpmAt ?? canonicalSummary?.computedAt ?? .distantPast
            if let existing = finalLatest {
                if summaryTs > existing.timestamp.addingTimeInterval(60) {
                    finalLatest = ArbitratedLatestHeartRate(
                        bpm: summaryBpm,
                        timestamp: summaryTs,
                        sourceDevice: DeviceSource.from(name: summarySrc).displayName
                    )
                }
            } else {
                finalLatest = ArbitratedLatestHeartRate(
                    bpm: summaryBpm,
                    timestamp: summaryTs,
                    sourceDevice: DeviceSource.from(name: summarySrc).displayName
                )
            }
        }
        
        if let winner = finalLatest {
            self.resolvedLatestBpm = winner.bpm
            self.latestBpmAt = winner.timestamp
            self.latestBpmSource = winner.sourceDevice
            var updated = self.currentVitals
            updated[.heartRate] = VitalMetricRecord(
                userId: "lean-hr",
                type: HealthMetricType.heartRate.rawValue,
                value: winner.bpm,
                unit: "bpm",
                date: dateKey,
                sourceDevice: winner.sourceDevice,
                createdAt: winner.timestamp
            )
            self.currentVitals = updated
        } else {
            self.resolvedLatestBpm = nil
            self.latestBpmAt = nil
            self.latestBpmSource = nil
        }
        
        let maxBucketMinute = buckets.map(\.bucketMinute).max() ?? 0
        let filteredBuckets: [HealthIntradayHeartRateRecord] = {
            if let filter = selectedDeviceFilter, !filter.isEmpty {
                let targetCanon = DeviceSource.from(name: filter).displayName
                return buckets.filter {
                    DeviceSource.from(name: $0.sourceDeviceKey).displayName == targetCanon
                }
            }
            guard buckets.count > 1 else { return buckets }
            var byBucket: [Int: [HealthIntradayHeartRateRecord]] = [:]
            for b in buckets {
                byBucket[b.bucketMinute, default: []].append(b)
            }
            return byBucket.keys.sorted().compactMap { bm -> HealthIntradayHeartRateRecord? in
                guard var group = byBucket[bm], !group.isEmpty else { return nil }
                if group.count == 1 { return group[0] }
                // For recent tail buckets (last 15 min) where the active Latest HR sensor is present, prefer that active sensor cleanly
                if let activeSrc = finalLatest?.sourceDevice,
                   bm >= maxBucketMinute - 15,
                   let exactActive = group.first(where: { DeviceSource.from(name: $0.sourceDeviceKey).displayName == activeSrc }) {
                    return exactActive
                }
                group.sort {
                    effectivePriorityRank(for: $0.sourceDeviceKey) < effectivePriorityRank(for: $1.sourceDeviceKey)
                }
                let primary = group[0]
                let totalCnt = group.reduce(0) { $0 + max(1, $1.sampleCount) }
                let weightedSum = group.reduce(0) { $0 + ($1.bpmAvg * max(1, $1.sampleCount)) }
                let minV = group.map { $0.bpmMin > 30 ? $0.bpmMin : $0.bpmAvg }.min() ?? primary.bpmAvg
                let maxV = group.map { $0.bpmMax > 30 ? $0.bpmMax : $0.bpmAvg }.max() ?? primary.bpmAvg
                return HealthIntradayHeartRateRecord(
                    id: primary.id,
                    userId: primary.userId,
                    localDate: primary.localDate,
                    sourceDeviceKey: primary.sourceDeviceKey,
                    bucketMinute: bm,
                    bpmAvg: Int(round(Double(weightedSum) / Double(max(1, totalCnt)))),
                    bpmMin: minV,
                    bpmMax: maxV,
                    sampleCount: totalCnt
                )
            }
        }()
        
        let points = filteredBuckets.map { $0.toPoint(for: targetDate) }.sorted(by: { $0.timestamp < $1.timestamp })
        self.intradayHeartRate = points
        
        if !filteredBuckets.isEmpty {
            let weightedSum = filteredBuckets.reduce(0.0) { $0 + Double($1.bpmAvg) * Double(max(1, $1.sampleCount)) }
            let totalSamples = filteredBuckets.reduce(0) { $0 + max(1, $1.sampleCount) }
            self.averageBpm = round((weightedSum / Double(max(1, totalSamples))) * 10) / 10
            var lo = Double(filteredBuckets.map { $0.bpmMin > 30 ? $0.bpmMin : $0.bpmAvg }.min() ?? 0)
            var hi = Double(filteredBuckets.map { $0.bpmMax > 30 ? $0.bpmMax : $0.bpmAvg }.max() ?? 0)
            if let live = self.resolvedLatestBpm, live > 30 {
                if lo <= 0 || live < lo { lo = live }
                if live > hi { hi = live }
            }
            self.minBpm = lo
            self.maxBpm = hi
            if self.restingBpm <= 0 {
                if let derived = StressAnalysisEngine.deriveNocturnalRhr(from: points, targetDate: targetDate, calendar: Calendar.current) {
                    self.restingBpm = derived
                } else if self.minBpm > 0 {
                    self.restingBpm = round(min(max(self.minBpm + 6, 45), 85))
                }
            }
            var zones: [HeartRateZone: Int] = [.resting: 0, .fatBurn: 0, .cardio: 0, .peak: 0]
            for pt in points {
                zones[pt.zone, default: 0] += 1
            }
            self.heartRateZones = zones
        } else {
            self.averageBpm = self.resolvedLatestBpm ?? 0
            self.minBpm = self.resolvedLatestBpm ?? 0
            self.maxBpm = self.resolvedLatestBpm ?? 0
            self.heartRateZones = [:]
        }
    }
    
    /// Stores canonical device catalog metadata without polluting the date-scoped `availableSources` selector.
    public func applyLeanHealthSources(_ sources: [HealthSourceRecord]) {
        self.currentLeanSources = sources
        rebuildConfigurableSources()
    }

    /// Re-evaluates current cached lean telemetry for the active device filter without network roundtrips.
    public func reapplyCurrentDeviceFilter() {
        if currentLeanSleepSessions.isEmpty && currentLeanDailyVitals.isEmpty && currentLeanIntradayHeartRate.isEmpty {
            if selectedDeviceFilter == nil, let summary = canonicalSummary {
                applyCanonicalSummary(summary, dateKey: isoDateFormatter.string(from: selectedDate))
                return
            }
        }
        
        applyLeanDailyVitals(currentLeanDailyVitals)
        applyLeanSleepSessions(currentLeanSleepSessions)
        applyLeanIntradayHeartRate(currentLeanIntradayHeartRate, targetDate: selectedDate)
        recalculateStressForCurrentDevice()
        
        if let stressVal = stressAnalysis?.currentScore, stressVal > 0 {
            let dateKey = isoDateFormatter.string(from: selectedDate)
            var updated = self.currentVitals
            let resolvedStressSource: String = {
                if let f = selectedDeviceFilter, !f.isEmpty { return DeviceSource.from(name: f).displayName }
                if let srvSrc = canonicalSummary?.stress?.sourceDevice, !srvSrc.isEmpty, !DeviceSource.from(name: srvSrc).isVirtualEngine {
                    return DeviceSource.from(name: srvSrc).displayName
                }
                if let liveHrSrc = latestBpmSource, !liveHrSrc.isEmpty {
                    return liveHrSrc
                }
                return stepsSourceDevice ?? primarySleepSession?.sourceDevice ?? "Biometric Engine"
            }()
            updated[.stress] = VitalMetricRecord(
                userId: "stress-engine",
                type: HealthMetricType.stress.rawValue,
                value: Double(stressVal),
                unit: "score",
                date: dateKey,
                sourceDevice: resolvedStressSource
            )
            self.currentVitals = updated
        }
    }
    
    /// Calculates or retrieves stress specifically for the active device filter.
    private func recalculateStressForCurrentDevice() {
        let cal = Calendar.current
        
        // If All Devices and canonicalSummary has up-to-date server stress (newer than or within 90s of latest HR), use it directly
        if selectedDeviceFilter == nil,
           let stress = canonicalSummary?.stress,
           let summaryComputedAt = canonicalSummary?.computedAt,
           (latestBpmAt == nil || summaryComputedAt.addingTimeInterval(90) >= latestBpmAt!) {
            self.currentStressScore = stress.currentScore
            self.currentStressLevel = stress.currentLevel
            self.intradayStress = stress.intradayPoints
            let breathing = BreathingProtocol(rawValue: stress.recommendedBreathing) ?? .boxBreathing
            self.stressAnalysis = StressAnalysisResult(
                currentScore: stress.currentScore,
                currentLevel: stress.currentLevel,
                dailyAverageScore: stress.dailyAverage,
                peakHour: stress.peakHour,
                peakScore: stress.peakScore,
                lowestHour: stress.lowestHour,
                lowestScore: stress.lowestScore,
                parasympatheticPercent: stress.parasympatheticPercent,
                sympatheticPercent: stress.sympatheticPercent,
                baselineHrvMs: stress.baselineHrvMs,
                currentHrvMs: stress.currentHrvMs,
                hrvDeltaPercent: stress.hrvDeltaPercent,
                restingHeartRateBpm: stress.restingHeartRateBpm,
                currentSedentaryBpm: stress.currentSedentaryBpm,
                heartRateElevationBpm: stress.heartRateElevationBpm,
                monkeyMood: stress.monkeyMood,
                adviceQuote: stress.adviceQuote,
                recommendedBreathing: breathing,
                lastUpdated: summaryComputedAt
            )
            return
        }
        
        let hasSdnn = (currentVitals[.hrvSdnn]?.value ?? 0) > 0
        let hasRmssd = !hasSdnn && (currentVitals[.hrvRmssd]?.value ?? 0) > 0
        let hrvVal = hasSdnn ? currentVitals[.hrvSdnn]?.value : (hasRmssd ? currentVitals[.hrvRmssd]?.value : nil)
        let canonFilter = selectedDeviceFilter.map { DeviceSource.from(name: $0).displayName }
        
        // Anchor RHR to the active HR sensor's own RHR in All Devices mode to avoid cross-sensor optical bias
        let activeHrSensorCanon = canonFilter ?? latestBpmSource
        let sensorMatchedRhr: Double? = {
            if let sensor = activeHrSensorCanon {
                if let rowRhr = currentLeanDailyVitals.first(where: { DeviceSource.from(name: $0.sourceDeviceKey).displayName == sensor })?.restingHeartRate, rowRhr > 0 {
                    return Double(rowRhr)
                }
                if let srvDerived = canonicalSummary?.sourcesBreakdown?[sensor]?["derived_rhr"], srvDerived > 0 {
                    return srvDerived
                }
            }
            return currentVitals[.restingHeartRate]?.value
        }()
        
        let summaryUsedRmssd = (canonicalSummary?.vitals["hrvsdnn"] == nil) && (canonicalSummary?.vitals["hrvrmssd"] != nil)
        let matchedBaselineHrv: Double? = {
            guard let base = canonicalSummary?.stress?.baselineHrvMs, base > 0 else { return nil }
            if hasRmssd && summaryUsedRmssd && base >= 35 { return base }
            if hasSdnn && !summaryUsedRmssd && base <= 120 { return base }
            return nil
        }()
        
        if hrvVal != nil || !intradayHeartRate.isEmpty || (sensorMatchedRhr != nil && sensorMatchedRhr! > 0) {
            let stressCalc = StressAnalysisEngine.calculateStress(
                targetDate: selectedDate,
                hrvMs: hrvVal,
                isRmssd: hasRmssd,
                hrTelemetry: intradayHeartRate,
                hourlySteps: hourlySteps,
                restingBpm: sensorMatchedRhr,
                priorSleepScore: primarySleepSession?.sleepScore,
                personalBaselineHrv: matchedBaselineHrv,
                personalBaselineRhr: nil,
                calendar: cal
            )
            if let stressCalc = stressCalc {
                var resolvedResult = stressCalc.result
                // Prefer exact server-precomputed per-device stress_score when present in sources_breakdown
                if let canon = canonFilter,
                   let srvScoreDouble = canonicalSummary?.sourcesBreakdown?[canon]?["stress_score"] {
                    let srvScore = Int(round(srvScoreDouble))
                    let srvAvg = canonicalSummary?.sourcesBreakdown?[canon]?["stress_daily_avg"].map { Int(round($0)) } ?? resolvedResult.dailyAverageScore
                    let srvLevel = StressLevel.from(score: srvScore)
                    let para = min(max(100 - srvScore, 10), 90)
                    resolvedResult = StressAnalysisResult(
                        currentScore: srvScore,
                        currentLevel: srvLevel,
                        dailyAverageScore: srvAvg,
                        peakHour: resolvedResult.peakHour,
                        peakScore: resolvedResult.peakScore,
                        lowestHour: resolvedResult.lowestHour,
                        lowestScore: resolvedResult.lowestScore,
                        parasympatheticPercent: para,
                        sympatheticPercent: 100 - para,
                        baselineHrvMs: resolvedResult.baselineHrvMs,
                        currentHrvMs: resolvedResult.currentHrvMs,
                        hrvDeltaPercent: resolvedResult.hrvDeltaPercent,
                        restingHeartRateBpm: resolvedResult.restingHeartRateBpm,
                        currentSedentaryBpm: resolvedResult.currentSedentaryBpm,
                        heartRateElevationBpm: resolvedResult.heartRateElevationBpm,
                        monkeyMood: resolvedResult.monkeyMood,
                        adviceQuote: resolvedResult.adviceQuote,
                        recommendedBreathing: resolvedResult.recommendedBreathing,
                        lastUpdated: resolvedResult.lastUpdated
                    )
                }
                self.stressAnalysis = resolvedResult
                self.intradayStress = stressCalc.intradayPoints
                self.currentStressScore = resolvedResult.currentScore
                self.currentStressLevel = resolvedResult.currentLevel
                return
            }
        }
        
        self.stressAnalysis = nil
        self.intradayStress = []
        self.currentStressScore = 0
        self.currentStressLevel = .calm
    }
    
    /// Unpacks canonical DailyHealthSummaryPayload into published properties.
    private func applyCanonicalSummary(_ summary: DailyHealthSummaryPayload, dateKey: String) {
        // Collect available canonical physical sources
        var sourcesSet = Set<DeviceSource>()
        
        for s in summary.sources where !s.isEmpty {
            let src = DeviceSource.from(name: s)
            if !src.isVirtualEngine { sourcesSet.insert(src) }
        }
        if let d = summary.sleep.primarySession?.sourceDevice, !d.isEmpty {
            let src = DeviceSource.from(name: d)
            if !src.isVirtualEngine { sourcesSet.insert(src) }
        }
        for s in summary.sleep.allSessions where !s.sourceDevice.isEmpty {
            let src = DeviceSource.from(name: s.sourceDevice)
            if !src.isVirtualEngine { sourcesSet.insert(src) }
        }
        if let d = summary.activity.sourceDevice, !d.isEmpty {
            let src = DeviceSource.from(name: d)
            if !src.isVirtualEngine { sourcesSet.insert(src) }
        }
        for (_, v) in summary.vitals {
            if let d = v.sourceDevice, !d.isEmpty {
                let src = DeviceSource.from(name: d)
                if !src.isVirtualEngine { sourcesSet.insert(src) }
            }
        }
        if currentLeanSleepSessions.isEmpty && currentLeanDailyVitals.isEmpty && currentLeanIntradayHeartRate.isEmpty {
            let sorted = Array(sourcesSet).sorted {
                effectivePriorityRank(for: $0.displayName) < effectivePriorityRank(for: $1.displayName)
            }
            self.availableSources = sorted
            self.availableDevices = sorted.map(\.displayName)
        }
        
        // 1. Sleep
        self.primarySleepSession = summary.sleep.primarySession
        self.allSleepSessions = summary.sleep.allSessions
        self.daytimeNaps = summary.sleep.naps
        
        // 2. Activity
        self.hourlySteps = summary.activity.hourlySteps
        if selectedDeviceSource == nil && selectedDeviceFilter == nil, let allSteps = summary.allDevicesView?["steps"], let v = allSteps.value {
            self.totalStepsToday = Int(v)
            self.stepsSourceDevice = (allSteps.sourceKey ?? summary.activity.sourceDevice).map { DeviceSource.from(name: $0).displayName }
        } else {
            self.totalStepsToday = summary.activity.totalSteps
            self.stepsSourceDevice = summary.activity.sourceDevice.map { DeviceSource.from(name: $0).displayName }
        }
        
        if selectedDeviceSource == nil && selectedDeviceFilter == nil, let allCal = summary.allDevicesView?["active_energy"], let v = allCal.value {
            self.totalActiveCalories = v
        } else {
            self.totalActiveCalories = summary.activity.activeCalories
        }
        
        // 3. Cardiovascular & Zones
        var hrPoints = summary.cardiovascular.intradayPoints
        if let filter = selectedDeviceFilter, !filter.isEmpty {
            hrPoints = hrPoints.filter { $0.sourceDevice?.localizedCaseInsensitiveContains(filter) == true }
        }
        self.intradayHeartRate = hrPoints
        self.averageBpm = summary.cardiovascular.averageBpm ?? 0
        self.restingBpm = summary.cardiovascular.restingBpm ?? 0
        self.minBpm = summary.cardiovascular.minBpm ?? 0
        self.maxBpm = summary.cardiovascular.maxBpm ?? 0
        if let lBpm = summary.cardiovascular.latestBpm, lBpm >= 30 {
            self.resolvedLatestBpm = lBpm
            self.latestBpmAt = summary.cardiovascular.latestBpmAt ?? summary.computedAt
            self.latestBpmSource = summary.cardiovascular.latestSourceDevice.map { DeviceSource.from(name: $0).displayName }
        } else if let lastPt = hrPoints.last {
            self.resolvedLatestBpm = lastPt.bpm
            self.latestBpmAt = lastPt.timestamp
            self.latestBpmSource = lastPt.sourceDevice.map { DeviceSource.from(name: $0).displayName }
        }
        self.heartRateZones = [
            .resting: summary.cardiovascular.zones.resting,
            .fatBurn: summary.cardiovascular.zones.fatBurn,
            .cardio: summary.cardiovascular.zones.cardio,
            .peak: summary.cardiovascular.zones.peak
        ]
        
        // 4. Stress
        if let stress = summary.stress {
            self.currentStressScore = stress.currentScore
            self.currentStressLevel = stress.currentLevel
            self.intradayStress = stress.intradayPoints
            let breathing = BreathingProtocol(rawValue: stress.recommendedBreathing) ?? .boxBreathing
            let result = StressAnalysisResult(
                currentScore: stress.currentScore,
                currentLevel: stress.currentLevel,
                dailyAverageScore: stress.dailyAverage,
                peakHour: stress.peakHour,
                peakScore: stress.peakScore,
                lowestHour: stress.lowestHour,
                lowestScore: stress.lowestScore,
                parasympatheticPercent: stress.parasympatheticPercent,
                sympatheticPercent: stress.sympatheticPercent,
                baselineHrvMs: stress.baselineHrvMs,
                currentHrvMs: stress.currentHrvMs,
                hrvDeltaPercent: stress.hrvDeltaPercent,
                restingHeartRateBpm: stress.restingHeartRateBpm,
                currentSedentaryBpm: stress.currentSedentaryBpm,
                heartRateElevationBpm: stress.heartRateElevationBpm,
                monkeyMood: stress.monkeyMood,
                adviceQuote: stress.adviceQuote,
                recommendedBreathing: breathing,
                lastUpdated: summary.computedAt
            )
            self.stressAnalysis = result
            
            if Calendar.current.isDateInToday(selectedDate) {
                WidgetDataCoordinator.shared.updateStressSnapshot(
                    score: result.currentScore,
                    level: result.currentLevel,
                    monkeyMood: result.monkeyMood,
                    advice: result.adviceQuote,
                    hrvMs: result.currentHrvMs,
                    restingHeartRate: result.restingHeartRateBpm,
                    parasympathetic: result.parasympatheticPercent,
                    sympathetic: result.sympatheticPercent
                )
            }
        } else {
            self.currentStressScore = 0
            self.currentStressLevel = .calm
            self.intradayStress = []
            self.stressAnalysis = nil
            if Calendar.current.isDateInToday(selectedDate) {
                WidgetDataCoordinator.shared.clearStressSnapshot()
            }
        }
        
        // 5. Vitals Map
        var vitalsMap: [HealthMetricType: VitalMetricRecord] = [:]
        for (k, v) in summary.vitals {
            if let type = HealthMetricType.from(rawString: k) ?? HealthMetricType.from(rawString: v.type) {
                vitalsMap[type] = VitalMetricRecord(
                    userId: "canonical",
                    type: type.rawValue,
                    value: v.value,
                    unit: v.unit,
                    date: dateKey,
                    sourceDevice: v.sourceDevice,
                    createdAt: v.timestamp
                )
            }
        }
        
        // If All Devices is selected, overlay freshest biometrics from allDevicesView
        if selectedDeviceSource == nil && selectedDeviceFilter == nil, let allView = summary.allDevicesView {
            for (metricKey, item) in allView {
                if let type = HealthMetricType.from(rawString: metricKey), let v = item.value {
                    let updatedDate: Date? = Self.parseIsoTimestamp(item.updatedAt)
                    vitalsMap[type] = VitalMetricRecord(
                        userId: "canonical",
                        type: type.rawValue,
                        value: v,
                        unit: item.unit ?? type.defaultUnit,
                        date: dateKey,
                        sourceDevice: item.sourceKey,
                        createdAt: updatedDate
                    )
                }
            }
        }
        
        if let lBpm = self.resolvedLatestBpm, lBpm >= 30 {
            vitalsMap[.heartRate] = VitalMetricRecord(
                userId: "canonical",
                type: HealthMetricType.heartRate.rawValue,
                value: lBpm,
                unit: "bpm",
                date: dateKey,
                sourceDevice: self.latestBpmSource ?? summary.cardiovascular.latestSourceDevice,
                createdAt: self.latestBpmAt
            )
        }
        
        if let stress = summary.stress {
            let stressSrc = stress.sourceDevice ?? self.latestBpmSource ?? summary.activity.sourceDevice ?? "Canonical Engine"
            vitalsMap[.stress] = VitalMetricRecord(
                userId: "canonical",
                type: HealthMetricType.stress.rawValue,
                value: Double(stress.currentScore),
                unit: "score",
                date: dateKey,
                sourceDevice: DeviceSource.from(name: stressSrc).isVirtualEngine ? stressSrc : DeviceSource.from(name: stressSrc).displayName
            )
        }
        
        if vitalsMap[.hydration] == nil {
            let waterMl = HabitsService.shared.totalWaterMlToday
            if waterMl > 0 {
                vitalsMap[.hydration] = VitalMetricRecord(
                    userId: "habits",
                    type: HealthMetricType.hydration.rawValue,
                    value: Double(waterMl),
                    unit: "ml",
                    date: dateKey,
                    sourceDevice: "Bubbles"
                )
            }
        }
        
        self.currentVitals = vitalsMap
        
        // 6. Update Sleep Snapshot for Widget
        if Calendar.current.isDateInToday(selectedDate) {
            WidgetDataCoordinator.shared.updateSleepSnapshot(
                from: summary.sleep.primarySession,
                restingHeartRate: self.restingBpm > 0 ? self.restingBpm : nil,
                hrvMs: summary.vitals["hrv_sdnn"]?.value ?? summary.stress?.currentHrvMs
            )
        }
    }
    
    private func ensureLocalDeviceSourcesPopulated() {
        let sourcesSet = Set(
            (availableDevices.map { DeviceSource.from(name: $0) } + availableSources)
                .filter { !$0.isVirtualEngine }
        )
        let sorted = Array(sourcesSet).sorted()
        self.availableSources = sorted
        self.availableDevices = sorted.map(\.displayName)
    }
    
    private func mergeLocalTelemetryWithSummary(telemetry: [HealthTelemetryRecord], isToday: Bool) {
        guard !telemetry.isEmpty else { return }
        let dateKey = isoDateFormatter.string(from: selectedDate)
        
        // 1. Devices & Sources
        var devicesSet = Set(self.availableDevices)
        var sourcesSet = Set(self.availableSources)
        for t in telemetry {
            if let d = t.sourceDevice, !d.isEmpty {
                let src = DeviceSource.from(name: d)
                if !src.isVirtualEngine {
                    devicesSet.insert(d)
                    sourcesSet.insert(src)
                }
            }
        }
        self.availableDevices = Array(devicesSet).sorted()
        self.availableSources = Array(sourcesSet).sorted()
        ensureLocalDeviceSourcesPopulated()
        
        // 2. Activity (Steps & Active Calories)
        let stepCalc = Self.calculateDailySteps(
            targetDate: selectedDate,
            telemetry: telemetry,
            vitalsSummary: [:],
            preferredDevice: selectedDeviceFilter,
            preferredSource: selectedDeviceSource,
            calendar: Calendar.current
        )
        if selectedDeviceSource == nil && selectedDeviceFilter == nil {
            // In "All Devices" mode, do not downgrade canonical summary with lower local phone pedometer steps
            if stepCalc.totalSteps > self.totalStepsToday {
                self.totalStepsToday = stepCalc.totalSteps
                self.hourlySteps = stepCalc.hourlyBuckets
                self.stepsSourceDevice = stepCalc.sourceDeviceUsed
            } else if self.hourlySteps.isEmpty && stepCalc.totalSteps > 0 {
                self.hourlySteps = stepCalc.hourlyBuckets
                if self.stepsSourceDevice == nil {
                    self.stepsSourceDevice = stepCalc.sourceDeviceUsed
                }
            }
        } else {
            if isToday || stepCalc.totalSteps > self.totalStepsToday {
                if stepCalc.totalSteps > 0 {
                    self.totalStepsToday = stepCalc.totalSteps
                    self.hourlySteps = stepCalc.hourlyBuckets
                    self.stepsSourceDevice = stepCalc.sourceDeviceUsed
                }
            }
        }
        
        let activeCals = telemetry.filter { $0.type == "active_energy" }.compactMap { $0.value }.reduce(0, +)
        if selectedDeviceSource == nil && selectedDeviceFilter == nil {
            if activeCals > self.totalActiveCalories {
                self.totalActiveCalories = activeCals
            } else if self.totalActiveCalories == 0 && stepCalc.activeCalories > 0 {
                self.totalActiveCalories = stepCalc.activeCalories
            }
        } else {
            if (isToday || activeCals > self.totalActiveCalories) && activeCals > 0 {
                self.totalActiveCalories = activeCals
            } else if self.totalActiveCalories == 0 && stepCalc.activeCalories > 0 {
                self.totalActiveCalories = stepCalc.activeCalories
            }
        }
        
        // 3. Intraday Heart Rate
        let hrSamples = telemetry.filter { $0.isHeartRate && ($0.value ?? 0) > 0 }
        if !hrSamples.isEmpty {
            let points = hrSamples.compactMap { t -> IntradayHeartRatePoint? in
                guard let val = t.value else { return nil }
                return IntradayHeartRatePoint(timestamp: t.startTime, bpm: val, sourceDevice: t.sourceDevice)
            }.sorted { $0.timestamp < $1.timestamp }
            
            if self.intradayHeartRate.isEmpty || (isToday && points.count >= self.intradayHeartRate.count) {
                self.intradayHeartRate = points
                let bpms = points.map { $0.bpm }
                self.averageBpm = bpms.reduce(0, +) / Double(bpms.count)
                self.minBpm = bpms.min() ?? 0
                self.maxBpm = bpms.max() ?? 0
                var zones: [HeartRateZone: Int] = [.resting: 0, .fatBurn: 0, .cardio: 0, .peak: 0]
                for pt in points {
                    zones[pt.zone, default: 0] += 1
                }
                self.heartRateZones = zones
            }
        }
        
        // 4. Vitals Map Enrichment
        var updatedVitals = self.currentVitals
        for t in telemetry.sorted(by: { $0.startTime < $1.startTime }) {
            guard let val = t.value, val > 0,
                  let metricType = HealthMetricType.from(rawString: t.type) else { continue }
            if metricType == .steps || t.isSleep || t.isSleepStage { continue }
            
            let existing = updatedVitals[metricType]
            if existing == nil || t.startTime >= (existing?.createdAt ?? Date.distantPast) {
                updatedVitals[metricType] = VitalMetricRecord(
                    userId: t.userId,
                    type: metricType.rawValue,
                    value: val,
                    unit: t.unit ?? metricType.defaultUnit,
                    date: dateKey,
                    sourceDevice: t.sourceDevice,
                    createdAt: t.startTime
                )
            }
        }
        self.currentVitals = updatedVitals
        
        // 5. Resting Heart Rate from vitals if missing
        if self.restingBpm == 0, let rhr = updatedVitals[.restingHeartRate]?.value {
            self.restingBpm = rhr
        }
        
        // 6. Sleep fallback if summary sleep was nil
        if self.primarySleepSession == nil {
            var vitalsSummary: [HealthMetricType: Double] = [:]
            for (k, v) in updatedVitals {
                vitalsSummary[k] = v.value
            }
            let sleepResult = SleepClusteringEngine.clusterSleep(
                targetDate: selectedDate,
                telemetry: telemetry,
                vitalsSummary: vitalsSummary,
                preferredDevice: selectedDeviceFilter
            )
            if sleepResult.primarySession != nil {
                self.primarySleepSession = sleepResult.primarySession
                self.allSleepSessions = sleepResult.allSessions
                self.daytimeNaps = sleepResult.naps
            }
        }
        
        // 7. Update Widget Snapshot if today
        if Calendar.current.isDateInToday(selectedDate) {
            WidgetDataCoordinator.shared.updateSleepSnapshot(
                from: self.primarySleepSession,
                restingHeartRate: self.restingBpm > 0 ? self.restingBpm : nil,
                hrvMs: updatedVitals[.hrvSdnn]?.value ?? updatedVitals[.hrvRmssd]?.value
            )
        }
    }
    
    private func applyRecords(telemetry: [HealthTelemetryRecord], vitals: [VitalMetricRecord]) async {
        // Collect available devices and canonical sources (filtering out virtual computational engines like StressWatch/Daily Biometric Engine)
        var devicesSet = Set<String>()
        var sourcesSet = Set<DeviceSource>()
        for t in telemetry {
            if let d = t.sourceDevice, !d.isEmpty {
                let src = DeviceSource.from(name: d)
                if !src.isVirtualEngine {
                    devicesSet.insert(d)
                    sourcesSet.insert(src)
                }
            }
        }
        for v in vitals {
            if let d = v.sourceDevice, !d.isEmpty {
                let src = DeviceSource.from(name: d)
                if !src.isVirtualEngine {
                    devicesSet.insert(d)
                    sourcesSet.insert(src)
                }
            }
        }
        availableDevices = Array(devicesSet).sorted()
        availableSources = Array(sourcesSet).sorted()
        ensureLocalDeviceSourcesPopulated()
        
        await processDataForCurrentDate()
    }
    
    private func processDataForCurrentDate() async {
        let dateKey = isoDateFormatter.string(from: selectedDate)
        guard let cached = telemetryCache[dateKey] else { return }
        
        var telemetry = cached.telemetry
        var vitals = cached.vitals
        
        // Filter by device source if active
        if let filterSource = selectedDeviceSource {
            telemetry = telemetry.filter { DeviceSource.from(name: $0.sourceDevice) == filterSource }
            vitals = vitals.filter { DeviceSource.from(name: $0.sourceDevice) == filterSource }
        } else if let filter = selectedDeviceFilter, !filter.isEmpty {
            telemetry = telemetry.filter { $0.sourceDevice?.localizedCaseInsensitiveContains(filter) == true }
            vitals = vitals.filter { $0.sourceDevice?.localizedCaseInsensitiveContains(filter) == true }
        }
        
        // Vitals map
        var vitalsMap: [HealthMetricType: VitalMetricRecord] = [:]
        var vitalsValues: [HealthMetricType: Double] = [:]
        for v in vitals {
            if let type = v.metricType {
                if let dev = v.sourceDevice, DeviceSource.from(name: dev).isVirtualEngine {
                    continue
                }
                vitalsMap[type] = v
                vitalsValues[type] = v.value
            }
        }
        
        // Enrich/synthesize missing vitals from telemetry (e.g. from ZeppOS Amazfit, WearOS, HarmonyOS, or Apple Health)
        let sortedTelemetry = telemetry.sorted { $0.startTime < $1.startTime }
        for t in sortedTelemetry {
            guard let val = t.value, val > 0,
                  let metricType = HealthMetricType.from(rawString: t.type) else { continue }
            
            // Skip steps and sleep stages which are handled by dedicated engines
            if metricType == .steps || t.isSleep || t.isSleepStage {
                continue
            }
            
            // Populate if not already present or if telemetry has a fresher sample
            if vitalsMap[metricType] == nil || (t.startTime >= (vitalsMap[metricType]?.createdAt ?? Date.distantPast)) {
                let record = VitalMetricRecord(
                    userId: t.userId,
                    type: metricType.rawValue,
                    value: val,
                    unit: t.unit ?? metricType.defaultUnit,
                    date: dateKey,
                    sourceDevice: t.sourceDevice,
                    createdAt: t.startTime
                )
                vitalsMap[metricType] = record
                vitalsValues[metricType] = val
            }
        }
        self.currentVitals = vitalsMap
        
        // 1. Process Sleep using SleepClusteringEngine
        let sleepResult = SleepClusteringEngine.clusterSleep(
            targetDate: selectedDate,
            telemetry: telemetry,
            vitalsSummary: vitalsValues,
            preferredDevice: selectedDeviceFilter
        )
        self.primarySleepSession = sleepResult.primarySession
        self.allSleepSessions = sleepResult.allSessions
        self.daytimeNaps = sleepResult.naps
        
        if self.primarySleepSession == nil && (ProcessInfo.processInfo.arguments.contains("-testSleepStudio") || ProcessInfo.processInfo.arguments.contains("-demoHealth")) {
            let demo = generateDemoData(for: selectedDate)
            let demoSleepResult = SleepClusteringEngine.clusterSleep(
                targetDate: selectedDate,
                telemetry: demo.telemetry,
                vitalsSummary: vitalsValues,
                preferredDevice: nil
            )
            self.primarySleepSession = demoSleepResult.primarySession
            self.allSleepSessions = demoSleepResult.allSessions
            self.daytimeNaps = demoSleepResult.naps
        }
        
        if Calendar.current.isDateInToday(selectedDate) {
            WidgetDataCoordinator.shared.updateSleepSnapshot(
                from: sleepResult.primarySession,
                restingHeartRate: vitalsValues[.restingHeartRate] ?? (self.restingBpm > 0 ? self.restingBpm : nil),
                hrvMs: vitalsValues[.hrvSdnn]
            )
        }
        
        // 2. Process Heart Rate
        let cal = Calendar.current
        let hrTelemetry = telemetry.filter { $0.isHeartRate && cal.isDate($0.startTime, inSameDayAs: selectedDate) }
        var hrPoints: [IntradayHeartRatePoint] = []
        for r in hrTelemetry {
            if let bpm = r.value, bpm > 30 && bpm < 240 {
                hrPoints.append(IntradayHeartRatePoint(
                    id: r.id,
                    timestamp: r.startTime,
                    bpm: bpm,
                    sourceDevice: r.sourceDevice
                ))
            }
        }
        self.intradayHeartRate = hrPoints.sorted { $0.timestamp < $1.timestamp }
        
        if !hrPoints.isEmpty {
            let bpms = hrPoints.map(\.bpm)
            self.averageBpm = round(bpms.reduce(0, +) / Double(bpms.count))
            self.minBpm = bpms.min() ?? 0
            self.maxBpm = bpms.max() ?? 0
            self.restingBpm = vitalsValues[.restingHeartRate] ?? (self.minBpm > 0 ? self.minBpm + 4 : 62)
            
            // Heart Rate Zones distribution
            var zones: [HeartRateZone: Int] = [.resting: 0, .fatBurn: 0, .cardio: 0, .peak: 0]
            for pt in hrPoints {
                zones[pt.zone, default: 0] += 1
            }
            self.heartRateZones = zones
        } else {
            self.averageBpm = vitalsValues[.heartRate] ?? 0
            self.restingBpm = vitalsValues[.restingHeartRate] ?? 0
            self.minBpm = 0
            self.maxBpm = 0
            self.heartRateZones = [:]
        }
        
        // 3. Process Steps & Hourly Cadence
        let stepsResult = Self.calculateDailySteps(
            targetDate: selectedDate,
            telemetry: telemetry,
            vitalsSummary: vitalsValues,
            preferredDevice: selectedDeviceFilter,
            preferredSource: selectedDeviceSource,
            calendar: cal
        )
        self.hourlySteps = stepsResult.hourlyBuckets
        self.totalStepsToday = stepsResult.totalSteps
        self.totalActiveCalories = stepsResult.activeCalories
        self.stepsSourceDevice = stepsResult.sourceDeviceUsed
        
        // Ensure restingHeartRate in vitalsMap if computed
        if vitalsMap[.restingHeartRate] == nil && self.restingBpm > 0 {
            let rhrRecord = VitalMetricRecord(
                userId: "computed",
                type: HealthMetricType.restingHeartRate.rawValue,
                value: self.restingBpm,
                unit: "bpm",
                date: dateKey,
                sourceDevice: selectedDeviceFilter ?? selectedDeviceSource?.displayName ?? "Biometric Engine"
            )
            vitalsMap[.restingHeartRate] = rhrRecord
            vitalsValues[.restingHeartRate] = self.restingBpm
        }
        
        // Ensure hydration in vitalsMap if logged in Habits
        if vitalsMap[.hydration] == nil {
            let waterMl = HabitsService.shared.totalWaterMlToday
            if waterMl > 0 {
                let hydRecord = VitalMetricRecord(
                    userId: "habits",
                    type: HealthMetricType.hydration.rawValue,
                    value: Double(waterMl),
                    unit: "ml",
                    date: dateKey,
                    sourceDevice: "Bubbles"
                )
                vitalsMap[.hydration] = hydRecord
                vitalsValues[.hydration] = Double(waterMl)
            }
        }
        
        // 4. Process Stress Level (Autonomic tone physiological model v2.0)
        let hasSdnnRaw = (vitalsValues[.hrvSdnn] ?? 0) > 0
        let hasRmssdRaw = !hasSdnnRaw && (vitalsValues[.hrvRmssd] ?? 0) > 0
        let hrvVal = hasSdnnRaw ? vitalsValues[.hrvSdnn] : (hasRmssdRaw ? vitalsValues[.hrvRmssd] : nil)
        let stressCalculation = StressAnalysisEngine.calculateStress(
            targetDate: selectedDate,
            hrvMs: hrvVal,
            isRmssd: hasRmssdRaw,
            hrTelemetry: self.intradayHeartRate,
            hourlySteps: self.hourlySteps,
            restingBpm: vitalsValues[.restingHeartRate] ?? (self.restingBpm > 0 ? self.restingBpm : nil),
            priorSleepScore: self.primarySleepSession?.sleepScore,
            personalBaselineHrv: nil,
            personalBaselineRhr: nil,
            calendar: cal
        )
        
        if let stressCalculation = stressCalculation {
            self.stressAnalysis = stressCalculation.result
            self.intradayStress = stressCalculation.intradayPoints
            self.currentStressScore = stressCalculation.result.currentScore
            self.currentStressLevel = stressCalculation.result.currentLevel
            
            // Resolve honest source device
            let resolvedSourceDevice: String = {
                if let filter = selectedDeviceFilter, !filter.isEmpty {
                    return filter
                }
                if let src = selectedDeviceSource?.displayName {
                    return src
                }
                let legacyFilter: (String) -> Bool = { name in
                    !name.isEmpty && !DeviceSource.from(name: name).isVirtualEngine
                }
                if let hrvSource = vitalsMap[.hrvSdnn]?.sourceDevice ?? vitalsMap[.hrvRmssd]?.sourceDevice, legacyFilter(hrvSource) {
                    return hrvSource
                }
                if let hrSource = self.intradayHeartRate.last(where: { $0.sourceDevice != nil && legacyFilter($0.sourceDevice!) })?.sourceDevice {
                    return hrSource
                }
                return "Daily Biometric Engine"
            }()
            
            // Always update stress metric in vitalsMap with fresh calculation and honest source
            let stressRecord = VitalMetricRecord(
                userId: "stress-engine",
                type: HealthMetricType.stress.rawValue,
                value: Double(self.currentStressScore),
                unit: "score",
                date: dateKey,
                sourceDevice: resolvedSourceDevice
            )
            vitalsMap[.stress] = stressRecord
            vitalsValues[.stress] = Double(self.currentStressScore)
            
            // Update Widget Coordinator with fresh stress snapshot if today
            if Calendar.current.isDateInToday(selectedDate) {
                WidgetDataCoordinator.shared.updateStressSnapshot(
                    score: stressCalculation.result.currentScore,
                    level: stressCalculation.result.currentLevel,
                    monkeyMood: stressCalculation.result.monkeyMood,
                    advice: stressCalculation.result.adviceQuote,
                    hrvMs: stressCalculation.result.currentHrvMs,
                    restingHeartRate: stressCalculation.result.restingHeartRateBpm,
                    parasympathetic: stressCalculation.result.parasympatheticPercent,
                    sympathetic: stressCalculation.result.sympatheticPercent
                )
            }
        } else {
            self.stressAnalysis = nil
            self.intradayStress = []
            self.currentStressScore = 0
            self.currentStressLevel = .calm
            vitalsMap.removeValue(forKey: .stress)
            vitalsValues.removeValue(forKey: .stress)
            
            WidgetDataCoordinator.shared.clearStressSnapshot()
        }
        
        self.currentVitals = vitalsMap
        
        // Persist daily vitals locally for instant offline/calendar access
        let vitalsList = Array(vitalsMap.values)
        if let encoded = try? JSONEncoder().encode(vitalsList) {
            userDefaults.set(encoded, forKey: "health_daily_vitals_\(dateKey)")
        }
    }
    
    /// Deprecated in Architecture V3 (vitals table was dropped in migration 20261007095958).
    /// Retained as a safe no-op for backward compatibility.
    public func syncVitalsToSupabase(vitals: [VitalMetricRecord]) async {
        // No-op in Architecture V3: canonical aggregates are computed into health_daily_summary
    }
    
    // MARK: - Lean Health Ingestion (Phase 2)
    
    /// Syncs local on-device health data to Supabase lean tables:
    /// - health_sleep_sessions (clustered discrete sessions, 1-2 rows/day)
    /// - health_daily_vitals (consolidated vitals, 1 row/day/device)
    /// - health_intraday_heart_rate (5-minute buckets, max 288 rows/day/device)
    /// - health_sources (hardware registration)
    public func syncTelemetryToSupabase(telemetry: [HealthTelemetryRecord]) async {
        guard AuthService.shared.isAuthenticated,
              let session = try? await supabase.auth.session,
              let userId = session.user.id.uuidString.lowercased() as String?,
              !telemetry.isEmpty else { return }
        
        let hostName = localDataProvider?.hostPhoneName ?? "Schmitz"
        
        // Group FULL telemetry by localDate ("YYYY-MM-DD") so daily step/kcal totals and retroactive Oura syncs are never truncated
        let recordsByDate = Dictionary(grouping: telemetry) { r -> String in
            r.localDate ?? isoDateFormatter.string(from: r.startTime)
        }
        
        var anySyncSucceeded = false
        var affectedDates = Set<String>()
        let now = Date()
        
        for (dateKey, dateRecords) in recordsByDate {
            let totalVal = dateRecords.compactMap(\.value).reduce(0.0, +)
            let maxEnd = dateRecords.map { ($0.endTime ?? $0.startTime).timeIntervalSince1970 }.max() ?? 0
            let signature = "\(dateRecords.count)_\(Int(round(totalVal)))_\(Int(maxEnd))"
            if let prev = lastSyncedSignatureByDate[dateKey],
               prev.signature == signature,
               now.timeIntervalSince(prev.timestamp) < 90 {
                continue
            }
            
            let targetDate = isoDateFormatter.date(from: dateKey) ?? now
            
            // 1. Sync Clustered Sleep Sessions to `health_sleep_sessions`
            let sleepOk = await syncLeanSleepSessions(
                records: dateRecords,
                targetDate: targetDate,
                dateKey: dateKey,
                userId: userId,
                hostName: hostName
            )
            
            // 2. Sync 5-minute Intraday Heart Rate Buckets to `health_intraday_heart_rate` BEFORE daily_vitals
            let hrOk = await syncLeanIntradayHeartRate(
                records: dateRecords,
                targetDate: targetDate,
                dateKey: dateKey,
                userId: userId
            )
            
            // 3. Sync Consolidated Daily Vitals (including spot `latest_heart_rate` & `vitals_timestamps`) to `health_daily_vitals`
            let vitalsOk = await syncLeanDailyVitals(
                records: dateRecords,
                targetDate: targetDate,
                dateKey: dateKey,
                userId: userId,
                hostName: hostName
            )
            
            if sleepOk || vitalsOk || hrOk {
                lastSyncedSignatureByDate[dateKey] = (timestamp: now, signature: signature)
                anySyncSucceeded = true
                affectedDates.insert(dateKey)
            }
        }
        
        // 4. Ensure local physical devices are registered in `health_sources` without clobbering custom priority order
        await registerLocalHealthSources(userId: userId, hostName: hostName, telemetry: telemetry)
        
        if anySyncSucceeded {
            let maxEpoch = telemetry.map { ($0.endTime ?? $0.startTime).timeIntervalSince1970 * 1000 }.max() ?? 0
            if maxEpoch > self.lastPushedTelemetryEpochMs {
                self.lastPushedTelemetryEpochMs = maxEpoch
            }
            for dKey in affectedDates {
                let fp = lastSyncedSignatureByDate[dKey]?.signature
                triggerCanonicalEngineIfNeeded(for: dKey, userId: userId, fingerprint: fp)
            }
        }
    }
    
    private func syncLeanSleepSessions(
        records: [HealthTelemetryRecord],
        targetDate: Date,
        dateKey: String,
        userId: String,
        hostName: String
    ) async -> Bool {
        let sleepRecords = records.filter { $0.isSleep || $0.isSleepStage }
        guard !sleepRecords.isEmpty else { return false }
        
        let clusterResult = SleepClusteringEngine.clusterSleep(
            targetDate: targetDate,
            telemetry: sleepRecords,
            vitalsSummary: [:],
            preferredDevice: nil
        )
        
        let sessions = Self.buildLeanSleepSessionRecords(
            primarySession: clusterResult.primarySession,
            allSessions: clusterResult.allSessions,
            naps: clusterResult.naps,
            dateKey: dateKey,
            userId: userId,
            hostName: hostName
        )
        
        guard !sessions.isEmpty else { return false }
        var success = true
        for session in sessions {
            do {
                try await supabase.from("health_sleep_sessions")
                    .upsert(session, onConflict: "user_id,local_date,session_type,source_device_key")
                    .execute()
            } catch {
                print("[HealthDataService] Warning: Failed to upsert sleep session: \(error.localizedDescription)")
                success = false
            }
        }
        return success
    }
    
    private func syncLeanDailyVitals(
        records: [HealthTelemetryRecord],
        targetDate: Date,
        dateKey: String,
        userId: String,
        hostName: String
    ) async -> Bool {
        let vitalsList = Self.buildLeanDailyVitalsRecords(
            records: records,
            targetDate: targetDate,
            dateKey: dateKey,
            userId: userId,
            hostName: hostName
        )
        guard !vitalsList.isEmpty else { return false }
        var success = true
        for vitals in vitalsList {
            do {
                try await supabase.from("health_daily_vitals")
                    .upsert(vitals, onConflict: "user_id,local_date,source_device_key")
                    .execute()
            } catch {
                print("[HealthDataService] Warning: Failed to upsert daily vitals: \(error.localizedDescription)")
                success = false
            }
        }
        return success
    }
    
    private func syncLeanIntradayHeartRate(
        records: [HealthTelemetryRecord],
        targetDate: Date,
        dateKey: String,
        userId: String
    ) async -> Bool {
        let buckets = Self.groupIntradayHeartRateIntoBuckets(
            records: records,
            userId: userId,
            dateKey: dateKey
        )
        guard !buckets.isEmpty else { return false }
        var success = true
        let batchSize = 100
        for i in stride(from: 0, to: buckets.count, by: batchSize) {
            let chunk = Array(buckets[i..<min(i + batchSize, buckets.count)])
            do {
                try await supabase.from("health_intraday_heart_rate")
                    .upsert(chunk, onConflict: "user_id,local_date,source_device_key,bucket_minute")
                    .execute()
            } catch {
                print("[HealthDataService] Warning: Failed to upsert intraday HR chunk: \(error.localizedDescription)")
                success = false
            }
        }
        return success
    }
    
    nonisolated private static func canonicalSlug(_ name: String) -> String {
        let lower = name.lowercased()
        let cleaned = lower.replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
    
    private func registerLocalHealthSources(userId: String, hostName: String, telemetry: [HealthTelemetryRecord]) async {
        let canonicalSources = Set(
            telemetry
                .compactMap { $0.sourceDevice }
                .map { DeviceSource.from(name: $0) }
                .filter { !$0.isVirtualEngine && $0 != .manual }
        )
        guard !canonicalSources.isEmpty else { return }
        
        for src in canonicalSources {
            let displayName = src.displayName
            let dLower = displayName.lowercased()
            let sourceId = Self.canonicalSourceId(for: src, displayName: displayName)
            
            // Skip redundant upsert if already registered with custom user priority
            if let existing = currentLeanSources.first(where: { $0.id == sourceId || DeviceSource.from(name: $0.displayName) == src }) {
                if existing.isCustomPriority {
                    continue
                }
            }
            
            let kind: String = {
                switch src {
                case .oura: return "ring"
                case .appleWatch, .pixelWatch, .fitbit, .oneplus, .amazfit, .huawei, .garmin, .polar: return "watch"
                case .whoop, .withings: return "wearable"
                default: return "phone"
                }
            }()
            let platform = (src == .appleWatch || src == .healthKit || dLower.contains("schmitz") || hostName.localizedCaseInsensitiveContains("schmitz")) ? "iOS" : "Android"
            let vendor: String = {
                switch src {
                case .oura: return "Oura"
                case .appleWatch, .healthKit: return "Apple"
                case .pixelWatch, .fitbit: return "Google"
                case .oneplus: return "OnePlus"
                case .samsungHealth: return "Samsung"
                default:
                    if dLower.contains("schmitz") || dLower.contains("iphone") { return "Apple" }
                    if dLower.contains("trapper") || dLower.contains("pixel") { return "Google" }
                    if dLower.contains("radar") || dLower.contains("galaxy") || dLower.contains("fold") { return "Samsung" }
                    return displayName
                }
            }()
            let color = DeviceColorPalette.getColor(for: displayName)
            // Unified 1-based ascending default rank (1 = Oura, 2 = AW, 3 = PW5, 4 = OnePlus, 5 = Other Wearable, 10..12 = Phones)
            let dbPriority = src.sortPriority
            
            let record = HealthSourceRecord(
                id: sourceId,
                userId: userId,
                platform: platform,
                deviceKind: kind,
                vendor: vendor,
                model: nil,
                displayName: displayName,
                hostDeviceName: hostName,
                prioritySleep: dbPriority,
                priorityActivity: dbPriority,
                isCustomPriority: false,
                color: color,
                createdAt: Date()
            )
            
            do {
                try await supabase.from("health_sources").upsert(record, onConflict: "id").execute()
            } catch {
                // Non-fatal background device registration
            }
        }
    }
    
    // MARK: - Static Lean Builders
    
    nonisolated public static func groupIntradayHeartRateIntoBuckets(
        records: [HealthTelemetryRecord],
        userId: String,
        dateKey: String,
        calendar: Calendar = Calendar.current
    ) -> [HealthIntradayHeartRateRecord] {
        let hrRecords = records.filter { $0.isHeartRate && ($0.value ?? 0) > 0 }
        guard !hrRecords.isEmpty else { return [] }
        
        struct BucketKey: Hashable {
            let sourceKey: String
            let bucketMinute: Int
        }
        struct BucketAgg {
            var weightedSum: Double = 0
            var totalCount: Int = 0
            var minBpm: Double = .greatestFiniteMagnitude
            var maxBpm: Double = 0
        }
        
        var buckets: [BucketKey: BucketAgg] = [:]
        for r in hrRecords {
            guard let bpm = r.value, bpm >= 30 && bpm <= 240 else { continue }
            let yr = calendar.component(.year, from: r.startTime)
            let mo = calendar.component(.month, from: r.startTime)
            let dy = calendar.component(.day, from: r.startTime)
            let sampleDateStr = String(format: "%04d-%02d-%02d", yr, mo, dy)
            if sampleDateStr != dateKey { continue }
            let rawKey = r.effectiveSourceKey.isEmpty ? (r.sourceDevice ?? "Schmitz (iPhone)") : r.effectiveSourceKey
            let src = DeviceSource.from(name: rawKey)
            if src.isVirtualEngine { continue }
            let canonKey = src.displayName
            let minute = calendar.component(.minute, from: r.startTime)
            let hour = calendar.component(.hour, from: r.startTime)
            let bucketMinute = hour * 60 + (minute / 5) * 5
            
            let bKey = BucketKey(sourceKey: canonKey, bucketMinute: bucketMinute)
            let cnt = max(1, r.sampleCount ?? 1)
            let rMin = (r.minValue ?? bpm) >= 30 ? (r.minValue ?? bpm) : bpm
            let rMax = (r.maxValue ?? bpm) <= 240 ? (r.maxValue ?? bpm) : bpm
            var agg = buckets[bKey] ?? BucketAgg()
            agg.weightedSum += bpm * Double(cnt)
            agg.totalCount += cnt
            agg.minBpm = min(agg.minBpm, rMin)
            agg.maxBpm = max(agg.maxBpm, rMax)
            buckets[bKey] = agg
        }
        
        var results: [HealthIntradayHeartRateRecord] = []
        for (bKey, agg) in buckets where agg.totalCount > 0 {
            let avg = agg.weightedSum / Double(agg.totalCount)
            let minBpm = agg.minBpm.isFinite ? agg.minBpm : avg
            let maxBpm = agg.maxBpm > 0 ? agg.maxBpm : avg
            let sourceSlug = canonicalSlug(bKey.sourceKey)
            let recordId = "hr_\(userId)_\(dateKey)_\(sourceSlug)_\(bKey.bucketMinute)"
            
            results.append(HealthIntradayHeartRateRecord(
                id: recordId,
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: bKey.sourceKey,
                bucketMinute: bKey.bucketMinute,
                bpmAvg: Int(round(avg)),
                bpmMin: Int(round(minBpm)),
                bpmMax: Int(round(maxBpm)),
                sampleCount: agg.totalCount,
                updatedAt: Date()
            ))
        }
        return results.sorted { $0.bucketMinute < $1.bucketMinute }
    }
    
    nonisolated public static func buildLeanSleepSessionRecords(
        primarySession: SleepSession?,
        allSessions: [SleepSession] = [],
        naps: [NapSession] = [],
        dateKey: String,
        userId: String,
        hostName: String = "Schmitz"
    ) -> [HealthSleepSessionRecord] {
        var results: [HealthSleepSessionRecord] = []
        let candidateSessions = allSessions.isEmpty ? [primarySession].compactMap { $0 } : allSessions
        var seenCanon = Set<String>()
        
        for session in candidateSessions {
            let src = DeviceSource.from(name: session.sourceDevice)
            if src.isVirtualEngine { continue }
            let canonKey = src.displayName
            guard seenCanon.insert(canonKey).inserted else { continue }
            
            let sourceSlug = canonicalSlug(canonKey)
            let id = "sleep_\(userId)_\(dateKey)_primary_sleep_\(sourceSlug)"
            let durationS = Int(session.asleepSeconds)
            let inBedS = Int(session.durationSeconds)
            guard durationS > 0 || inBedS > 0 else { continue }
            let efficiency = Double(session.efficiencyPercent)
            let priority = src.sortPriority
            
            results.append(HealthSleepSessionRecord(
                id: id,
                userId: userId,
                localDate: dateKey,
                sessionType: "primary_sleep",
                sourceDeviceKey: canonKey,
                hostDeviceName: hostName,
                startTime: session.startTime,
                endTime: session.endTime,
                durationSeconds: durationS,
                timeInBedSeconds: max(durationS, inBedS),
                efficiencyPercent: efficiency,
                sleepScore: session.sleepScore,
                deepSeconds: Int(session.deepSeconds),
                remSeconds: Int(session.remSeconds),
                lightSeconds: Int(session.lightSeconds),
                awakeSeconds: Int(session.awakeSeconds),
                latencySeconds: 0,
                qualityRating: session.sleepQualityRating,
                stages: session.stages,
                sourcePriority: priority,
                isUserSelected: false
            ))
        }
        
        for nap in naps {
            let src = DeviceSource.from(name: nap.sourceDevice)
            if src.isVirtualEngine { continue }
            let canonKey = src.displayName
            let sourceSlug = canonicalSlug(canonKey)
            let id = "sleep_\(userId)_\(dateKey)_nap_\(sourceSlug)"
            let durationS = Int(nap.durationSeconds)
            guard durationS > 0 else { continue }
            
            results.append(HealthSleepSessionRecord(
                id: id,
                userId: userId,
                localDate: dateKey,
                sessionType: "nap",
                sourceDeviceKey: canonKey,
                hostDeviceName: hostName,
                startTime: nap.startTime,
                endTime: nap.endTime,
                durationSeconds: durationS,
                timeInBedSeconds: durationS,
                efficiencyPercent: 100.0,
                sleepScore: nil,
                deepSeconds: 0,
                remSeconds: 0,
                lightSeconds: durationS,
                awakeSeconds: 0,
                latencySeconds: 0,
                qualityRating: "Nap",
                stages: [],
                sourcePriority: 99,
                isUserSelected: false
            ))
        }
        
        return results
    }
    
    nonisolated public static func buildLeanDailyVitalsRecords(
        records: [HealthTelemetryRecord],
        targetDate: Date,
        dateKey: String,
        userId: String,
        hostName: String = "Schmitz",
        calendar: Calendar = Calendar.current
    ) -> [HealthDailyVitalsRecord] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let bySource = Dictionary(grouping: records) { r -> String in
            let raw = r.effectiveSourceKey.isEmpty ? (r.sourceDevice ?? "\(hostName) (iPhone)") : r.effectiveSourceKey
            return DeviceSource.from(name: raw).displayName
        }
        
        var results: [HealthDailyVitalsRecord] = []
        for (canonKey, sourceRecords) in bySource {
            if DeviceSource.from(name: canonKey).isVirtualEngine { continue }
            
            let stepRecords = sourceRecords.filter { $0.type == "steps" }
            let totalSteps: Int
            let hourlyBuckets: [HourlyStepBucket]?
            if !stepRecords.isEmpty {
                let calc = Self.calculateDailySteps(
                    targetDate: targetDate,
                    telemetry: stepRecords,
                    vitalsSummary: [:],
                    preferredDevice: nil,
                    preferredSource: nil,
                    calendar: calendar
                )
                totalSteps = calc.totalSteps
                hourlyBuckets = calc.hourlyBuckets.isEmpty ? nil : calc.hourlyBuckets
            } else {
                totalSteps = 0
                hourlyBuckets = nil
            }
            
            func newestRecord(where predicate: (HealthTelemetryRecord) -> Bool) -> HealthTelemetryRecord? {
                sourceRecords
                    .filter { predicate($0) && $0.value != nil }
                    .max(by: { ($0.endTime ?? $0.startTime) < ($1.endTime ?? $1.startTime) })
            }
            
            var tsMap: [String: String] = [:]
            func extractLatest(_ key: String, where predicate: (HealthTelemetryRecord) -> Bool) -> Double? {
                guard let rec = newestRecord(where: predicate), let val = rec.value else { return nil }
                tsMap[key] = isoFormatter.string(from: rec.endTime ?? rec.startTime)
                return val
            }
            
            let activeKcal = sourceRecords.filter { $0.type == "active_energy" }.compactMap { $0.value }.reduce(0, +)
            let rhr = extractLatest("rhr") { $0.type == "resting_heart_rate" }.map { Int(round($0)) }
            let spo2 = extractLatest("spo2") { $0.type == "oxygen_saturation" }
            let resp = extractLatest("resp") { $0.type == "respiratory_rate" }
            let temp = extractLatest("temp") { $0.type == "wrist_temperature" || $0.type == "body_temperature" }
            let weight = extractLatest("weight") { $0.type == "weight" }
            let hrvSdnn = extractLatest("hrv_sdnn") { $0.type == "hrv_sdnn" }
            let hrvRmssd = extractLatest("hrv_rmssd") { $0.type == "hrv_rmssd" }
            
            let spotHrRec = newestRecord { $0.isLatestHeartRate && ($0.value ?? 0) >= 30 && ($0.value ?? 0) <= 240 }
            let bucketHrRec = newestRecord { $0.isHeartRate && ($0.value ?? 0) >= 30 && ($0.value ?? 0) <= 240 }
            let bestHrRec = spotHrRec ?? bucketHrRec
            let latestHr = bestHrRec?.value.map { Int(round($0)) }
            let latestHrAt = bestHrRec.map { $0.endTime ?? $0.startTime }
            
            guard totalSteps > 0 || activeKcal > 0 || rhr != nil || spo2 != nil || resp != nil || temp != nil || weight != nil || hrvSdnn != nil || hrvRmssd != nil || latestHr != nil else {
                continue
            }
            
            let sourceSlug = canonicalSlug(canonKey)
            let recordId = "vitals_\(userId)_\(dateKey)_\(sourceSlug)"
            
            results.append(HealthDailyVitalsRecord(
                id: recordId,
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: canonKey,
                hostDeviceName: hostName,
                steps: totalSteps,
                activeKcal: activeKcal,
                restingHeartRate: rhr,
                spo2: spo2,
                respiratoryRate: resp,
                skinTempCelsius: temp,
                weightKg: weight,
                hrvSdnnNightly: hrvSdnn,
                hrvRmssdNightly: hrvRmssd,
                hourlySteps: hourlyBuckets,
                latestHeartRate: latestHr,
                latestHrAt: latestHrAt,
                vitalsTimestamps: tsMap.isEmpty ? nil : tsMap,
                updatedAt: Date()
            ))
        }
        return results
    }
    
    private struct HealthEngineDatePayload: Encodable {
        let date: String
        let user_id: String
    }
    
    private struct HealthEngineDirtyPayload: Encodable {
        let user_id: String
        let process_dirty: Bool
    }
    
    /// Triggers the canonical Edge Function `health-engine` with payload-fingerprint deduplication and short coalescing,
    /// ensuring newly uploaded wearable readings immediately recompute `health_daily_summary` without quota burn.
    public func triggerCanonicalEngineIfNeeded(
        for dateKey: String,
        userId: String,
        fingerprint: String? = nil,
        force: Bool = false
    ) {
        let now = Date()
        if !force {
            if let fp = fingerprint,
               let prevFp = lastEnginePayloadFingerprint[dateKey],
               fp == prevFp,
               let last = lastEngineInvocation[dateKey],
               now.timeIntervalSince(last) < 180 {
                return
            }
            if fingerprint == nil,
               let last = lastEngineInvocation[dateKey],
               now.timeIntervalSince(last) < 180 {
                return
            }
            // Enforce a minimum 15s floor between non-forced invocations on the same date
            if let last = lastEngineInvocation[dateKey], now.timeIntervalSince(last) < 15 {
                pendingEngineDebounceTask[dateKey]?.cancel()
                pendingEngineDebounceTask[dateKey] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    guard let self = self, !Task.isCancelled else { return }
                    self.invokeCanonicalEngineNow(for: dateKey, userId: userId, fingerprint: fingerprint)
                }
                return
            }
        }
        
        pendingEngineDebounceTask[dateKey]?.cancel()
        if force {
            invokeCanonicalEngineNow(for: dateKey, userId: userId, fingerprint: fingerprint)
        } else {
            // Short 4-second coalesce so simultaneous multi-table uploads trigger a single computation
            pendingEngineDebounceTask[dateKey] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self = self, !Task.isCancelled else { return }
                self.invokeCanonicalEngineNow(for: dateKey, userId: userId, fingerprint: fingerprint)
            }
        }
    }
    
    private func invokeCanonicalEngineNow(for dateKey: String, userId: String, fingerprint: String?) {
        lastEngineInvocation[dateKey] = Date()
        if let fp = fingerprint {
            lastEnginePayloadFingerprint[dateKey] = fp
        }
        Task { [weak self] in
            guard let self = self else { return }
            do {
                _ = try await self.supabase.functions.invoke(
                    "health-engine",
                    options: FunctionInvokeOptions(body: HealthEngineDatePayload(date: dateKey, user_id: userId))
                )
            } catch {
                // Non-fatal background invocation
            }
        }
    }
    
    /// Checks Supabase for any missing historical daily summaries across the last 14 days.
    /// Only queries and syncs local HealthKit data for dates that do NOT exist in Supabase,
    /// preventing redundant network bandwidth and Edge Function quota burn.
    public func syncMissingHistoricalDataIfNeeded() async {
        guard !isSyncingHistory else { return }
        isSyncingHistory = true
        defer { isSyncingHistory = false }
        
        guard AuthService.shared.isAuthenticated,
              let session = try? await supabase.auth.session,
              let userId = session.user.id.uuidString.lowercased() as String?,
              let provider = localDataProvider else { return }
        
        let lastSyncEpoch = userDefaults.double(forKey: "last_historical_health_sync_epoch")
        let nowEpoch = Date().timeIntervalSince1970
        // Throttle check to at most once every 12 hours
        if lastSyncEpoch > 0 && (nowEpoch - lastSyncEpoch) < 12 * 3600 {
            return
        }
        
        let cal = Calendar.current
        guard let minDate = cal.date(byAdding: .day, value: -14, to: Date()),
              let maxDate = cal.date(byAdding: .day, value: -1, to: Date()) else { return }
        
        let minDateStr = isoDateFormatter.string(from: minDate)
        let maxDateStr = isoDateFormatter.string(from: maxDate)
        
        // 1. Query existing summaries from Supabase
        var existingDatesWithData = Set<String>()
        do {
            let existingRows: [HealthDailySummaryRecord] = try await supabase
                .from("health_daily_summary")
                .select()
                .eq("user_id", value: userId)
                .gte("local_date", value: minDateStr)
                .lte("local_date", value: maxDateStr)
                .execute()
                .value
            
            for row in existingRows {
                if (row.steps ?? 0) > 0 || (row.sleepAsleepS ?? 0) > 0 || (row.rhr ?? 0) > 0 {
                    existingDatesWithData.insert(row.localDate)
                }
            }
        } catch {
            print("[HealthDataService] Note: Could not query existing historical summaries: \(error)")
        }
        
        // 2. Identify missing dates
        var missingDates: [Date] = []
        for dayOffset in 1...14 {
            if let d = cal.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let dKey = isoDateFormatter.string(from: d)
                if !existingDatesWithData.contains(dKey) {
                    missingDates.append(d)
                }
            }
        }
        
        // If no dates are missing, mark complete and return
        if missingDates.isEmpty {
            userDefaults.set(nowEpoch, forKey: "last_historical_health_sync_epoch")
            return
        }
        
        // 3. For missing dates only, fetch local HealthKit data and upload
        var hasUploadedAnyHistory = false
        for missingDate in missingDates {
            let pastTelem = await provider.fetchLocalTelemetry(for: missingDate)
            let pastSleep = await provider.fetchLocalSleepStages(for: missingDate)
            let combined = pastTelem + pastSleep
            
            if !combined.isEmpty {
                await syncTelemetryToSupabase(telemetry: combined)
                
                hasUploadedAnyHistory = true
            }
        }
        
        // 4. If new historical telemetry was uploaded, trigger a single batch dirty computation in health-engine
        if hasUploadedAnyHistory {
            do {
                _ = try await self.supabase.functions.invoke(
                    "health-engine",
                    options: FunctionInvokeOptions(body: HealthEngineDirtyPayload(user_id: userId, process_dirty: true))
                )
            } catch {
                // Non-fatal background invocation
            }
        }
        
        userDefaults.set(nowEpoch, forKey: "last_historical_health_sync_epoch")
    }
    
    // MARK: - 7-Day & 30-Day Trend Generator
    
    public func loadHistoricalTrends() async {
        let cal = Calendar.current
        var trends: [HealthMetricType: [DailyMetricTrendPoint]] = [:]
        
        let metrics: [HealthMetricType] = [.steps, .sleepDuration, .heartRate, .stress, .hrvSdnn, .activeEnergy, .weight]
        
        var historicalVitalsByDate: [String: [HealthMetricType: Double]] = [:]
        
        let activeFilterCanon: String? = {
            guard let f = selectedDeviceFilter, !f.isEmpty else { return nil }
            return DeviceSource.from(name: f).displayName
        }()
        
        // 1. Read persistent on-device summary cache ONLY in All Devices mode (unfiltered)
        if activeFilterCanon == nil {
            for dayOffset in 0..<7 {
                if let date = cal.date(byAdding: .day, value: -dayOffset, to: selectedDate) {
                    let dKey = isoDateFormatter.string(from: date)
                    if let summaryData = userDefaults.data(forKey: "health_daily_summary_\(dKey)"),
                       let summary = try? summaryDecoder.decode(DailyHealthSummaryPayload.self, from: summaryData) {
                        if summary.activity.totalSteps > 0 {
                            historicalVitalsByDate[dKey, default: [:]][.steps] = Double(summary.activity.totalSteps)
                        }
                        if let asleep = summary.sleep.primarySession?.asleepSeconds, asleep > 0 {
                            historicalVitalsByDate[dKey, default: [:]][.sleepDuration] = asleep / 60.0
                        }
                        if let rhr = summary.cardiovascular.restingBpm, rhr > 0 {
                            historicalVitalsByDate[dKey, default: [:]][.heartRate] = rhr
                        }
                        if let st = summary.stress?.currentScore, st > 0 {
                            historicalVitalsByDate[dKey, default: [:]][.stress] = Double(st)
                        }
                        if let hrv = summary.stress?.currentHrvMs, hrv > 0 {
                            historicalVitalsByDate[dKey, default: [:]][.hrvSdnn] = hrv
                        }
                        if summary.activity.activeCalories > 0 {
                            historicalVitalsByDate[dKey, default: [:]][.activeEnergy] = summary.activity.activeCalories
                        }
                    } else if let data = userDefaults.data(forKey: "health_daily_vitals_\(dKey)"),
                              let records = try? JSONDecoder().decode([VitalMetricRecord].self, from: data) {
                        for r in records {
                            if let t = r.metricType, r.value > 0 {
                                historicalVitalsByDate[dKey, default: [:]][t] = r.value
                            }
                        }
                    }
                }
            }
        }
        
        // 2. For authenticated users, query 7-day historical lean tables + canonical summaries from Supabase
        let session = try? await supabase.auth.session
        if let userId = session?.user.id.uuidString.lowercased(),
           let minDate = cal.date(byAdding: .day, value: -6, to: selectedDate) {
            let minDateStr = isoDateFormatter.string(from: minDate)
            let maxDateStr = isoDateFormatter.string(from: selectedDate)
            
            // A. Fetch lean daily vitals
            async let vitalsRowsFetch: [HealthDailyVitalsRecord] = {
                do {
                    return try await supabase
                        .from("health_daily_vitals")
                        .select()
                        .eq("user_id", value: userId)
                        .gte("local_date", value: minDateStr)
                        .lte("local_date", value: maxDateStr)
                        .order("local_date", ascending: true)
                        .execute()
                        .value
                } catch {
                    return []
                }
            }()
            
            // B. Fetch lean sleep sessions
            async let sleepRowsFetch: [HealthSleepSessionRecord] = {
                do {
                    return try await supabase
                        .from("health_sleep_sessions")
                        .select()
                        .eq("user_id", value: userId)
                        .gte("local_date", value: minDateStr)
                        .lte("local_date", value: maxDateStr)
                        .order("source_priority", ascending: true)
                        .execute()
                        .value
                } catch {
                    return []
                }
            }()
            
            // C. Fetch canonical summaries for All Devices stress & historical fallback
            async let summaryRowsFetch: [HealthDailySummaryRecord] = {
                guard activeFilterCanon == nil else { return [] }
                do {
                    return try await supabase
                        .from("health_daily_summary")
                        .select()
                        .eq("user_id", value: userId)
                        .gte("local_date", value: minDateStr)
                        .lte("local_date", value: maxDateStr)
                        .order("local_date", ascending: true)
                        .execute()
                        .value
                } catch {
                    return []
                }
            }()
            
            let (leanVitalsRows, leanSleepRows, summaryRows) = await (vitalsRowsFetch, sleepRowsFetch, summaryRowsFetch)
            
            // Group lean vitals by date and apply canonical filter
            var vitalsByDate: [String: [HealthDailyVitalsRecord]] = [:]
            for row in leanVitalsRows {
                let rowCanon = DeviceSource.from(name: row.sourceDeviceKey).displayName
                if let targetCanon = activeFilterCanon, rowCanon != targetCanon {
                    continue
                }
                vitalsByDate[row.localDate, default: []].append(row)
            }
            
            // Group lean sleep by date and apply canonical filter
            var sleepByDate: [String: [HealthSleepSessionRecord]] = [:]
            for row in leanSleepRows {
                let rowCanon = DeviceSource.from(name: row.sourceDeviceKey).displayName
                if let targetCanon = activeFilterCanon, rowCanon != targetCanon {
                    continue
                }
                sleepByDate[row.localDate, default: []].append(row)
            }
            
            var sleepScoreByDate: [String: Int] = [:]
            for (dStr, rows) in sleepByDate {
                let sortedRows = rows.sorted {
                    if $0.isUserSelected != $1.isUserSelected { return $0.isUserSelected && !$1.isUserSelected }
                    if (!$0.stages.isEmpty) != (!$1.stages.isEmpty) { return !$0.stages.isEmpty }
                    let p0 = effectivePriorityRank(for: $0.sourceDeviceKey)
                    let p1 = effectivePriorityRank(for: $1.sourceDeviceKey)
                    if p0 != p1 { return p0 < p1 }
                    return $0.durationSeconds > $1.durationSeconds
                }
                let primary = sortedRows.first(where: { $0.sessionType == "primary_sleep" }) ?? sortedRows.first
                if let session = primary, session.durationSeconds > 0 {
                    historicalVitalsByDate[dStr, default: [:]][.sleepDuration] = Double(session.durationSeconds) / 60.0
                    if let sc = session.sleepScore {
                        sleepScoreByDate[dStr] = sc
                    }
                }
            }
            
            for (dStr, rows) in vitalsByDate {
                let sortedRows = rows.sorted {
                    let p0 = effectivePriorityRank(for: $0.sourceDeviceKey)
                    let p1 = effectivePriorityRank(for: $1.sourceDeviceKey)
                    if p0 != p1 { return p0 < p1 }
                    return $0.steps > $1.steps
                }
                let activityRes = Self.arbitrateHourlyActivity(vitals: rows, sources: currentLeanSources)
                if activityRes.totalSteps > 0 { historicalVitalsByDate[dStr, default: [:]][.steps] = Double(activityRes.totalSteps) }
                if activityRes.activeCalories > 0 { historicalVitalsByDate[dStr, default: [:]][.activeEnergy] = activityRes.activeCalories }
                
                let rhrVal = sortedRows.compactMap(\.restingHeartRate).first(where: { $0 > 0 })
                if let rhr = rhrVal {
                    historicalVitalsByDate[dStr, default: [:]][.heartRate] = Double(rhr)
                }
                if let spo2 = Self.arbitrateSpotVital(vitals: rows, timestampKey: "spo2", sources: currentLeanSources, extract: \.spo2)?.value {
                    historicalVitalsByDate[dStr, default: [:]][.oxygenSaturation] = spo2
                }
                if let resp = sortedRows.compactMap(\.respiratoryRate).first(where: { $0 > 0 }) {
                    historicalVitalsByDate[dStr, default: [:]][.respiratoryRate] = resp
                }
                if let temp = sortedRows.compactMap(\.skinTempCelsius).first {
                    historicalVitalsByDate[dStr, default: [:]][.bodyTemperature] = temp
                }
                if let weight = Self.arbitrateSpotVital(vitals: rows, timestampKey: "weight", sources: currentLeanSources, extract: \.weightKg)?.value {
                    historicalVitalsByDate[dStr, default: [:]][.weight] = weight
                }
                let hrvVal = sortedRows.compactMap { $0.hrvSdnnNightly ?? $0.hrvRmssdNightly }.first(where: { $0 > 0 })
                if let hrv = hrvVal {
                    historicalVitalsByDate[dStr, default: [:]][.hrvSdnn] = hrv
                }
                
                // When filtering by a specific device, synthesize per-device stress for each historical day
                if activeFilterCanon != nil, (hrvVal != nil || rhrVal != nil), let dayDate = isoDateFormatter.date(from: dStr) {
                    if let calc = StressAnalysisEngine.calculateStress(
                        targetDate: dayDate,
                        hrvMs: hrvVal,
                        hrTelemetry: [],
                        hourlySteps: sortedRows.first?.hourlySteps ?? [],
                        restingBpm: rhrVal.map { Double($0) },
                        priorSleepScore: sleepScoreByDate[dStr],
                        personalBaselineHrv: nil,
                        personalBaselineRhr: nil,
                        calendar: cal
                    ) {
                        historicalVitalsByDate[dStr, default: [:]][.stress] = Double(calc.result.currentScore)
                    }
                }
            }
            
            // Fallback to health_daily_summary ONLY in All Devices mode
            if activeFilterCanon == nil {
                for row in summaryRows {
                    let dStr = row.localDate
                    if historicalVitalsByDate[dStr]?[.steps] == nil, let s = row.steps, s > 0 {
                        historicalVitalsByDate[dStr, default: [:]][.steps] = Double(s)
                    }
                    if historicalVitalsByDate[dStr]?[.sleepDuration] == nil, let sl = row.sleepAsleepS, sl > 0 {
                        historicalVitalsByDate[dStr, default: [:]][.sleepDuration] = Double(sl) / 60.0
                    }
                    if historicalVitalsByDate[dStr]?[.heartRate] == nil, let r = row.rhr, r > 0 {
                        historicalVitalsByDate[dStr, default: [:]][.heartRate] = r
                    }
                    if historicalVitalsByDate[dStr]?[.stress] == nil, let st = row.stressAvg, st > 0 {
                        historicalVitalsByDate[dStr, default: [:]][.stress] = Double(st)
                    }
                    if historicalVitalsByDate[dStr]?[.hrvSdnn] == nil, let h = row.hrvSdnn ?? row.hrvRmssd, h > 0 {
                        historicalVitalsByDate[dStr, default: [:]][.hrvSdnn] = h
                    }
                    if historicalVitalsByDate[dStr]?[.activeEnergy] == nil, let cal = row.activeKcal, cal > 0 {
                        historicalVitalsByDate[dStr, default: [:]][.activeEnergy] = cal
                    }
                    if historicalVitalsByDate[dStr]?[.weight] == nil, let w = row.weight, w > 0 {
                        historicalVitalsByDate[dStr, default: [:]][.weight] = w
                    }
                    if historicalVitalsByDate[dStr]?[.oxygenSaturation] == nil, let sp = row.spo2, sp > 0 {
                        historicalVitalsByDate[dStr, default: [:]][.oxygenSaturation] = sp
                    }
                }
            }
        }
        
        // 3. Assemble final trend points with honest data (zero fallback for missing history)
        for m in metrics {
            var points: [DailyMetricTrendPoint] = []
            for dayOffset in (0..<7).reversed() {
                if let date = cal.date(byAdding: .day, value: -dayOffset, to: selectedDate) {
                    let dateStr = isoDateFormatter.string(from: date)
                    let isComplete = dayOffset > 0
                    let target = defaultTarget(for: m)
                    
                    var val: Double = 0
                    if let dayVitals = historicalVitalsByDate[dateStr], let v = dayVitals[m], v > 0 {
                        val = v
                    } else if cal.isDate(date, inSameDayAs: selectedDate) {
                        // Use current day computed metrics
                        switch m {
                        case .steps: val = Double(totalStepsToday)
                        case .sleepDuration: val = Double(primarySleepSession?.asleepSeconds ?? 0) / 60.0
                        case .heartRate: val = averageBpm > 0 ? averageBpm : restingBpm
                        case .activeEnergy: val = totalActiveCalories
                        case .stress: val = Double(stressAnalysis?.currentScore ?? currentStressScore)
                        default: val = currentVitals[m]?.value ?? 0
                        }
                    } else if ProcessInfo.processInfo.arguments.contains("-demoHealth") {
                        val = generateHistoricalValue(for: m, dayOffset: dayOffset, target: target)
                    } else {
                        val = 0
                    }
                    
                    points.append(DailyMetricTrendPoint(
                        date: date,
                        value: val,
                        target: target,
                        isCompleteDay: isComplete && val > 0
                    ))
                }
            }
            trends[m] = points
        }
        
        self.historicalTrends = trends
    }
    
    private func defaultTarget(for metric: HealthMetricType) -> Double {
        switch metric {
        case .steps: return 10_000
        case .sleepDuration: return 480 // 8 hours in minutes
        case .activeEnergy: return 550 // kcal
        case .hydration: return 2_500 // ml
        case .stress: return 35 // Optimal recovery threshold
        default: return 0
        }
    }
    
    private func generateHistoricalValue(for metric: HealthMetricType, dayOffset: Int, target: Double) -> Double {
        // Deterministic pseudo-random based on dayOffset for stable preview
        let baseSeed = Double(dayOffset * 17 % 10) / 10.0
        switch metric {
        case .steps:
            return Double(8_500 + Int(baseSeed * 3_500))
        case .sleepDuration:
            return Double(410 + Int(baseSeed * 85)) // ~7h to 8.2h in minutes
        case .heartRate:
            return Double(68 + Int(baseSeed * 8))
        case .hrvSdnn:
            return Double(45 + Int(baseSeed * 22))
        case .activeEnergy:
            return Double(480 + Int(baseSeed * 220))
        case .weight:
            return Double(78.2 + (baseSeed * 0.8))
        case .stress:
            return Double(32 + Int(baseSeed * 24))
        default:
            return 0
        }
    }
    
    // MARK: - Realistic Demo / Fallback Generator
    
    private func generateDemoData(for date: Date) -> (telemetry: [HealthTelemetryRecord], vitals: [VitalMetricRecord]) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        var telemetry: [HealthTelemetryRecord] = []
        var vitals: [VitalMetricRecord] = []
        
        let dateStr = isoDateFormatter.string(from: date)
        
        // 1. Bedtime & Sleep stages last night (23:15 to 07:10)
        let sleepStart = cal.date(byAdding: .minute, value: -50, to: startOfDay) ?? startOfDay // 23:10 of previous night
        var cursor = sleepStart
        
        let stageDurations: [(SleepStageType, Int)] = [
            (.awake, 15),
            (.light, 45),
            (.deep, 55),
            (.light, 30),
            (.rem, 35),
            (.light, 40),
            (.deep, 45),
            (.rem, 40),
            (.light, 60),
            (.awake, 10),
            (.rem, 45),
            (.light, 55),
            (.awake, 5)
        ]
        
        for (st, mins) in stageDurations {
            let end = cal.date(byAdding: .minute, value: mins, to: cursor)!
            let typeName: String
            switch st {
            case .deep: typeName = "sleep_stage_deep"
            case .rem: typeName = "sleep_stage_rem"
            case .light: typeName = "sleep_stage_light"
            case .awake: typeName = "sleep_stage_awake"
            case .unknown: typeName = "sleep_stage_light"
            }
            
            telemetry.append(HealthTelemetryRecord(
                userId: "demo",
                type: typeName,
                value: Double(mins),
                unit: "minutes",
                startTime: cursor,
                endTime: end,
                sourceDevice: "Amazfit Balance"
            ))
            cursor = end
        }
        
        // 2. Daytime Nap (14:15 to 14:55)
        if let napStart = cal.date(byAdding: .minute, value: 855, to: startOfDay),
           let napEnd = cal.date(byAdding: .minute, value: 895, to: startOfDay) {
            telemetry.append(HealthTelemetryRecord(
                userId: "demo",
                type: "sleep_nap",
                value: 40,
                unit: "minutes",
                startTime: napStart,
                endTime: napEnd,
                sourceDevice: "Amazfit Balance"
            ))
        }
        
        // 3. Intraday Heart Rate (sampled every 20-30 mins throughout the day)
        for hour in 0..<24 {
            for half in [0, 30] {
                if let t = cal.date(byAdding: .minute, value: hour * 60 + half, to: startOfDay) {
                    if t > Date() && cal.isDateInToday(date) { break }
                    
                    let bpm: Double
                    if hour >= 0 && hour <= 6 {
                        bpm = Double(52 + (hour * half % 8)) // Resting sleep HR
                    } else if hour == 17 || hour == 18 {
                        bpm = Double(132 + (half % 25)) // Workout/Cardio
                    } else {
                        bpm = Double(70 + ((hour * 7 + half) % 28)) // Daytime activity
                    }
                    
                    telemetry.append(HealthTelemetryRecord(
                        userId: "demo",
                        type: "heart_rate",
                        value: bpm,
                        unit: "bpm",
                        startTime: t,
                        endTime: t,
                        sourceDevice: "Apple Watch"
                    ))
                }
            }
        }
        
        // 4. Hourly Steps
        for hour in 7..<22 {
            if let t = cal.date(byAdding: .hour, value: hour, to: startOfDay) {
                if t > Date() && cal.isDateInToday(date) { break }
                let steps = (hour == 8 || hour == 17) ? 1450 : (200 + (hour * 70 % 600))
                telemetry.append(HealthTelemetryRecord(
                    userId: "demo",
                    type: "steps",
                    value: Double(steps),
                    unit: "count",
                    startTime: t,
                    endTime: t,
                    sourceDevice: "Apple Watch"
                ))
            }
        }
        
        // 5. Daily Vitals
        vitals.append(VitalMetricRecord(userId: "demo", type: "steps", value: 10420, unit: "count", date: dateStr, sourceDevice: "Apple Watch"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "active_energy", value: 615, unit: "kcal", date: dateStr, sourceDevice: "Apple Watch"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "heart_rate", value: 74, unit: "bpm", date: dateStr, sourceDevice: "Apple Watch"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "resting_heart_rate", value: 58, unit: "bpm", date: dateStr, sourceDevice: "Apple Watch"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "hrv_sdnn", value: 54, unit: "ms", date: dateStr, sourceDevice: "Apple Watch"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "oxygen_saturation", value: 98.5, unit: "%", date: dateStr, sourceDevice: "Amazfit Balance"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "respiratory_rate", value: 14.2, unit: "br/min", date: dateStr, sourceDevice: "Apple Watch"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "blood_pressure_systolic", value: 118, unit: "mmHg", date: dateStr, sourceDevice: "Health Connect"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "blood_pressure_diastolic", value: 76, unit: "mmHg", date: dateStr, sourceDevice: "Health Connect"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "stress", value: 34, unit: "pts", date: dateStr, sourceDevice: "Amazfit Balance"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "pai", value: 88, unit: "pts", date: dateStr, sourceDevice: "Amazfit Balance"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "hydration", value: 2100, unit: "ml", date: dateStr, sourceDevice: "Manual"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "weight", value: 78.4, unit: "kg", date: dateStr, sourceDevice: "HealthKit"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "body_fat_percentage", value: 17.8, unit: "%", date: dateStr, sourceDevice: "HealthKit"))
        vitals.append(VitalMetricRecord(userId: "demo", type: "bmi", value: 23.6, unit: "kg/m²", date: dateStr, sourceDevice: "HealthKit"))
        
        return (telemetry, vitals)
    }
    
    // MARK: - Daily Steps Processing & Telemetry Deduplication
    
    public struct DailyStepsResult: Sendable {
        public let totalSteps: Int
        public let hourlyBuckets: [HourlyStepBucket]
        public let activeCalories: Double
        public let sourceDeviceUsed: String?
        
        public init(
            totalSteps: Int,
            hourlyBuckets: [HourlyStepBucket],
            activeCalories: Double,
            sourceDeviceUsed: String? = nil
        ) {
            self.totalSteps = totalSteps
            self.hourlyBuckets = hourlyBuckets
            self.activeCalories = activeCalories
            self.sourceDeviceUsed = sourceDeviceUsed
        }
    }
    
    public nonisolated static func deduplicateTelemetry(_ records: [HealthTelemetryRecord]) -> [HealthTelemetryRecord] {
        var seen = Set<String>()
        var unique: [HealthTelemetryRecord] = []
        
        for r in records {
            let typeKey = r.normalizedType
            let devKey = r.sourceDevice?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stKey = Int(r.startTime.timeIntervalSince1970)
            let etKey = Int((r.endTime ?? r.startTime).timeIntervalSince1970)
            let valKey = Int((r.value ?? 0) * 100)
            
            let compositeKey = "\(typeKey)_\(devKey)_\(stKey)_\(etKey)_\(valKey)"
            if seen.insert(compositeKey).inserted {
                unique.append(r)
            }
        }
        return unique
    }
    
    public nonisolated static func calculateDailySteps(
        targetDate: Date,
        telemetry: [HealthTelemetryRecord],
        vitalsSummary: [HealthMetricType: Double] = [:],
        preferredDevice: String? = nil,
        preferredSource: DeviceSource? = nil,
        calendar: Calendar = .current
    ) -> DailyStepsResult {
        let daySteps = telemetry.filter { $0.isSteps && calendar.isDate($0.startTime, inSameDayAs: targetDate) }
        
        // Group by device
        let grouped = Dictionary(grouping: daySteps) { $0.sourceDevice ?? "Unknown" }
        
        var deviceResults: [(device: String, total: Int, hourly: [Int: Int], isWearable: Bool)] = []
        
        for (device, records) in grouped {
            let source = DeviceSource.from(name: device)
            let isWearable = source.isWearable
            
            let isCumulative = isCumulativeStepDevice(device: device, records: records)
            
            var hourlyMap = [Int: Int]()
            var total = 0
            
            if isCumulative {
                // Device reports cumulative total for the day (e.g. Zepp OS step.getCurrent())
                let sorted = records.sorted { $0.startTime < $1.startTime }
                let maxVal = sorted.compactMap { $0.value }.max() ?? 0
                total = Int(maxVal)
                
                var prevVal: Double = 0
                for r in sorted {
                    guard let val = r.value, val > 0 else { continue }
                    let delta = val >= prevVal ? (val - prevVal) : val
                    let hour = calendar.component(.hour, from: r.startTime)
                    hourlyMap[hour, default: 0] += Int(delta)
                    prevVal = val
                }
            } else {
                // Device reports interval step slices (e.g. Apple Watch / HealthKit)
                // Deduplicate overlapping interval slices
                let sorted = records.sorted { $0.startTime < $1.startTime }
                var uniqueSlices: [HealthTelemetryRecord] = []
                for r in sorted {
                    if let last = uniqueSlices.last {
                        let isIdenticalInterval = abs(last.startTime.timeIntervalSince(r.startTime)) < 5 &&
                                                 abs((last.endTime ?? last.startTime).timeIntervalSince(r.endTime ?? r.startTime)) < 5
                        if isIdenticalInterval { continue }
                    }
                    uniqueSlices.append(r)
                }
                
                for r in uniqueSlices {
                    let val = Int(r.value ?? 0)
                    let hour = calendar.component(.hour, from: r.startTime)
                    hourlyMap[hour, default: 0] += val
                }
                total = hourlyMap.values.reduce(0, +)
            }
            
            deviceResults.append((device: device, total: total, hourly: hourlyMap, isWearable: isWearable))
        }
        
        // Multi-device selection:
        // 1. If preferredSource is set
        let isAllDevices = preferredSource == nil && (preferredDevice == nil || preferredDevice?.isEmpty == true)
        var chosen: (device: String, total: Int, hourly: [Int: Int], isWearable: Bool)?
        if let ps = preferredSource {
            chosen = deviceResults.first {
                let dSrc = DeviceSource.from(name: $0.device)
                return dSrc == ps || dSrc.displayName.caseInsensitiveCompare(ps.displayName) == .orderedSame
            }
        }
        // 2. If preferredDevice is set
        if chosen == nil, let pd = preferredDevice, !pd.isEmpty {
            let pdCanon = DeviceSource.from(name: pd).displayName
            chosen = deviceResults.first {
                $0.device.localizedCaseInsensitiveContains(pd) ||
                DeviceSource.from(name: $0.device).displayName.caseInsensitiveCompare(pdCanon) == .orderedSame
            }
        }
        // 3. Fallback (ONLY in "All Devices" mode): Prioritize wearables with max steps, then any device with max steps
        if chosen == nil && isAllDevices {
            let wearables = deviceResults.filter { $0.isWearable && $0.total > 0 }
            if let bestWearable = wearables.max(by: { $0.total < $1.total }) {
                chosen = bestWearable
            } else {
                chosen = deviceResults.max(by: { $0.total < $1.total })
            }
        }
        
        var chosenTotal = chosen?.total ?? 0
        let chosenHourly = chosen?.hourly ?? [:]
        var chosenDevice = chosen?.device
        
        // Incorporate backend vitals summary (e.g. smartwatch daily sync row)
        if let vitalsSteps = vitalsSummary[.steps], vitalsSteps > 0 {
            let vitalsInt = Int(vitalsSteps)
            if isAllDevices {
                // In "All Devices", take the maximum between live deduplicated sensor telemetry and backend smartwatch vitals summary
                if vitalsInt > chosenTotal {
                    chosenTotal = vitalsInt
                    if chosenDevice == nil {
                        chosenDevice = "Smartwatch"
                    }
                }
            } else if chosenTotal == 0 {
                chosenTotal = vitalsInt
            }
        }
        
        let finalTotal = chosenTotal
        
        var buckets: [HourlyStepBucket] = []
        for h in 0..<24 {
            buckets.append(HourlyStepBucket(hour: h, steps: chosenHourly[h] ?? 0))
        }
        
        // Active calories
        var activeCal = vitalsSummary[.activeEnergy] ?? 0
        if activeCal <= 0 {
            // Check telemetry for activeEnergy
            let energyRecs = telemetry.filter {
                $0.normalizedType == "activeenergy" || $0.normalizedType == "calories"
            }
            if let chosenDevice = chosenDevice {
                let devEnergy = energyRecs.filter { $0.sourceDevice == chosenDevice }
                if isCumulativeStepDevice(device: chosenDevice, records: devEnergy) {
                    activeCal = devEnergy.compactMap { $0.value }.max() ?? 0
                } else {
                    activeCal = devEnergy.compactMap { $0.value }.reduce(0, +)
                }
            }
            if activeCal <= 0 {
                // Estimation: 0.042 kcal per step
                activeCal = Double(Int(Double(finalTotal) * 0.042))
            }
        }
        
        return DailyStepsResult(
            totalSteps: finalTotal,
            hourlyBuckets: buckets,
            activeCalories: activeCal,
            sourceDeviceUsed: chosenDevice
        )
    }
    
    private nonisolated static func isCumulativeStepDevice(device: String, records: [HealthTelemetryRecord]) -> Bool {
        if records.contains(where: { $0.semantics == "cumulative_daily" }) { return true }
        if records.contains(where: { $0.semantics == "interval_delta" }) { return false }
        
        let lower = device.lowercased()
        if lower.contains("zepp") || lower.contains("amazfit") || lower.contains("balance") ||
           lower.contains("huawei") || lower.contains("harmony") || lower.contains("gt5") {
            return true
        }
        let nonZero = records.compactMap { $0.value }.filter { $0 > 0 }
        if nonZero.count >= 2 {
            let isIncreasing = zip(nonZero, nonZero.dropFirst()).allSatisfy { $0 <= $1 }
            let hasLargeValues = nonZero.contains { $0 >= 500 }
            let hasShortIntervals = records.contains(where: { r in
                guard let end = r.endTime else { return false }
                let dur = end.timeIntervalSince(r.startTime)
                return dur > 0 && dur <= 3600
            })
            if isIncreasing && hasLargeValues && !hasShortIntervals {
                return true
            }
        }
        return false
    }
}
