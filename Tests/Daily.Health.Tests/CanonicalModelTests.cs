using System;
using System.IO;
using System.Text.Json;
using Daily.Models.Health;
using SQLite;
using Xunit;

namespace Daily.Health.Tests
{
    public class CanonicalModelTests
    {
        [Fact]
        public void TestSerializationRoundtrip()
        {
            var summary = new HealthDailySummaryRecord
            {
                Id = "rec-12345",
                UserId = "user-abc",
                LocalDate = "2026-10-05",
                ComputedAt = "2026-10-05T20:00:00Z",
                EngineVersion = "1.0",
                Steps = 10450,
                ActiveKcal = 540.5,
                SleepAsleepS = 27000,
                SleepScore = 88,
                StressAvg = 28,
                Rhr = 58.0,
                HrvSdnn = 64.2,
                HrvRmssd = 48.0,
                Weight = 74.5,
                Spo2 = 98.0,
                Summary = new DailyHealthSummaryPayload
                {
                    Date = "2026-10-05",
                    Sources = new() { "Oura Ring", "Apple Watch" },
                    Sleep = new CanonicalSleepSummary
                    {
                        PrimarySession = new CanonicalSleepSession
                        {
                            StartTime = "2026-10-04T23:00:00Z",
                            EndTime = "2026-10-05T07:00:00Z",
                            DurationSeconds = 28800,
                            AsleepSeconds = 27000,
                            DeepSeconds = 7200,
                            RemSeconds = 6500,
                            LightSeconds = 13300,
                            AwakeSeconds = 1800,
                            AwakeCount = 2,
                            EfficiencyPercent = 94,
                            SleepScore = 88,
                            Tracker = "Oura Ring",
                            Stages = new()
                            {
                                new SleepStageRecord { Stage = "light", StartTime = "2026-10-04T23:00:00Z", EndTime = "2026-10-04T23:30:00Z", DurationSeconds = 1800 },
                                new SleepStageRecord { Stage = "deep", StartTime = "2026-10-04T23:30:00Z", EndTime = "2026-10-05T01:30:00Z", DurationSeconds = 7200 },
                                new SleepStageRecord { Stage = "rem", StartTime = "2026-10-05T01:30:00Z", EndTime = "2026-10-05T03:18:20Z", DurationSeconds = 6500 }
                            }
                        },
                        Guidance = new CanonicalSleepGuidance
                        {
                            Verdict = new CanonicalSleepVerdict
                            {
                                Status = "optimal",
                                Headline = "Peak Recharging",
                                Narrative = "Deep sleep exceeded baseline by 18%.",
                                ReadinessScore = 92
                            }
                        }
                    },
                    Stress = new CanonicalStressSummary
                    {
                        DailyAverageScore = 28,
                        CurrentScore = 22,
                        CurrentLevel = "calm",
                        MonkeyMood = "zen",
                        AutonomicBalance = new CanonicalAutonomicBalance
                        {
                            SympatheticPercent = 38,
                            ParasympatheticPercent = 62
                        },
                        BiometricDrivers = new CanonicalStressDrivers
                        {
                            BaselineHrvMs = 45.0,
                            CurrentHrvMs = 64.2,
                            RestingHeartRateBpm = 58.0,
                            CurrentSedentaryBpm = 62.0
                        }
                    },
                    Cardiovascular = new CanonicalCardiovascularSummary
                    {
                        RestingHeartRateBpm = 58.0,
                        AverageHeartRateBpm = 72.0,
                        HeartRateZones = new CanonicalHeartRateZones
                        {
                            RestingMinutes = 520,
                            FatBurnMinutes = 45,
                            CardioMinutes = 20,
                            PeakMinutes = 5
                        }
                    }
                }
            };

            var json = HealthJsonSerializer.Serialize(summary, indented: true);
            Assert.Contains("\"user_id\": \"user-abc\"", json);
            Assert.Contains("\"sleep_score\": 88", json);
            Assert.Contains("\"monkey_mood\": \"zen\"", json);

            var deserialized = HealthJsonSerializer.Deserialize<HealthDailySummaryRecord>(json);
            Assert.NotNull(deserialized);
            Assert.Equal("rec-12345", deserialized.Id);
            Assert.Equal(10450, deserialized.Steps);
            Assert.Equal(88, deserialized.SleepScore);
            Assert.Equal("optimal", deserialized.Summary?.Sleep?.Guidance?.Verdict?.Status);
            Assert.Equal("zen", deserialized.Summary?.Stress?.MonkeyMood);
            Assert.Equal(62, deserialized.Summary?.Stress?.AutonomicBalance?.ParasympatheticPercent);
        }

