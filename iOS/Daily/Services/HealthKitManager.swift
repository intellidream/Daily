import Foundation
import HealthKit
import DailyCore

/// Native iOS HealthKit provider querying on-device biometric sensors and Apple Watch data.
@MainActor
public final class HealthKitManager: ObservableObject {
    public static let shared = HealthKitManager()
    
    public let healthStore = HKHealthStore()
    @Published public private(set) var isAuthorized: Bool = false
    
    public var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    public init() {}
    
    // MARK: - Authorization
    
    public func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        
        var typesToRead = Set<HKObjectType>()
        
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
        
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            typesToRead.insert(sleepType)
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            self.isAuthorized = true
            return true
        } catch {
            print("[HealthKitManager] Auth error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Fetch Today's Activity & Sleep
    
    public func fetchMetrics(for date: Date) async -> [HealthTelemetryRecord] {
        guard isAvailable else { return [] }
        
        var records: [HealthTelemetryRecord] = []
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        // 1. Steps
        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
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
        
        // 3. Sleep Analysis Stages
        let sleepRecords = await fetchSleepStages(targetDate: date)
        records.append(contentsOf: sleepRecords)
        
        return records
    }
    
    public func fetchSleepStages(targetDate: Date) async -> [HealthTelemetryRecord] {
        guard isAvailable, let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        
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
                    
                    let durationMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    records.append(HealthTelemetryRecord(
                        id: sample.uuid.uuidString,
                        userId: "healthkit",
                        type: typeName,
                        value: durationMinutes,
                        unit: "minutes",
                        startTime: sample.startDate,
                        endTime: sample.endDate,
                        sourceDevice: "Apple Health"
                    ))
                }
                
                continuation.resume(returning: records)
            }
            
            healthStore.execute(query)
        }
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
}
