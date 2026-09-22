package com.intellidream.daily.health

import com.intellidream.daily.model.HealthMetricType
import com.intellidream.daily.model.HealthTelemetryRecord
import com.intellidream.daily.model.NapSession
import com.intellidream.daily.model.SleepSession
import com.intellidream.daily.model.SleepStageRecord
import com.intellidream.daily.model.SleepStageType
import java.util.Calendar
import java.util.Date
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Result data class for sleep clustering operations.
 */
data class SleepClusteringResult(
    val primarySession: SleepSession?,
    val allSessions: List<SleepSession>,
    val naps: List<NapSession>
)

/**
 * Pure deterministic engine for clustering wearable sleep telemetry into nocturnal sessions and daytime naps.
 * 1:1 Kotlin port of iOS DailyCore's SleepClusteringEngine.
 */
object SleepClusteringEngine {

    /**
     * Clusters raw telemetry records for a given morning wake-up day.
     *
     * @param targetDate The morning date D on which the user wakes up.
     * @param telemetry All telemetry records within the window (D-1 18:00 to D 18:00).
     * @param vitalsSummary Optional daily vitals map for fallback when telemetry is absent.
     * @param preferredDevice Optional device name to filter by.
     */
    fun clusterSleep(
        targetDate: Date,
        telemetry: List<HealthTelemetryRecord>,
        vitalsSummary: Map<HealthMetricType, Double> = emptyMap(),
        preferredDevice: String? = null
    ): SleepClusteringResult {
        val calendar = Calendar.getInstance()
        calendar.time = targetDate
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val morningStartOfDay = calendar.time

        // Window boundaries: D-1 18:00 to D 18:00
        val windowStartCal = Calendar.getInstance().apply {
            time = morningStartOfDay
            add(Calendar.HOUR_OF_DAY, -6) // 18:00 of D-1
        }
        val windowEndCal = Calendar.getInstance().apply {
            time = morningStartOfDay
            add(Calendar.HOUR_OF_DAY, 18) // 18:00 of D
        }
        val windowStart = windowStartCal.timeInMillis
        val windowEnd = windowEndCal.timeInMillis

        val allNocturnalSessions = mutableListOf<SleepSession>()
        val allNaps = mutableListOf<NapSession>()

        // 1. Filter sleep-related telemetry strictly within the window
        val sleepTelemetry = telemetry.filter { record ->
            record.isSleep && record.startTime in windowStart..windowEnd
        }

        // 2. Partition by source device to prevent cross-device stage collision
        val groupedByDevice = sleepTelemetry.groupBy { record ->
            record.sourceDevice?.trim() ?: "Unknown"
        }

        for ((device, deviceRecords) in groupedByDevice) {
            // Check explicit nap records first - must be genuine daytime naps on targetDate
            val explicitNaps = deviceRecords.filter { record ->
                if (!record.isNap) return@filter false
                val cal = Calendar.getInstance().apply { timeInMillis = record.startTime }
                val startHour = cal.get(Calendar.HOUR_OF_DAY)
                val calEnd = Calendar.getInstance().apply { timeInMillis = record.effectiveEndTime }
                val endHour = calEnd.get(Calendar.HOUR_OF_DAY)
                val isSameDay = isSameDay(record.startTime, targetDate.time)
                isSameDay && (startHour >= 9 && endHour <= 21) && record.durationSeconds < 3.5 * 3600
            }

            for (nap in explicitNaps) {
                allNaps.add(
                    NapSession(
                        id = nap.id,
                        startTime = nap.startTime,
                        endTime = nap.effectiveEndTime,
                        durationSeconds = nap.durationSeconds,
                        sourceDevice = device
                    )
                )
            }

            // Non-nap sleep records
            val nonNapRecords = deviceRecords.filter { !it.isNap }
            val stageRecords = nonNapRecords.filter { it.isSleepStage }
            val aggregateRecords = nonNapRecords.filter { !it.isSleepStage }

            // A. If granular stage records exist for this device
            if (stageRecords.isNotEmpty()) {
                val clusteredStageSessions = clusterStageRecords(
                    stages = stageRecords,
                    targetDate = morningStartOfDay,
                    sourceDevice = device
                )

                for (session in clusteredStageSessions) {
                    if (session.isNap) {
                        allNaps.add(
                            NapSession(
                                id = session.id,
                                startTime = session.startTime,
                                endTime = session.endTime,
                                durationSeconds = session.durationSeconds,
                                sourceDevice = device
                            )
                        )
                    } else {
                        allNocturnalSessions.add(session)
                    }
                }
            }
            // B. If only aggregate sleep records exist for this device
            else if (aggregateRecords.isNotEmpty()) {
                val clusteredAggregates = clusterAggregateRecords(
                    records = aggregateRecords,
                    targetDate = morningStartOfDay,
                    sourceDevice = device
                )

                for (session in clusteredAggregates) {
                    if (session.isNap) {
                        allNaps.add(
                            NapSession(
                                id = session.id,
                                startTime = session.startTime,
                                endTime = session.endTime,
                                durationSeconds = session.durationSeconds,
                                sourceDevice = device
                            )
                        )
                    } else {
                        allNocturnalSessions.add(session)
                    }
                }
            }
        }

        // 3. Fallback: If no nocturnal telemetry session was found, check daily vitals summary
        val durationMin = vitalsSummary[HealthMetricType.SLEEP_DURATION]
        if (allNocturnalSessions.isEmpty() && durationMin != null && durationMin > 0) {
            val totalAsleepSec = durationMin * 60.0
            val deepSec = (vitalsSummary[HealthMetricType.SLEEP_DEEP] ?: 0.0) * 60.0
            val remSec = (vitalsSummary[HealthMetricType.SLEEP_REM] ?: 0.0) * 60.0
            val lightSec = (vitalsSummary[HealthMetricType.SLEEP_LIGHT] ?: 0.0) * 60.0
            val awakeSec = (vitalsSummary[HealthMetricType.SLEEP_AWAKE] ?: 0.0) * 60.0

            // Reference wake-up time: 07:15 AM on morning of targetDate
            val wakeCal = Calendar.getInstance().apply {
                time = morningStartOfDay
                set(Calendar.HOUR_OF_DAY, 7)
                set(Calendar.MINUTE, 15)
            }
            var wakeTime = wakeCal.timeInMillis

            // If checking today and current time is earlier than 07:15, use current time
            val now = System.currentTimeMillis()
            if (isSameDay(targetDate.time, now) && now < wakeTime) {
                wakeTime = now
            }

            val totalInBedSec = totalAsleepSec + awakeSec
            val bedtime = wakeTime - (totalInBedSec * 1000).toLong()

            val summaryStages = mutableListOf<SleepStageRecord>()
            var currentCursor = bedtime

            if (awakeSec > 0) {
                val end = currentCursor + (awakeSec * 1000).toLong()
                summaryStages.add(
                    SleepStageRecord(
                        stageType = SleepStageType.AWAKE,
                        startTime = currentCursor,
                        endTime = end,
                        durationSeconds = awakeSec,
                        sourceDevice = "Daily Vitals"
                    )
                )
                currentCursor = end
            }
            if (deepSec > 0) {
                val end = currentCursor + (deepSec * 1000).toLong()
                summaryStages.add(
                    SleepStageRecord(
                        stageType = SleepStageType.DEEP,
                        startTime = currentCursor,
                        endTime = end,
                        durationSeconds = deepSec,
                        sourceDevice = "Daily Vitals"
                    )
                )
                currentCursor = end
            }
            if (remSec > 0) {
                val end = currentCursor + (remSec * 1000).toLong()
                summaryStages.add(
                    SleepStageRecord(
                        stageType = SleepStageType.REM,
                        startTime = currentCursor,
                        endTime = end,
                        durationSeconds = remSec,
                        sourceDevice = "Daily Vitals"
                    )
                )
                currentCursor = end
            }
            if (lightSec > 0) {
                val end = currentCursor + (lightSec * 1000).toLong()
                summaryStages.add(
                    SleepStageRecord(
                        stageType = SleepStageType.LIGHT,
                        startTime = currentCursor,
                        endTime = end,
                        durationSeconds = lightSec,
                        sourceDevice = "Daily Vitals"
                    )
                )
            }

            val fallbackSession = SleepSession(
                startTime = bedtime,
                endTime = wakeTime,
                isNap = false,
                stages = summaryStages,
                sourceDevice = "Cloud Vitals",
                hasGranularHypnogram = false
            )
            allNocturnalSessions.add(fallbackSession)
        }

        // 4. Also check for naps in vitalsSummary
        val napMin = vitalsSummary[HealthMetricType.NAP_DURATION]
        if (napMin != null && napMin > 0) {
            val napSec = napMin * 60.0
            val napStartCal = Calendar.getInstance().apply {
                time = morningStartOfDay
                set(Calendar.HOUR_OF_DAY, 14)
                set(Calendar.MINUTE, 0)
            }
            val napStart = napStartCal.timeInMillis
            val napEnd = napStart + (napSec * 1000).toLong()
            allNaps.add(
                NapSession(
                    startTime = napStart,
                    endTime = napEnd,
                    durationSeconds = napSec,
                    sourceDevice = "Cloud Vitals"
                )
            )
        }

        // 5. Select Primary Nocturnal Session
        val eligibleSessions = if (!preferredDevice.isNullOrEmpty()) {
            val filtered = allNocturnalSessions.filter { it.sourceDevice.contains(preferredDevice, ignoreCase = true) }
            if (filtered.isEmpty()) allNocturnalSessions else filtered
        } else {
            allNocturnalSessions
        }

        // Prioritize:
        // 1. Granular hypnogram sessions over summary sessions
        // 2. Dedicated sleep tracking device priority (Oura > Watch > Amazfit > etc.)
        // 3. Highest asleep duration
        val primary = eligibleSessions.sortedWith { a, b ->
            if (a.hasGranularHypnogram != b.hasGranularHypnogram) {
                return@sortedWith if (a.hasGranularHypnogram) -1 else 1
            }
            val rankA = deviceSleepPriorityRank(a.sourceDevice)
            val rankB = deviceSleepPriorityRank(b.sourceDevice)
            if (rankA != rankB) {
                return@sortedWith rankB.compareTo(rankA)
            }
            b.asleepSeconds.compareTo(a.asleepSeconds)
        }.firstOrNull()

        // 6. Deduplicate and merge duplicate or overlapping nap sessions
        val sortedNaps = allNaps.sortedBy { it.startTime }
        val uniqueNaps = mutableListOf<NapSession>()
        for (nap in sortedNaps) {
            if (uniqueNaps.isNotEmpty()) {
                val last = uniqueNaps.last()
                val overlapStart = max(last.startTime, nap.startTime)
                val overlapEnd = min(last.endTime, nap.endTime)
                val overlapSec = max(0.0, (overlapEnd - overlapStart) / 1000.0)
                val minDur = min(last.durationSeconds, nap.durationSeconds)
                val isSameDevice = (last.sourceDevice == nap.sourceDevice)
                val isNearDuplicate = abs(last.startTime - nap.startTime) < 15 * 60 * 1000 &&
                        abs(last.endTime - nap.endTime) < 15 * 60 * 1000

                // If near-exact duplicate or overlapping by more than 40%
                if (isNearDuplicate || (isSameDevice && (overlapSec > 0.4 * minDur || overlapSec > 600))) {
                    val mergedStart = min(last.startTime, nap.startTime)
                    val mergedEnd = max(last.endTime, nap.endTime)
                    val mergedDuration = maxOf(last.durationSeconds, nap.durationSeconds, (mergedEnd - mergedStart) / 1000.0)
                    uniqueNaps[uniqueNaps.size - 1] = NapSession(
                        id = last.id,
                        startTime = mergedStart,
                        endTime = mergedEnd,
                        durationSeconds = mergedDuration,
                        sourceDevice = last.sourceDevice
                    )
                    continue
                }
            }
            uniqueNaps.add(nap)
        }

        return SleepClusteringResult(primary, allNocturnalSessions, uniqueNaps)
    }