        [Fact]
        public void TestSQLiteCacheStorageAndRetrieval()
        {
            SQLitePCL.Batteries_V2.Init();
            var dbPath = Path.Combine(Path.GetTempPath(), $"test_daily_{Guid.NewGuid():N}.db");
            try
            {
                using var conn = new SQLiteConnection(dbPath);
                conn.CreateTable<HealthDailySummaryEntity>();

                var entity = new HealthDailySummaryEntity
                {
                    LocalDate = "2026-10-05",
                    UserId = "user-123",
                    Steps = 9800,
                    SleepScore = 84,
                    StressAvg = 31,
                    Rhr = 60.5,
                    HrvSdnn = 55.0,
                    SummaryJson = "{\"sample\": true}",
                    UpdatedAtTimestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                };

                conn.InsertOrReplace(entity);

                var retrieved = conn.Find<HealthDailySummaryEntity>("2026-10-05");
                Assert.NotNull(retrieved);
                Assert.Equal("2026-10-05", retrieved.LocalDate);
                Assert.Equal(9800, retrieved.Steps);
                Assert.Equal(84, retrieved.SleepScore);
                Assert.Equal(31, retrieved.StressAvg);
                Assert.Equal(60.5, retrieved.Rhr);
                Assert.Equal("{\"sample\": true}", retrieved.SummaryJson);
                conn.Close();
            }
            finally
            {
                if (File.Exists(dbPath))
                {
                    File.Delete(dbPath);
                }
            }
        }

        [Fact]
        public void TestNaiveAndExplicitUtcIsoTimestampsParseEquivalently()
        {
            var fallback = new DateTime(2026, 11, 15, 0, 0, 0, DateTimeKind.Local);
            var fromExplicitZ = HealthSleepSessionRecord.ParseUtcToLocal("2026-11-15T01:04:01.000Z", fallback);
            var fromNaive = HealthSleepSessionRecord.ParseUtcToLocal("2026-11-15T01:04:01.000", fallback);

            Assert.Equal(fromExplicitZ, fromNaive);

            var expectedUtc = new DateTimeOffset(2026, 11, 15, 1, 4, 1, TimeSpan.Zero);
            Assert.Equal(expectedUtc.LocalDateTime, fromNaive);

            var lean = new HealthSleepSessionRecord
            {
                Id = "sleep_u1_2026-11-15_primary_sleep_oura_ring",
                UserId = "u1",
                LocalDate = "2026-11-15",
                SourceDeviceKey = "Oura Ring",
                StartTime = "2026-11-15T01:04:01.000Z",
                EndTime = "2026-11-15T11:48:31.000Z",
                DurationSeconds = 35460,
                DeepSeconds = 6480,
                RemSeconds = 6420,
                LightSeconds = 22560,
                AwakeSeconds = 3210,
                Stages = new List<SleepStageRecord>
                {
                    new SleepStageRecord
                    {
                        Stage = "deep",
                        StartTime = "2026-11-15T01:04:01.000",
                        EndTime = "2026-11-15T02:52:01.000",
                        DurationSeconds = 6480
                    }
                }
            };

            var domain = lean.ToDomainSleepSession(new DateTime(2026, 11, 15));
            Assert.Single(domain.Stages);
            Assert.Equal(domain.StartTime, domain.Stages[0].StartTime);
            Assert.Equal(18, domain.DeepPercent);
            Assert.Equal(18, domain.RemPercent);
        }

        [Fact]
        public void TestLeanStageDurationDerivedFromTimestampsWhenOmitted()
        {
            var json = """
            {
                "id": "sleep_u1_2026-11-16_primary_sleep_pixel_watch_5",
                "user_id": "u1",
                "local_date": "2026-11-16",
                "source_device_key": "Pixel Watch 5",
                "start_time": "2026-11-16T00:06:00Z",
                "end_time": "2026-11-16T08:12:00Z",
                "duration_seconds": 28200,
                "deep_seconds": 3660,
                "rem_seconds": 7380,
                "light_seconds": 17160,
                "awake_seconds": 960,
                "stages": [
                    {
                        "id": "s1",
                        "stage_type": "REM",
                        "start_time": "2026-11-16T04:42:00Z",
                        "end_time": "2026-11-16T05:13:00Z",
                        "source_device": "Pixel Watch 5"
                    }
                ]
            }
            """;

            var record = HealthJsonSerializer.Deserialize<HealthSleepSessionRecord>(json);
            Assert.NotNull(record);
            var session = record!.ToDomainSleepSession(new DateTime(2026, 11, 16));
            Assert.Single(session.Stages);
            Assert.Equal(1860, session.Stages[0].DurationSeconds);
            Assert.Equal(7380, session.RemSeconds);
            Assert.Equal(3660, session.DeepSeconds);
            Assert.Equal(26, session.RemPercent);
            Assert.Equal(13, session.DeepPercent);
        }

