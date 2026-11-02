import Foundation
import HealthKit
import Supabase
import os.log

private struct WatchHourlyStepPayload: Codable {
    let hour: Int
    let steps: Int
}

private struct WatchDailyVitalsPayload: Codable {
    let id: String
    let user_id: String
    let local_date: String
    let source_device_key: String
    let host_device_name: String
    let steps: Int
    let active_kcal: Double
    let resting_heart_rate: Int?
    let spo2: Double?
    let hrv_sdnn_nightly: Double?
    let hourly_steps: [WatchHourlyStepPayload]?
    let updated_at: String
}

private struct WatchIntradayHrPayload: Codable {
    let id: String
    let user_id: String
    let local_date: String
    let source_device_key: String
    let bucket_minute: Int
    let bpm_avg: Int
    let bpm_min: Int
    let bpm_max: Int
    let sample_count: Int
    let updated_at: String
}

private struct WatchSleepStagePayload: Codable {
    let id: String
    let stageType: String
    let startTime: String
    let endTime: String
    let durationSeconds: Double
    let sourceDevice: String
}

private struct WatchSleepSessionPayload: Codable {
    let id: String
    let user_id: String
    let local_date: String
    let session_type: String
    let source_device_key: String
    let host_device_name: String
    let start_time: String
    let end_time: String
    let duration_seconds: Int
    let time_in_bed_seconds: Int
    let efficiency_percent: Double
    let sleep_score: Int
    let deep_seconds: Int
    let rem_seconds: Int
    let light_seconds: Int
    let awake_seconds: Int
    let latency_seconds: Int
    let quality_rating: String
    let stages: [WatchSleepStagePayload]
    let source_priority: Int
    let is_user_selected: Bool
}

class HealthTelemetryManager {
    static let shared = HealthTelemetryManager()
    private let healthStore = HKHealthStore()
    private let canonicalWatchKey = "Apple Watch Ultra 2"
    private let canonicalWatchSlug = "apple_watch_ultra_2"
    private let minSyncIntervalSeconds: TimeInterval = 600 // 10-minute smartwatch battery throttle
    
    // Tier 1: Fast Sync (Real-time active metrics)
    private let tier1QuantityTypes: [HKQuantityTypeIdentifier] = [
        .heartRate,
        .stepCount,
        .activeEnergyBurned
    ]
    
    // Tier 2: Deep Analytics & Vitals (Sleep, HRV, Resting HR, SpO2)
    private let tier2QuantityTypes: [HKQuantityTypeIdentifier] = [
        .heartRateVariabilitySDNN,
        .restingHeartRate,
        .oxygenSaturation
    ]
    