    // MARK: - Granular Stage Clustering

    private fun clusterStageRecords(
        stages: List<HealthTelemetryRecord>,
        targetDate: Date,
        sourceDevice: String
    ): List<SleepSession> {
        val sorted = stages.sortedBy { it.startTime }
        if (sorted.isEmpty()) return emptyList()

        val sessions = mutableListOf<SleepSession>()
        var currentCluster = mutableListOf<HealthTelemetryRecord>()
        currentCluster.add(sorted.first())

        for (i in 1 until sorted.size) {
            val prev = currentCluster.last()
            val curr = sorted[i]

            val gapMinutes = (curr.startTime - prev.effectiveEndTime) / (60.0 * 1000.0)

            // Allow up to 45 minutes between micro-stages before splitting into separate session
            if (gapMinutes < 45) {
                currentCluster.add(curr)
            } else {
                buildSessionFromCluster(currentCluster, targetDate, sourceDevice)?.let {
                    sessions.add(it)
                }
                currentCluster = mutableListOf(curr)
            }
        }

        buildSessionFromCluster(currentCluster, targetDate, sourceDevice)?.let {
            sessions.add(it)
        }

        return sessions
    }

    private fun buildSessionFromCluster(
        cluster: List<HealthTelemetryRecord>,
        targetDate: Date,
        sourceDevice: String
    ): SleepSession? {
        val start = cluster.minOfOrNull { it.startTime } ?: return null
        val end = cluster.maxOfOrNull { it.effectiveEndTime } ?: return null

        val totalDuration = max(0.0, (end - start) / 1000.0)
        if (totalDuration < 600.0) return null // Ignore < 10 mins noise

        val stageRecords = normalizeAndDeduplicateStages(cluster, sourceDevice)

        // Daytime Nap Heuristic:
        // Duration < 3.5 hours AND starts during daytime (>= 09:00) AND ends <= 20:30 on day D
        val calStart = Calendar.getInstance().apply { timeInMillis = start }
        val calEnd = Calendar.getInstance().apply { timeInMillis = end }
        val startHour = calStart.get(Calendar.HOUR_OF_DAY)
        val endHour = calEnd.get(Calendar.HOUR_OF_DAY)
        val isSameDay = isSameDay(start, targetDate.time)
        val isNap = (totalDuration < 3.5 * 3600) && isSameDay && (startHour >= 9 && endHour <= 20)

        return SleepSession(
            startTime = start,
            endTime = end,
            isNap = isNap,
            stages = stageRecords,
            sourceDevice = sourceDevice,
            hasGranularHypnogram = true
        )
    }

