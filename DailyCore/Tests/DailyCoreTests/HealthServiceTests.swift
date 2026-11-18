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
    
    @Test @MainActor func testHealthDataServiceDateNavigation() throws {
        let service = HealthDataService.shared
        service.goToToday()
        #expect(service.isToday == true)
        #expect(service.formattedDateTitle == "Today")
        
        service.goToPreviousDay()
        #expect(service.isToday == false)
        #expect(service.formattedDateTitle == "Yesterday")
        
        service.goToToday()
        #expect(service.isToday == true)
    }
    
    @Test func testDeviceClassificationAndVirtualEngineFiltering() throws {
        // Physical wearables
        let appleWatch = DeviceSource.from(name: "Apple Watch Ultra 2")
        #expect(appleWatch == .appleWatch)
        #expect(appleWatch.isVirtualEngine == false)
        #expect(appleWatch.displayName == "Apple Watch Ultra 2")
        
        let ouraRing = DeviceSource.from(name: "Oura Ring Gen 3")
        #expect(ouraRing == .oura)
        #expect(ouraRing.isVirtualEngine == false)
        #expect(ouraRing.displayName == "Oura Ring")
        
        let amazfit = DeviceSource.from(name: "Amazfit Balance")
        #expect(amazfit == .amazfit)
        #expect(amazfit.isVirtualEngine == false)
        
        // Virtual engines (must be flagged as isVirtualEngine and never appear in physical device lists)
        let stressWatch = DeviceSource.from(name: "StressWatch Model")
        #expect(stressWatch.isVirtualEngine == true)
        
        let stressWatchBare = DeviceSource.from(name: "StressWatch")
        #expect(stressWatchBare.isVirtualEngine == true)
        
        let dailyBiometric = DeviceSource.from(name: "Daily Biometric Engine")
        #expect(dailyBiometric.isVirtualEngine == true)
        
        let bubbles = DeviceSource.from(name: "Bubbles")
        #expect(bubbles.isVirtualEngine == true)
        
        let computed = DeviceSource.from(name: "computed")
        #expect(computed.isVirtualEngine == true)
    }
    
    @Test func testCanonicalDailySummaryPayloadRoundTrip() throws {
        let now = Date()
        let cal = Calendar.current
        let bedtime = cal.date(byAdding: .hour, value: -8, to: now)!
        let wakeTime = now
        
        let primarySession = SleepSession(
            id: "sleep-1",
            startTime: bedtime,
            endTime: wakeTime,
            isNap: false,
            stages: [
                SleepStageRecord(
                    id: "stage-1",
                    stageType: .deep,
                    startTime: bedtime,
                    endTime: bedtime.addingTimeInterval(3600),
                    durationSeconds: 3600,
                    sourceDevice: "Apple Watch"
                ),
                SleepStageRecord(
                    id: "stage-2",
                    stageType: .rem,
                    startTime: bedtime.addingTimeInterval(3600),
                    endTime: bedtime.addingTimeInterval(7200),
                    durationSeconds: 3600,
                    sourceDevice: "Apple Watch"
                ),
                SleepStageRecord(
                    id: "stage-3",
                    stageType: .light,
                    startTime: bedtime.addingTimeInterval(7200),
                    endTime: wakeTime,
                    durationSeconds: 21600,
                    sourceDevice: "Apple Watch"
                )
            ],
            sourceDevice: "Apple Watch",
            hasGranularHypnogram: true
        )
        
        let sleepSummary = CanonicalSleepSummary(
            primarySession: primarySession,
            allSessions: [primarySession],
            naps: [
                NapSession(
                    id: "nap-1",
                    startTime: now.addingTimeInterval(-14400),
                    endTime: now.addingTimeInterval(-12600),
                    durationSeconds: 1800,
                    sourceDevice: "Apple Watch"
                )
            ],
            guidance: CanonicalSleepGuidance(
                verdict: SleepRecoveryVerdict(
                    id: "verdict-1",
                    status: .optimal,
                    headline: "Superb Architecture",
                    narrative: "Solid deep sleep and restorative REM balance.",
                    readinessScore: 92,
                    physicalRepairRating: "High",
                    cognitiveRestoreRating: "High",
                    sleepContinuityRating: "Continuous"
                ),
                tips: [
                    SleepActionableTip(
                        id: "tip-1",
                        category: .circadian,
                        title: "Early Sun",
                        advice: "Get 10 minutes of direct sunlight.",
                        scientificRationale: "Resets suprachiasmatic nucleus."
                    )
                ],
                aiContext: SleepAIContext(
                    narrativeSynthesis: "Your rest was exceptional.",
                    suggestedPrompts: ["How do I sustain this recovery?"]
                )
            )
        )
        
        let activitySummary = CanonicalActivitySummary(
            totalSteps: 11420,
            activeCalories: 620.5,
            sourceDevice: "Apple Watch",
            hourlySteps: [
                HourlyStepBucket(hour: 8, steps: 1200),
                HourlyStepBucket(hour: 9, steps: 2300),
                HourlyStepBucket(hour: 10, steps: 3500)
            ]
        )
        
        let cardioSummary = CanonicalCardiovascularSummary(
            averageBpm: 68.0,
            restingBpm: 56.0,
            minBpm: 52.0,
            maxBpm: 142.0,
            zones: CanonicalHeartRateZones(resting: 420, fatBurn: 60, cardio: 25, peak: 5),
            intradayPoints: [
                IntradayHeartRatePoint(
                    id: "hr-1",
                    timestamp: now.addingTimeInterval(-3600),
                    bpm: 72.0,
                    sourceDevice: "Apple Watch"
                )
            ]
        )
        
        let stressSummary = CanonicalStressSummary(
            currentScore: 24,
            currentLevel: .restful,
            dailyAverage: 28,
            peakHour: 14,
            peakScore: 48,
            lowestHour: 4,
            lowestScore: 12,
            parasympatheticPercent: 78,
            sympatheticPercent: 22,
            baselineHrvMs: 65.0,
            currentHrvMs: 72.0,
            hrvDeltaPercent: 10.8,
            restingHeartRateBpm: 56.0,
            currentSedentaryBpm: 62.0,
            heartRateElevationBpm: 6.0,
            monkeyMood: .zen,
            adviceQuote: "You're in peak recovery mode!",
            recommendedBreathing: "Resonance Flow (5.5s)",
            intradayPoints: [
                IntradayStressPoint(
                    id: "st-1",
                    timestamp: now,
                    hour: 10,
                    score: 24,
                    level: .restful,
                    hrvMs: 72.0,
                    heartRateBpm: 62.0,
                    isSedentary: true
                )
            ]
        )
        
        let payload = DailyHealthSummaryPayload(
            date: "2026-10-05",
            engineVersion: "1.0",
            computedAt: now,
            sleep: sleepSummary,
            activity: activitySummary,
            cardiovascular: cardioSummary,
            stress: stressSummary,
            vitals: [
                "steps": CanonicalVitalSummaryItem(type: "steps", value: 11420, unit: "count", sourceDevice: "Apple Watch", timestamp: now),
                "resting_heart_rate": CanonicalVitalSummaryItem(type: "resting_heart_rate", value: 56, unit: "bpm", sourceDevice: "Apple Watch", timestamp: now),
                "hrv_sdnn": CanonicalVitalSummaryItem(type: "hrv_sdnn", value: 72, unit: "ms", sourceDevice: "Apple Watch", timestamp: now)
            ]
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        
        // Decode back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DailyHealthSummaryPayload.self, from: data)
        
        #expect(decoded.date == "2026-10-05")
        #expect(decoded.activity.totalSteps == 11420)
        #expect(decoded.activity.hourlySteps.count == 3)
        #expect(decoded.activity.hourlySteps[0].steps == 1200)
        #expect(decoded.sleep.primarySession?.sleepScore ?? 0 > 80)
        #expect(decoded.sleep.naps.count == 1)
        #expect(decoded.cardiovascular.restingBpm == 56.0)
        #expect(decoded.stress?.currentLevel == .restful)
        #expect(decoded.stress?.monkeyMood == .zen)
        #expect(decoded.vitals["hrv_sdnn"]?.value == 72.0)
    }

    @Test func testCanonicalSleepGuidanceDecodingWithoutId() async throws {
        let jsonWithoutId = """
        {
            "status": "Great",
            "headline": "Strong Recharging with Balanced Sleep Stages",
            "narrative": "Solid overall rest of 5.3 hours. Autonomic tone and muscular recovery are in healthy parameters.",
            "readiness_score": 80,
            "physical_repair_rating": "High",
            "cognitive_restore_rating": "High",
            "sleep_continuity_rating": "Continuous"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let verdict = try decoder.decode(SleepRecoveryVerdict.self, from: jsonWithoutId)
        #expect(verdict.status == .great)
        #expect(!verdict.id.isEmpty)
        #expect(verdict.readinessScore == 80)
        #expect(verdict.physicalRepairRating == "High")
    }

    @Test func testLeanHealthModelsAndSessionConversion() async throws {
        let now = Date()
        let bedTime = now.addingTimeInterval(-28800)
        let stages: [SleepStageRecord] = [
            SleepStageRecord(id: "s1", stageType: .light, startTime: bedTime, endTime: bedTime.addingTimeInterval(3600), sourceDevice: "Oura Ring"),
            SleepStageRecord(id: "s2", stageType: .deep, startTime: bedTime.addingTimeInterval(3600), endTime: bedTime.addingTimeInterval(7200), sourceDevice: "Oura Ring"),
            SleepStageRecord(id: "s3", stageType: .rem, startTime: bedTime.addingTimeInterval(7200), endTime: bedTime.addingTimeInterval(10800), sourceDevice: "Oura Ring"),
            SleepStageRecord(id: "s4", stageType: .awake, startTime: bedTime.addingTimeInterval(10800), endTime: bedTime.addingTimeInterval(12600), sourceDevice: "Oura Ring"),
            SleepStageRecord(id: "s5", stageType: .light, startTime: bedTime.addingTimeInterval(12600), endTime: now, sourceDevice: "Oura Ring")
        ]
        
        let record = HealthSleepSessionRecord(
            id: "sleep_test_1",
            userId: "user-123",
            localDate: "2026-11-02",
            sessionType: "primary_sleep",
            sourceDeviceKey: "Oura Ring",
            hostDeviceName: "Schmitz",
            startTime: bedTime,
            endTime: now,
            durationSeconds: 28800,
            timeInBedSeconds: 28800,
            efficiencyPercent: 93.7,
            sleepScore: 85,
            deepSeconds: 3600,
            remSeconds: 3600,
            lightSeconds: 19800,
            awakeSeconds: 1800,
            stages: stages,
            sourcePriority: 1,
            isUserSelected: true
        )
        
        let session = record.toSleepSession()
        #expect(session.id == "sleep_test_1")
        #expect(session.sourceDevice == "Oura Ring")
        #expect(session.hasGranularHypnogram == true)
        #expect(session.deepSeconds == 3600)
        #expect(session.remSeconds == 3600)
        #expect(session.awakeSeconds == 1800)
        #expect(session.stages.count == 5)
        #expect(session.sleepScore > 70)
        
        // Intraday Heart Rate Bucket to Point
        let bucket = HealthIntradayHeartRateRecord(
            id: "hr_1",
            userId: "user-123",
            localDate: "2026-11-02",
            sourceDeviceKey: "Pixel Watch 5",
            bucketMinute: 120, // 02:00 AM
            bpmAvg: 62,
            bpmMin: 58,
            bpmMax: 68,
            sampleCount: 5
        )
        let point = bucket.toPoint(for: now)
        #expect(point.bpm == 62)
        #expect(point.sourceDevice == "Pixel Watch 5")
    }
    
    @Test func testLeanStaticBuilders() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = cal.timeZone
        df.dateFormat = "yyyy-MM-dd"
        let dateKey = df.string(from: today)
        let userId = "user-test-123"
        let host = "Schmitz"
        
        // 1. Test 5-minute Intraday HR Bucketing
        let t10_01 = cal.date(byAdding: .minute, value: 601, to: today)! // 10:01
        let t10_03 = cal.date(byAdding: .minute, value: 603, to: today)! // 10:03
        let t10_04 = cal.date(byAdding: .minute, value: 604, to: today)! // 10:04
        let t10_07 = cal.date(byAdding: .minute, value: 607, to: today)! // 10:07 (next bucket: 605)
        
        let hrSamples = [
            HealthTelemetryRecord(userId: userId, type: "heart_rate", value: 60, unit: "bpm", startTime: t10_01, endTime: t10_01, sourceDevice: "Apple Watch Ultra 2"),
            HealthTelemetryRecord(userId: userId, type: "heart_rate", value: 70, unit: "bpm", startTime: t10_03, endTime: t10_03, sourceDevice: "Apple Watch Ultra 2"),
            HealthTelemetryRecord(userId: userId, type: "heart_rate", value: 80, unit: "bpm", startTime: t10_04, endTime: t10_04, sourceDevice: "Apple Watch Ultra 2"),
            HealthTelemetryRecord(userId: userId, type: "heart_rate", value: 65, unit: "bpm", startTime: t10_07, endTime: t10_07, sourceDevice: "Apple Watch Ultra 2")
        ]
        
        let buckets = HealthDataService.groupIntradayHeartRateIntoBuckets(
            records: hrSamples,
            userId: userId,
            dateKey: dateKey,
            calendar: cal
        )
        
        #expect(buckets.count == 2)
        let b600 = buckets.first(where: { $0.bucketMinute == 600 })
        #expect(b600 != nil)
        #expect(b600?.bpmAvg == 70) // (60 + 70 + 80) / 3
        #expect(b600?.bpmMin == 60)
        #expect(b600?.bpmMax == 80)
        #expect(b600?.sampleCount == 3)
        
        let b605 = buckets.first(where: { $0.bucketMinute == 605 })
        #expect(b605 != nil)
        #expect(b605?.bpmAvg == 65)
        #expect(b605?.sampleCount == 1)
        
        // 2. Test Daily Vitals Builder
        let vitalsTelemetry = [
            HealthTelemetryRecord(userId: userId, type: "steps", value: 8500, unit: "count", startTime: today, endTime: today, sourceDevice: "Apple Watch Ultra 2"),
            HealthTelemetryRecord(userId: userId, type: "active_energy", value: 450, unit: "kcal", startTime: today, endTime: today, sourceDevice: "Apple Watch Ultra 2"),
            HealthTelemetryRecord(userId: userId, type: "resting_heart_rate", value: 54, unit: "bpm", startTime: today, endTime: today, sourceDevice: "Apple Watch Ultra 2"),
            HealthTelemetryRecord(userId: userId, type: "oxygen_saturation", value: 98.5, unit: "%", startTime: today, endTime: today, sourceDevice: "Apple Watch Ultra 2")
        ]
        
        let vitalsRecords = HealthDataService.buildLeanDailyVitalsRecords(
            records: vitalsTelemetry,
            targetDate: today,
            dateKey: dateKey,
            userId: userId,
            hostName: host,
            calendar: cal
        )
        
        #expect(vitalsRecords.count == 1)
        let primaryVitals = vitalsRecords[0]
        #expect(primaryVitals.steps == 8500)
        #expect(primaryVitals.activeKcal == 450)
        #expect(primaryVitals.restingHeartRate == 54)
        #expect(primaryVitals.spo2 == 98.5)
        #expect(primaryVitals.sourceDeviceKey == "Apple Watch Ultra 2")
        
        // 3. Test Sleep Session Builder
        let sStart = cal.date(byAdding: .hour, value: -8, to: today)!
        let sEnd = today
        let stages = [
            SleepStageRecord(id: "s1", stageType: .deep, startTime: sStart, endTime: sStart.addingTimeInterval(3600)),
            SleepStageRecord(id: "s2", stageType: .rem, startTime: sStart.addingTimeInterval(3600), endTime: sEnd)
        ]
        let session = SleepSession(
            startTime: sStart,
            endTime: sEnd,
            stages: stages,
            sourceDevice: "Apple Watch Ultra 2"
        )
        
        let sleepRecords = HealthDataService.buildLeanSleepSessionRecords(
            primarySession: session,
            naps: [],
            dateKey: dateKey,
            userId: userId,
            hostName: host
        )
        
        #expect(sleepRecords.count == 1)
        let sRec = sleepRecords[0]
        #expect(sRec.sessionType == "primary_sleep")
        #expect(sRec.sourceDeviceKey == "Apple Watch Ultra 2")
        #expect(sRec.deepSeconds == 3600)
        #expect(sRec.sleepScore != nil && sRec.sleepScore! > 0)
    }
    
    @Test func testRecencyFirstLatestHeartRateMidDayDeviceSwitch() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dateKey = "2026-11-05"
        let userId = "user-test-123"
        
        let t10_00 = cal.date(byAdding: .minute, value: 600, to: today)! // 10:00 AM
        let t10_05 = cal.date(byAdding: .minute, value: 605, to: today)! // 10:05 AM
        let t14_35 = cal.date(byAdding: .minute, value: 875, to: today)! // 14:35 PM (4.5 hours later!)
        
        // Oura Ring (#1 priority) & Pixel Watch 5 (#3 priority) stopped reporting at ~10:05 AM.
        // OnePlus Watch 3 (#4 priority) is worn in the afternoon and reports 78 BPM at 14:35 PM.
        let vitals = [
            HealthDailyVitalsRecord(
                id: "v_oura",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "Oura Ring",
                steps: 1200,
                latestHeartRate: 64,
                latestHrAt: t10_00
            ),
            HealthDailyVitalsRecord(
                id: "v_pw5",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "Pixel Watch 5",
                steps: 1150,
                latestHeartRate: 66,
                latestHrAt: t10_05
            ),
            HealthDailyVitalsRecord(
                id: "v_opw3",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "OnePlus Watch 3",
                steps: 2400,
                latestHeartRate: 78,
                latestHrAt: t14_35
            )
        ]
        
        let winner = HealthDataService.arbitrateLatestHeartRate(
            vitals: vitals,
            intradayBuckets: [],
            targetDate: today,
            sources: [],
            calendar: cal
        )
        
        #expect(winner != nil)
        #expect(winner?.sourceDevice == "OnePlus Watch 3")
        #expect(winner?.bpm == 78)
        #expect(winner?.timestamp == t14_35)
    }
    
    @Test func testSimultaneousWearHeartRateTieBreakAndCustomPriority() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dateKey = "2026-11-05"
        let userId = "user-test-123"
        
        let t14_30 = cal.date(byAdding: .minute, value: 870, to: today)! // 14:30
        let t14_36 = cal.date(byAdding: .minute, value: 876, to: today)! // 14:36 (within 15m simultaneous window)
        
        let vitals = [
            HealthDailyVitalsRecord(
                id: "v_oura",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "Oura Ring",
                latestHeartRate: 68,
                latestHrAt: t14_30
            ),
            HealthDailyVitalsRecord(
                id: "v_opw3",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "OnePlus Watch 3",
                latestHeartRate: 72,
                latestHrAt: t14_36
            )
        ]
        
        // 1. Default priority order: Oura Ring (#1) wins tie-break within 15-minute simultaneous window
        let defaultWinner = HealthDataService.arbitrateLatestHeartRate(
            vitals: vitals,
            intradayBuckets: [],
            targetDate: today,
            sources: [],
            calendar: cal
        )
        #expect(defaultWinner?.sourceDevice == "Oura Ring")
        #expect(defaultWinner?.bpm == 68)
        
        // 2. Custom user priority order: OnePlus Watch 3 promoted to #1, Oura Ring #2
        let customSources = [
            HealthSourceRecord(
                id: "oneplus_watch_3",
                userId: userId,
                platform: "Android",
                deviceKind: "watch",
                displayName: "OnePlus Watch 3",
                prioritySleep: 1,
                priorityActivity: 1,
                isCustomPriority: true
            ),
            HealthSourceRecord(
                id: "oura_ring",
                userId: userId,
                platform: "iOS",
                deviceKind: "ring",
                displayName: "Oura Ring",
                prioritySleep: 2,
                priorityActivity: 2,
                isCustomPriority: true
            )
        ]
        
        let customWinner = HealthDataService.arbitrateLatestHeartRate(
            vitals: vitals,
            intradayBuckets: [],
            targetDate: today,
            sources: customSources,
            calendar: cal
        )
        #expect(customWinner?.sourceDevice == "OnePlus Watch 3")
        #expect(customWinner?.bpm == 72)
    }
    
    @Test func testHourlyActivityEnvelopeMidDaySwitchVsSimultaneousWear() throws {
        let userId = "user-test-123"
        let dateKey = "2026-11-05"
        
        // Hours 8, 9, 10: Oura Ring (1000/h = 3000) AND Pixel Watch 5 (950/h = 2850) worn simultaneously
        // Hours 14, 15, 16: Both removed; OnePlus Watch 3 worn exclusively (1200/h = 3600)
        // Expected envelope: (1000 * 3) + (1200 * 3) = 6600 steps (zero double-counting at 8..10, full summation at 14..16!)
        let vitals = [
            HealthDailyVitalsRecord(
                id: "v_oura",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "Oura Ring",
                steps: 3000,
                activeKcal: 120,
                hourlySteps: [
                    HourlyStepBucket(hour: 8, steps: 1000),
                    HourlyStepBucket(hour: 9, steps: 1000),
                    HourlyStepBucket(hour: 10, steps: 1000)
                ]
            ),
            HealthDailyVitalsRecord(
                id: "v_pw5",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "Pixel Watch 5",
                steps: 2850,
                activeKcal: 115,
                hourlySteps: [
                    HourlyStepBucket(hour: 8, steps: 950),
                    HourlyStepBucket(hour: 9, steps: 950),
                    HourlyStepBucket(hour: 10, steps: 950)
                ]
            ),
            HealthDailyVitalsRecord(
                id: "v_opw3",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "OnePlus Watch 3",
                steps: 3600,
                activeKcal: 160,
                hourlySteps: [
                    HourlyStepBucket(hour: 14, steps: 1200),
                    HourlyStepBucket(hour: 15, steps: 1200),
                    HourlyStepBucket(hour: 16, steps: 1200)
                ]
            )
        ]
        
        let result = HealthDataService.arbitrateHourlyActivity(vitals: vitals, sources: [])
        #expect(result.totalSteps == 6600)
        #expect(result.activeCalories == 280) // 120 (Oura 100% contributed) + 160 (OPW3 100% contributed), PW5 0%
        #expect(result.sourceDevice == "OnePlus Watch 3") // Largest contributor (3600 > 3000)
    }
    
    @Test func testRecencyFirstSpotVitalsSpo2() throws {
        let userId = "user-test-123"
        let dateKey = "2026-11-05"
        
        let vitals = [
            HealthDailyVitalsRecord(
                id: "v_oura",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "Oura Ring",
                spo2: 97.5,
                vitalsTimestamps: ["spo2": "2026-11-05T07:00:00Z"]
            ),
            HealthDailyVitalsRecord(
                id: "v_opw3",
                userId: userId,
                localDate: dateKey,
                sourceDeviceKey: "OnePlus Watch 3",
                spo2: 99.0,
                vitalsTimestamps: ["spo2": "2026-11-05T15:30:00Z"]
            )
        ]
        
        let spot = HealthDataService.arbitrateSpotVital(
            vitals: vitals,
            timestampKey: "spo2",
            sources: [],
            extract: { $0.spo2 }
        )
        #expect(spot != nil)
        #expect(spot?.sourceDevice == "OnePlus Watch 3")
        #expect(spot?.value == 99.0)
    }

    @MainActor
    @Test("7-day retention fallback preserves archived cardiovascular HR curve & per-device filter when raw buckets are pruned")
    func historicalArchivedCurvePreservedWhenIntradayBucketsPruned() {
        let svc = HealthDataService()
        let pastDate = Date(timeIntervalSince1970: 1_761_000_000) // >7 days ago
        let archivedPts = [
            IntradayHeartRatePoint(timestamp: pastDate, bpm: 56, sourceDevice: "Oura Ring"),
            IntradayHeartRatePoint(timestamp: pastDate.addingTimeInterval(3600), bpm: 78, sourceDevice: "OnePlus Watch 3"),
            IntradayHeartRatePoint(timestamp: pastDate.addingTimeInterval(7200), bpm: 84, sourceDevice: "OnePlus Watch 3")
        ]
        svc.canonicalSummary = DailyHealthSummaryPayload(
            date: "2025-10-20",
            engineVersion: "v2.0",
            computedAt: pastDate.addingTimeInterval(10_000),
            sleep: CanonicalSleepSummary(),
            activity: CanonicalActivitySummary(totalSteps: 8200, activeCalories: 410),
            cardiovascular: CanonicalCardiovascularSummary(
                latestBpm: 84,
                latestBpmAt: pastDate.addingTimeInterval(7200),
                latestSourceDevice: "OnePlus Watch 3",
                averageBpm: 72.7,
                restingBpm: 54,
                minBpm: 56,
                maxBpm: 84,
                zones: CanonicalHeartRateZones(resting: 2, fatBurn: 1, cardio: 0, peak: 0),
                intradayPoints: archivedPts
            )
        )

        // All Devices mode with 0 rows in `health_intraday_heart_rate`
        svc.selectedDeviceFilter = nil
        svc.applyLeanIntradayHeartRate([], targetDate: pastDate)
        #expect(svc.intradayHeartRate.count == 3)
        #expect(svc.averageBpm == 72.7)
        #expect(svc.minBpm == 56)
        #expect(svc.maxBpm == 84)
        #expect(svc.heartRateZones[.resting] == 2)
        #expect(svc.resolvedLatestBpm == 84)

        // Per-device filter mode on >7d historical day
        svc.selectedDeviceFilter = "OnePlus Watch 3"
        svc.applyLeanIntradayHeartRate([], targetDate: pastDate)
        #expect(svc.intradayHeartRate.count == 2)
        #expect(svc.minBpm == 78)
        #expect(svc.maxBpm == 84)
    }

    @Test("Scalar sleep session projection decodes cleanly when stages JSONB is omitted")
    func scalarSleepSessionDecodesWithoutStagesJsonb() throws {
        let json = """
        {
          "id": "sleep_u1_2026-11-04_oura",
          "user_id": "u1",
          "local_date": "2026-11-04",
          "session_type": "primary_sleep",
          "source_device_key": "Oura Ring",
          "start_time": "2026-11-03T23:00:00Z",
          "end_time": "2026-11-04T06:30:00Z",
          "duration_seconds": 25200,
          "time_in_bed_seconds": 27000,
          "sleep_score": 88,
          "deep_seconds": 5400,
          "rem_seconds": 6000,
          "light_seconds": 13800,
          "awake_seconds": 1800,
          "source_priority": 1,
          "is_user_selected": false
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(HealthSleepSessionRecord.self, from: json)
        #expect(record.stages.isEmpty)
        #expect(record.hasGranularSleepStages == true)
        let uiSession = record.toSleepSession()
        #expect(uiSession.hasGranularHypnogram == true)
        #expect(uiSession.stages.count == 4)
    }

    @Test("Recency-aware stage painting lets newer reclassified HealthKit samples override older passes and coalesces adjacent stages")
    func testMultiPassRecencyAwareStageDeduplicationAndCoalescing() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let bedtime = cal.date(byAdding: .hour, value: -1, to: today)! // 23:00
        let t1 = today.addingTimeInterval(3600)   // Pass #1 written at 01:00
        let t2 = today.addingTimeInterval(18000)  // Pass #2 reclassified at 05:00

        // Pass #1: coarse 3h Light + 1h Light adjacent
        // Pass #2: newer reclassified 45m Deep inside [00:00..00:45], 45m REM inside [00:45..01:30] + 30m adjacent REM [01:30..02:00]
        // Also an earlier 1h Light at [02:00..03:00] and adjacent [03:00..04:00 Light]
        let telemetry: [HealthTelemetryRecord] = [
            HealthTelemetryRecord(
                id: "p1_block",
                userId: "u1",
                type: "sleep_stage_light",
                value: 300,
                unit: "minutes",
                startTime: bedtime,
                endTime: bedtime.addingTimeInterval(5 * 3600), // 23:00..04:00 (5h Light)
                sourceDevice: "Oura Ring",
                createdAt: t1
            ),
            HealthTelemetryRecord(
                id: "p2_deep",
                userId: "u1",
                type: "sleep_stage_deep",
                value: 45,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(3600),      // 00:00..00:45 Deep
                endTime: bedtime.addingTimeInterval(3600 + 2700),
                sourceDevice: "Oura Ring",
                createdAt: t2
            ),
            HealthTelemetryRecord(
                id: "p2_rem_1",
                userId: "u1",
                type: "sleep_stage_rem",
                value: 45,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(3600 + 2700), // 00:45..01:30 REM
                endTime: bedtime.addingTimeInterval(3600 + 5400),
                sourceDevice: "Oura Ring",
                createdAt: t2
            ),
            HealthTelemetryRecord(
                id: "p2_rem_2",
                userId: "u1",
                type: "sleep_stage_rem",
                value: 30,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(3600 + 5400), // 01:30..02:00 REM (adjacent!)
                endTime: bedtime.addingTimeInterval(3600 + 7200),
                sourceDevice: "Oura Ring",
                createdAt: t2
            ),
            HealthTelemetryRecord(
                id: "p2_light_tail",
                userId: "u1",
                type: "sleep_stage_light",
                value: 120,
                unit: "minutes",
                startTime: bedtime.addingTimeInterval(3600 + 7200), // 02:00..04:00 Light
                endTime: bedtime.addingTimeInterval(5 * 3600),
                sourceDevice: "Oura Ring",
                createdAt: t2
            )
        ]

        let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: telemetry)
        let primary = try #require(result.primarySession)

        #expect(Int(primary.deepSeconds.rounded()) == 2700)   // 45m
        #expect(Int(primary.remSeconds.rounded()) == 4500)    // 45m + 30m = 75m
        #expect(Int(primary.lightSeconds.rounded()) == 10800) // Remaining 1h (23:00-00:00) + 2h (02:00-04:00) = 3h
        #expect(Int(primary.asleepSeconds.rounded()) == 18000)
        // Adjacent REM [00:45..01:30] + [01:30..02:00] must coalesce into 1 stage -> 4 total blocks (Light, Deep, REM, Light)
        #expect(primary.stages.count == 4)
    }

    @Test("SleepStageRecord encodes explicit UTC Z and decodes timezone-naive ISO as UTC")
    func testSleepStageRecordUtcZEncodingAndNaiveUtcDecoding() throws {
        let fixed = Date(timeIntervalSince1970: 1794704641) // 2026-11-15T01:04:01Z
        let stage = SleepStageRecord(
            id: "st1",
            stageType: .deep,
            startTime: fixed,
            endTime: fixed.addingTimeInterval(600),
            sourceDevice: "Oura Ring"
        )
        let data = try JSONEncoder().encode(stage)
        let encodedJson = String(data: data, encoding: .utf8) ?? ""
        #expect(encodedJson.contains("2026-11-15T01:04:01.000Z"))

        let naivePayload = """
        {
          "id": "st_naive",
          "stage_type": "REM",
          "start_time": "2026-11-15T01:04:01.000",
          "end_time": "2026-11-15T01:14:01.000",
          "duration_seconds": 600,
          "source_device": "Oura Ring"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SleepStageRecord.self, from: naivePayload)
        #expect(abs(decoded.startTime.timeIntervalSince1970 - fixed.timeIntervalSince1970) < 0.001)
        #expect(decoded.stageType == .rem)
    }

    @Test("mergeLeanSleepSessions accepts reclassified local stages when duration ties or coalesces while protecting against transient truncation")
    func testMergeLeanSleepSessionsReclassificationAndTruncationGuard() throws {
        let start = Date(timeIntervalSince1970: 1794704641)
        let end = start.addingTimeInterval(38670)
        let dummyStage = SleepStageRecord(id: "s1", stageType: .light, startTime: start, endTime: end)
        let remoteStages = (0..<81).map { i in
            SleepStageRecord(id: "r_\(i)", stageType: .light, startTime: start, endTime: start.addingTimeInterval(60))
        }
        let freshLocalStages = (0..<75).map { i in
            SleepStageRecord(id: "l_\(i)", stageType: i < 20 ? .deep : .rem, startTime: start, endTime: start.addingTimeInterval(60))
        }

        let remote = HealthSleepSessionRecord(
            id: "sleep_u1_2026-11-15_primary_sleep_oura_ring",
            userId: "u1",
            localDate: "2026-11-15",
            sessionType: "primary_sleep",
            sourceDeviceKey: "Oura Ring",
            hostDeviceName: "Schmitz",
            startTime: start,
            endTime: end,
            durationSeconds: 35460,
            timeInBedSeconds: 38670,
            deepSeconds: 5310,
            remSeconds: 5490,
            lightSeconds: 24660,
            awakeSeconds: 3210,
            stages: remoteStages,
            sourcePriority: 1,
            isUserSelected: true
        )

        let freshReclassifiedLocal = HealthSleepSessionRecord(
            id: "sleep_u1_2026-11-15_primary_sleep_oura_ring",
            userId: "u1",
            localDate: "2026-11-15",
            sessionType: "primary_sleep",
            sourceDeviceKey: "Oura Ring",
            hostDeviceName: "Schmitz",
            startTime: start,
            endTime: end,
            durationSeconds: 35460,
            timeInBedSeconds: 38670,
            deepSeconds: 6480,
            remSeconds: 6420,
            lightSeconds: 22560,
            awakeSeconds: 3210,
            stages: freshLocalStages,
            sourcePriority: 1,
            isUserSelected: false
        )

        let merged = HealthDataService.mergeLeanSleepSessions(
            remote: [remote],
            local: [freshReclassifiedLocal],
            preferFreshLocal: true
        )
        #expect(merged.count == 1)
        #expect(merged[0].deepSeconds == 6480)
        #expect(merged[0].remSeconds == 6420)
        #expect(merged[0].stages.count == 75)
        #expect(merged[0].isUserSelected == true)

        // Guard: transient partial read (13 minutes) must NOT overwrite full remote session
        let truncatedLocal = HealthSleepSessionRecord(
            id: "sleep_u1_2026-11-15_primary_sleep_oura_ring",
            userId: "u1",
            localDate: "2026-11-15",
            sessionType: "primary_sleep",
            sourceDeviceKey: "Oura Ring",
            hostDeviceName: "Schmitz",
            startTime: start,
            endTime: start.addingTimeInterval(780),
            durationSeconds: 780,
            timeInBedSeconds: 780,
            deepSeconds: 0,
            remSeconds: 0,
            lightSeconds: 780,
            awakeSeconds: 0,
            stages: [dummyStage],
            sourcePriority: 1
        )
        let guarded = HealthDataService.mergeLeanSleepSessions(
            remote: [remote],
            local: [truncatedLocal],
            preferFreshLocal: true
        )
        #expect(guarded.count == 1)
        #expect(guarded[0].durationSeconds == 35460)
        #expect(guarded[0].stages.count == 81)
    }

    @Test func testSleepUploadFingerprintPersistenceAndUserIsolation() throws {
        let suiteName = "com.intellidream.daily.tests.sleepfp.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let refDate = Date(timeIntervalSince1970: 1794744000) // 2026-11-15T12:00:00Z
        let start = Date(timeIntervalSince1970: 1794704640)
        let mid = start.addingTimeInterval(3600)
        let end = start.addingTimeInterval(7200)

        let sessionA = HealthSleepSessionRecord(
            id: "sleep_u1_2026-11-15_primary_sleep_oura_ring",
            userId: "user-a",
            localDate: "2026-11-15",
            sessionType: "primary_sleep",
            sourceDeviceKey: "Oura Ring",
            hostDeviceName: "Schmitz",
            startTime: start,
            endTime: end,
            durationSeconds: 7200,
            timeInBedSeconds: 7200,
            deepSeconds: 3600,
            remSeconds: 0,
            lightSeconds: 3600,
            awakeSeconds: 0,
            stages: [
                SleepStageRecord(id: "s1", stageType: .deep, startTime: start, endTime: mid),
                SleepStageRecord(id: "s2", stageType: .light, startTime: mid, endTime: end)
            ],
            sourcePriority: 1
        )

        let fp1 = SleepUploadFingerprintStore.computeFingerprint(for: [sessionA])
        #expect(fp1.hasPrefix("v2|"))
        #expect(fp1 == SleepUploadFingerprintStore.computeFingerprint(for: [sessionA]))

        // Saving today + stale 20-day-old entry prunes the stale one immediately
        let saved = SleepUploadFingerprintStore.saveEntry(
            dateKey: "2026-11-15",
            fingerprint: fp1,
            existing: ["2026-10-20": "v2|stale"],
            userDefaults: defaults,
            userId: "User-A",
            referenceDate: refDate,
            calendar: cal
        )
        #expect(saved["2026-11-15"] == fp1)
        #expect(saved["2026-10-20"] == nil)

        // Simulated cold launch loads persisted fingerprint for matching user (case-insensitive)
        let reloaded = SleepUploadFingerprintStore.load(
            userDefaults: defaults,
            userId: "user-a",
            referenceDate: refDate,
            calendar: cal
        )
        #expect(reloaded["2026-11-15"] == fp1)

        // User isolation: a different user never inherits cached fingerprints
        let otherUserLoaded = SleepUploadFingerprintStore.load(
            userDefaults: defaults,
            userId: "user-b",
            referenceDate: refDate,
            calendar: cal
        )
        #expect(otherUserLoaded.isEmpty)

        // Stage reclassification invalidates fingerprint even with identical duration & stage count
        let sessionReclassified = HealthSleepSessionRecord(
            id: "sleep_u1_2026-11-15_primary_sleep_oura_ring",
            userId: "user-a",
            localDate: "2026-11-15",
            sessionType: "primary_sleep",
            sourceDeviceKey: "Oura Ring",
            hostDeviceName: "Schmitz",
            startTime: start,
            endTime: end,
            durationSeconds: 7200,
            timeInBedSeconds: 7200,
            deepSeconds: 3600,
            remSeconds: 3600,
            lightSeconds: 0,
            awakeSeconds: 0,
            stages: [
                SleepStageRecord(id: "s1", stageType: .deep, startTime: start, endTime: mid),
                SleepStageRecord(id: "s2", stageType: .rem, startTime: mid, endTime: end)
            ],
            sourcePriority: 1
        )
        let fp2 = SleepUploadFingerprintStore.computeFingerprint(for: [sessionReclassified])
        #expect(fp2 != fp1)

        // Self-healing invalidation & sign-out clear
        let afterRemove = SleepUploadFingerprintStore.removeEntry(
            dateKey: "2026-11-15",
            existing: reloaded,
            userDefaults: defaults,
            userId: "user-a",
            referenceDate: refDate,
            calendar: cal
        )
        #expect(afterRemove.isEmpty)

        _ = SleepUploadFingerprintStore.saveEntry(
            dateKey: "2026-11-15",
            fingerprint: fp2,
            existing: [:],
            userDefaults: defaults,
            userId: "user-a",
            referenceDate: refDate,
            calendar: cal
        )
        SleepUploadFingerprintStore.clear(userDefaults: defaults)
        #expect(
            SleepUploadFingerprintStore.load(
                userDefaults: defaults,
                userId: "user-a",
                referenceDate: refDate,
                calendar: cal
            ).isEmpty
        )
    }

    @Test func testSleepUploadFingerprintStaleRemoteSelfHeal() {
        let start = Date(timeIntervalSince1970: 1794787560) // 2026-11-16T00:06:00Z
        let staleEnd = start.addingTimeInterval(25680)
        let fullEnd = start.addingTimeInterval(29160)

        let fullLocal = HealthSleepSessionRecord(
            id: "sleep_u1_2026-11-16_primary_sleep_pixel_watch_5",
            userId: "u1",
            localDate: "2026-11-16",
            sessionType: "primary_sleep",
            sourceDeviceKey: "Pixel Watch 5",
            hostDeviceName: "Trapper",
            startTime: start,
            endTime: fullEnd,
            durationSeconds: 28200,
            timeInBedSeconds: 29160,
            deepSeconds: 3660,
            remSeconds: 7380,
            lightSeconds: 17160,
            awakeSeconds: 960,
            stages: [
                SleepStageRecord(id: "s1", stageType: .deep, startTime: start, endTime: start.addingTimeInterval(3660)),
                SleepStageRecord(id: "s2", stageType: .rem, startTime: start.addingTimeInterval(3660), endTime: fullEnd)
            ],
            sourcePriority: 2
        )

        let staleRemote = HealthSleepSessionRecord(
            id: "sleep_u1_2026-11-16_primary_sleep_pixel_watch_5",
            userId: "u1",
            localDate: "2026-11-16",
            sessionType: "primary_sleep",
            sourceDeviceKey: "Pixel Watch 5",
            hostDeviceName: "Radar",
            startTime: start,
            endTime: staleEnd,
            durationSeconds: 24540,
            timeInBedSeconds: 25680,
            deepSeconds: 3600,
            remSeconds: 5700,
            lightSeconds: 15240,
            awakeSeconds: 1140,
            stages: [
                SleepStageRecord(id: "r1", stageType: .light, startTime: start, endTime: staleEnd)
            ],
            sourcePriority: 2
        )

        #expect(SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(local: [fullLocal], remote: [fullLocal]) == false)
        #expect(SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(local: [fullLocal], remote: nil) == false)
        #expect(SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(local: [fullLocal], remote: []) == true)
        #expect(SleepUploadFingerprintStore.shouldInvalidateStaleRemoteSleep(local: [fullLocal], remote: [staleRemote]) == true)
    }

    @Test func testAtomicSleepBridgeOverridesStaleDefaultsAndRejectsYesterdaySummary() async throws {
        let suiteName = "group.com.intellidream.daily.test.sleep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleep_bridge_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WidgetDataCoordinator.shared
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 9, minute: 30, second: 0, of: Date())!
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let todayKey = f.string(from: now)
        let yesterdayKey = f.string(from: yesterday)

        // 1. Simulate yesterday's canonical health summary sitting in UserDefaults alongside an ISO8601 timestamp
        let ySleep = SleepSession(
            id: "y-sleep",
            startTime: cal.date(byAdding: .hour, value: -31, to: now)!,
            endTime: cal.date(byAdding: .hour, value: -24, to: now)!,
            stages: [
                SleepStageRecord(
                    id: "ys1",
                    stageType: .deep,
                    startTime: cal.date(byAdding: .hour, value: -31, to: now)!,
                    endTime: cal.date(byAdding: .hour, value: -29, to: now)!
                )
            ],
            sourceDevice: "Oura Ring"
        )
        let yPayload = DailyHealthSummaryPayload(
            date: yesterdayKey,
            computedAt: yesterday,
            sleep: CanonicalSleepSummary(primarySession: ySleep, allSessions: [ySleep], naps: []),
            activity: CanonicalActivitySummary(totalSteps: 5000, activeCalories: 200),
            cardiovascular: CanonicalCardiovascularSummary()
        )
        let isoEncoder = JSONEncoder()
        isoEncoder.dateEncodingStrategy = .iso8601
        defaults.set(try isoEncoder.encode(yPayload), forKey: "health_daily_summary_\(yesterdayKey)")

        // Put a stale legacy sleep snapshot from yesterday in UserDefaults
        let staleLegacySnap = SleepWidgetSnapshot.from(session: ySleep, lastUpdated: yesterday)
        defaults.set(try JSONEncoder().encode(staleLegacySnap), forKey: "daily_sleep_widget_snapshot_v1")

        // Before today's data arrives, fetchSleepSnapshot must NOT serve yesterday's sleep
        let coldToday = coordinator.fetchSleepSnapshot(bridgeDirectoryURL: tempDir, defaults: defaults, now: now)
        #expect(coldToday.hasData == false)

        // 2. If today's ISO8601 canonical health summary exists in UserDefaults without a bridge file yet, decode succeeds
        let tSleep = SleepSession(
            id: "t-sleep",
            startTime: cal.date(byAdding: .hour, value: -8, to: now)!,
            endTime: cal.date(byAdding: .hour, value: -1, to: now)!,
            stages: [
                SleepStageRecord(
                    id: "ts1",
                    stageType: .deep,
                    startTime: cal.date(byAdding: .hour, value: -8, to: now)!,
                    endTime: cal.date(byAdding: .hour, value: -5, to: now)!
                ),
                SleepStageRecord(
                    id: "ts2",
                    stageType: .rem,
                    startTime: cal.date(byAdding: .hour, value: -5, to: now)!,
                    endTime: cal.date(byAdding: .hour, value: -3, to: now)!
                ),
                SleepStageRecord(
                    id: "ts3",
                    stageType: .light,
                    startTime: cal.date(byAdding: .hour, value: -3, to: now)!,
                    endTime: cal.date(byAdding: .hour, value: -1, to: now)!
                )
            ],
            sourceDevice: "Apple Watch Ultra 2",
            hasGranularHypnogram: true
        )
        let tPayload = DailyHealthSummaryPayload(
            date: todayKey,
            computedAt: now,
            sleep: CanonicalSleepSummary(primarySession: tSleep, allSessions: [tSleep], naps: []),
            activity: CanonicalActivitySummary(totalSteps: 1200, activeCalories: 60),
            cardiovascular: CanonicalCardiovascularSummary()
        )
        defaults.set(try isoEncoder.encode(tPayload), forKey: "health_daily_summary_\(todayKey)")
        let isoFallbackSnap = coordinator.fetchSleepSnapshot(bridgeDirectoryURL: tempDir, defaults: defaults, now: now)
        #expect(isoFallbackSnap.hasData == true)
        #expect(isoFallbackSnap.sourceDevice == "Apple Watch Ultra 2")
        #expect(isoFallbackSnap.sleepScore == tSleep.sleepScore)

        // 3. Atomic bridge file must override stale/older UserDefaults immediately
        coordinator.updateSleepSnapshot(
            from: tSleep,
            restingHeartRate: 54,
            hrvMs: 62,
            bridgeDirectoryURL: tempDir,
            defaults: defaults,
            now: now
        )
        // Corrupt/downgrade UserDefaults to simulate lagging cfprefsd process view
        defaults.set(try JSONEncoder().encode(SleepWidgetSnapshot.empty), forKey: "daily_sleep_widget_snapshot_v1")

        let bridgedSnap = coordinator.fetchSleepSnapshot(bridgeDirectoryURL: tempDir, defaults: defaults, now: now)
        #expect(bridgedSnap.hasData == true)
        #expect(bridgedSnap.restingHeartRate == 54)
        #expect(bridgedSnap.hrvMs == 62)
        #expect(bridgedSnap.totalAsleepFormatted == tSleep.totalAsleepFormatted)
    }

    @Test func testMorningBriefRejectsStaleYesterdayOrWrongSlotBriefingAndUsesLiveSnapshots() async throws {
        let suiteName = "group.com.intellidream.daily.test.brief.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brief_bridge_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WidgetDataCoordinator.shared
        let cal = Calendar.current
        let morningNow = cal.date(bySettingHour: 9, minute: 15, second: 0, of: Date())!
        let yesterday = cal.date(byAdding: .day, value: -1, to: morningNow)!

        // Write live Today Sleep
        let todaySleep = SleepSession(
            id: "live-sleep",
            startTime: cal.date(byAdding: .hour, value: -8, to: morningNow)!,
            endTime: cal.date(byAdding: .hour, value: -1, to: morningNow)!,
            stages: [
                SleepStageRecord(
                    id: "s1",
                    stageType: .deep,
                    startTime: cal.date(byAdding: .hour, value: -8, to: morningNow)!,
                    endTime: cal.date(byAdding: .hour, value: -1, to: morningNow)!
                )
            ],
            sourceDevice: "Oura Ring",
            hasGranularHypnogram: true
        )
        coordinator.updateSleepSnapshot(
            from: todaySleep,
            restingHeartRate: 51,
            hrvMs: 74,
            bridgeDirectoryURL: tempDir,
            defaults: defaults,
            now: morningNow
        )

        // Write live TagDoS
        let tagdosSnap = TagdosWidgetSnapshot(
            streams: [
                TagdosWidgetSnapshotStream(
                    id: "st1",
                    title: "Work",
                    drivingPillText: "Ship iOS sleep widget fix",
                    drivingPillType: "urgent",
                    activePillsCount: 2,
                    reminderTimeFormatted: "10:00",
                    pills: []
                )
            ],
            totalActivePills: 2,
            nextReminderFormatted: "10:00",
            lastUpdated: morningNow
        )
        coordinator.updateTagdosSnapshot(tagdosSnap, bridgeDirectoryURL: tempDir, defaults: defaults)

        // Simulate STALE yesterday SmartBriefingRecord lingering in UserDefaults
        let staleYesterdayBrief = SmartBriefingRecord(
            id: "old-brief",
            userId: "u1",
            timeSlot: BriefingTimeSlot.morning.rawValue,
            dataHash: "old",
            narrative: SmartBriefingNarrative(tagdosText: "Stale yesterday task"),
            metrics: SmartBriefingMetrics(weatherTemp: 2.0, weatherCondition: "Old Snow", sleepScore: 41, sleepDurationFormatted: "4h 10m"),
            isAiGenerated: false,
            createdAt: yesterday,
            updatedAt: yesterday
        )
        defaults.set(try JSONEncoder().encode(staleYesterdayBrief), forKey: "daily_smart_summary_cache_v4")

        let combinedWithStale = coordinator.fetchCombinedSnapshot(bridgeDirectoryURL: tempDir, defaults: defaults, now: morningNow)
        #expect(combinedWithStale.isMorningSlot == true)
        #expect(combinedWithStale.sleep.hasData == true)
        #expect(combinedWithStale.sleep.sleepScore == todaySleep.sleepScore)
        #expect(combinedWithStale.morningSummary?.topFocusText == "Focus: Ship iOS sleep widget fix")
        #expect(combinedWithStale.morningSummary?.sleepScore == todaySleep.sleepScore)
        #expect(combinedWithStale.morningSummary?.weatherCondition != "Old Snow")

        // Now write a valid today morning briefing atomically -> atomic bridge overrides UserDefaults
        let freshMorningBrief = SmartBriefingRecord(
            id: "fresh-brief",
            userId: "u1",
            timeSlot: BriefingTimeSlot.morning.rawValue,
            dataHash: "fresh",
            narrative: SmartBriefingNarrative(tagdosText: "Focus on iOS Sleep & Morning Brief"),
            metrics: SmartBriefingMetrics(weatherTemp: 16.0, weatherCondition: "Sunny", weatherIcon: "01d"),
            isAiGenerated: true,
            createdAt: morningNow,
            updatedAt: morningNow
        )
        coordinator.updateBriefingSnapshot(freshMorningBrief, bridgeDirectoryURL: tempDir, defaults: defaults)

        let combinedFresh = coordinator.fetchCombinedSnapshot(bridgeDirectoryURL: tempDir, defaults: defaults, now: morningNow)
        #expect(combinedFresh.morningSummary?.topFocusText == "Focus on iOS Sleep & Morning Brief")
        #expect(combinedFresh.morningSummary?.weatherTemp == 16.0)
        #expect(combinedFresh.morningSummary?.isAiGenerated == true)
        // Sleep still overlaid cleanly from live sleep snapshot
        #expect(combinedFresh.morningSummary?.sleepScore == todaySleep.sleepScore)
    }

    @Test func testBoundaryAlignedTimelineDatesAndRolloverTracker() async throws {
        let cal = Calendar.current
        let baseDay = cal.startOfDay(for: Date())

        let preFive = cal.date(bySettingHour: 4, minute: 52, second: 0, of: baseDay)!
        let nextFive = WidgetDataCoordinator.nextBoundaryAlignedDate(
            after: preFive,
            defaultIntervalMinutes: 15,
            boundaryHours: [0, 5, 12, 17, 21],
            calendar: cal
        )
        #expect(cal.component(.hour, from: nextFive) == 5)
        #expect(cal.component(.minute, from: nextFive) == 0)

        let preNoon = cal.date(bySettingHour: 11, minute: 53, second: 0, of: baseDay)!
        let nextNoon = WidgetDataCoordinator.nextBoundaryAlignedDate(
            after: preNoon,
            defaultIntervalMinutes: 15,
            boundaryHours: [0, 5, 12, 17, 21],
            calendar: cal
        )
        #expect(cal.component(.hour, from: nextNoon) == 12)
        #expect(cal.component(.minute, from: nextNoon) == 0)

        let preMidnight = cal.date(bySettingHour: 23, minute: 50, second: 0, of: baseDay)!
        let nextMidnight = WidgetDataCoordinator.nextBoundaryAlignedDate(
            after: preMidnight,
            defaultIntervalMinutes: 30,
            boundaryHours: [0, 6, 8, 10],
            calendar: cal
        )
        #expect(cal.component(.hour, from: nextMidnight) == 0)
        #expect(cal.component(.minute, from: nextMidnight) == 0)
        #expect(nextMidnight > preMidnight)

        let suiteName = "group.com.intellidream.daily.test.rollover.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let nineAm = cal.date(bySettingHour: 9, minute: 0, second: 0, of: baseDay)!
        let initial = WidgetDataCoordinator.shared.consumePendingWidgetRolloverReload(for: nineAm, defaults: defaults)
        #expect(initial.dayChanged == false)
        #expect(initial.slotChanged == false)

        let onePmSameDay = cal.date(bySettingHour: 13, minute: 0, second: 0, of: baseDay)!
        let afternoon = WidgetDataCoordinator.shared.consumePendingWidgetRolloverReload(for: onePmSameDay, defaults: defaults)
        #expect(afternoon.dayChanged == false)
        #expect(afternoon.slotChanged == true)

        let nextMorning = cal.date(byAdding: .day, value: 1, to: nineAm)!
        let rollover = WidgetDataCoordinator.shared.consumePendingWidgetRolloverReload(for: nextMorning, defaults: defaults)
        #expect(rollover.dayChanged == true)
        #expect(rollover.slotChanged == true)
    }

    @Test func testLegacyFlatSleepAndStressDefaultsRemainDecodableAlongsideDateEnvelopes() async throws {
        let suiteName = "group.com.intellidream.daily.test.compat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compat_bridge_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = WidgetDataCoordinator.shared
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 10, minute: 15, second: 0, of: Date())!

        let session = SleepSession(
            id: "compat-sleep",
            startTime: cal.date(byAdding: .hour, value: -8, to: now)!,
            endTime: cal.date(byAdding: .hour, value: -1, to: now)!,
            stages: [
                SleepStageRecord(
                    id: "cs1",
                    stageType: .deep,
                    startTime: cal.date(byAdding: .hour, value: -8, to: now)!,
                    endTime: cal.date(byAdding: .hour, value: -6, to: now)!
                ),
                SleepStageRecord(
                    id: "cs2",
                    stageType: .rem,
                    startTime: cal.date(byAdding: .hour, value: -6, to: now)!,
                    endTime: cal.date(byAdding: .hour, value: -4, to: now)!
                )
            ],
            sourceDevice: "Apple Watch Ultra 2",
            hasGranularHypnogram: true
        )

        coordinator.updateSleepSnapshot(
            from: session,
            restingHeartRate: 53,
            hrvMs: 68,
            bridgeDirectoryURL: tempDir,
            defaults: defaults,
            now: now
        )
        coordinator.updateStressSnapshot(
            score: 42,
            level: .calm,
            monkeyMood: .zen,
            advice: "Balanced nervous system.",
            hrvMs: 68,
            restingHeartRate: 53,
            parasympathetic: 61,
            sympathetic: 39,
            bridgeDirectoryURL: tempDir,
            defaults: defaults,
            now: now
        )

        // Legacy defaults keys must decode cleanly as flat SleepWidgetSnapshot / StressWidgetSnapshot
        let legacySleepData = try #require(defaults.data(forKey: "daily_sleep_widget_snapshot_v1"))
        let legacySleep = try JSONDecoder().decode(SleepWidgetSnapshot.self, from: legacySleepData)
        #expect(legacySleep.hasData == true)
        #expect(legacySleep.sleepScore == session.sleepScore)

        let legacyStressData = try #require(defaults.data(forKey: "daily_stress_widget_snapshot_v1"))
        let legacyStress = try JSONDecoder().decode(StressWidgetSnapshot.self, from: legacyStressData)
        #expect(legacyStress.hasData == true)
        #expect(legacyStress.stressScore == 42)

        // Explicit same-day clear via envelope overrides even without deleting summary/legacy keys
        coordinator.clearStressSnapshot(bridgeDirectoryURL: tempDir, defaults: defaults, now: now)
        let clearedStress = coordinator.fetchStressSnapshot(bridgeDirectoryURL: tempDir, defaults: defaults, now: now)
        #expect(clearedStress.hasData == false)
    }

    @Test func testBiphasicUntrackedGapSleepConsolidationAndSegments() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let prevDay = cal.date(byAdding: .day, value: -1, to: today)!

        // Episode 1: 22:18 -> 03:28 (REM 53m, Deep 39m, Light 182m, Awake 36m = 4h 34m asleep, 5h 10m in bed)
        let ep1Start = cal.date(bySettingHour: 22, minute: 18, second: 0, of: prevDay)!
        let r1End = ep1Start.addingTimeInterval(53 * 60)
        let d1End = r1End.addingTimeInterval(39 * 60)
        let l1End = d1End.addingTimeInterval(182 * 60)
        let ep1End = l1End.addingTimeInterval(36 * 60) // 03:28

        // Untracked break: 03:28 -> 05:31 (2h 03m = 123m >= 45m)
        // Episode 2: 05:31 -> 09:45 (REM 24m, Deep 35m, Light 146m, Awake 49m = 3h 25m asleep, 4h 14m in bed)
        let ep2Start = cal.date(bySettingHour: 5, minute: 31, second: 0, of: today)!
        let r2End = ep2Start.addingTimeInterval(24 * 60)
        let d2End = r2End.addingTimeInterval(35 * 60)
        let l2End = d2End.addingTimeInterval(146 * 60)
        let ep2End = l2End.addingTimeInterval(49 * 60) // 09:45

        // Plus an afternoon nap on the same wearable (14:15 -> 15:00) that MUST remain separate
        let napStart = cal.date(bySettingHour: 14, minute: 15, second: 0, of: today)!
        let napEnd = napStart.addingTimeInterval(45 * 60)

        for wearableName in ["Oura Ring", "Apple Watch Ultra 2", "OnePlus Watch 3"] {
            let telemetry = [
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_rem", value: 53, unit: "min", startTime: ep1Start, endTime: r1End, sourceDevice: wearableName),
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_deep", value: 39, unit: "min", startTime: r1End, endTime: d1End, sourceDevice: wearableName),
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_light", value: 182, unit: "min", startTime: d1End, endTime: l1End, sourceDevice: wearableName),
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_awake", value: 36, unit: "min", startTime: l1End, endTime: ep1End, sourceDevice: wearableName),
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_rem", value: 24, unit: "min", startTime: ep2Start, endTime: r2End, sourceDevice: wearableName),
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_deep", value: 35, unit: "min", startTime: r2End, endTime: d2End, sourceDevice: wearableName),
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_light", value: 146, unit: "min", startTime: d2End, endTime: l2End, sourceDevice: wearableName),
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_awake", value: 49, unit: "min", startTime: l2End, endTime: ep2End, sourceDevice: wearableName),
                HealthTelemetryRecord(userId: "u", type: "sleep_stage_light", value: 45, unit: "min", startTime: napStart, endTime: napEnd, sourceDevice: wearableName)
            ]

            let result = SleepClusteringEngine.clusterSleep(targetDate: today, telemetry: telemetry)
            #expect(result.allSessions.count == 1)
            #expect(result.naps.count == 1)

            let primary = try #require(result.primarySession)
            #expect(primary.startTime == ep1Start)
            #expect(primary.endTime == ep2End)
            #expect(Int(primary.asleepSeconds) == (274 + 205) * 60) // 7h 59m
            #expect(Int(primary.remSeconds) == 77 * 60)             // 1h 17m
            #expect(Int(primary.deepSeconds) == 74 * 60)            // 1h 14m
            #expect(Int(primary.awakeSeconds) == 85 * 60)           // No fake awake added for untracked break
            #expect(Int(primary.durationSeconds) == (310 + 254) * 60) // 9h 24m in bed (NOT 11h 27m)

            let segments = primary.sleepSegments
            #expect(segments.count == 2)
            #expect(Int(segments[0].asleepSeconds) == 274 * 60)
            #expect(Int(segments[1].asleepSeconds) == 205 * 60)
        }
    }

    @Test func testBiphasicSustainedAwakeEnvelopeAndSegments() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let prevDay = cal.date(byAdding: .day, value: -1, to: today)!

        // Continuous envelope 22:21 -> 09:38 with 2h 49m Awake bridge 03:18 -> 06:07
        let sStart = cal.date(bySettingHour: 22, minute: 21, second: 0, of: prevDay)!
        let a0End = sStart.addingTimeInterval(10 * 60)
        let r1End = a0End.addingTimeInterval(49 * 60)
        let d1End = r1End.addingTimeInterval(64 * 60)
        let l1End = d1End.addingTimeInterval(174 * 60) // 03:18
        let bridgeEnd = l1End.addingTimeInterval(169 * 60) // 06:07 (2h 49m Awake)
        let r2End = bridgeEnd.addingTimeInterval(48 * 60)
        let d2End = r2End.addingTimeInterval(35 * 60)
        let sEnd = d2End.addingTimeInterval(128 * 60) // 09:38

        let stages = [
            SleepStageRecord(stageType: .awake, startTime: sStart, endTime: a0End, durationSeconds: 10 * 60),
            SleepStageRecord(stageType: .rem, startTime: a0End, endTime: r1End, durationSeconds: 49 * 60),
            SleepStageRecord(stageType: .deep, startTime: r1End, endTime: d1End, durationSeconds: 64 * 60),
            SleepStageRecord(stageType: .light, startTime: d1End, endTime: l1End, durationSeconds: 174 * 60),
            SleepStageRecord(stageType: .awake, startTime: l1End, endTime: bridgeEnd, durationSeconds: 169 * 60),
            SleepStageRecord(stageType: .rem, startTime: bridgeEnd, endTime: r2End, durationSeconds: 48 * 60),
            SleepStageRecord(stageType: .deep, startTime: r2End, endTime: d2End, durationSeconds: 35 * 60),
            SleepStageRecord(stageType: .light, startTime: d2End, endTime: sEnd, durationSeconds: 128 * 60)
        ]

        let fullSession = SleepSession(
            startTime: sStart,
            endTime: sEnd,
            isNap: false,
            stages: stages,
            sourceDevice: "Pixel Watch 5",
            hasGranularHypnogram: true
        )

        #expect(Int(fullSession.asleepSeconds) == 498 * 60)   // 8h 18m
        #expect(Int(fullSession.durationSeconds) == 677 * 60) // 11h 17m
        #expect(Int(fullSession.remSeconds) == 97 * 60)       // 1h 37m
        #expect(Int(fullSession.deepSeconds) == 99 * 60)      // 1h 39m
        #expect(Int(fullSession.awakeSeconds) == 179 * 60)    // 2h 59m

        let segments = fullSession.sleepSegments
        #expect(segments.count == 2)
        #expect(Int(segments[0].asleepSeconds) == 287 * 60)   // 4h 47m
        #expect(Int(segments[0].awakeSeconds) == 10 * 60)     // 10m (excludes 2h 49m inter-segment bridge)
        #expect(Int(segments[1].asleepSeconds) == 211 * 60)   // 3h 31m
        #expect(Int(segments[1].awakeSeconds) == 0)
    }
}


