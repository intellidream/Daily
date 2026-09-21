import Testing
import Foundation
@testable import DailyCore

struct HealthServiceTests {
    
    @Test func testMetricTypeNormalization() async throws {
        #expect(HealthMetricType.from(rawString: "steps") == .steps)
        #expect(HealthMetricType.from(rawString: "step_count") == .steps)
        #expect(HealthMetricType.from(rawString: "heart_rate") == .heartRate)
        #expect(HealthMetricType.from(rawString: "HR") == .heartRate)
        #expect(HealthMetricType.from(rawString: "resting_heart_rate") == .restingHeartRate)
        #expect(HealthMetricType.from(rawString: "hrv_sdnn") == .hrvSdnn)
        #expect(HealthMetricType.from(rawString: "sleep_stage_deep") == .sleepDeep)
        #expect(HealthMetricType.from(rawString: "sleep_stage_rem") == .sleepRem)
        #expect(HealthMetricType.from(rawString: "sleep_nap") == .napDuration)
        #expect(HealthMetricType.from(rawString: "blood_pressure_systolic") == .bloodPressureSystolic)
    }
    
    @Test func testNocturnalSleepAttributionMorningWakeUp() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        // Sleep starting at 23:15 yesterday, ending at 07:15 this morning
        let bedtime = cal.date(byAdding: .minute, value: -45, to: today)! // 23:15
        let wakeTime = cal.date(byAdding: .minute, value: 435, to: today)! // 07:15
        
        let telemetry = [
            HealthTelemetryRecord(
                userId: "user-1",
                type: "sleep_stage_deep",
                value: 120,
                unit: "minutes",
                startTime: bedtime,
                endTime: bedtime.addingTimeInterval(7200),
                sourceDevice: "Amazfit Balance"
            ),
            HealthTelemetryRecord(
                userId: "user-1",
                type: "sleep_stage_light",
                value: 180,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(7200),
                endTime: bedtime.addingTimeInterval(18000),
                sourceDevice: "Amazfit Balance"
            ),
            HealthTelemetryRecord(
                userId: "user-1",
                type: "sleep_stage_rem",
                value: 100,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(18000),
                endTime: wakeTime,
                sourceDevice: "Amazfit Balance"
            )
        ]
        