    // MARK: - Aggregate Record Clustering

    private fun clusterAggregateRecords(
        records: List<HealthTelemetryRecord>,
        targetDate: Date,
        sourceDevice: String
    ): List<SleepSession> {
        val sorted = records.sortedBy { it.startTime }
        if (sorted.isEmpty()) return emptyList()

        val sessions = mutableListOf<SleepSession>()
        var currentCluster = mutableListOf<HealthTelemetryRecord>()
        currentCluster.add(sorted.first())

        for (i in 1 until sorted.size) {
            val prev = currentCluster.last()
            val curr = sorted[i]

            val gapMinutes = (curr.startTime - prev.effectiveEndTime) / (60.0 * 1000.0)
            if (gapMinutes < 45) {
                currentCluster.add(curr)
            } else {
                buildAggregateSession(currentCluster, targetDate, sourceDevice)?.let {
                    sessions.add(it)
                }
                currentCluster = mutableListOf(curr)
            }
        }

        buildAggregateSession(currentCluster, targetDate, sourceDevice)?.let {
            sessions.add(it)
        }

        return sessions
    }

    private fun buildAggregateSession(
        cluster: List<HealthTelemetryRecord>,
        targetDate: Date,
        sourceDevice: String
    ): SleepSession? {
        val start = cluster.minOfOrNull { it.startTime } ?: return null
        val end = cluster.maxOfOrNull { it.effectiveEndTime } ?: return null

        val totalDuration = max(0.0, (end - start) / 1000.0)
        if (totalDuration < 600.0) return null

        val calStart = Calendar.getInstance().apply { timeInMillis = start }
        val calEnd = Calendar.getInstance().apply { timeInMillis = end }
        val startHour = calStart.get(Calendar.HOUR_OF_DAY)
        val endHour = calEnd.get(Calendar.HOUR_OF_DAY)
        val isSameDay = isSameDay(start, targetDate.time)
        val isNap = (totalDuration < 3.5 * 3600) && isSameDay && (startHour >= 9 && endHour <= 20)

        return SleepSession(
            startTime = start,
            endTime = end,
            isNap = isNap,
            stages = emptyList(),
            sourceDevice = sourceDevice,
            hasGranularHypnogram = false
        )
    }

