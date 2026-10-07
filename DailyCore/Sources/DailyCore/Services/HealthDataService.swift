import Foundation
import Combine
import Supabase

/// Multiplatform provider protocol allowing platform-specific engines (such as iOS HealthKit)
/// to inject on-device biometric telemetry and sleep stages into HealthDataService.
@MainActor
public protocol LocalHealthDataProvider: AnyObject {
    func requestAuthorization() async -> Bool
    func fetchLocalTelemetry(for date: Date) async -> [HealthTelemetryRecord]
    func fetchLocalSleepStages(for date: Date) async -> [HealthTelemetryRecord]
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
    
    /// Most recent intraday heart rate reading from the currently active wearable
    public var latestBpm: Double? {
        intradayHeartRate.last?.bpm
    }
    
    // Activity
    @Published public var hourlySteps: [HourlyStepBucket] = []
    @Published public var totalStepsToday: Int = 0
    @Published public var totalActiveCalories: Double = 0
    
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
    
    private let groupSuiteName = "group.com.intellidream.daily"
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
    private var isSyncingHistory: Bool = false
    
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
        self.userDefaults = UserDefaults(suiteName: "group.com.intellidream.daily") ?? UserDefaults.standard
        
        // Observe auth session state changes so that once user authentication resolves,
        // real telemetry and canonical summaries are fetched immediately.
        AuthService.shared.$sessionState
            .dropFirst()
            .sink { [weak self] state in
                if case .authenticated = state {
                    Task { @MainActor [weak self] in
                        self?.setupRealtimeSubscription()
                        await self?.loadDataForSelectedDate(forceRefresh: true)
                        await self?.syncMissingHistoricalDataIfNeeded()
                    }
                }
            }
            .store(in: &cancellables)
        
        if AuthService.shared.isAuthenticated {
            setupRealtimeSubscription()
            Task { @MainActor [weak self] in
                await self?.syncMissingHistoricalDataIfNeeded()
            }
        }
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
            
            let channel = self.supabase.channel("health-summary-\(userId)")
            self.realtimeChannel = channel
            
            self.realtimeTask = Task { [weak self] in
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "health_daily_summary",
                    filter: .eq("user_id", value: userId)
                )
                
                do {
                    try await channel.subscribe()
                } catch {
                    print("[HealthDataService] Realtime subscription error: \(error)")
                    return
                }
                
