import Foundation
import HealthKit
#if canImport(UIKit)
import UIKit
#endif
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
        Self.configureHostName()
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
    
    private nonisolated(unsafe) static var _cachedHostPhoneName: String = "Schmitz"

    @MainActor
    public static func configureHostName() {
        #if canImport(UIKit)
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            _cachedHostPhoneName = name
        }
        #endif
    }
    
    nonisolated public static var hostPhoneName: String {
        return _cachedHostPhoneName
    }

    nonisolated public static func resolveCompoundSource(device: HKDevice?, source: HKSource) -> (host: String, sensor: String, compoundKey: String, color: String) {
        let host = hostPhoneName
        let sensor = resolveDeviceName(device: device, source: source)
        let key = "\(host) - \(sensor)"
        let color = DeviceColorPalette.getColor(for: key)
        return (host, sensor, key, color)
    }

    public func fetchLocalTelemetry(for date: Date) async -> [HealthTelemetryRecord] {
        guard isAvailable else { return [] }
        _ = await ensureAuthorized()
        guard isAuthorized else { return [] }
        
        var records: [HealthTelemetryRecord] = []
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let tzOffsetMin = cal.timeZone.secondsFromGMT(for: date) / 60
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let dateStr = f.string(from: date)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        let host = Self.hostPhoneName
        let defaultSensor = "Apple Health"
        let defaultKey = "\(host) - \(defaultSensor)"
        let defaultColor = DeviceColorPalette.getColor(for: defaultKey)
        
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
                    sourceDevice: defaultKey,
                    externalId: "steps_daily_\(Int(startOfDay.timeIntervalSince1970))",
                    semantics: "interval_delta",
                    tzOffsetMin: tzOffsetMin,
                    localDate: dateStr,
                    hostDeviceName: host,
                    sensorSourceName: defaultSensor,
                    sourceDeviceKey: defaultKey,
                    sourceColor: defaultColor
                ))
            }
        }
        
        // 2. Active Calories (Queried per hour via HKStatisticsCollectionQuery for accurate hourly accumulation)
        let hourlyEnergy = await fetchHourlyActiveEnergy(for: date)
        if !hourlyEnergy.isEmpty {
            records.append(contentsOf: hourlyEnergy)
        } else if let calType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            if let kcal = await fetchCumulativeSum(for: calType, unit: .kilocalorie(), predicate: predicate) {
                let epoch = Int(startOfDay.timeIntervalSince1970)
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "active_energy",
                    value: kcal,
                    unit: "kcal",
                    startTime: startOfDay,
                    endTime: endOfDay,
                    sourceDevice: defaultKey,
                    externalId: "active_energy_daily_\(epoch)",
                    semantics: "interval_delta",
                    tzOffsetMin: tzOffsetMin,
                    localDate: dateStr,
                    hostDeviceName: host,
                    sensorSourceName: defaultSensor,
                    sourceDeviceKey: defaultKey,
                    sourceColor: defaultColor
                ))
            }
        }
        
        // 3. Intraday Heart Rate Samples (downsampled to 5-minute buckets to prevent high-frequency row bloat)
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let hrSamples = await fetchQuantitySamples(for: hrType, predicate: predicate, unit: HKUnit.count().unitDivided(by: .minute()), typeName: "heart_rate", limit: HKObjectQueryNoLimit)
            let downsampled = downsampleHeartRateRecords(hrSamples, bucketIntervalSeconds: 300)
            records.append(contentsOf: downsampled)
        }
        
        // Predicate for nocturnal & daily vital samples (from 18:00 D-1 to 24:00 D)
        let vitalsStart = cal.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
        let vitalsPredicate = HKQuery.predicateForSamples(withStart: vitalsStart, end: endOfDay, options: [])
        
        // 4. Resting Heart Rate (capture recent sample per distinct wearable source: Apple Watch, Oura Ring, etc.)
        if let rhrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            let rhrList = await fetchRecentSamplesPerSource(for: rhrType, predicate: vitalsPredicate, unit: HKUnit.count().unitDivided(by: .minute()))
            for rhr in rhrList {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "resting_heart_rate",
                    value: rhr.value,
                    unit: "bpm",
                    startTime: rhr.timestamp,
                    endTime: rhr.timestamp,
                    sourceDevice: rhr.compoundKey,
                    externalId: rhr.uuid,
                    semantics: "spot",
                    tzOffsetMin: tzOffsetMin,
                    localDate: f.string(from: rhr.timestamp),
                    hostDeviceName: rhr.host,
                    sensorSourceName: rhr.sensor,
                    sourceDeviceKey: rhr.compoundKey,
                    sourceColor: rhr.color
                ))
            }
        }
        
        // 5. Heart Rate Variability (SDNN) (capture recent sample per distinct wearable source)
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let hrvList = await fetchRecentSamplesPerSource(for: hrvType, predicate: vitalsPredicate, unit: HKUnit.secondUnit(with: .milli))
            for hrv in hrvList {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "hrv_sdnn",
                    value: hrv.value,
                    unit: "ms",
                    startTime: hrv.timestamp,
                    endTime: hrv.timestamp,
                    sourceDevice: hrv.compoundKey,
                    externalId: hrv.uuid,
                    semantics: "spot",
                    tzOffsetMin: tzOffsetMin,
                    localDate: f.string(from: hrv.timestamp),
                    hostDeviceName: hrv.host,
                    sensorSourceName: hrv.sensor,
                    sourceDeviceKey: hrv.compoundKey,
                    sourceColor: hrv.color
                ))
            }
        }
        
        // 6. Blood Oxygen / SpO2
        if let o2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            let o2List = await fetchRecentSamplesPerSource(for: o2Type, predicate: vitalsPredicate, unit: HKUnit.percent())
            for o2 in o2List {
                let val = o2.value <= 1.0 ? (o2.value * 100.0) : o2.value
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "oxygen_saturation",
                    value: val,
                    unit: "%",
                    startTime: o2.timestamp,
                    endTime: o2.timestamp,
                    sourceDevice: o2.compoundKey,
                    externalId: o2.uuid,
                    semantics: "spot",
                    tzOffsetMin: tzOffsetMin,
                    localDate: f.string(from: o2.timestamp),
                    hostDeviceName: o2.host,
                    sensorSourceName: o2.sensor,
                    sourceDeviceKey: o2.compoundKey,
                    sourceColor: o2.color
                ))
            }
        }
        
        // 7. Respiratory Rate
        if let respType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            let respList = await fetchRecentSamplesPerSource(for: respType, predicate: vitalsPredicate, unit: HKUnit.count().unitDivided(by: .minute()))
            for resp in respList {
                records.append(HealthTelemetryRecord(
                    userId: "healthkit",
                    type: "respiratory_rate",
                    value: resp.value,
                    unit: "br/min",
                    startTime: resp.timestamp,
                    endTime: resp.timestamp,
                    sourceDevice: resp.compoundKey,
                    externalId: resp.uuid,
                    semantics: "spot",
                    tzOffsetMin: tzOffsetMin,
                    localDate: f.string(from: resp.timestamp),
                    hostDeviceName: resp.host,
                    sensorSourceName: resp.sensor,
                    sourceDeviceKey: resp.compoundKey,
                    sourceColor: resp.color
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
                    sourceDevice: weight.compoundKey,
                    externalId: weight.uuid,
                    semantics: "spot",
                    tzOffsetMin: tzOffsetMin,
                    localDate: f.string(from: weight.timestamp),
                    hostDeviceName: weight.host,
                    sensorSourceName: weight.sensor,
                    sourceDeviceKey: weight.compoundKey,
                    sourceColor: weight.color
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
                    sourceDevice: fat.compoundKey,
                    externalId: fat.uuid,
                    semantics: "spot",
                    tzOffsetMin: tzOffsetMin,
                    localDate: f.string(from: fat.timestamp),
                    hostDeviceName: fat.host,
                    sensorSourceName: fat.sensor,
                    sourceDeviceKey: fat.compoundKey,
                    sourceColor: fat.color
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
                    
                    let (host, sensor, key, color) = Self.resolveCompoundSource(device: sample.device, source: sample.sourceRevision.source)
                    let tzOffset = Calendar.current.timeZone.secondsFromGMT(for: sample.startDate) / 60
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    let durationMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    records.append(HealthTelemetryRecord(
                        id: sample.uuid.uuidString,
                        userId: "healthkit",
                        type: typeName,
                        value: durationMinutes,
                        unit: "minutes",
                        startTime: sample.startDate,
                        endTime: sample.endDate,
                        sourceDevice: key,
                        externalId: sample.uuid.uuidString,
                        semantics: "session_stage",
                        tzOffsetMin: tzOffset,
                        localDate: f.string(from: sample.startDate),
                        hostDeviceName: host,
                        sensorSourceName: sensor,
                        sourceDeviceKey: key,
                        sourceColor: color
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
                let host = Self.hostPhoneName
                let sensor = "Apple Health"
                let key = "\(host) - \(sensor)"
                let color = DeviceColorPalette.getColor(for: key)
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                
                results.enumerateStatistics(from: startOfDay, to: endOfDay) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                        let epoch = Int(stats.startDate.timeIntervalSince1970)
                        let tzOffset = Calendar.current.timeZone.secondsFromGMT(for: stats.startDate) / 60
                        hourlyRecords.append(HealthTelemetryRecord(
                            id: UUID().uuidString,
                            userId: "healthkit",
                            type: "steps",
                            value: sum,
                            unit: "count",
                            startTime: stats.startDate,
                            endTime: stats.endDate,
                            sourceDevice: key,
                            externalId: "steps_hourly_\(epoch)",
                            semantics: "interval_delta",
                            tzOffsetMin: tzOffset,
                            localDate: f.string(from: stats.startDate),
                            hostDeviceName: host,
                            sensorSourceName: sensor,
                            sourceDeviceKey: key,
                            sourceColor: color
                        ))
                    }
                }
                continuation.resume(returning: hourlyRecords)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchHourlyActiveEnergy(for date: Date) async -> [HealthTelemetryRecord] {
        guard let calType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: calType,
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
                let host = Self.hostPhoneName
                let sensor = "Apple Health"
                let key = "\(host) - \(sensor)"
                let color = DeviceColorPalette.getColor(for: key)
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                
                results.enumerateStatistics(from: startOfDay, to: endOfDay) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: .kilocalorie()), sum > 0 {
                        let epoch = Int(stats.startDate.timeIntervalSince1970)
                        let tzOffset = Calendar.current.timeZone.secondsFromGMT(for: stats.startDate) / 60
                        hourlyRecords.append(HealthTelemetryRecord(
                            id: UUID().uuidString,
                            userId: "healthkit",
                            type: "active_energy",
                            value: sum,
                            unit: "kcal",
                            startTime: stats.startDate,
                            endTime: stats.endDate,
                            sourceDevice: key,
                            externalId: "active_energy_hourly_\(epoch)",
                            semantics: "interval_delta",
                            tzOffsetMin: tzOffset,
                            localDate: f.string(from: stats.startDate),
                            hostDeviceName: host,
                            sensorSourceName: sensor,
                            sourceDeviceKey: key,
                            sourceColor: color
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
    
    private func fetchQuantitySamples(for quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit, typeName: String, limit: Int = HKObjectQueryNoLimit) async -> [HealthTelemetryRecord] {
        await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: limit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let qSamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                let records = qSamples.map { sample in
                    let (host, sensor, key, color) = Self.resolveCompoundSource(device: sample.device, source: sample.sourceRevision.source)
                    let tzOffset = Calendar.current.timeZone.secondsFromGMT(for: sample.startDate) / 60
                    return HealthTelemetryRecord(
                        id: sample.uuid.uuidString,
                        userId: "healthkit",
                        type: typeName,
                        value: sample.quantity.doubleValue(for: unit),
                        unit: unit.unitString,
                        startTime: sample.startDate,
                        endTime: sample.endDate,
                        sourceDevice: key,
                        externalId: sample.uuid.uuidString,
                        semantics: "spot",
                        tzOffsetMin: tzOffset,
                        localDate: f.string(from: sample.startDate),
                        hostDeviceName: host,
                        sensorSourceName: sensor,
                        sourceDeviceKey: key,
                        sourceColor: color
                    )
                }
                continuation.resume(returning: records)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchRecentSamplesPerSource(
        for quantityType: HKQuantityType,
        predicate: NSPredicate,
        unit: HKUnit,
        sampleLimit: Int = 50
    ) async -> [(value: Double, device: String, timestamp: Date, uuid: String, host: String, sensor: String, compoundKey: String, color: String)] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: sampleLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let qSamples = samples as? [HKQuantitySample], !qSamples.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                
                var seenDevices = Set<String>()
                var results: [(value: Double, device: String, timestamp: Date, uuid: String, host: String, sensor: String, compoundKey: String, color: String)] = []
                
                for sample in qSamples {
                    let (host, sensor, key, color) = Self.resolveCompoundSource(device: sample.device, source: sample.sourceRevision.source)
                    if DeviceSource.from(name: sensor).isVirtualEngine {
                        continue
                    }
                    if !seenDevices.contains(key) {
                        seenDevices.insert(key)
                        results.append((sample.quantity.doubleValue(for: unit), key, sample.endDate, sample.uuid.uuidString, host, sensor, key, color))
                    }
                }
                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchMostRecentSample(for quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async -> (value: Double, device: String, timestamp: Date, uuid: String, host: String, sensor: String, compoundKey: String, color: String)? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    let (host, sensor, key, color) = Self.resolveCompoundSource(device: sample.device, source: sample.sourceRevision.source)
                    continuation.resume(returning: (sample.quantity.doubleValue(for: unit), key, sample.endDate, sample.uuid.uuidString, host, sensor, key, color))
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
    
    nonisolated private static func resolveDeviceName(device: HKDevice?, source: HKSource) -> String {
        if let d = device?.name, !d.isEmpty {
            let lowerD = d.lowercased()
            if lowerD.contains("stresswatch") || lowerD.contains("stress-engine") {
                // Ignore virtual synthetic name
            } else if lowerD.contains("oura") {
                return "Oura Ring"
            } else if lowerD.contains("watch") {
                return "Apple Watch"
            } else {
                return d
            }
        }
        let src = source.name
        let lowerSrc = src.lowercased()
        if lowerSrc.contains("stresswatch") || lowerSrc.contains("stress-engine") {
            return "Daily Biometric Engine"
        } else if lowerSrc.contains("oura") {
            return "Oura Ring"
        } else if lowerSrc.contains("watch") {
            return "Apple Watch"
        } else if lowerSrc.contains("zepp") || lowerSrc.contains("amazfit") {
            return "Amazfit Balance"
        } else if !src.isEmpty {
            return src
        } else {
            return "Apple Health"
        }
    }
    
    private func downsampleHeartRateRecords(_ samples: [HealthTelemetryRecord], bucketIntervalSeconds: TimeInterval = 300) -> [HealthTelemetryRecord] {
        guard !samples.isEmpty else { return [] }
        
        var buckets: [String: (sum: Double, count: Int, timestamp: Date, device: String, host: String?, sensor: String?, key: String?, color: String?)] = [:]
        
        for sample in samples {
            guard let bpm = sample.value, bpm >= 30, bpm <= 240 else { continue }
            let epoch = sample.startTime.timeIntervalSince1970
            let bucketTime = floor(epoch / bucketIntervalSeconds) * bucketIntervalSeconds
            let device = sample.sourceDeviceKey ?? sample.sourceDevice ?? "Apple Health"
            let bucketKey = "\(Int64(bucketTime))_\(device)"
            
            if var existing = buckets[bucketKey] {
                existing.sum += bpm
                existing.count += 1
                buckets[bucketKey] = existing
            } else {
                buckets[bucketKey] = (
                    sum: bpm,
                    count: 1,
                    timestamp: Date(timeIntervalSince1970: bucketTime),
                    device: device,
                    host: sample.hostDeviceName,
                    sensor: sample.sensorSourceName,
                    key: sample.sourceDeviceKey,
                    color: sample.sourceColor
                )
            }
        }
        
        let tzOffsetMin = Calendar.current.timeZone.secondsFromGMT() / 60
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        
        return buckets.values.map { b in
            let avgBpm = (round((b.sum / Double(b.count)) * 10.0)) / 10.0
            let bucketEpoch = Int64(b.timestamp.timeIntervalSince1970)
            let finalDevice = b.key ?? b.device
            return HealthTelemetryRecord(
                id: UUID().uuidString,
                userId: "healthkit",
                type: "heart_rate",
                value: avgBpm,
                unit: "bpm",
                startTime: b.timestamp,
                endTime: b.timestamp.addingTimeInterval(bucketIntervalSeconds),
                sourceDevice: finalDevice,
                externalId: "hr_\(finalDevice)_\(bucketEpoch)",
                semantics: "interval_avg",
                tzOffsetMin: tzOffsetMin,
                localDate: f.string(from: b.timestamp),
                hostDeviceName: b.host,
                sensorSourceName: b.sensor,
                sourceDeviceKey: finalDevice,
                sourceColor: b.color
            )
        }.sorted { $0.startTime < $1.startTime }
    }
}


