import Foundation
import HealthKit
import Supabase
import os.log

struct TelemetryPayload: Codable {
    let user_id: String
    let type: String
    let value: Double
    let unit: String
    let start_time: String
    let end_time: String
    let source_device: String
}

class HealthTelemetryManager {
    static let shared = HealthTelemetryManager()
    private let healthStore = HKHealthStore()
    
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
    
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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
    
    // Called by background tasks and on app activation
    func syncTelemetry(isDeepSync: Bool = false) async {
        os_log("Starting HealthTelemetryManager sync (isDeepSync: %d)...", type: .info, isDeepSync)
        guard let pClient = WatchSessionManager.shared.supabaseClient,
              let userId = WatchSessionManager.shared.currentUserId else {
            os_log("Supabase client or user not available. Skipping telemetry sync.", type: .error)
            return
        }
        
        var allPayloads: [TelemetryPayload] = []
        var pendingAnchors: [String: HKQueryAnchor] = [:]
        
        // --- TIER 1: Real-time active vitals ---
        
        // Heart Rate
        let (hrSamples, hrAnchor) = await fetchQuantitySamplesWithAnchor(typeIdentifier: .heartRate)
        if let anchor = hrAnchor { pendingAnchors[HKQuantityTypeIdentifier.heartRate.rawValue] = anchor }
        for sample in hrSamples {
            let val = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            allPayloads.append(createPayload(userId: userId, type: "heart_rate", value: val, unit: "bpm", sample: sample))
        }
        
        // Steps
        let (stepSamples, stepAnchor) = await fetchQuantitySamplesWithAnchor(typeIdentifier: .stepCount)
        if let anchor = stepAnchor { pendingAnchors[HKQuantityTypeIdentifier.stepCount.rawValue] = anchor }
        for sample in stepSamples {
            let val = sample.quantity.doubleValue(for: HKUnit.count())
            allPayloads.append(createPayload(userId: userId, type: "steps", value: val, unit: "count", sample: sample))
        }
        
        // Active Energy
        let (energySamples, energyAnchor) = await fetchQuantitySamplesWithAnchor(typeIdentifier: .activeEnergyBurned)
        if let anchor = energyAnchor { pendingAnchors[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] = anchor }
        for sample in energySamples {
            let val = sample.quantity.doubleValue(for: HKUnit.kilocalorie())
            allPayloads.append(createPayload(userId: userId, type: "active_energy", value: val, unit: "kcal", sample: sample))
        }
        
        // --- TIER 2: Deep Analytics (Sleep, HRV, Resting HR, SpO2) ---
        if isDeepSync {
            // Sleep
            let (sleepSamples, sleepAnchor) = await fetchCategorySamplesWithAnchor(typeIdentifier: .sleepAnalysis)
            if let anchor = sleepAnchor { pendingAnchors[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = anchor }
            for sample in sleepSamples {
                if sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                   sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                   sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                   sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                    
                    let durationHours = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                    allPayloads.append(createPayload(userId: userId, type: "sleep", value: durationHours, unit: "hours", sample: sample))
                }
            }
            
            // HRV (Heart Rate Variability SDNN in milliseconds)
            let (hrvSamples, hrvAnchor) = await fetchQuantitySamplesWithAnchor(typeIdentifier: .heartRateVariabilitySDNN)
            if let anchor = hrvAnchor { pendingAnchors[HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue] = anchor }
            for sample in hrvSamples {
                let val = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                allPayloads.append(createPayload(userId: userId, type: "hrv", value: val, unit: "ms", sample: sample))
            }
            
            // Resting Heart Rate (bpm)
            let (restingSamples, restingAnchor) = await fetchQuantitySamplesWithAnchor(typeIdentifier: .restingHeartRate)
            if let anchor = restingAnchor { pendingAnchors[HKQuantityTypeIdentifier.restingHeartRate.rawValue] = anchor }
            for sample in restingSamples {
                let val = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                allPayloads.append(createPayload(userId: userId, type: "resting_heart_rate", value: val, unit: "bpm", sample: sample))
            }
            
            // Blood Oxygen / SpO2 (%)
            let (spo2Samples, spo2Anchor) = await fetchQuantitySamplesWithAnchor(typeIdentifier: .oxygenSaturation)
            if let anchor = spo2Anchor { pendingAnchors[HKQuantityTypeIdentifier.oxygenSaturation.rawValue] = anchor }
            for sample in spo2Samples {
                let rawFraction = sample.quantity.doubleValue(for: HKUnit.percent())
                let percentage = rawFraction <= 1.0 ? (rawFraction * 100.0) : rawFraction
                allPayloads.append(createPayload(userId: userId, type: "spo2", value: percentage, unit: "%", sample: sample))
            }
        }
        
        guard !allPayloads.isEmpty else {
            os_log("No new telemetry data to sync.", type: .info)
            return
        }
        
        os_log("Pushing %d telemetry payloads to Supabase...", type: .info, allPayloads.count)
        
        do {
            try await pClient.from("health_telemetry").insert(allPayloads).execute()
            os_log("Successfully pushed telemetry data. Committing delta anchors.", type: .info)
            
            // Only advance anchors AFTER successful upload to ensure zero data loss
            for (key, anchor) in pendingAnchors {
                self.saveAnchor(anchor, for: key)
            }
        } catch {
            os_log("Failed to push telemetry data: %@. Retaining previous anchors for retry.", type: .error, error.localizedDescription)
        }
    }
    
    private func createPayload(userId: UUID, type: String, value: Double, unit: String, sample: HKSample) -> TelemetryPayload {
        let deviceName = sample.device?.name ?? "Apple Watch"
        let model = sample.device?.model ?? "watchOS"
        
        return TelemetryPayload(
            user_id: userId.uuidString,
            type: type,
            value: value,
            unit: unit,
            start_time: dateFormatter.string(from: sample.startDate),
            end_time: dateFormatter.string(from: sample.endDate),
            source_device: "\(deviceName) (\(model))"
        )
    }
    
    // MARK: - Anchored Queries (Zero-Loss Delta Sync)
    
    private func getAnchor(for key: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: "anchor_\(key)") else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
    
    private func saveAnchor(_ anchor: HKQueryAnchor, for key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: "anchor_\(key)")
        }
    }
    
    private func fetchQuantitySamplesWithAnchor(typeIdentifier: HKQuantityTypeIdentifier) async -> ([HKQuantitySample], HKQueryAnchor?) {
        guard let type = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else { return ([], nil) }
        let anchor = getAnchor(for: typeIdentifier.rawValue)
        
        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { _, samples, _, newAnchor, _ in
                continuation.resume(returning: ((samples as? [HKQuantitySample]) ?? [], newAnchor))
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchCategorySamplesWithAnchor(typeIdentifier: HKCategoryTypeIdentifier) async -> ([HKCategorySample], HKQueryAnchor?) {
        guard let type = HKCategoryType.categoryType(forIdentifier: typeIdentifier) else { return ([], nil) }
        let anchor = getAnchor(for: typeIdentifier.rawValue)
        
        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { _, samples, _, newAnchor, _ in
                continuation.resume(returning: ((samples as? [HKCategorySample]) ?? [], newAnchor))
            }
            healthStore.execute(query)
        }
    }
}