                for await _ in changes {
                    guard !Task.isCancelled else { break }
                    Task { @MainActor [weak self] in
                        await self?.loadDataForSelectedDate(forceRefresh: true)
                    }
                }
            }
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
        Task {
            await processDataForCurrentDate()
        }
    }
    
    public func setDeviceFilter(_ device: String?) {
        guard selectedDeviceFilter != device else { return }
        selectedDeviceFilter = device
        selectedDeviceSource = device != nil ? DeviceSource.from(name: device) : nil
        Task {
            await processDataForCurrentDate()
        }
    }
    
    // MARK: - Smart Refresh
    public var lastRefreshTimestamp: Date = .distantPast
    
    public func refreshIfStale() async {
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let staleThreshold: TimeInterval = isToday ? 900 : 3600 // 15 min for today, 1 hour for past
        
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
        isLoading = true
        defer { isLoading = false }
        
        let targetDate = selectedDate
        let dateKey = isoDateFormatter.string(from: targetDate)
        let isToday = Calendar.current.isDateInToday(targetDate)
        let effectiveTTL: TimeInterval = isToday ? 30 : cacheTTL
        
        // 1. Check in-memory canonical summary cache
        if !forceRefresh, let cached = summaryCache[dateKey], !cached.summary.isEmpty, Date().timeIntervalSince(cached.timestamp) < effectiveTTL {
            self.canonicalSummary = cached.summary
            applyCanonicalSummary(cached.summary, dateKey: dateKey)
            if !isToday {
                ensureLocalDeviceSourcesPopulated()
                await loadHistoricalTrends()
                return
            }
        }
        
        // 2. Check persistent on-device App Group local storage for instantaneous (<300ms) startup
        if !forceRefresh, let summaryData = userDefaults.data(forKey: "health_daily_summary_\(dateKey)"),
           let summary = try? summaryDecoder.decode(DailyHealthSummaryPayload.self, from: summaryData) {
            if !summary.isEmpty {
                self.canonicalSummary = summary
                summaryCache[dateKey] = (timestamp: Date(), summary: summary)
                applyCanonicalSummary(summary, dateKey: dateKey)
                if !isToday {
                    ensureLocalDeviceSourcesPopulated()
                    await loadHistoricalTrends()
                    return
                }
            } else {
                userDefaults.removeObject(forKey: "health_daily_summary_\(dateKey)")
            }
        }
        
        // 3. Concurrently fetch Supabase canonical summary while reading local on-device provider (HealthKit)
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
        
        // 4. If canonical summary was found, apply and merge local sensor data atomically to eliminate UI flickering
        if let payload = remotePayload {
            self.canonicalSummary = payload
            if let encoded = try? summaryEncoder.encode(payload) {
                userDefaults.set(encoded, forKey: "health_daily_summary_\(dateKey)")
            }
            summaryCache[dateKey] = (timestamp: Date(), summary: payload)
            applyCanonicalSummary(payload, dateKey: dateKey)
            
            if !localTelemetry.isEmpty {
                mergeLocalTelemetryWithSummary(telemetry: localTelemetry, isToday: isToday)
            }
            ensureLocalDeviceSourcesPopulated()
            await loadHistoricalTrends()
            return
        }
        
        // 6. Fallback to on-device provisional calculation if remote canonical summary is not yet computed, empty, or user is offline
        var fetchedTelemetry = localTelemetry
        var fetchedVitals: [VitalMetricRecord] = []
        
        if let userId = userId {
            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: targetDate)
            let windowStart = cal.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
            let windowEnd = cal.date(byAdding: .hour, value: 24, to: startOfDay) ?? startOfDay
            
            let startIso = isoTimestampFormatter.string(from: windowStart)
            let endIso = isoTimestampFormatter.string(from: windowEnd)
            
            do {
                let records: [HealthTelemetryRecord] = try await supabase.from("health_telemetry")
                    .select()
                    .eq("user_id", value: userId)
                    .gte("start_time", value: startIso)
                    .lte("start_time", value: endIso)
                    .order("start_time", ascending: true)
                    .execute()
                    .value
                fetchedTelemetry.append(contentsOf: records)
            } catch {
                print("[HealthDataService] Warning: Could not fetch health_telemetry: \(error.localizedDescription)")
            }
        }
        
        fetchedTelemetry = Self.deduplicateTelemetry(fetchedTelemetry)
        
        // Check persistent legacy cached vitals if no telemetry exists
        if fetchedTelemetry.isEmpty {
            if let data = userDefaults.data(forKey: "health_daily_vitals_\(dateKey)"),
               let cached = try? JSONDecoder().decode([VitalMetricRecord].self, from: data),
               !cached.isEmpty {
                fetchedVitals = cached.filter { v in
                    guard let dev = v.sourceDevice, !dev.isEmpty else { return true }
                    return !DeviceSource.from(name: dev).isVirtualEngine
                }
            } else if ProcessInfo.processInfo.arguments.contains("-demoHealth") {
                let demo = generateDemoData(for: targetDate)
                fetchedTelemetry = demo.telemetry
                fetchedVitals = demo.vitals
            }
        }
        
        guard !Task.isCancelled, Calendar.current.isDate(targetDate, inSameDayAs: self.selectedDate) else { return }
        
        telemetryCache[dateKey] = (timestamp: Date(), telemetry: fetchedTelemetry, vitals: fetchedVitals)
        await applyRecords(telemetry: fetchedTelemetry, vitals: fetchedVitals)
        await loadHistoricalTrends()
        
        // If we have an authenticated user and unsynced day, trigger Edge Function in background to compute canonical summary
        if let userId = userId, !fetchedTelemetry.isEmpty {
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    _ = try await self.supabase.functions.invoke(
                        "health-engine",
                        options: FunctionInvokeOptions(body: ["date": dateKey, "user_id": userId])
                    )
                } catch {
                    // Non-fatal background invocation
                }
            }
        }
    }
    
    /// Unpacks canonical DailyHealthSummaryPayload into published properties.
    private func applyCanonicalSummary(_ summary: DailyHealthSummaryPayload, dateKey: String) {
        // Collect available devices and sources
        var devicesSet = Set<String>()
        var sourcesSet = Set<DeviceSource>()
        
        if let d = summary.sleep.primarySession?.sourceDevice, !d.isEmpty {
            let src = DeviceSource.from(name: d)
            if !src.isVirtualEngine {
                devicesSet.insert(d)
                sourcesSet.insert(src)
            }
        }
        if let d = summary.activity.sourceDevice, !d.isEmpty {
            let src = DeviceSource.from(name: d)
            if !src.isVirtualEngine {
                devicesSet.insert(d)
                sourcesSet.insert(src)
            }
        }
        for (_, v) in summary.vitals {
            if let d = v.sourceDevice, !d.isEmpty {
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
        
        // 1. Sleep
        self.primarySleepSession = summary.sleep.primarySession
        self.allSleepSessions = summary.sleep.allSessions
        self.daytimeNaps = summary.sleep.naps
        
        // 2. Activity
        self.hourlySteps = summary.activity.hourlySteps
        let isToday = Calendar.current.isDateInToday(selectedDate)
        if isToday {
            self.totalStepsToday = max(self.totalStepsToday, summary.activity.totalSteps)
            self.totalActiveCalories = max(self.totalActiveCalories, summary.activity.activeCalories)
        } else {
            self.totalStepsToday = summary.activity.totalSteps
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
        
        if let stress = summary.stress {
            vitalsMap[.stress] = VitalMetricRecord(
                userId: "canonical",
                type: HealthMetricType.stress.rawValue,
                value: Double(stress.currentScore),
                unit: "score",
                date: dateKey,
                sourceDevice: summary.activity.sourceDevice ?? "Canonical Engine"
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
        var devicesSet = Set(availableDevices)
        var sourcesSet = Set(availableSources)
        
        if localDataProvider != nil {
            if !devicesSet.contains(where: { $0.localizedCaseInsensitiveContains("watch") }) {
                devicesSet.insert("Apple Watch")
                sourcesSet.insert(.appleWatch)
            }
            if !sourcesSet.contains(.healthKit) {
                devicesSet.insert("Apple Health")
                sourcesSet.insert(.healthKit)
            }
        }
        
        self.availableDevices = Array(devicesSet).sorted()
        self.availableSources = Array(sourcesSet).sorted()
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
        if isToday || stepCalc.totalSteps > self.totalStepsToday {
            if stepCalc.totalSteps > 0 {
                self.totalStepsToday = stepCalc.totalSteps
                self.hourlySteps = stepCalc.hourlyBuckets
            }
        }
        
        let activeCals = telemetry.filter { $0.type == "active_energy" }.compactMap { $0.value }.reduce(0, +)
        if (isToday || activeCals > self.totalActiveCalories) && activeCals > 0 {
            self.totalActiveCalories = activeCals
        } else if self.totalActiveCalories == 0 && stepCalc.activeCalories > 0 {
            self.totalActiveCalories = stepCalc.activeCalories
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
        
        // 4. Process Stress Level (Autonomic tone physiological model)
        let hrvVal = vitalsValues[.hrvSdnn] ?? vitalsValues[.hrvRmssd]
        let stressCalculation = StressAnalysisEngine.calculateStress(
            targetDate: selectedDate,
            hrvMs: hrvVal,
            hrTelemetry: self.intradayHeartRate,
            hourlySteps: self.hourlySteps,
            restingBpm: self.restingBpm > 0 ? self.restingBpm : vitalsValues[.restingHeartRate],
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
        
        // Sync computed daily vitals to Supabase asynchronously
        Task { [weak self] in
            await self?.syncVitalsToSupabase(vitals: vitalsList)
        }
    }
    
    /// Syncs real device daily aggregate vitals to Supabase `vitals` table.
    /// Excludes virtual engines (StressWatch, Biometric Engine, Bubbles, computed) to prevent duplicate pollution.
    public func syncVitalsToSupabase(vitals: [VitalMetricRecord]) async {
        guard AuthService.shared.isAuthenticated,
              let session = try? await supabase.auth.session,
              let userId = session.user.id.uuidString.lowercased() as String?,
              !vitals.isEmpty else { return }
        
        let realVitals = vitals.filter { v in
            if v.userId == "stress-engine" || v.userId == "computed" || v.userId == "canonical" || v.userId == "habits" {
                return false
            }
            if let dev = v.sourceDevice, DeviceSource.from(name: dev).isVirtualEngine {
                return false
            }
            return true
        }
        
        guard !realVitals.isEmpty else { return }
        
        do {
            let prepared = realVitals.map { v in
                VitalMetricRecord(
                    id: v.id,
                    userId: userId,
                    type: v.type,
                    value: v.value,
                    unit: v.unit,
                    date: v.date,
                    sourceDevice: v.sourceDevice,
                    createdAt: v.createdAt ?? Date(),
                    updatedAt: Date(),
                    syncedAt: Date()
                )
            }
            try await supabase.from("vitals").upsert(prepared, onConflict: "user_id,date,type").execute()
        } catch {
            print("[HealthDataService] Warning: Failed to sync vitals to Supabase: \(error.localizedDescription)")
        }
    }
    
    /// Syncs local high-frequency telemetry samples to Supabase `health_telemetry` table idempotently.
    public func syncTelemetryToSupabase(telemetry: [HealthTelemetryRecord]) async {
        guard AuthService.shared.isAuthenticated,
              let session = try? await supabase.auth.session,
              let userId = session.user.id.uuidString.lowercased() as String?,
              !telemetry.isEmpty else { return }
        
        let tzOffsetMin = Calendar.current.timeZone.secondsFromGMT() / 60
        
        let prepared = telemetry.compactMap { r -> HealthTelemetryRecord? in
            if let dev = r.sourceDevice, DeviceSource.from(name: dev).isVirtualEngine {
                return nil
            }
            let dKey = isoDateFormatter.string(from: r.startTime)
            return HealthTelemetryRecord(
                id: r.id,
                userId: userId,
                type: r.type,
                value: r.value,
                unit: r.unit,
                startTime: r.startTime,
                endTime: r.endTime,
                sourceDevice: r.sourceDevice,
                createdAt: r.createdAt ?? Date(),
                externalId: r.externalId ?? r.id,
                sourceId: r.sourceId,
                semantics: r.semantics,
                tzOffsetMin: tzOffsetMin,
                localDate: dKey
            )
        }
        
        guard !prepared.isEmpty else { return }
        
        var newRecords = prepared
        do {
            let externalIds = prepared.map { $0.externalId ?? "" }.filter { !$0.isEmpty }
            struct IdResponse: Decodable { let external_id: String }
            let existing: [IdResponse] = try await supabase.from("health_telemetry")
                .select("external_id")
                .in("external_id", values: externalIds)
                .execute()
                .value
            let existingSet = Set(existing.map { $0.external_id })
            newRecords = prepared.filter {
                guard let extId = $0.externalId else { return true }
                return !existingSet.contains(extId)
            }
        } catch {
            print("[HealthDataService] Warning: Could not fetch existing external_ids: \(error)")
        }
        
        guard !newRecords.isEmpty else { return }
        
        var anyChunkSucceeded = false
        var affectedDates = Set<String>()
        for r in newRecords {
            affectedDates.insert(r.localDate ?? isoDateFormatter.string(from: r.startTime))
        }
        
        let batchSize = 200
        for i in stride(from: 0, to: newRecords.count, by: batchSize) {
            let chunk = Array(newRecords[i..<min(i + batchSize, newRecords.count)])
            do {
                try await supabase.from("health_telemetry").insert(chunk).execute()
                anyChunkSucceeded = true
            } catch {
                print("[HealthDataService] Warning: Failed to sync telemetry batch: \(error.localizedDescription)")
            }
        }
        
        // If telemetry was successfully uploaded, trigger canonical engine computation (throttled)
        if anyChunkSucceeded {
            for dKey in affectedDates {
                triggerCanonicalEngineIfNeeded(for: dKey, userId: userId)
            }
        }
    }
    
    private struct HealthEngineDatePayload: Encodable {
        let date: String
        let user_id: String
    }
    
    private struct HealthEngineDirtyPayload: Encodable {
        let user_id: String
        let process_dirty: Bool
    }
    
    /// Triggers the canonical Edge Function `health-engine` with strict throttling to prevent burning function quotas.
    public func triggerCanonicalEngineIfNeeded(for dateKey: String, userId: String) {
        if let last = lastEngineInvocation[dateKey], Date().timeIntervalSince(last) < 180 {
            // Throttled: invoked within last 3 minutes for this date
            return
        }
        lastEngineInvocation[dateKey] = Date()
        
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
                
                // Calculate and sync daily vitals for this day
                let pastDateKey = isoDateFormatter.string(from: missingDate)
                var vitalsList: [VitalMetricRecord] = []
                for t in combined {
                    guard let val = t.value, val > 0,
                          let mType = HealthMetricType.from(rawString: t.type) else { continue }
                    if mType == .steps || t.isSleep || t.isSleepStage { continue }
                    vitalsList.append(VitalMetricRecord(
                        userId: userId,
                        type: mType.rawValue,
                        value: val,
                        unit: t.unit ?? mType.defaultUnit,
                        date: pastDateKey,
                        sourceDevice: t.sourceDevice,
                        createdAt: t.startTime
                    ))
                }
                if !vitalsList.isEmpty {
                    await syncVitalsToSupabase(vitals: vitalsList)
                }
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
        
        // 1. Read persistent on-device records for the 7-day window
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
        
        // 2. For authenticated users, query 7-day historical summaries from health_daily_summary
        let session = try? await supabase.auth.session
        if let userId = session?.user.id.uuidString.lowercased(),
           let minDate = cal.date(byAdding: .day, value: -6, to: selectedDate) {
            let minDateStr = isoDateFormatter.string(from: minDate)
            let maxDateStr = isoDateFormatter.string(from: selectedDate)
            
            if let summaryRows: [HealthDailySummaryRecord] = try? await supabase
                .from("health_daily_summary")
                .select()
                .eq("user_id", value: userId)
                .gte("local_date", value: minDateStr)
                .lte("local_date", value: maxDateStr)
                .order("local_date", ascending: true)
                .execute()
                .value {
                for row in summaryRows {
                    let dStr = row.localDate
                    if let s = row.steps, s > 0 { historicalVitalsByDate[dStr, default: [:]][.steps] = Double(s) }
                    if let sl = row.sleepAsleepS, sl > 0 { historicalVitalsByDate[dStr, default: [:]][.sleepDuration] = Double(sl) / 60.0 }
                    if let r = row.rhr, r > 0 { historicalVitalsByDate[dStr, default: [:]][.heartRate] = r }
                    if let st = row.stressAvg, st > 0 { historicalVitalsByDate[dStr, default: [:]][.stress] = Double(st) }
                    if let h = row.hrvSdnn, h > 0 { historicalVitalsByDate[dStr, default: [:]][.hrvSdnn] = h }
                    if let cal = row.activeKcal, cal > 0 { historicalVitalsByDate[dStr, default: [:]][.activeEnergy] = cal }
                    if let w = row.weight, w > 0 { historicalVitalsByDate[dStr, default: [:]][.weight] = w }
                    if let sp = row.spo2, sp > 0 { historicalVitalsByDate[dStr, default: [:]][.oxygenSaturation] = sp }
                }
            }
            
            // Also check legacy vitals table for any historical entries
            if let vitalsRows: [VitalMetricRecord] = try? await supabase.from("vitals")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: minDateStr)
                .lte("date", value: maxDateStr)
                .execute()
                .value {
                for row in vitalsRows {
                    if let t = row.metricType, row.value > 0 {
                        if historicalVitalsByDate[row.date]?[t] == nil {
                            historicalVitalsByDate[row.date, default: [:]][t] = row.value
                        }
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
            let lower = device.lowercased()
            let source = DeviceSource.from(name: device)
            let isPhone = lower.contains("phone") || lower.contains("pixel") || lower.contains("galaxy") || lower.contains("handset")
            let isWearable = !isPhone && (
                source == .appleWatch || source == .amazfit || source == .oneplus || source == .huawei || source == .oura ||
                lower.contains("watch") || lower.contains("balance") || lower.contains("gt5") || lower.contains("oura") ||
                (lower.contains("health") && !lower.contains("phone"))
            )
            
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
        var chosen: (device: String, total: Int, hourly: [Int: Int], isWearable: Bool)?
        if let ps = preferredSource {
            chosen = deviceResults.first { DeviceSource.from(name: $0.device) == ps }
        }
        // 2. If preferredDevice is set
        if chosen == nil, let pd = preferredDevice, !pd.isEmpty {
            chosen = deviceResults.first { $0.device.localizedCaseInsensitiveContains(pd) }
        }
        // 3. Fallback: Prioritize wearables with max steps, then any device with max steps
        if chosen == nil {
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
        let isAllDevices = preferredSource == nil && (preferredDevice == nil || preferredDevice?.isEmpty == true)
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
