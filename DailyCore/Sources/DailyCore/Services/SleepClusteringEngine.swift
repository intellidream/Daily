import Foundation

/// Pure deterministic engine for clustering wearable sleep telemetry into nocturnal sessions and daytime naps.
public enum SleepClusteringEngine {
    
    /// Clusters raw telemetry records for a given morning wake-up day.
    ///
    /// - Parameters:
    ///   - targetDate: The morning date D on which the user wakes up.
    ///   - telemetry: All telemetry records within the window (D-1 18:00 to D 18:00).
    ///   - vitalsSummary: Optional daily vitals row for fallback when telemetry is absent.
    ///   - preferredDevice: Optional device name to filter by.
    /// - Returns: A tuple containing the primary nocturnal `SleepSession?`, all candidate sessions, and segregated daytime `[NapSession]`.
    public static func clusterSleep(
        targetDate: Date,
        telemetry: [HealthTelemetryRecord],
        vitalsSummary: [HealthMetricType: Double] = [:],
        preferredDevice: String? = nil
    ) -> (primarySession: SleepSession?, allSessions: [SleepSession], naps: [NapSession]) {
        
        let calendar = Calendar.current
        let morningStartOfDay = calendar.startOfDay(for: targetDate)
        
        // Window boundaries: D-1 18:00 to D 18:00
        guard let windowStart = calendar.date(byAdding: .hour, value: -6, to: morningStartOfDay), // 18:00 of D-1
              let windowEnd = calendar.date(byAdding: .hour, value: 18, to: morningStartOfDay)   // 18:00 of D
        else {
            return (nil, [], [])
        }
        
        var allNocturnalSessions: [SleepSession] = []
        var allNaps: [NapSession] = []
        
        // 1. Filter sleep-related telemetry strictly within the window
        let sleepTelemetry = telemetry.filter { record in
            guard record.isSleep else { return false }
            return record.startTime >= windowStart && record.startTime <= windowEnd
        }
        
        // 2. Partition by source device to prevent cross-device stage collision
        let groupedByDevice = Dictionary(grouping: sleepTelemetry) { record in
            record.sourceDevice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
        }
        
        for (device, deviceRecords) in groupedByDevice {
            // Check explicit nap records first
            let explicitNaps = deviceRecords.filter { $0.isNap }
            for nap in explicitNaps {
                let napSession = NapSession(
                    id: nap.id,
                    startTime: nap.startTime,
                    endTime: nap.effectiveEndTime,
                    durationSeconds: nap.durationSeconds,
                    sourceDevice: device
                )
                allNaps.append(napSession)
            }
            
            // Non-nap sleep records
            let nonNapRecords = deviceRecords.filter { !$0.isNap }
            let stageRecords = nonNapRecords.filter { $0.isSleepStage }
            let aggregateRecords = nonNapRecords.filter { !$0.isSleepStage }
            
            // A. If granular stage records exist for this device
            if !stageRecords.isEmpty {
                let clusteredStageSessions = clusterStageRecords(
                    stages: stageRecords,
                    targetDate: morningStartOfDay,
                    sourceDevice: device,
                    calendar: calendar
                )
                
                for session in clusteredStageSessions {
                    if session.isNap {
                        allNaps.append(NapSession(
                            id: session.id,
                            startTime: session.startTime,
                            endTime: session.endTime,
                            durationSeconds: session.durationSeconds,
                            sourceDevice: device
                        ))
                    } else {
                        allNocturnalSessions.append(session)
                    }
                }
            }
            // B. If only aggregate sleep records exist for this device (e.g. Apple Watch "sleep" without explicit stage prefixes)
            else if !aggregateRecords.isEmpty {
                let clusteredAggregates = clusterAggregateRecords(
                    records: aggregateRecords,
                    targetDate: morningStartOfDay,
                    sourceDevice: device,
                    calendar: calendar
                )
                
                for session in clusteredAggregates {
                    if session.isNap {
                        allNaps.append(NapSession(
                            id: session.id,
                            startTime: session.startTime,
                            endTime: session.endTime,
                            durationSeconds: session.durationSeconds,
                            sourceDevice: device
                        ))
                    } else {
                        allNocturnalSessions.append(session)
                    }
                }
            }
        }
        
        // 3. Fallback: If no nocturnal telemetry session was found, check daily vitals summary
        if allNocturnalSessions.isEmpty, let durationMin = vitalsSummary[.sleepDuration], durationMin > 0 {
            let totalAsleepSec = durationMin * 60.0
            let deepSec = (vitalsSummary[.sleepDeep] ?? 0) * 60.0
            let remSec = (vitalsSummary[.sleepRem] ?? 0) * 60.0
            let lightSec = (vitalsSummary[.sleepLight] ?? 0) * 60.0
            let awakeSec = (vitalsSummary[.sleepAwake] ?? 0) * 60.0
            
            // Reference wake-up time: 07:15 AM on morning of targetDate
            var wakeComponents = calendar.dateComponents([.year, .month, .day], from: morningStartOfDay)
            wakeComponents.hour = 7
            wakeComponents.minute = 15
            var wakeTime = calendar.date(from: wakeComponents) ?? morningStartOfDay.addingTimeInterval(7.25 * 3600)
            
            // If checking today and current time is earlier than 07:15, use current time
            let now = Date()
            if calendar.isDateInToday(targetDate) && now < wakeTime {
                wakeTime = now
            }
            
            let totalInBedSec = totalAsleepSec + awakeSec
            let bedtime = wakeTime.addingTimeInterval(-totalInBedSec)
            
            var summaryStages: [SleepStageRecord] = []
            var currentCursor = bedtime
            
            if awakeSec > 0 {
                let end = currentCursor.addingTimeInterval(awakeSec)
                summaryStages.append(SleepStageRecord(stageType: .awake, startTime: currentCursor, endTime: end, durationSeconds: awakeSec, sourceDevice: "Daily Vitals"))
                currentCursor = end
            }
            if deepSec > 0 {
                let end = currentCursor.addingTimeInterval(deepSec)
                summaryStages.append(SleepStageRecord(stageType: .deep, startTime: currentCursor, endTime: end, durationSeconds: deepSec, sourceDevice: "Daily Vitals"))
                currentCursor = end
            }
            if remSec > 0 {
                let end = currentCursor.addingTimeInterval(remSec)
                summaryStages.append(SleepStageRecord(stageType: .rem, startTime: currentCursor, endTime: end, durationSeconds: remSec, sourceDevice: "Daily Vitals"))
                currentCursor = end
            }
            if lightSec > 0 {
                let end = currentCursor.addingTimeInterval(lightSec)
                summaryStages.append(SleepStageRecord(stageType: .light, startTime: currentCursor, endTime: end, durationSeconds: lightSec, sourceDevice: "Daily Vitals"))
                currentCursor = end
            }
            
            let fallbackSession = SleepSession(
                startTime: bedtime,
                endTime: wakeTime,
                isNap: false,
                stages: summaryStages,
                sourceDevice: "Cloud Vitals",
                hasGranularHypnogram: false // Proportional summary only, not fake timeline
            )
            allNocturnalSessions.append(fallbackSession)
        }
        
        // 4. Also check for naps in vitalsSummary
        if let napMin = vitalsSummary[.napDuration], napMin > 0 {
            let napSec = napMin * 60.0
            var napComponents = calendar.dateComponents([.year, .month, .day], from: morningStartOfDay)
            napComponents.hour = 14
            napComponents.minute = 0
            let napStart = calendar.date(from: napComponents) ?? morningStartOfDay.addingTimeInterval(14 * 3600)
            let napEnd = napStart.addingTimeInterval(napSec)
            allNaps.append(NapSession(
                startTime: napStart,
                endTime: napEnd,
                durationSeconds: napSec,
                sourceDevice: "Cloud Vitals"
            ))
        }
        
        // 5. Select Primary Nocturnal Session
        // Filter by preferred device if requested and available
        let eligibleSessions: [SleepSession]
        if let pref = preferredDevice, !pref.isEmpty {
            let filtered = allNocturnalSessions.filter { $0.sourceDevice.localizedCaseInsensitiveContains(pref) }
            eligibleSessions = filtered.isEmpty ? allNocturnalSessions : filtered
        } else {
            eligibleSessions = allNocturnalSessions
        }
        
        // Prioritize:
        // 1. Granular hypnogram sessions over summary sessions
        // 2. Highest asleep duration
        let primary = eligibleSessions
            .sorted { (a, b) -> Bool in
                if a.hasGranularHypnogram != b.hasGranularHypnogram {
                    return a.hasGranularHypnogram && !b.hasGranularHypnogram
                }
                return a.asleepSeconds > b.asleepSeconds
            }
            .first
        
        return (primary, allNocturnalSessions, allNaps)
    }
    