    /**
     * Priority ranking for selecting the primary nocturnal sleep session among multiple wearables.
     * Dedicated sleep trackers (Oura Ring) have highest clinical accuracy, followed by Pixel/Galaxy/Apple Watch and Amazfit.
     */
    private fun deviceSleepPriorityRank(deviceName: String): Int {
        val lower = deviceName.lowercase()
        if (lower.contains("oura")) return 100
        if (lower.contains("watch") || lower.contains("pixel") || lower.contains("galaxy") || lower.contains("apple")) return 80
        if (lower.contains("amazfit") || lower.contains("zepp") || lower.contains("balance")) return 70
        if (lower.contains("oneplus") || lower.contains("wearos") || lower.contains("wear os")) return 60
        if (lower.contains("huawei") || lower.contains("harmony")) return 50
        if (lower.contains("health connect") || lower.contains("health")) return 40
        return 10
    }

    /**
     * Normalizes and clips stage records within a cluster to prevent overlapping time spans.
     * Guarantees that the sum of stage durations can mathematically never exceed the session's wall-clock duration.
     */
    private fun normalizeAndDeduplicateStages(
        rawRecords: List<HealthTelemetryRecord>,
        sourceDevice: String
    ): List<SleepStageRecord> {
        val sorted = rawRecords.sortedWith { a, b ->
            if (a.startTime != b.startTime) {
                a.startTime.compareTo(b.startTime)
            } else {
                a.effectiveEndTime.compareTo(b.effectiveEndTime)
            }
        }

        val normalized = mutableListOf<SleepStageRecord>()
        var lastEnd: Long? = null

        for (record in sorted) {
            var start = record.startTime
            val end = record.effectiveEndTime
            if (end <= start) continue

            val prevEnd = lastEnd
            if (prevEnd != null) {
                if (start < prevEnd) {
                    if (end <= prevEnd) {
                        // Completely subsumed by previous stage, ignore duplicate
                        continue
                    } else {
                        // Partially overlapping: clip start to prevEnd
                        start = prevEnd
                    }
                }
            }

            val dur = max(0.0, (end - start) / 1000.0)
            if (dur < 10.0) continue // Ignore sub-10s artifacts

            normalized.add(
                SleepStageRecord(
                    id = record.id,
                    stageType = record.sleepStageType,
                    startTime = start,
                    endTime = end,
                    durationSeconds = dur,
                    sourceDevice = sourceDevice
                )
            )
            lastEnd = end
        }

        return normalized
    }

    private fun isSameDay(time1: Long, time2: Long): Boolean {
        val c1 = Calendar.getInstance().apply { timeInMillis = time1 }
        val c2 = Calendar.getInstance().apply { timeInMillis = time2 }
        return c1.get(Calendar.YEAR) == c2.get(Calendar.YEAR) &&
                c1.get(Calendar.DAY_OF_YEAR) == c2.get(Calendar.DAY_OF_YEAR)
    }
}