    private let tier2CategoryTypes: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis
    ]
    
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthTelemetryManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Health data not available on this device."])
        }
        
        var typesToRead = Set<HKSampleType>()
        for t in tier1QuantityTypes {
            if let type = HKObjectType.quantityType(forIdentifier: t) {
                typesToRead.insert(type)
            }
        }
        for t in tier2QuantityTypes {
            if let type = HKObjectType.quantityType(forIdentifier: t) {
                typesToRead.insert(type)
            }
        }
        for t in tier2CategoryTypes {
            if let type = HKObjectType.categoryType(forIdentifier: t) {
                typesToRead.insert(type)
            }
        }
        
        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
    }
    
    /// Syncs Watch-originated biometrics directly into Supabase lean tables (`health_daily_vitals`,
    /// `health_intraday_heart_rate`, `health_sleep_sessions`) with zero writes to legacy `health_telemetry`.
    func syncTelemetry(isDeepSync: Bool = false) async {
        let now = Date()
        let lastSync = UserDefaults.standard.double(forKey: "last_health_sync_time")
        if !isDeepSync && lastSync > 0 && (now.timeIntervalSince1970 - lastSync) < minSyncIntervalSeconds {
            return
        }
        
        guard let pClient = WatchSessionManager.shared.supabaseClient,
              let userUUID = WatchSessionManager.shared.currentUserId else {
            os_log("Supabase client or user not available. Skipping lean watch sync.", type: .error)
            return
        }
        
        let userId = userUUID.uuidString.lowercased()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let dateKey = localDateFormatter.string(from: now)
        let nowIso = isoFormatter.string(from: now)
        
        // 1. Fetch Watch-only Hourly Steps & Active Calories for Today
        let (totalSteps, hourlySteps) = await fetchTodayWatchSteps(startOfDay: startOfDay, now: now, calendar: cal)
        let activeKcal = await fetchTodayWatchActiveEnergy(startOfDay: startOfDay, now: now)
        
        // 2. Fetch Watch-only Spot Biometrics (RHR, HRV SDNN, SpO2)
        let rhr = await fetchLatestWatchQuantity(.restingHeartRate, unit: HKUnit(from: "count/min"), since: startOfDay)
        let hrv = await fetchLatestWatchQuantity(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), since: startOfDay)
        let rawSpo2 = await fetchLatestWatchQuantity(.oxygenSaturation, unit: HKUnit.percent(), since: startOfDay)
        let spo2 = rawSpo2.map { $0 <= 1.0 ? ($0 * 100.0) : $0 }
        
        // 3. Fetch Watch-only 5-Minute Heart Rate Buckets for Today
        let hrBuckets = await fetchTodayWatchHeartRateBuckets(
            userId: userId,
            dateKey: dateKey,
            startOfDay: startOfDay,
            now: now,
            nowIso: nowIso,
            calendar: cal
        )
        
        var didPushAny = false
        
        if totalSteps > 0 || activeKcal > 0 || rhr != nil || hrv != nil || spo2 != nil {
            let vitalsPayload = WatchDailyVitalsPayload(
                id: "vitals_\(userId)_\(dateKey)_\(canonicalWatchSlug)",
                user_id: userId,
                local_date: dateKey,
                source_device_key: canonicalWatchKey,
                host_device_name: "Schmitz",
                steps: totalSteps,
                active_kcal: round(activeKcal * 10) / 10,
                resting_heart_rate: rhr.map { Int(round($0)) },
                spo2: spo2.map { round($0 * 10) / 10 },
                hrv_sdnn_nightly: hrv.map { round($0 * 10) / 10 },
                hourly_steps: hourlySteps.isEmpty ? nil : hourlySteps,
                updated_at: nowIso
            )
            do {
                try await pClient.from("health_daily_vitals")
                    .upsert(vitalsPayload, onConflict: "user_id,local_date,source_device_key")
                    .execute()
                didPushAny = true
            } catch {
                os_log("Watch lean vitals upsert warning: %@", type: .error, error.localizedDescription)
            }
        }
        
        if !hrBuckets.isEmpty {
            do {
                try await pClient.from("health_intraday_heart_rate")
                    .upsert(hrBuckets, onConflict: "user_id,local_date,source_device_key,bucket_minute")
                    .execute()
                didPushAny = true
            } catch {
                os_log("Watch lean intraday HR upsert warning: %@", type: .error, error.localizedDescription)
            }
        }
        
        if isDeepSync, let sleepPayload = await fetchTodayWatchSleepSession(userId: userId, dateKey: dateKey, startOfDay: startOfDay) {
            do {
                try await pClient.from("health_sleep_sessions")
                    .upsert(sleepPayload, onConflict: "user_id,local_date,session_type,source_device_key")
                    .execute()
                didPushAny = true
            } catch {
                os_log("Watch lean sleep upsert warning: %@", type: .error, error.localizedDescription)
            }
        }
        
        let syncTimestamp = now.timeIntervalSince1970
        let status = didPushAny ? "synced" : "no_new_data"
        UserDefaults.standard.set(syncTimestamp, forKey: "last_health_sync_time")
        UserDefaults.standard.set(status, forKey: "last_health_sync_status")
        if let groupPrefs = UserDefaults(suiteName: "group.com.intellidream.daily") {
            groupPrefs.set(syncTimestamp, forKey: "last_health_sync_time")
            groupPrefs.set(status, forKey: "last_health_sync_status")
        }
    }
    
    // MARK: - Watch-Only Source Filtering & Queries
    
    private func isWatchSource(_ source: HKSource, device: HKDevice? = nil) -> Bool {
        let bundle = source.bundleIdentifier.lowercased()
        if bundle.contains("oura") || bundle.contains("fitbit") || bundle.contains("google") {
            return false
        }
        if let model = device?.model?.lowercased() {
            if model.contains("iphone") || model.contains("ipad") {
                return false
            }
            if model.contains("watch") {
                return true
            }
        }
        let name = source.name.lowercased()
        if name.contains("watch") {
            return true
        }
        if name.contains("iphone") {
            return false
        }
        return bundle.hasPrefix("com.apple.health")
    }
    
    private func fetchTodayWatchSteps(startOfDay: Date, now: Date, calendar: Calendar) async -> (Int, [WatchHourlyStepPayload]) {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return (0, []) }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        var interval = DateComponents()
        interval.hour = 1
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .separateBySource],
                anchorDate: startOfDay,
                intervalComponents: interval
            )
            query.initialResultsHandler = { [weak self] _, results, _ in
                guard let self = self, let results = results else {
                    continuation.resume(returning: (0, []))
                    return
                }
                var hourlyMap: [Int: Int] = [:]
                results.enumerateStatistics(from: startOfDay, to: now) { stats, _ in
                    let hour = calendar.component(.hour, from: stats.startDate)
                    if let sources = stats.sources {
                        for src in sources where self.isWatchSource(src) {
                            if let sum = stats.sumQuantity(for: src)?.doubleValue(for: .count()), sum > 0 {
                                hourlyMap[hour, default: 0] += Int(round(sum))
                            }
                        }
                    }
                }
                let total = hourlyMap.values.reduce(0, +)
                guard total > 0 else {
                    continuation.resume(returning: (0, []))
                    return
                }
                let buckets = (0..<24).map { WatchHourlyStepPayload(hour: $0, steps: hourlyMap[$0] ?? 0) }
                continuation.resume(returning: (total, buckets))
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchTodayWatchActiveEnergy(startOfDay: Date, now: Date) async -> Double {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .separateBySource]
            ) { [weak self] _, stats, _ in
                guard let self = self, let stats = stats, let sources = stats.sources else {
                    continuation.resume(returning: 0)
                    return
                }
                var sumKcal = 0.0
                for src in sources where self.isWatchSource(src) {
                    sumKcal += stats.sumQuantity(for: src)?.doubleValue(for: .kilocalorie()) ?? 0
                }
                continuation.resume(returning: sumKcal)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchLatestWatchQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, since: Date) async -> Double? {
        guard let qType = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: since.addingTimeInterval(-6 * 3600), end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: qType, predicate: predicate, limit: 25, sortDescriptors: [sort]) { [weak self] _, samples, _ in
                guard let self = self, let qSamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                for s in qSamples where self.isWatchSource(s.sourceRevision.source, device: s.device) {
                    let val = s.quantity.doubleValue(for: unit)
                    if val > 0 {
                        continuation.resume(returning: val)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchTodayWatchHeartRateBuckets(
        userId: String,
        dateKey: String,
        startOfDay: Date,
        now: Date,
        nowIso: String,
        calendar: Calendar
    ) async -> [WatchIntradayHrPayload] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let bpmUnit = HKUnit(from: "count/min")
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 600, sortDescriptors: [sort]) { [weak self] _, samples, _ in
                guard let self = self, let qSamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                var buckets: [Int: [Double]] = [:]
                for s in qSamples where self.isWatchSource(s.sourceRevision.source, device: s.device) {
                    let bpm = s.quantity.doubleValue(for: bpmUnit)
                    guard bpm >= 30 && bpm <= 240 else { continue }
                    let hour = calendar.component(.hour, from: s.startDate)
                    let min = calendar.component(.minute, from: s.startDate)
                    let bucketMin = hour * 60 + (min / 5) * 5
                    buckets[bucketMin, default: []].append(bpm)
                }
                let payloads = buckets.keys.sorted().compactMap { bMin -> WatchIntradayHrPayload? in
                    guard let vals = buckets[bMin], !vals.isEmpty else { return nil }
                    let avg = vals.reduce(0, +) / Double(vals.count)
                    return WatchIntradayHrPayload(
                        id: "hr_\(userId)_\(dateKey)_\(self.canonicalWatchSlug)_\(bMin)",
                        user_id: userId,
                        local_date: dateKey,
                        source_device_key: self.canonicalWatchKey,
                        bucket_minute: bMin,
                        bpm_avg: Int(round(avg)),
                        bpm_min: Int(round(vals.min() ?? avg)),
                        bpm_max: Int(round(vals.max() ?? avg)),
                        sample_count: vals.count,
                        updated_at: nowIso
                    )
                }
                continuation.resume(returning: payloads)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchTodayWatchSleepSession(userId: String, dateKey: String, startOfDay: Date) async -> WatchSleepSessionPayload? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let windowStart = startOfDay.addingTimeInterval(-6 * 3600) // 18:00 previous evening
        let windowEnd = startOfDay.addingTimeInterval(14 * 3600)   // 14:00 wake-up day
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 250, sortDescriptors: [sort]) { [weak self] _, samples, _ in
                guard let self = self, let cSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                var deepS = 0
                var remS = 0
                var lightS = 0
                var awakeS = 0
                var stages: [WatchSleepStagePayload] = []
                var minStart: Date?
                var maxEnd: Date?
                
                for s in cSamples where self.isWatchSource(s.sourceRevision.source, device: s.device) {
                    let dur = Int(round(s.endDate.timeIntervalSince(s.startDate)))
                    guard dur > 0 else { continue }
                    let stageLabel: String?
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        stageLabel = "Deep"; deepS += dur
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        stageLabel = "REM"; remS += dur
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        stageLabel = "Light"; lightS += dur
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        stageLabel = "Awake"; awakeS += dur
                    default:
                        stageLabel = nil // Ignore .inBed container envelope
                    }
                    guard let label = stageLabel else { continue }
                    if minStart == nil || s.startDate < minStart! { minStart = s.startDate }
                    if maxEnd == nil || s.endDate > maxEnd! { maxEnd = s.endDate }
                    stages.append(WatchSleepStagePayload(
                        id: s.uuid.uuidString,
                        stageType: label,
                        startTime: self.isoFormatter.string(from: s.startDate),
                        endTime: self.isoFormatter.string(from: s.endDate),
                        durationSeconds: Double(dur),
                        sourceDevice: self.canonicalWatchKey
                    ))
                }
                
                let asleepS = deepS + remS + lightS
                guard asleepS >= 5400, let start = minStart, let end = maxEnd else {
                    continuation.resume(returning: nil)
                    return
                }
                let inBedS = max(asleepS + awakeS, Int(round(end.timeIntervalSince(start))))
                let eff = min(100.0, max(10.0, Double(asleepS) / Double(max(1, inBedS)) * 100.0))
                let score = min(100, max(40, Int(round((Double(asleepS) / 28800.0) * 50.0 + (eff / 100.0) * 30.0 + (Double(deepS + remS) / Double(max(1, asleepS))) * 50.0))))
                let rating = score >= 85 ? "Optimal" : (score >= 75 ? "Good" : (score >= 60 ? "Fair" : "Restless"))
                
                continuation.resume(returning: WatchSleepSessionPayload(
                    id: "sleep_\(userId)_\(dateKey)_primary_sleep_\(self.canonicalWatchSlug)",
                    user_id: userId,
                    local_date: dateKey,
                    session_type: "primary_sleep",
                    source_device_key: self.canonicalWatchKey,
                    host_device_name: "Schmitz",
                    start_time: self.isoFormatter.string(from: start),
                    end_time: self.isoFormatter.string(from: end),
                    duration_seconds: asleepS,
                    time_in_bed_seconds: inBedS,
                    efficiency_percent: round(eff * 10) / 10,
                    sleep_score: score,
                    deep_seconds: deepS,
                    rem_seconds: remS,
                    light_seconds: lightS,
                    awake_seconds: awakeS,
                    latency_seconds: 0,
                    quality_rating: rating,
                    stages: stages,
                    source_priority: 2,
                    is_user_selected: false
                ))
            }
            healthStore.execute(query)
        }
    }
}
