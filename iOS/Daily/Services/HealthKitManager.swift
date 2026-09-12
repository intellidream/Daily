import Foundation
import HealthKit
import DailyCore

/// Native iOS HealthKit provider querying on-device biometric sensors and Apple Watch data.
@MainActor
public final class HealthKitManager: ObservableObject, LocalHealthDataProvider {
    public static let shared = HealthKitManager()
    
    public let healthStore = HKHealthStore()
    @Published public private(set) var isAuthorized: Bool = false
    
    public var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    public init() {
        HabitsService.shared.onWaterLogged = { [weak self] amountMl, date in
            Task {
                await self?.writeWaterIntake(amountMl: amountMl, date: date)
            }
        }
    }
    
    private var authTask: Task<Bool, Never>?
    
    public func ensureAuthorized() async -> Bool {
        if isAuthorized { return true }
        if let existing = authTask {
            return await existing.value
        }
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self = self else { return false }
            return await self.requestAuthorization()
        }
        authTask = task
        let result = await task.value
        authTask = nil
        return result
    }

    public func requestAuthorization() async -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard isAvailable else { return false }
        
        var typesToRead = Set<HKObjectType>()
        var typesToShare = Set<HKSampleType>()
        
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .flightsClimbed,
            .walkingSpeed,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .oxygenSaturation,
            .respiratoryRate,
            .bodyMass,
            .bodyFatPercentage,
            .dietaryWater
        ]
        
        for q in quantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: q) {
                typesToRead.insert(type)
            }
        }
        
        if let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) {
            typesToShare.insert(waterType)
        }
        
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            typesToRead.insert(sleepType)
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            self.isAuthorized = true
            return true
        } catch {
            print("[HealthKitManager] Auth error: \(error.localizedDescription)")
            return false
        }
        #endif
    }
    
    // MARK: - LocalHealthDataProvider Conformance
    
    public func fetchLocalTelemetry(for date: Date) async -> [HealthTelemetryRecord] {
        guard isAvailable else { return [] }
        _ = await ensureAuthorized()
        guard isAuthorized else { return [] }
        
        var records: [HealthTelemetryRecord] = []
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        // 1. Steps (Queried per hour via HKStatisticsCollectionQuery for clean hourly distribution and automatic deduplication)
        let hourlySteps = await fetchHourlySteps(for: date)
        if !hourlySteps.isEmpty {
            records.append(contentsOf: hourlySteps)
        } else if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            if let count = await fetchCumulativeSum(for: stepType, unit: .count(), predicate: predicate) {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "steps",
                    value: count,
                    unit: "count",
                    startTime: startOfDay,
                    endTime: endOfDay,
                    sourceDevice: "Apple Health"
                ))
            }
        }
        
        // 2. Active Calories
        if let calType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            if let kcal = await fetchCumulativeSum(for: calType, unit: .kilocalorie(), predicate: predicate) {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "active_energy",
                    value: kcal,
                    unit: "kcal",
                    startTime: startOfDay,
                    endTime: endOfDay,
                    sourceDevice: "Apple Health"
                ))
            }
        }
        
        // 3. Intraday Heart Rate Samples
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let hrSamples = await fetchQuantitySamples(for: hrType, predicate: predicate, unit: HKUnit.count().unitDivided(by: .minute()), typeName: "heart_rate")
            records.append(contentsOf: hrSamples)
        }
        
        // Predicate for nocturnal & daily vital samples (from 18:00 D-1 to 24:00 D)
        let vitalsStart = cal.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
        let vitalsPredicate = HKQuery.predicateForSamples(withStart: vitalsStart, end: endOfDay, options: [])
        
        // 4. Resting Heart Rate
        if let rhrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            if let rhr = await fetchMostRecentSample(for: rhrType, predicate: vitalsPredicate, unit: HKUnit.count().unitDivided(by: .minute())) {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "resting_heart_rate",
                    value: rhr.value,
                    unit: "bpm",
                    startTime: rhr.timestamp,
                    endTime: rhr.timestamp,
                    sourceDevice: rhr.device
                ))
            }
        }
        
        // 5. Heart Rate Variability (SDNN)
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            if let hrv = await fetchMostRecentSample(for: hrvType, predicate: vitalsPredicate, unit: HKUnit.secondUnit(with: .milli)) {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "hrv_sdnn",
                    value: hrv.value,
                    unit: "ms",
                    startTime: hrv.timestamp,
                    endTime: hrv.timestamp,
                    sourceDevice: hrv.device
                ))
            }
        }
        
        // 6. Blood Oxygen / SpO2
        if let o2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            if let o2 = await fetchMostRecentSample(for: o2Type, predicate: vitalsPredicate, unit: HKUnit.percent()) {
                let val = o2.value <= 1.0 ? (o2.value * 100.0) : o2.value
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "oxygen_saturation",
                    value: val,
                    unit: "%",
                    startTime: o2.timestamp,
                    endTime: o2.timestamp,
                    sourceDevice: o2.device
                ))
            }
        }
        
        // 7. Respiratory Rate
        if let respType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            if let resp = await fetchMostRecentSample(for: respType, predicate: vitalsPredicate, unit: HKUnit.count().unitDivided(by: .minute())) {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "respiratory_rate",
                    value: resp.value,
                    unit: "br/min",
                    startTime: resp.timestamp,
                    endTime: resp.timestamp,
                    sourceDevice: resp.device
                ))
            }
        }
        
        // 8. Body Mass (Weight) - query latest reading up to end of selected day
        let anyPastPredicate = HKQuery.predicateForSamples(withStart: nil, end: endOfDay, options: [])
        if let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            if let weight = await fetchMostRecentSample(for: weightType, predicate: anyPastPredicate, unit: HKUnit.gramUnit(with: .kilo)) {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "weight",
                    value: weight.value,
                    unit: "kg",
                    startTime: weight.timestamp,
                    endTime: weight.timestamp,
                    sourceDevice: weight.device
                ))
            }
        }
        
        // 9. Body Fat Percentage
        if let fatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
            if let fat = await fetchMostRecentSample(for: fatType, predicate: anyPastPredicate, unit: HKUnit.percent()) {
                let val = fat.value <= 1.0 ? (fat.value * 100.0) : fat.value
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "body_fat_percentage",
                    value: val,
                    unit: "%",
                    startTime: fat.timestamp,
                    endTime: fat.timestamp,
                    sourceDevice: fat.device
                ))
            }
        }
        
        return records
    }
    
    public func fetchLocalSleepStages(for date: Date) async -> [HealthTelemetryRecord] {
        return await fetchSleepStages(targetDate: date)
    }
    
    // MARK: - Legacy Fetch All
    
    public func fetchMetrics(for date: Date) async -> [HealthTelemetryRecord] {
        var records = await fetchLocalTelemetry(for: date)
        let sleepRecords = await fetchSleepStages(targetDate: date)
        records.append(contentsOf: sleepRecords)
        return records
    }
    
    public func fetchSleepStages(targetDate: Date) async -> [HealthTelemetryRecord] {
        guard isAvailable else { return [] }
        _ = await ensureAuthorized()
        guard isAuthorized, let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: targetDate)
        // Nocturnal window: 18:00 yesterday to 18:00 today
        guard let windowStart = cal.date(byAdding: .hour, value: -6, to: startOfDay),
              let windowEnd = cal.date(byAdding: .hour, value: 18, to: startOfDay)
        else { return [] }
        
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                
                var records: [HealthTelemetryRecord] = []
                for sample in categorySamples {
                    let typeName: String
                    if #available(iOS 16.0, *) {
                        switch sample.value {
                        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                            typeName = "sleep_stage_deep"
                        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                            typeName = "sleep_stage_rem"
                        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                            typeName = "sleep_stage_light"
                        case HKCategoryValueSleepAnalysis.awake.rawValue:
                            typeName = "sleep_stage_awake"
                        default:
                            typeName = "sleep"
                        }
                    } else {
                        typeName = sample.value == HKCategoryValueSleepAnalysis.awake.rawValue ? "sleep_stage_awake" : "sleep"
                    }
                    
                    let devName: String
                    if let d = sample.device?.name, !d.isEmpty {
                        devName = d
                    } else if sample.sourceRevision.source.name.localizedCaseInsensitiveContains("Watch") {
                        devName = "Apple Watch"
                    } else {
                        devName = "Apple Health"
                    }
                    
                    let durationMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    records.append(HealthTelemetryRecord(
                        id: sample.uuid.uuidString,
                        userId: "healthkit",
                        type: typeName,
                        value: durationMinutes,
                        unit: "minutes",
                        startTime: sample.startDate,
                        endTime: sample.endDate,
                        sourceDevice: devName
                    ))
                }
                
                continuation.resume(returning: records)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Water Logging (Bubbles)
    
    public func writeWaterIntake(amountMl: Double, date: Date = Date()) async {
        guard isAvailable, let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) else { return }
        #if !targetEnvironment(simulator)
        guard healthStore.authorizationStatus(for: waterType) == .sharingAuthorized else {
            print("[HealthKitManager] Dietary water sharing not authorized, skipping HealthKit save.")
            return
        }
        #endif
        
        let quantity = HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: amountMl)
        let sample = HKQuantitySample(
            type: waterType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        
        do {
            try await healthStore.save(sample)
            print("[HealthKitManager] Successfully saved \(amountMl) ml water to HealthKit")
        } catch {
            print("[HealthKitManager] Failed to save water to HealthKit: \(error.localizedDescription)")
        }
    }
    
    private func fetchHourlySteps(for date: Date) async -> [HealthTelemetryRecord] {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return [] }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: DateComponents(hour: 1)
            )
            
            query.initialResultsHandler = { _, results, error in
                guard let results = results, error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                var hourlyRecords: [HealthTelemetryRecord] = []
                results.enumerateStatistics(from: startOfDay, to: endOfDay) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                        hourlyRecords.append(HealthTelemetryRecord(
                            id: UUID().uuidString,
                            userId: "healthkit",
                            type: "steps",
                            value: sum,
                            unit: "count",
                            startTime: stats.startDate,
                            endTime: stats.endDate,
                            sourceDevice: "Apple Health"
                        ))
                    }
                }
                continuation.resume(returning: hourlyRecords)
            }
            healthStore.execute(query)
        }
    }
    
    public func fetchDietaryWater(for date: Date) async -> Double {
        guard isAvailable, let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) else { return 0 }
        
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        return await fetchCumulativeSum(for: waterType, unit: HKUnit.literUnit(with: .milli), predicate: predicate) ?? 0
    }
    
    // MARK: - Helpers
    
    private func fetchCumulativeSum(for quantityType: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                if let sum = stats?.sumQuantity()?.doubleValue(for: unit) {
                    continuation.resume(returning: sum)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchQuantitySamples(for quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit, typeName: String, limit: Int = 120) async -> [HealthTelemetryRecord] {
        await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: limit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let qSamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let records = qSamples.map { sample in
                    let dev = sample.device?.name ?? (sample.sourceRevision.source.name.localizedCaseInsensitiveContains("Watch") ? "Apple Watch" : "Apple Health")
                    return HealthTelemetryRecord(
                        id: sample.uuid.uuidString,
                        userId: "healthkit",
                        type: typeName,
                        value: sample.quantity.doubleValue(for: unit),
                        unit: unit.unitString,
                        startTime: sample.startDate,
                        endTime: sample.endDate,
                        sourceDevice: dev
                    )
                }
                continuation.resume(returning: records)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchMostRecentSample(for quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async -> (value: Double, device: String, timestamp: Date)? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    let dev = sample.device?.name ?? (sample.sourceRevision.source.name.localizedCaseInsensitiveContains("Watch") ? "Apple Watch" : "Apple Health")
                    continuation.resume(returning: (sample.quantity.doubleValue(for: unit), dev, sample.endDate))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchMostRecentQuantity(for quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: sample.quantity.doubleValue(for: unit))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
}