        [Fact]
        public void TestBiphasicSleepUntrackedGapAndSustainedAwakeSegments()
        {
            // 1. Untracked break >= 45m (22:18 -> 03:28, break 2h03m, 05:31 -> 09:45)
            var ep1Start = new DateTime(2026, 11, 17, 22, 18, 0);
            var r1End = ep1Start.AddMinutes(53);
            var d1End = r1End.AddMinutes(39);
            var l1End = d1End.AddMinutes(182);
            var ep1End = l1End.AddMinutes(36); // 03:28

            var ep2Start = new DateTime(2026, 11, 18, 5, 31, 0);
            var r2End = ep2Start.AddMinutes(24);
            var d2End = r2End.AddMinutes(35);
            var l2End = d2End.AddMinutes(146);
            var ep2End = l2End.AddMinutes(49); // 09:45

            var splitSession = new SleepSession
            {
                StartTime = ep1Start,
                EndTime = ep2End,
                SourceDevice = "Oura Ring",
                HasGranularHypnogram = true,
                Stages = new System.Collections.Generic.List<HealthTelemetry>
                {
                    new() { TypeString = "sleep_stage_rem", StartTime = ep1Start, EndTime = r1End, Value = 53 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_deep", StartTime = r1End, EndTime = d1End, Value = 39 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_light", StartTime = d1End, EndTime = l1End, Value = 182 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_awake", StartTime = l1End, EndTime = ep1End, Value = 36 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_rem", StartTime = ep2Start, EndTime = r2End, Value = 24 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_deep", StartTime = r2End, EndTime = d2End, Value = 35 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_light", StartTime = d2End, EndTime = l2End, Value = 146 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_awake", StartTime = l2End, EndTime = ep2End, Value = 49 * 60, Unit = "sec" }
                }
            };

            Assert.Equal(479 * 60, splitSession.AsleepSeconds);
            Assert.Equal(564 * 60, splitSession.DurationSeconds); // 9h 24m (subtracts 2h 03m untracked break)
            Assert.Equal(ep2End, splitSession.EffectiveEndTime);  // Wake time stays 09:45!

            var segments = splitSession.GetSleepSegments();
            Assert.Equal(2, segments.Count);
            Assert.Equal(274 * 60, segments[0].AsleepSeconds);
            Assert.Equal(205 * 60, segments[1].AsleepSeconds);

            // 2. Continuous session with 2h 49m Awake bridge (03:18 -> 06:07)
            var sStart = new DateTime(2026, 11, 17, 22, 21, 0);
            var a0End = sStart.AddMinutes(10);
            var s1End = a0End.AddMinutes(287); // 03:18
            var bridgeEnd = s1End.AddMinutes(169); // 06:07
            var s2End = bridgeEnd.AddMinutes(211); // 09:38

            var envelopeSession = new SleepSession
            {
                StartTime = sStart,
                EndTime = s2End,
                SourceDevice = "Pixel Watch 5",
                HasGranularHypnogram = true,
                Stages = new System.Collections.Generic.List<HealthTelemetry>
                {
                    new() { TypeString = "sleep_stage_awake", StartTime = sStart, EndTime = a0End, Value = 10 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_light", StartTime = a0End, EndTime = s1End, Value = 287 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_awake", StartTime = s1End, EndTime = bridgeEnd, Value = 169 * 60, Unit = "sec" },
                    new() { TypeString = "sleep_stage_light", StartTime = bridgeEnd, EndTime = s2End, Value = 211 * 60, Unit = "sec" }
                }
            };

            Assert.Equal(498 * 60, envelopeSession.AsleepSeconds);
            Assert.Equal(677 * 60, envelopeSession.DurationSeconds);
            Assert.Equal(179 * 60, envelopeSession.AwakeSeconds);

            var envSegments = envelopeSession.GetSleepSegments();
            Assert.Equal(2, envSegments.Count);
            Assert.Equal(287 * 60, envSegments[0].AsleepSeconds);
            Assert.Equal(10 * 60, envSegments[0].AwakeSeconds);
            Assert.Equal(211 * 60, envSegments[1].AsleepSeconds);
            Assert.Equal(0, envSegments[1].AwakeSeconds);
        }
    }
}