    // MARK: - Granular Stage Clustering
    
    private static func clusterStageRecords(
        stages: [HealthTelemetryRecord],
        targetDate: Date,
        sourceDevice: String,
        calendar: Calendar
    ) -> [SleepSession] {
        let sorted = stages.sorted { $0.startTime < $1.startTime }
        guard let first = sorted.first else { return [] }
        
        var sessions: [SleepSession] = []
        var currentCluster: [HealthTelemetryRecord] = [first]
        
        for i in 1..<sorted.count {
            let prev = currentCluster.last!
            let curr = sorted[i]
            
            let gapMinutes = curr.startTime.timeIntervalSince(prev.effectiveEndTime) / 60.0
            
            // Allow up to 45 minutes between micro-stages before splitting into separate session
            if gapMinutes < 45 {
                currentCluster.append(curr)
            } else {
                if let s = buildSessionFromCluster(currentCluster, targetDate: targetDate, sourceDevice: sourceDevice, calendar: calendar) {
                    sessions.append(s)
                }
                currentCluster = [curr]
            }
        }
        
        if let s = buildSessionFromCluster(currentCluster, targetDate: targetDate, sourceDevice: sourceDevice, calendar: calendar) {
            sessions.append(s)
        }
        
        return sessions
    }
    
    private static func buildSessionFromCluster(
        _ cluster: [HealthTelemetryRecord],
        targetDate: Date,
        sourceDevice: String,
        calendar: Calendar
    ) -> SleepSession? {
        guard let start = cluster.map(\.startTime).min(),
              let end = cluster.map(\.effectiveEndTime).max()
        else { return nil }
        
        let totalDuration = max(0, end.timeIntervalSince(start))
        guard totalDuration >= 600 else { return nil } // Ignore < 10 mins noise
        
        let stageRecords = cluster.map { record in
            SleepStageRecord(
                id: record.id,
                stageType: record.sleepStageType,
                startTime: record.startTime,
                endTime: record.effectiveEndTime,
                durationSeconds: record.durationSeconds,
                sourceDevice: sourceDevice
            )
        }
        
        // Daytime Nap Heuristic:
        // Duration < 3.5 hours AND starts during daytime (>= 09:00) AND ends <= 20:30 on day D
        let startHour = calendar.component(.hour, from: start)
        let endHour = calendar.component(.hour, from: end)
        let isSameDay = calendar.isDate(start, inSameDayAs: targetDate)
        let isNap = (totalDuration < 3.5 * 3600) && isSameDay && (startHour >= 9 && endHour <= 20)
        
        return SleepSession(
            startTime: start,
            endTime: end,
            isNap: isNap,
            stages: stageRecords,
            sourceDevice: sourceDevice,
            hasGranularHypnogram: true
        )
    }
    
