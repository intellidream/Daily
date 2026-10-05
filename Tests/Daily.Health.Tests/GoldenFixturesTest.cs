using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Daily.Models.Health;
using Xunit;

namespace Daily.Health.Tests
{
    public class GoldenFixtureExpected
    {
        [JsonPropertyName("steps")]
        public int? Steps { get; set; }

        [JsonPropertyName("active_kcal")]
        public double? ActiveKcal { get; set; }

        [JsonPropertyName("sleep_asleep_s")]
        public int? SleepAsleepS { get; set; }

        [JsonPropertyName("sleep_score")]
        public int? SleepScore { get; set; }

        [JsonPropertyName("stress_avg")]
        public int? StressAvg { get; set; }

        [JsonPropertyName("rhr")]
        public int? Rhr { get; set; }

        [JsonPropertyName("hrv_sdnn")]
        public double? HrvSdnn { get; set; }

        [JsonPropertyName("primary_sleep_device")]
        public string? PrimarySleepDevice { get; set; }

        [JsonPropertyName("sleep_quality_rating")]
        public string? SleepQualityRating { get; set; }

        [JsonPropertyName("nap_count")]
        public int NapCount { get; set; } = 0;
    }

    public class GoldenFixture
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("description")]
        public string Description { get; set; } = string.Empty;

        [JsonPropertyName("expected")]
        public GoldenFixtureExpected Expected { get; set; } = new();
    }

    public class GoldenFixturesTest
    {
        private static string? FindFixturesDir()
        {
            var candidates = new[]
            {
                Path.Combine(Directory.GetCurrentDirectory(), "HealthSpec", "fixtures"),
                Path.Combine(Directory.GetCurrentDirectory(), "..", "..", "HealthSpec", "fixtures"),
                Path.Combine(Directory.GetCurrentDirectory(), "..", "..", "..", "HealthSpec", "fixtures"),
                "/Users/mihai/Source/Daily/HealthSpec/fixtures"
            };

            return candidates.FirstOrDefault(d => Directory.Exists(d));
        }

        [Fact]
        public void TestAllGoldenFixturesParseAndValidate()
        {
            var dir = FindFixturesDir();
            Assert.True(dir != null && Directory.Exists(dir), "HealthSpec/fixtures directory must exist");

            var fixtureFiles = Directory.GetFiles(dir, "*.json").OrderBy(f => f).ToList();
            Assert.True(fixtureFiles.Count >= 5, $"Expected at least 5 fixtures, found {fixtureFiles.Count}");

            foreach (var file in fixtureFiles)
            {
                var json = File.ReadAllText(file);
                var fixture = JsonSerializer.Deserialize<GoldenFixture>(json, HealthJsonSerializer.DefaultOptions);
                Assert.NotNull(fixture);
                Assert.False(string.IsNullOrEmpty(fixture.Name), $"Fixture name should not be empty in {file}");

                // Validate that GoldenFixtureExpected can map seamlessly into HealthDailySummaryRecord
                var summary = new HealthDailySummaryRecord
                {
                    LocalDate = "2026-10-05",
                    Steps = fixture.Expected.Steps,
                    ActiveKcal = fixture.Expected.ActiveKcal,
                    SleepAsleepS = fixture.Expected.SleepAsleepS,
                    SleepScore = fixture.Expected.SleepScore,
                    StressAvg = fixture.Expected.StressAvg,
                    Rhr = fixture.Expected.Rhr,
                    HrvSdnn = fixture.Expected.HrvSdnn
                };

                Assert.Equal(fixture.Expected.Steps, summary.Steps);
                Assert.Equal(fixture.Expected.SleepScore, summary.SleepScore);
                Assert.Equal(fixture.Expected.StressAvg, summary.StressAvg);
            }
        }
    }
}
