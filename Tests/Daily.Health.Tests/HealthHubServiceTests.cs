using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Daily.Models;
using Daily.Models.Health;
using Daily.Services;
using Daily_WinUI.Services;
using SQLite;
using Xunit;

namespace Daily.Health.Tests
{
    public class MockDatabaseService : IDatabaseService
    {
        private readonly SQLiteAsyncConnection _connection;

        public MockDatabaseService(string dbPath)
        {
            SQLitePCL.Batteries_V2.Init();
            _connection = new SQLiteAsyncConnection(dbPath);
        }

        public SQLiteAsyncConnection Connection => _connection;

        public async Task InitializeAsync()
        {
            await _connection.CreateTableAsync<HealthDailySummaryEntity>();
        }

        public Task BackupDatabaseAsync(string destinationPath) => Task.CompletedTask;
        public Task RestoreDatabaseAsync(string sourcePath) => Task.CompletedTask;
    }

    public class MockSettingsService : ISettingsService
    {
        public UserPreferences Settings { get; } = new();
        public bool IsAuthenticated => false;
        public string? CurrentUserEmail => null;
        public string? CurrentUserAvatarUrl => null;
        public string? CurrentUserId => "test-user-id";
        public event Action? OnSettingsChanged;

        public Task InitializeAsync() => Task.CompletedTask;
        public Task SaveSettingsAsync() => Task.CompletedTask;
        public Task ReloadFromDatabaseAsync() => Task.CompletedTask;
    }