    // MARK: - Aggregate Record Clustering
    
    private static func clusterAggregateRecords(
        records: [HealthTelemetryRecord],
        targetDate: Date,
        sourceDevice: String,
        calendar: Calendar
    ) -> [SleepSession] {
        let sorted = records.sorted { $0.startTime < $1.startTime }
        guard let first = sorted.first else { return [] }
        
        var sessions: [SleepSession] = []
        var currentCluster: [HealthTelemetryRecord] = [first]
        
        for i in 1..<sorted.count {
            let prev = currentCluster.last!
            let curr = sorted[i]
            
            let gapMinutes = curr.startTime.timeIntervalSince(prev.effectiveEndTime) / 60.0
            if gapMinutes < 45 {
                currentCluster.append(curr)
            } else {
                if let s = buildAggregateSession(currentCluster, targetDate: targetDate, sourceDevice: sourceDevice, calendar: calendar) {
                    sessions.append(s)
                }
                currentCluster = [curr]
            }
        }
        
        if let s = buildAggregateSession(currentCluster, targetDate: targetDate, sourceDevice: sourceDevice, calendar: calendar) {
            sessions.append(s)
        }
        
        return sessions
    }
    
    private static func buildAggregateSession(
        _ cluster: [HealthTelemetryRecord],
        targetDate: Date,
        sourceDevice: String,
        calendar: Calendar
    ) -> SleepSession? {
        guard let start = cluster.map(\.startTime).min(),
              let end = cluster.map(\.effectiveEndTime).max()
        else { return nil }
        
        let totalDuration = max(0, end.timeIntervalSince(start))
        guard totalDuration >= 600 else { return nil }
        
        let startHour = calendar.component(.hour, from: start)
        let endHour = calendar.component(.hour, from: end)
        let isSameDay = calendar.isDate(start, inSameDayAs: targetDate)
        let isNap = (totalDuration < 3.5 * 3600) && isSameDay && (startHour >= 9 && endHour <= 20)
        
        return SleepSession(
            startTime: start,
            endTime: end,
            isNap: isNap,
            stages: [],
            sourceDevice: sourceDevice,
            hasGranularHypnogram: false
        )
    }
}