        let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: telemetry)
        
        let primary = try #require(result.primarySession)
        #expect(primary.hasGranularHypnogram == true)
        #expect(!primary.isNap)
        #expect(primary.asleepSeconds > 6 * 3600)
        #expect(result.naps.isEmpty)
    }
    
    @Test func testEarlyMorningWakeUpNotDropped() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        // Sleep starting at 21:30 yesterday, ending at 03:45 early morning today
        let bedtime = cal.date(byAdding: .minute, value: -150, to: today)! // 21:30
        let wakeTime = cal.date(byAdding: .minute, value: 225, to: today)! // 03:45 AM
        
        let telemetry = [
            HealthTelemetryRecord(
                userId: "user-1",
                type: "sleep_stage_deep",
                value: 90,
                unit: "minutes",
                startTime: bedtime,
                endTime: bedtime.addingTimeInterval(5400),
                sourceDevice: "Apple Watch"
            ),
            HealthTelemetryRecord(
                userId: "user-1",
                type: "sleep_stage_light",
                value: 285,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(5400),
                endTime: wakeTime,
                sourceDevice: "Apple Watch"
            )
        ]
        
        let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: telemetry)
        
        // In WinUI this was dropped because EndTime.Hour was 3 (< 4)
        // In our engine, this is correctly preserved as the nocturnal session for today!
        let primary = try #require(result.primarySession)
        #expect(primary.endTime == wakeTime)
        #expect(primary.stages.count == 2)
    }
    
    @Test func testDaytimeNapSeparation() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        let napStart = cal.date(byAdding: .minute, value: 855, to: today)! // 14:15
        let napEnd = cal.date(byAdding: .minute, value: 895, to: today)!   // 14:55 (40 mins)
        
        let telemetry = [
            HealthTelemetryRecord(
                userId: "user-1",
                type: "sleep_nap",
                value: 40,
                unit: "minutes",
                startTime: napStart,
                endTime: napEnd,
                sourceDevice: "Amazfit Balance"
            )
        ]
        
        let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: telemetry)
        #expect(result.primarySession == nil)
        #expect(result.naps.count == 1)
        #expect(result.naps[0].durationSeconds == 40 * 60)
    }
    
    @Test func testMultiDeviceIsolation() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        let bedtime = cal.date(byAdding: .minute, value: -60, to: today)! // 23:00
        let wakeTime = cal.date(byAdding: .minute, value: 420, to: today)! // 07:00
        
        // Device A (Amazfit) logs granular stages
        let amazfitRecords = [
            HealthTelemetryRecord(userId: "u", type: "sleep_stage_deep", value: 60, unit: "minutes", startTime: bedtime, endTime: bedtime.addingTimeInterval(3600), sourceDevice: "Amazfit Balance"),
            HealthTelemetryRecord(userId: "u", type: "sleep_stage_light", value: 360, unit: "minutes", startTime: bedtime.addingTimeInterval(3600), endTime: wakeTime, sourceDevice: "Amazfit Balance")
        ]
        
        // Device B (Apple Watch) logs generic total duration
        let appleWatchRecords = [
            HealthTelemetryRecord(userId: "u", type: "sleep", value: 7.5, unit: "hours", startTime: bedtime, endTime: wakeTime, sourceDevice: "Apple Watch")
        ]
        
        let combined = amazfitRecords + appleWatchRecords
        let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: combined)
        
        // Granular session from Amazfit should be prioritized as primary because hasGranularHypnogram == true
        let primary = try #require(result.primarySession)
        #expect(primary.sourceDevice == "Amazfit Balance")
        #expect(primary.hasGranularHypnogram == true)
        
        // Total sessions found across both devices = 2
        #expect(result.allSessions.count == 2)
    }
    
    @Test func testSleepScoreAndEfficiencyFormula() async throws {
        let now = Date()
        let stages = [
            SleepStageRecord(stageType: .awake, startTime: now, endTime: now.addingTimeInterval(1800), durationSeconds: 1800), // 30m
            SleepStageRecord(stageType: .deep, startTime: now.addingTimeInterval(1800), endTime: now.addingTimeInterval(7200), durationSeconds: 5400), // 1.5h
            SleepStageRecord(stageType: .rem, startTime: now.addingTimeInterval(7200), endTime: now.addingTimeInterval(14400), durationSeconds: 7200), // 2.0h
            SleepStageRecord(stageType: .light, startTime: now.addingTimeInterval(14400), endTime: now.addingTimeInterval(28800), durationSeconds: 14400) // 4.0h
        ]
        
        let session = SleepSession(
            startTime: now,
            endTime: now.addingTimeInterval(28800),
            stages: stages,
            sourceDevice: "Test Device",
            hasGranularHypnogram: true
        )
        
        #expect(session.asleepSeconds == (1.5 + 2.0 + 4.0) * 3600) // 7.5 hours
        #expect(session.awakeSeconds == 1800) // 0.5 hours
        #expect(session.efficiencyPercent >= 90)
        #expect(session.sleepScore >= 80)
        #expect(session.sleepQualityRating == "Optimal" || session.sleepQualityRating == "Good")
    }
    
    @Test func testHeartRateZones() async throws {
        #expect(HeartRateZone.zone(for: 65) == .resting)
        #expect(HeartRateZone.zone(for: 105) == .fatBurn)
        #expect(HeartRateZone.zone(for: 135) == .cardio)
        #expect(HeartRateZone.zone(for: 165) == .peak)
    }
    
    @Test func testNapDeduplicationAndMerging() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let napStart = cal.date(byAdding: .hour, value: 14, to: today)!
        let napEnd = cal.date(byAdding: .minute, value: 85, to: napStart)!
        
        // Two duplicate records from Zepp OS sync
        let dupRecords = [
            HealthTelemetryRecord(id: "r1", userId: "u", type: "sleep_nap", value: 85, unit: "minutes", startTime: napStart, endTime: napEnd, sourceDevice: "Zepp OS Watch"),
            HealthTelemetryRecord(id: "r2", userId: "u", type: "sleep_nap", value: 85, unit: "minutes", startTime: napStart, endTime: napEnd, sourceDevice: "Zepp OS Watch")
        ]
        
        // 1. Raw deduplicateTelemetry test
        let deduped = HealthDataService.deduplicateTelemetry(dupRecords)
        #expect(deduped.count == 1)
        
        // 2. SleepClusteringEngine nap deduplication test
        let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: dupRecords)
        #expect(result.naps.count == 1)
        #expect(result.naps[0].durationSeconds == 85 * 60)
        #expect(result.naps[0].sourceDevice == "Zepp OS Watch")
    }
    
    @Test func testCumulativeStepCalculation() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let t1 = cal.date(byAdding: .hour, value: 11, to: today)!.addingTimeInterval(16 * 60) // 11:16
        let t2 = cal.date(byAdding: .hour, value: 11, to: today)!.addingTimeInterval(58 * 60) // 11:58
        let t3 = cal.date(byAdding: .hour, value: 16, to: today)!.addingTimeInterval(21 * 60) // 16:21
        
        // Zepp OS reports cumulative snapshots: 3107, 3254, 7986
        let zeppRecords = [
            HealthTelemetryRecord(userId: "u", type: "steps", value: 3107, unit: "count", startTime: t1, endTime: t1, sourceDevice: "Zepp OS Watch"),
            HealthTelemetryRecord(userId: "u", type: "steps", value: 3254, unit: "count", startTime: t2, endTime: t2, sourceDevice: "Zepp OS Watch"),
            HealthTelemetryRecord(userId: "u", type: "steps", value: 7986, unit: "count", startTime: t3, endTime: t3, sourceDevice: "Zepp OS Watch")
        ]
        
        let result = HealthDataService.calculateDailySteps(
            targetDate: today,
            telemetry: zeppRecords,
            calendar: cal
        )
        
        // Total steps must be exactly the max cumulative value (7986), NEVER the naive sum (14347)
        #expect(result.totalSteps == 7986)
        
        // Hourly buckets sum must match total steps exactly
        let hourlySum = result.hourlyBuckets.map(\.steps).reduce(0, +)
        #expect(hourlySum == 7986)
        
        // Hour 11 should have 3254 steps, Hour 16 should have 4732 steps (7986 - 3254)
        #expect(result.hourlyBuckets[11].steps == 3254)
        #expect(result.hourlyBuckets[16].steps == 4732)
    }
    
    @Test func testMultiDeviceStepResolution() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tWatch = cal.date(byAdding: .hour, value: 16, to: today)!
        let tPhone = cal.date(byAdding: .hour, value: 15, to: today)!
        
        let watchRecord = HealthTelemetryRecord(userId: "u", type: "steps", value: 7986, unit: "count", startTime: tWatch, endTime: tWatch, sourceDevice: "Amazfit Balance")
        let phoneRecord = HealthTelemetryRecord(userId: "u", type: "steps", value: 2400, unit: "count", startTime: tPhone, endTime: tPhone.addingTimeInterval(3600), sourceDevice: "Apple Health")
        
        let combined = [watchRecord, phoneRecord]
        
        // "All Devices": should pick the primary wearable (Amazfit Balance with 7986 steps) rather than summing (10386)
        let allDevicesResult = HealthDataService.calculateDailySteps(
            targetDate: today,
            telemetry: combined,
            calendar: cal
        )
        #expect(allDevicesResult.totalSteps == 7986)
        #expect(allDevicesResult.sourceDeviceUsed == "Amazfit Balance")
        
        // Explicit filter for Apple Health:
        let healthKitResult = HealthDataService.calculateDailySteps(
            targetDate: today,
            telemetry: combined,
            preferredSource: .healthKit,
            calendar: cal
        )
        #expect(healthKitResult.totalSteps == 2400)
    }
    
    @Test func testStepResolutionBetweenTelemetryAndVitalsSummary() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tPhone = cal.date(byAdding: .hour, value: 15, to: today)!
        
        // Scenario A: Live HealthKit telemetry reports 8878 steps, while earlier backend vitals has 7896.
        // In "All Devices" view: Authoritative live steps (8878) must not be truncated back to stale 7896.
        let liveTelemetry = [
            HealthTelemetryRecord(userId: "u", type: "steps", value: 8878, unit: "count", startTime: tPhone, endTime: tPhone.addingTimeInterval(3600), sourceDevice: "Apple Health")
        ]
        let staleVitalsSummary: [HealthMetricType: Double] = [.steps: 7896]
        
        let liveResult = HealthDataService.calculateDailySteps(
            targetDate: today,
            telemetry: liveTelemetry,
            vitalsSummary: staleVitalsSummary,
            calendar: cal
        )
        #expect(liveResult.totalSteps == 8878)
        
        // Scenario B: Smartwatch vitals summary has 7896 steps, but phone was only carried for 2400 steps.
        // In "All Devices" view: Smartwatch count (7896) is preserved over partial phone count (2400).
        let partialPhoneTelemetry = [
            HealthTelemetryRecord(userId: "u", type: "steps", value: 2400, unit: "count", startTime: tPhone, endTime: tPhone.addingTimeInterval(3600), sourceDevice: "Apple Health")
        ]
        let smartwatchVitalsSummary: [HealthMetricType: Double] = [.steps: 7896]
        
        let smartwatchResult = HealthDataService.calculateDailySteps(
            targetDate: today,
            telemetry: partialPhoneTelemetry,
            vitalsSummary: smartwatchVitalsSummary,
            calendar: cal
        )
        #expect(smartwatchResult.totalSteps == 7896)
        
        // Scenario C: Explicit device filter for Apple Health (8878)
        let healthKitFilterResult = HealthDataService.calculateDailySteps(
            targetDate: today,
            telemetry: liveTelemetry,
            vitalsSummary: staleVitalsSummary,
            preferredSource: .healthKit,
            calendar: cal
        )
        #expect(healthKitFilterResult.totalSteps == 8878)
    }
    
    @Test func testConcurrentOuraAndAmazfitIsolationAndPrioritization() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let bedtime = cal.date(byAdding: .hour, value: -1, to: today)! // 23:00 yesterday
        let wakeTime = cal.date(byAdding: .minute, value: 420, to: today)! // 07:00 today (8 hours)
        
        // Oura Ring telemetry: ~7.5 hours
        let ouraTelemetry = [
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_light",
                value: 60,
                unit: "minutes",
                startTime: bedtime,
                endTime: bedtime.addingTimeInterval(3600),
                sourceDevice: "Oura Ring"
            ),
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_deep",
                value: 90,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(3600),
                endTime: bedtime.addingTimeInterval(9000),
                sourceDevice: "Oura Ring"
            ),
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_rem",
                value: 120,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(9000),
                endTime: bedtime.addingTimeInterval(16200),
                sourceDevice: "Oura Ring"
            ),
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_light",
                value: 180,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(16200),
                endTime: wakeTime,
                sourceDevice: "Oura Ring"
            )
        ]
        
        // Amazfit Balance telemetry: ~7.5 hours (slight time offset)
        let amazfitBedtime = bedtime.addingTimeInterval(300) // 23:05
        let amazfitWake = wakeTime.addingTimeInterval(300)   // 07:05
        let amazfitTelemetry = [
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_light",
                value: 90,
                unit: "minutes",
                startTime: amazfitBedtime,
                endTime: amazfitBedtime.addingTimeInterval(5400),
                sourceDevice: "Amazfit Balance"
            ),
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_deep",
                value: 75,
                unit: "minutes",
                startTime: amazfitBedtime.addingTimeInterval(5400),
                endTime: amazfitBedtime.addingTimeInterval(9900),
                sourceDevice: "Amazfit Balance"
            ),
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_rem",
                value: 105,
                unit: "minutes",
                startTime: amazfitBedtime.addingTimeInterval(9900),
                endTime: amazfitBedtime.addingTimeInterval(16200),
                sourceDevice: "Amazfit Balance"
            ),
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_light",
                value: 180,
                unit: "minutes",
                startTime: amazfitBedtime.addingTimeInterval(16200),
                endTime: amazfitWake,
                sourceDevice: "Amazfit Balance"
            )
        ]
        
        let combinedTelemetry = ouraTelemetry + amazfitTelemetry
        
        // 1. Cluster both without preferred device filter
        let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: combinedTelemetry)
        
        // Verify both sessions exist independently (no lumping / doubling into a 15-hour session!)
        #expect(result.allSessions.count == 2)
        
        // Primary session must prioritize dedicated tracker Oura Ring
        let primary = try #require(result.primarySession)
        #expect(primary.sourceDevice == "Oura Ring")
        #expect(primary.asleepSeconds == 450 * 60) // 7.5 hours, NOT doubled to 15 hours!
        #expect(primary.asleepSeconds <= 8 * 3600)
        
        // 2. Explicit device preference for Amazfit Balance
        let amazfitResult = SleepClusteringEngine.clusterSleep(
            targetDate: today,
            telemetry: combinedTelemetry,
            preferredDevice: "Amazfit Balance"
        )
        let amazfitPrimary = try #require(amazfitResult.primarySession)
        #expect(amazfitPrimary.sourceDevice == "Amazfit Balance")
        #expect(amazfitPrimary.asleepSeconds == 450 * 60)
    }
    
    @Test func testOverlappingStageIntervalClippingDefenseInDepth() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let bedtime = cal.date(byAdding: .hour, value: -1, to: today)! // 23:00
        
        // 3 overlapping records for the same device
        // Record 1: 23:00 to 02:00 (3h)
        // Record 2: 01:00 to 03:00 (2h - overlaps with 1 by 1h)
        // Record 3: 02:30 to 05:00 (2.5h - overlaps with 2 by 0.5h)
        // Total unclipped sum: 3 + 2 + 2.5 = 7.5h
        // Actual elapsed span: 23:00 to 05:00 = 6 hours!
        let overlappingTelemetry = [
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_deep",
                value: 180,
                unit: "minutes",
                startTime: bedtime,
                endTime: bedtime.addingTimeInterval(10800), // 02:00
                sourceDevice: "Apple Health"
            ),
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_light",
                value: 180,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(3600), // 00:00 to 03:00 (overlaps with 1)
                endTime: bedtime.addingTimeInterval(14400), // 03:00
                sourceDevice: "Apple Health"
            ),
            HealthTelemetryRecord(
                userId: "u1",
                type: "sleep_stage_rem",
                value: 150,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(12600), // 02:30 (overlapping)
                endTime: bedtime.addingTimeInterval(21600), // 05:00
                sourceDevice: "Apple Health"
            )
        ]
        
        let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: overlappingTelemetry)
        let session = try #require(result.primarySession)
        
        // Defense-in-depth: asleepSeconds must NEVER exceed the elapsed wall-clock span (6 hours)
        let elapsedWallClock = session.endTime.timeIntervalSince(session.startTime)
        #expect(session.asleepSeconds <= elapsedWallClock)
        #expect(session.asleepSeconds == 6 * 3600) // Exactly 6 hours, not 7.5 hours!
    }
    
    @Test func testCalibratedSleepScoreDiscrimination() async throws {
        let now = Date()
        
        // Scenario A: Mediocre / restless night (5.5h sleep, 78% efficiency, 6 awakenings, 50m awake, 8% deep)
        let restlessStages = [
            SleepStageRecord(stageType: .light, startTime: now, endTime: now.addingTimeInterval(12600), durationSeconds: 12600), // 3.5h
            SleepStageRecord(stageType: .deep, startTime: now.addingTimeInterval(12600), endTime: now.addingTimeInterval(14400), durationSeconds: 1800), // 30m (9%)
            SleepStageRecord(stageType: .rem, startTime: now.addingTimeInterval(14400), endTime: now.addingTimeInterval(19800), durationSeconds: 5400), // 1.5h
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(19800), endTime: now.addingTimeInterval(20300), durationSeconds: 500),
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(20300), endTime: now.addingTimeInterval(20800), durationSeconds: 500),
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(20800), endTime: now.addingTimeInterval(21300), durationSeconds: 500),
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(21300), endTime: now.addingTimeInterval(21800), durationSeconds: 500),
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(21800), endTime: now.addingTimeInterval(22300), durationSeconds: 500),
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(22300), endTime: now.addingTimeInterval(22800), durationSeconds: 500) // 6 awakes, 3000s = 50m
        ]
        let restlessSession = SleepSession(
            startTime: now,
            endTime: now.addingTimeInterval(25400), // 7.05h bed, 5.5h sleep -> 78% eff
            stages: restlessStages,
            sourceDevice: "Oura Ring",
            hasGranularHypnogram: true
        )
        // Under old formula this scored ~74 ("Fair"). Now it must score <= 58 ("Restless")!
        #expect(restlessSession.sleepScore <= 58)
        #expect(restlessSession.sleepQualityRating == "Restless")
        
        // Scenario B: Solid normal night (7.2h sleep, 90% efficiency, 2 awakenings, 20m awake, 16% deep, 22% rem)
        let normalStages = [
            SleepStageRecord(stageType: .light, startTime: now, endTime: now.addingTimeInterval(13680), durationSeconds: 13680), // 3.8h
            SleepStageRecord(stageType: .deep, startTime: now.addingTimeInterval(13680), endTime: now.addingTimeInterval(17880), durationSeconds: 4200), // 1.16h (~16%)
            SleepStageRecord(stageType: .rem, startTime: now.addingTimeInterval(17880), endTime: now.addingTimeInterval(23640), durationSeconds: 5760), // 1.6h (~22%)
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(23640), endTime: now.addingTimeInterval(24240), durationSeconds: 600),
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(24240), endTime: now.addingTimeInterval(24840), durationSeconds: 600)
        ]
        let normalSession = SleepSession(
            startTime: now,
            endTime: now.addingTimeInterval(26000), // 7.2h sleep, 89% eff
            stages: normalStages,
            sourceDevice: "Oura Ring",
            hasGranularHypnogram: true
        )
        #expect(normalSession.sleepScore >= 78 && normalSession.sleepScore <= 88)
        #expect(normalSession.sleepQualityRating == "Good" || normalSession.sleepQualityRating == "Optimal")
        
        // Scenario C: Truly restorative night (8.0h sleep, 94% efficiency, 1 awakening, 15m awake, 18% deep, 24% rem)
        let optimalStages = [
            SleepStageRecord(stageType: .light, startTime: now, endTime: now.addingTimeInterval(16704), durationSeconds: 16704), // 4.64h
            SleepStageRecord(stageType: .deep, startTime: now.addingTimeInterval(16704), endTime: now.addingTimeInterval(21888), durationSeconds: 5184), // 1.44h (18%)
            SleepStageRecord(stageType: .rem, startTime: now.addingTimeInterval(21888), endTime: now.addingTimeInterval(28800), durationSeconds: 6912), // 1.92h (24%)
            SleepStageRecord(stageType: .awake, startTime: now.addingTimeInterval(28800), endTime: now.addingTimeInterval(29700), durationSeconds: 900)  // 1 awake 15m
        ]
        let optimalSession = SleepSession(
            startTime: now,
            endTime: now.addingTimeInterval(30638), // 8h sleep / 8.51h bed = 94% eff
            stages: optimalStages,
            sourceDevice: "Oura Ring",
            hasGranularHypnogram: true
        )
        #expect(optimalSession.sleepScore >= 90)
        #expect(optimalSession.sleepQualityRating == "Optimal")
    }
}

