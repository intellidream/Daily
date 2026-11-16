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
    }
}