    public class HealthHubServiceTests
    {
        [Fact]
        public async Task TestOfflineColdStartAndMetricMapping()
        {
            var dbPath = Path.Combine(Path.GetTempPath(), $"test_hub_{Guid.NewGuid():N}.db");
            try
            {
                var mockDb = new MockDatabaseService(dbPath);
                await mockDb.InitializeAsync();

                var testDate = new DateTime(2026, 10, 5);
                var testDateStr = testDate.ToString("yyyy-MM-dd");

                // Seed SQLite cache entity
                var payload = new DailyHealthSummaryPayload
                {
                    Date = testDateStr,
                    Sources = new() { "Oura Ring Gen3" },
                    Sleep = new CanonicalSleepSummary
                    {
                        PrimarySession = new CanonicalSleepSession
                        {
                            StartTime = "2026-10-04T22:30:00Z",
                            EndTime = "2026-10-05T06:30:00Z",
                            DurationSeconds = 28800,
                            AsleepSeconds = 26400,
                            DeepSeconds = 7200,
                            RemSeconds = 6000,
                            LightSeconds = 13200,
                            AwakeSeconds = 2400,
                            SleepScore = 91,
                            Tracker = "Oura Ring Gen3",
                            Stages = new()
                            {
                                new SleepStageRecord { Stage = "light", StartTime = "2026-10-04T22:30:00Z", EndTime = "2026-10-04T23:00:00Z", DurationSeconds = 1800 },
                                new SleepStageRecord { Stage = "deep", StartTime = "2026-10-04T23:00:00Z", EndTime = "2026-10-05T01:00:00Z", DurationSeconds = 7200 }
                            }
                        }
                    },
                    Cardiovascular = new CanonicalCardiovascularSummary
                    {
                        RestingHeartRateBpm = 52.0,
                        AverageHeartRateBpm = 70.0,
                        IntradayHeartRate = new()
                        {
                            new IntradayHeartRatePoint { Timestamp = "2026-10-05T08:00:00Z", Bpm = 68.0 },
                            new IntradayHeartRatePoint { Timestamp = "2026-10-05T12:00:00Z", Bpm = 85.0 }
                        }
                    },
                    Activity = new CanonicalActivitySummary
                    {
                        TotalSteps = 10500,
                        ActiveCaloriesKcal = 441.0,
                        HourlySteps = new()
                        {
                            new HourlyStepBucket { Hour = 8, Steps = 1200, ActiveCalories = 50.0 },
                            new HourlyStepBucket { Hour = 14, Steps = 3500, ActiveCalories = 150.0 }
                        }
                    },
                    Stress = new CanonicalStressSummary
                    {
                        DailyAverageScore = 19,
                        CurrentScore = 15,
                        CurrentLevel = "calm",
                        MonkeyMood = "zen"
                    }
                };

                var entity = new HealthDailySummaryEntity
                {
                    LocalDate = testDateStr,
                    UserId = "test-user-id",
                    ComputedAt = "2026-10-05T07:00:00Z",
                    EngineVersion = "1.0",
                    Steps = 10500,
                    ActiveKcal = 441.0,
                    SleepAsleepS = 26400,
                    SleepScore = 91,
                    StressAvg = 19,
                    Rhr = 52.0,
                    SummaryJson = HealthJsonSerializer.Serialize(payload),
                    UpdatedAtTimestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                };

                await mockDb.Connection.InsertAsync(entity);

                // Create client and mock service
                var options = new Supabase.SupabaseOptions { AutoConnectRealtime = false };
                var client = new Supabase.Client("https://dummy.supabase.co", "dummy_key", options);
                var mockSettings = new MockSettingsService();

                var hubService = new HealthHubService(client, mockDb, mockSettings);

                // Test 1: Fetch daily summary loads from SQLite in < 300ms
                var sw = System.Diagnostics.Stopwatch.StartNew();
                var summary = await hubService.GetDailySummaryAsync(testDate);
                sw.Stop();

                Assert.NotNull(summary);
                Assert.True(sw.ElapsedMilliseconds < 300, $"Cold load should be < 300ms, was {sw.ElapsedMilliseconds}ms");
                Assert.Equal(10500, summary.Steps);
                Assert.Equal(91, summary.SleepScore);
                Assert.Equal(19, summary.StressAvg);
                Assert.Equal(52.0, summary.Rhr);

                // Test 2: FetchMetricsForDate maps honest values
                var metrics = await hubService.FetchMetricsForDateAsync(testDate);
                Assert.NotEmpty(metrics);
                var stepsMetric = metrics.FirstOrDefault(m => m.Type == VitalType.Steps);
                var rhrMetric = metrics.FirstOrDefault(m => m.Type == VitalType.RestingHeartRate);
                var stressMetric = metrics.FirstOrDefault(m => m.Type == VitalType.Stress);

                Assert.NotNull(stepsMetric);
                Assert.Equal(10500, stepsMetric.Value);
                Assert.NotNull(rhrMetric);
                Assert.Equal(52.0, rhrMetric.Value);
                Assert.NotNull(stressMetric);
                Assert.Equal(19, stressMetric.Value);

                // Test 3: GetSleepSessionsAsync correctly parses primary session and hypnogram
                var (primarySession, allSessions) = await hubService.GetSleepSessionsAsync(testDate);
                Assert.NotNull(primarySession);
                Assert.Equal(26400, primarySession.AsleepSeconds);
                Assert.Equal(91, primarySession.SleepScore);
                Assert.Equal("Oura Ring Gen3", primarySession.Stages.First().SourceDevice);
                Assert.Equal(2, primarySession.Stages.Count);

                // Test 4: GetHealthTelemetryAsync returns intraday heart rate and steps
                var telemetry = await hubService.GetHealthTelemetryAsync(testDate, testDate);
                Assert.NotEmpty(telemetry);
                Assert.Contains(telemetry, t => t.TypeString == "heart_rate" && t.Value == 68.0);
                Assert.Contains(telemetry, t => t.TypeString == "steps" && t.Value == 1200);

                // Test 5: Empty day has NO fake data
                var emptyDate = testDate.AddDays(-10);
                var emptySummary = await hubService.GetDailySummaryAsync(emptyDate);
                Assert.Null(emptySummary); // ZERO fake generation
                var emptyMetrics = await hubService.FetchMetricsForDateAsync(emptyDate);
                Assert.Empty(emptyMetrics); // Honest empty state
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
        public async Task TestFiveTabPayloadAndStressParity()
        {
            var dbPath = Path.Combine(Path.GetTempPath(), $"test_hub_tabs_{Guid.NewGuid():N}.db");
            try
            {
                var mockDb = new MockDatabaseService(dbPath);
                await mockDb.InitializeAsync();

                var testDate = new DateTime(2026, 10, 5);
                var testDateStr = testDate.ToString("yyyy-MM-dd");

                var payload = new DailyHealthSummaryPayload
                {
                    Date = testDateStr,
                    Sources = new() { "Oura Ring Gen3", "Apple Watch Series 10" },
                    Sleep = new CanonicalSleepSummary
                    {
                        PrimarySession = new CanonicalSleepSession
                        {
                            StartTime = "2026-10-04T22:30:00Z",
                            EndTime = "2026-10-05T06:30:00Z",
                            DurationSeconds = 28800,
                            AsleepSeconds = 26400,
                            SleepScore = 91,
                            Tracker = "Oura Ring Gen3",
                            Stages = new()
                            {
                                new SleepStageRecord { Stage = "light", StartTime = "2026-10-04T22:30:00Z", EndTime = "2026-10-04T23:00:00Z", DurationSeconds = 1800 },
                                new SleepStageRecord { Stage = "deep", StartTime = "2026-10-04T23:00:00Z", EndTime = "2026-10-05T01:00:00Z", DurationSeconds = 7200 },
                                new SleepStageRecord { Stage = "rem", StartTime = "2026-10-05T01:00:00Z", EndTime = "2026-10-05T02:30:00Z", DurationSeconds = 5400 }
                            }
                        },
                        Guidance = new CanonicalSleepGuidance
                        {
                            Verdict = new CanonicalSleepVerdict
                            {
                                Headline = "Optimal Sleep Quality",
                                Narrative = "Optimal sleep architecture with solid deep and REM cycles."
                            }
                        }
                    },
                    Stress = new CanonicalStressSummary
                    {
                        DailyAverageScore = 18,
                        CurrentScore = 14,
                        CurrentLevel = "restful",
                        MonkeyMood = "zen",
                        AutonomicBalance = new CanonicalAutonomicBalance
                        {
                            SympatheticPercent = 35,
                            ParasympatheticPercent = 65
                        },
                        BiometricDrivers = new CanonicalStressDrivers
                        {
                            BaselineHrvMs = 60.0,
                            CurrentHrvMs = 45.0,
                            RestingHeartRateBpm = 49.0
                        }
                    },
                    Cardiovascular = new CanonicalCardiovascularSummary
                    {
                        RestingHeartRateBpm = 49.0,
                        AverageHeartRateBpm = 64.0,
                        MinHeartRateBpm = 46.0,
                        MaxHeartRateBpm = 118.0,
                        HeartRateZones = new CanonicalHeartRateZones
                        {
                            RestingMinutes = 900,
                            FatBurnMinutes = 200,
                            CardioMinutes = 60,
                            PeakMinutes = 10
                        }
                    },
                    Activity = new CanonicalActivitySummary
                    {
                        TotalSteps = 12450,
                        ActiveCaloriesKcal = 510.0,
                        HourlySteps = Enumerable.Range(0, 24).Select(h => new HourlyStepBucket
                        {
                            Hour = h,
                            Steps = (h >= 7 && h <= 21) ? 800 : 50,
                            ActiveCalories = (h >= 7 && h <= 21) ? 35.0 : 2.0
                        }).ToList()
                    }
                };

                var entity = new HealthDailySummaryEntity
                {
                    LocalDate = testDateStr,
                    UserId = "test-user-id",
                    ComputedAt = "2026-10-05T07:00:00Z",
                    Steps = 12450,
                    ActiveKcal = 510.0,
                    SleepAsleepS = 26400,
                    SleepScore = 91,
                    StressAvg = 18,
                    Rhr = 49.0,
                    HrvSdnn = 68.0,
                    Spo2 = 98.0,
                    Weight = 74.5,
                    SummaryJson = HealthJsonSerializer.Serialize(payload),
                    UpdatedAtTimestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                };

                await mockDb.Connection.InsertAsync(entity);

                var options = new Supabase.SupabaseOptions { AutoConnectRealtime = false };
                var client = new Supabase.Client("https://dummy.supabase.co", "dummy_key", options);
                var mockSettings = new MockSettingsService();
                var hubService = new HealthHubService(client, mockDb, mockSettings);

                // Verify Payload
                var extracted = await hubService.GetPayloadForDateAsync(testDate);
                Assert.NotNull(extracted);
                Assert.Equal("zen", extracted.Stress?.MonkeyMood);
                Assert.Equal(35, extracted.Stress?.AutonomicBalance?.SympatheticPercent);
                Assert.Equal(65, extracted.Stress?.AutonomicBalance?.ParasympatheticPercent);
                Assert.Equal(49.0, extracted.Cardiovascular?.RestingHeartRateBpm);
                Assert.Equal(12450, extracted.Activity?.TotalSteps);
                Assert.Equal(24, extracted.Activity?.HourlySteps?.Count);
                Assert.Equal("Optimal sleep architecture with solid deep and REM cycles.", extracted.Sleep?.Guidance?.Verdict?.Narrative);

                // Verify Metrics
                var metrics = await hubService.FetchMetricsForDateAsync(testDate);
                Assert.Contains(metrics, m => m.Type == VitalType.Steps && m.Value == 12450);
                Assert.Contains(metrics, m => m.Type == VitalType.RestingHeartRate && m.Value == 49.0);
                Assert.Contains(metrics, m => m.Type == VitalType.HeartRateVariabilitySDNN && m.Value == 68.0);
                Assert.Contains(metrics, m => m.Type == VitalType.OxygenSaturation && m.Value == 98.0);
                Assert.Contains(metrics, m => m.Type == VitalType.Weight && m.Value == 74.5);
                Assert.Contains(metrics, m => m.Type == VitalType.Stress && m.Value == 18);
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
        public async Task TestDateRangeAndHistoryIntegrity()
        {
            var dbPath = Path.Combine(Path.GetTempPath(), $"test_hub_range_{Guid.NewGuid():N}.db");
            try
            {
                var mockDb = new MockDatabaseService(dbPath);
                await mockDb.InitializeAsync();

                var baseDate = new DateTime(2026, 10, 1);
                for (int i = 0; i < 5; i++)
                {
                    var dt = baseDate.AddDays(i);
                    var entity = new HealthDailySummaryEntity
                    {
                        LocalDate = dt.ToString("yyyy-MM-dd"),
                        UserId = "test-user-id",
                        Steps = 8000 + (i * 500),
                        Rhr = 55.0 - i,
                        SleepAsleepS = 25000 + (i * 300),
                        StressAvg = 20 - i,
                        UpdatedAtTimestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                    };
                    await mockDb.Connection.InsertAsync(entity);
                }

                var options = new Supabase.SupabaseOptions { AutoConnectRealtime = false };
                var client = new Supabase.Client("https://dummy.supabase.co", "dummy_key", options);
                var mockSettings = new MockSettingsService();
                var hubService = new HealthHubService(client, mockDb, mockSettings);

                // Range query
                var range = await hubService.GetDailySummariesRangeAsync(baseDate, baseDate.AddDays(4));
                Assert.Equal(5, range.Count);
                Assert.Equal(8000, range[0].Steps);
                Assert.Equal(10000, range[4].Steps);

                // History queries
                var stepsHistory = await hubService.GetHistoryAsync(VitalType.Steps, 5);
                Assert.NotEmpty(stepsHistory);
                Assert.All(stepsHistory, h => Assert.True(h.Value >= 8000));
            }
            finally
            {
                if (File.Exists(dbPath))
                {
                    File.Delete(dbPath);
                }
            }
        }
    }
}
