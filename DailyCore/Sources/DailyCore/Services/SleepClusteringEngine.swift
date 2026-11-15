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
            // Check explicit nap records first - must be genuine daytime naps on targetDate
            let explicitNaps = deviceRecords.filter { record in
                guard record.isNap else { return false }
                let startHour = calendar.component(.hour, from: record.startTime)
                let endHour = calendar.component(.hour, from: record.effectiveEndTime)
                let isSameDay = calendar.isDate(record.startTime, inSameDayAs: targetDate)
                return isSameDay && (startHour >= 9 && endHour <= 21) && record.durationSeconds < 3.5 * 3600
            }
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
        // 2. Dedicated sleep tracking device priority (Oura > Apple Watch > Amazfit > etc.)
        // 3. Highest asleep duration
        let primary = eligibleSessions
            .sorted { (a, b) -> Bool in
                if a.hasGranularHypnogram != b.hasGranularHypnogram {
                    return a.hasGranularHypnogram && !b.hasGranularHypnogram
                }
                let rankA = deviceSleepPriorityRank(a.sourceDevice)
                let rankB = deviceSleepPriorityRank(b.sourceDevice)
                if rankA != rankB {
                    return rankA > rankB
                }
                return a.asleepSeconds > b.asleepSeconds
            }
            .first
        
        // 6. Deduplicate and merge duplicate or overlapping nap sessions
        let sortedNaps = allNaps.sorted { $0.startTime < $1.startTime }
        var uniqueNaps: [NapSession] = []
        for nap in sortedNaps {
            if let last = uniqueNaps.last {
                let overlapStart = max(last.startTime, nap.startTime)
                let overlapEnd = min(last.endTime, nap.endTime)
                let overlapSec = max(0, overlapEnd.timeIntervalSince(overlapStart))
                let minDur = min(last.durationSeconds, nap.durationSeconds)
                let isSameDevice = (last.sourceDevice == nap.sourceDevice)
                let isNearDuplicate = abs(last.startTime.timeIntervalSince(nap.startTime)) < 15 * 60 &&
                                      abs(last.endTime.timeIntervalSince(nap.endTime)) < 15 * 60
                
                // If near-exact duplicate or overlapping by more than 40%
                if isNearDuplicate || (isSameDevice && (overlapSec > 0.4 * minDur || overlapSec > 600)) {
                    let mergedStart = min(last.startTime, nap.startTime)
                    let mergedEnd = max(last.endTime, nap.endTime)
                    let mergedDuration = max(last.durationSeconds, nap.durationSeconds, mergedEnd.timeIntervalSince(mergedStart))
                    uniqueNaps[uniqueNaps.count - 1] = NapSession(
                        id: last.id,
                        startTime: mergedStart,
                        endTime: mergedEnd,
                        durationSeconds: mergedDuration,
                        sourceDevice: last.sourceDevice
                    )
                    continue
                }
            }
            uniqueNaps.append(nap)
        }
        
        return (primary, allNocturnalSessions, uniqueNaps)
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
        
        let stageRecords = normalizeAndDeduplicateStages(cluster, sourceDevice: sourceDevice)
        guard !stageRecords.isEmpty else { return nil }
        
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
    
    // MARK: - Dedicated Tracker Priority Ranking
    
    /// Priority ranking for selecting the primary nocturnal sleep session among multiple wearables.
    /// Dedicated sleep trackers (Oura Ring) have highest clinical accuracy, followed by Apple Watch and Amazfit.
    private static func deviceSleepPriorityRank(_ deviceName: String) -> Int {
        let lower = deviceName.lowercased()
        if lower.contains("oura") { return 100 }
        if lower.contains("watch") || lower.contains("apple") { return 80 }
        if lower.contains("amazfit") || lower.contains("zepp") || lower.contains("balance") { return 70 }
        if lower.contains("oneplus") || lower.contains("wearos") { return 60 }
        if lower.contains("huawei") || lower.contains("harmony") { return 50 }
        if lower.contains("healthkit") || lower.contains("health") { return 40 }
        return 10
    }
    
    // MARK: - Stage Interval Clipping & De-duplication
    
    /// Normalizes and clips stage records within a cluster to prevent overlapping time spans.
    /// Guarantees that the sum of stage durations can mathematically never exceed the session's wall-clock duration.
    private static func stageSpecificity(_ type: SleepStageType) -> Int {
        switch type {
        case .deep, .rem, .awake: return 2
        case .light: return 1
        case .unknown: return 0
        }
    }

    /// Resolves overlapping multi-pass HealthKit/Health Connect stage samples using painter's algorithm:
    /// older samples paint first and newer (`createdAt`) samples split/overwrite overlapping intervals,
    /// then drops sub-10s boundary artifacts and coalesces adjacent identical stages.
    private static func normalizeAndDeduplicateStages(
        _ rawRecords: [HealthTelemetryRecord],
        sourceDevice: String
    ) -> [SleepStageRecord] {
        // Ascending paint order (lowest precedence first -> highest precedence paints last):
        // 1. Oldest createdAt first (nil treated as distantPast so stamped writes override unstamped ones)
        // 2. Coarser stage specificity first when createdAt ties (deep/rem/awake beat coarse light/unknown)
        // 3. Later startTime first on full ties so earlier startTime retains precedence (legacy tie-break)
        let paintOrder = rawRecords
            .filter { $0.effectiveEndTime > $0.startTime }
            .sorted { a, b in
                let ca = a.createdAt ?? .distantPast
                let cb = b.createdAt ?? .distantPast
                if ca != cb { return ca < cb }
                let sa = stageSpecificity(a.sleepStageType)
                let sb = stageSpecificity(b.sleepStageType)
                if sa != sb { return sa < sb }
                if a.startTime != b.startTime { return a.startTime > b.startTime }
                return a.effectiveEndTime < b.effectiveEndTime
            }

        struct PaintedSegment {
            let id: String
            let stageType: SleepStageType
            var start: Date
            var end: Date
        }

        var timeline: [PaintedSegment] = []

        for record in paintOrder {
            let newStart = record.startTime
            let newEnd = record.effectiveEndTime
            let newType = record.sleepStageType

            var nextTimeline: [PaintedSegment] = []
            nextTimeline.reserveCapacity(timeline.count + 2)
            var inserted = false

            for seg in timeline {
                if seg.end <= newStart {
                    nextTimeline.append(seg)
                } else if seg.start >= newEnd {
                    if !inserted {
                        nextTimeline.append(PaintedSegment(id: record.id, stageType: newType, start: newStart, end: newEnd))
                        inserted = true
                    }
                    nextTimeline.append(seg)
                } else {
                    if seg.start < newStart {
                        nextTimeline.append(PaintedSegment(id: "\(seg.id)#L", stageType: seg.stageType, start: seg.start, end: newStart))
                    }
                    if !inserted {
                        nextTimeline.append(PaintedSegment(id: record.id, stageType: newType, start: newStart, end: newEnd))
                        inserted = true
                    }
                    if seg.end > newEnd {
                        nextTimeline.append(PaintedSegment(id: "\(seg.id)#R", stageType: seg.stageType, start: newEnd, end: seg.end))
                    }
                }
            }

            if !inserted {
                nextTimeline.append(PaintedSegment(id: record.id, stageType: newType, start: newStart, end: newEnd))
            }
            timeline = nextTimeline
        }

        // Filter out sub-10s slivers caused by boundary misalignment, then coalesce adjacent identical stages
        var coalesced: [PaintedSegment] = []
        for seg in timeline {
            let dur = seg.end.timeIntervalSince(seg.start)
            guard dur >= 10 else { continue }
            if var prev = coalesced.last,
               prev.stageType == seg.stageType,
               seg.start.timeIntervalSince(prev.end) <= 1.0 {
                prev.end = max(prev.end, seg.end)
                coalesced[coalesced.count - 1] = prev
            } else {
                coalesced.append(seg)
            }
        }

        return coalesced.map { seg in
            SleepStageRecord(
                id: seg.id,
                stageType: seg.stageType,
                startTime: seg.start,
                endTime: seg.end,
                durationSeconds: max(0, seg.end.timeIntervalSince(seg.start)),
                sourceDevice: sourceDevice
            )
        }
    }
}
