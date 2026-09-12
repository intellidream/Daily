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
    
    // Activity
    @Published public var hourlySteps: [HourlyStepBucket] = []
    @Published public var totalStepsToday: Int = 0
    @Published public var totalActiveCalories: Double = 0
    
    // Vitals Grid & Trends
    @Published public var currentVitals: [HealthMetricType: VitalMetricRecord] = [:]
    @Published public var historicalTrends: [HealthMetricType: [DailyMetricTrendPoint]] = [:]
    
    // MARK: - Private State & Dependencies
    
    private let supabase = SupabaseService.shared.client
    private let cacheTTL: TimeInterval = 300 // 5 minutes in-memory cache
    private var telemetryCache: [String: (timestamp: Date, telemetry: [HealthTelemetryRecord], vitals: [VitalMetricRecord])] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var activeLoadTask: Task<Void, Never>?
    
    private let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private let isoTimestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    public init() {
        // Observe auth session state changes so that once user authentication resolves,
        // real telemetry is fetched immediately instead of falling back to or caching demo data.
        AuthService.shared.$sessionState
            .dropFirst()
            .sink { [weak self] state in
                if case .authenticated = state {
                    Task { @MainActor [weak self] in
                        await self?.loadDataForSelectedDate(forceRefresh: true)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Navigation Actions
    
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
        Task {
            await loadDataForSelectedDate()
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
        
        let dateKey = isoDateFormatter.string(from: selectedDate)
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let effectiveTTL: TimeInterval = isToday ? 30 : cacheTTL
        
        // 1. Check cache if not forcing refresh
        if !forceRefresh, let cached = telemetryCache[dateKey], Date().timeIntervalSince(cached.timestamp) < effectiveTTL {
            let hasSteps = cached.telemetry.contains(where: { $0.isSteps && ($0.value ?? 0) > 0 }) ||
                           cached.vitals.contains(where: { $0.type == "steps" && $0.value > 0 })
            if hasSteps || localDataProvider == nil {
                await applyRecords(telemetry: cached.telemetry, vitals: cached.vitals)
                return
            }
        }
        
        // 2. Fetch from Supabase and Local Provider concurrently
        var fetchedTelemetry: [HealthTelemetryRecord] = []
        var fetchedVitals: [VitalMetricRecord] = []
        
        let session = try? await supabase.auth.session
        if let userId = session?.user.id.uuidString.lowercased() {
            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: selectedDate)
            let windowStart = cal.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay // D-1 18:00
            let windowEnd = cal.date(byAdding: .hour, value: 24, to: startOfDay) ?? startOfDay   // D 24:00
            
            let startIso = isoTimestampFormatter.string(from: windowStart)
            let endIso = isoTimestampFormatter.string(from: windowEnd)
            
            // Query Supabase telemetry
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
            
            // Query Supabase daily vitals
            do {
                let vitals: [VitalMetricRecord] = try await supabase.from("vitals")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("date", value: dateKey)
                    .execute()
                    .value
                fetchedVitals = vitals
            } catch {
                print("[HealthDataService] Warning: Could not fetch vitals: \(error.localizedDescription)")
            }
        }
        
        // 3. Concurrently fetch local on-device provider (e.g. Apple HealthKit)
        if let provider = localDataProvider {
            let localTelem = await provider.fetchLocalTelemetry(for: selectedDate)
            let localSleep = await provider.fetchLocalSleepStages(for: selectedDate)
            fetchedTelemetry.append(contentsOf: localTelem)
            fetchedTelemetry.append(contentsOf: localSleep)
        }
        
        // Deduplicate any repeated database or provider records
        fetchedTelemetry = Self.deduplicateTelemetry(fetchedTelemetry)
        
        // 4. Fallback to realistic demo data ONLY if in explicit Guest mode with no data
        if AuthService.shared.isGuest && fetchedTelemetry.isEmpty && fetchedVitals.isEmpty {
            let demo = generateDemoData(for: selectedDate)
            fetchedTelemetry = demo.telemetry
            fetchedVitals = demo.vitals
        }
        
        // 5. Update cache & apply (never cache empty state if session is still initializing)
        if AuthService.shared.isAuthenticated || AuthService.shared.isGuest {
            telemetryCache[dateKey] = (timestamp: Date(), telemetry: fetchedTelemetry, vitals: fetchedVitals)
        }
        await applyRecords(telemetry: fetchedTelemetry, vitals: fetchedVitals)
        
        // 6. Also load 7-day trend history
        await loadHistoricalTrends()
    }
    
    private func applyRecords(telemetry: [HealthTelemetryRecord], vitals: [VitalMetricRecord]) async {
        // Collect available devices and canonical sources
        var devicesSet = Set<String>()
        var sourcesSet = Set<DeviceSource>()
        for t in telemetry {
            if let d = t.sourceDevice, !d.isEmpty {
                devicesSet.insert(d)
                sourcesSet.insert(DeviceSource.from(name: d))
            }
        }
        for v in vitals {
            if let d = v.sourceDevice, !d.isEmpty {
                devicesSet.insert(d)
                sourcesSet.insert(DeviceSource.from(name: d))
            }
        }
        availableDevices = Array(devicesSet).sorted()
        availableSources = Array(sourcesSet).sorted()
        
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
        
        self.currentVitals = vitalsMap
    }
    
    // MARK: - 7-Day & 30-Day Trend Generator
    
    public func loadHistoricalTrends() async {
        let cal = Calendar.current
        var trends: [HealthMetricType: [DailyMetricTrendPoint]] = [:]
        
        let metrics: [HealthMetricType] = [.steps, .sleepDuration, .heartRate, .hrvSdnn, .activeEnergy, .weight]
        
        // In Guest mode with no real data, generate preview points
        if AuthService.shared.isGuest && currentVitals.isEmpty {
            for m in metrics {
                var points: [DailyMetricTrendPoint] = []
                for dayOffset in (0..<7).reversed() {
                    if let date = cal.date(byAdding: .day, value: -dayOffset, to: selectedDate) {
                        let isComplete = dayOffset > 0
                        let target = defaultTarget(for: m)
                        let val = generateHistoricalValue(for: m, dayOffset: dayOffset, target: target)
                        points.append(DailyMetricTrendPoint(
                            date: date,
                            value: val,
                            target: target,
                            isCompleteDay: isComplete
                        ))
                    }
                }
                trends[m] = points
            }
            self.historicalTrends = trends
            return
        }
        
        // For authenticated users, query real 7-day historical vitals from Supabase
        var historicalVitalsByDate: [String: [HealthMetricType: Double]] = [:]
        let session = try? await supabase.auth.session
        if let userId = session?.user.id.uuidString.lowercased(),
           let minDate = cal.date(byAdding: .day, value: -6, to: selectedDate) {
            let minDateStr = isoDateFormatter.string(from: minDate)
            let maxDateStr = isoDateFormatter.string(from: selectedDate)
            
            if let vitalsRows: [VitalMetricRecord] = try? await supabase.from("vitals")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: minDateStr)
                .lte("date", value: maxDateStr)
                .execute()
                .value {
                for row in vitalsRows {
                    if let t = row.metricType {
                        historicalVitalsByDate[row.date, default: [:]][t] = row.value
                    }
                }
            }
            
            // Also fetch 7-day telemetry to populate steps and sleep for days without aggregated vitals row
            let minDateTimeStr = isoTimestampFormatter.string(from: cal.startOfDay(for: minDate))
            let maxDateTimeStr = isoTimestampFormatter.string(from: cal.date(bySettingHour: 23, minute: 59, second: 59, of: selectedDate) ?? selectedDate)
            
            if let telemRows: [HealthTelemetryRecord] = try? await supabase.from("health_telemetry")
                .select()
                .eq("user_id", value: userId)
                .gte("start_time", value: minDateTimeStr)
                .lte("start_time", value: maxDateTimeStr)
                .execute()
                .value {
                let deduped = Self.deduplicateTelemetry(telemRows)
                let groupedByDay = Dictionary(grouping: deduped) { r in
                    isoDateFormatter.string(from: r.startTime)
                }
                for (dayStr, dayRecords) in groupedByDay {
                    guard let dayDate = isoDateFormatter.date(from: dayStr) else { continue }
                    
                    if (historicalVitalsByDate[dayStr]?[.steps] ?? 0) <= 0 {
                        let stepRes = Self.calculateDailySteps(
                            targetDate: dayDate,
                            telemetry: dayRecords,
                            vitalsSummary: historicalVitalsByDate[dayStr] ?? [:],
                            preferredDevice: selectedDeviceFilter,
                            preferredSource: selectedDeviceSource,
                            calendar: cal
                        )
                        if stepRes.totalSteps > 0 {
                            historicalVitalsByDate[dayStr, default: [:]][.steps] = Double(stepRes.totalSteps)
                        }
                    }
                    
                    if (historicalVitalsByDate[dayStr]?[.sleepDuration] ?? 0) <= 0 {
                        let sleepRes = SleepClusteringEngine.clusterSleep(
                            targetDate: dayDate,
                            telemetry: dayRecords,
                            vitalsSummary: historicalVitalsByDate[dayStr] ?? [:],
                            preferredDevice: selectedDeviceFilter
                        )
                        if let prim = sleepRes.primarySession, prim.asleepSeconds > 0 {
                            historicalVitalsByDate[dayStr, default: [:]][.sleepDuration] = prim.asleepSeconds / 60.0
                        }
                    }
                }
            }
        }
        
        for m in metrics {
            var points: [DailyMetricTrendPoint] = []
            for dayOffset in (0..<7).reversed() {
                if let date = cal.date(byAdding: .day, value: -dayOffset, to: selectedDate) {
                    let dateStr = isoDateFormatter.string(from: date)
                    let isComplete = dayOffset > 0
                    let target = defaultTarget(for: m)
                    
                    var val: Double = 0
                    if let dayVitals = historicalVitalsByDate[dateStr], let v = dayVitals[m] {
                        val = v
                    } else if cal.isDate(date, inSameDayAs: selectedDate) {
                        // Use current day computed metrics
                        switch m {
                        case .steps: val = Double(totalStepsToday)
                        case .sleepDuration: val = Double(primarySleepSession?.asleepSeconds ?? 0) / 60.0
                        case .heartRate: val = averageBpm > 0 ? averageBpm : restingBpm
                        case .activeEnergy: val = totalActiveCalories
                        default: val = currentVitals[m]?.value ?? 0
                        }
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
            let isWearable = (source == .appleWatch || source == .amazfit || source == .oneplus || source == .huawei || source == .healthKit) ||
                             lower.contains("watch") || lower.contains("balance") || lower.contains("gt5") || lower.contains("health")
            
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
        let lower = device.lowercased()
        if lower.contains("zepp") || lower.contains("amazfit") || lower.contains("balance") ||
           lower.contains("huawei") || lower.contains("harmony") || lower.contains("gt5") {
            return true
        }
        let nonZero = records.compactMap { $0.value }.filter { $0 > 0 }
        if nonZero.count >= 2 {
            let isIncreasing = zip(nonZero, nonZero.dropFirst()).allSatisfy { $0 <= $1 }
            let hasLargeValues = nonZero.contains { $0 >= 500 }
            if isIncreasing && hasLargeValues {
                return true
            }
        }
        return false
    }
}
