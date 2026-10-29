using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Daily.Models;
using Daily_WinUI.Services.Cosmos;
using Xunit;

namespace Daily.Health.Tests
{
    public class CosmosGoldenVectorTests
    {
        private sealed class ExpectedXY
        {
            [JsonPropertyName("x")] public double X { get; set; }
            [JsonPropertyName("y")] public double Y { get; set; }
        }

        private sealed class CameraProjectionCase
        {
            [JsonPropertyName("name")] public string Name { get; set; } = "";
            [JsonPropertyName("camAz")] public double CamAz { get; set; }
            [JsonPropertyName("camAlt")] public double CamAlt { get; set; }
            [JsonPropertyName("fov")] public double Fov { get; set; }
            [JsonPropertyName("width")] public double Width { get; set; }
            [JsonPropertyName("height")] public double Height { get; set; }
            [JsonPropertyName("targetAz")] public double TargetAz { get; set; }
            [JsonPropertyName("targetAlt")] public double TargetAlt { get; set; }
            [JsonPropertyName("expected")] public ExpectedXY? Expected { get; set; }
        }

        private sealed class StarEqjCase
        {
            [JsonPropertyName("name")] public string Name { get; set; } = "";
            [JsonPropertyName("raHours")] public double RaHours { get; set; }
            [JsonPropertyName("decDeg")] public double DecDeg { get; set; }
            [JsonPropertyName("lat")] public double Lat { get; set; }
            [JsonPropertyName("lon")] public double Lon { get; set; }
            [JsonPropertyName("utc")] public string Utc { get; set; } = "";
            [JsonPropertyName("expectedAzDeg")] public double ExpectedAzDeg { get; set; }
            [JsonPropertyName("expectedAltDeg")] public double ExpectedAltDeg { get; set; }
            [JsonPropertyName("expectedHorNWZ")] public List<double> ExpectedHorNWZ { get; set; } = new();
        }

        private sealed class MoonMetricsCase
        {
            [JsonPropertyName("utc")] public string Utc { get; set; } = "";
            [JsonPropertyName("lat")] public double Lat { get; set; }
            [JsonPropertyName("lon")] public double Lon { get; set; }
            [JsonPropertyName("expectedGeoDistanceKm")] public double ExpectedGeoDistanceKm { get; set; }
            [JsonPropertyName("expectedTopoDistanceKm")] public double ExpectedTopoDistanceKm { get; set; }
            [JsonPropertyName("expectedPhaseFraction")] public double ExpectedPhaseFraction { get; set; }
            [JsonPropertyName("expectedBrightLimbDeg")] public double ExpectedBrightLimbDeg { get; set; }
        }

        private sealed class GalileanMoonVector
        {
            [JsonPropertyName("name")] public string Name { get; set; } = "";
            [JsonPropertyName("offsetRightRadii")] public double OffsetRightRadii { get; set; }
            [JsonPropertyName("offsetUpRadii")] public double OffsetUpRadii { get; set; }
            [JsonPropertyName("depthRadii")] public double DepthRadii { get; set; }
        }

        private sealed class JupiterGalileanCase
        {
            [JsonPropertyName("utc")] public string Utc { get; set; } = "";
            [JsonPropertyName("lat")] public double Lat { get; set; }
            [JsonPropertyName("lon")] public double Lon { get; set; }
            [JsonPropertyName("moons")] public List<GalileanMoonVector> Moons { get; set; } = new();
        }

        private sealed class TopocentricIss
        {
            [JsonPropertyName("utc")] public string Utc { get; set; } = "";
            [JsonPropertyName("lat")] public double Lat { get; set; }
            [JsonPropertyName("lon")] public double Lon { get; set; }
            [JsonPropertyName("elevM")] public double ElevM { get; set; }
            [JsonPropertyName("azDeg")] public double AzDeg { get; set; }
            [JsonPropertyName("altDeg")] public double AltDeg { get; set; }
            [JsonPropertyName("rangeKm")] public double RangeKm { get; set; }
        }

        private sealed class Sgp4Case
        {
            [JsonPropertyName("omm")] public CelesTrakOmmRecord Omm { get; set; } = new();
            [JsonPropertyName("temeAtEpochKm")] public List<double> TemeAtEpochKm { get; set; } = new();
            [JsonPropertyName("temePlus45MinKm")] public List<double> TemePlus45MinKm { get; set; } = new();
            [JsonPropertyName("topocentricPlus45Min")] public TopocentricIss TopocentricPlus45Min { get; set; } = new();
        }

        private sealed class ScoreCase
        {
            [JsonPropertyName("name")] public string Name { get; set; } = "";
            [JsonPropertyName("cloudLow")] public double CloudLow { get; set; }
            [JsonPropertyName("cloudMid")] public double CloudMid { get; set; }
            [JsonPropertyName("cloudHigh")] public double CloudHigh { get; set; }
            [JsonPropertyName("moonIllum")] public double MoonIllum { get; set; }
            [JsonPropertyName("moonAltDeg")] public double MoonAltDeg { get; set; }
            [JsonPropertyName("bortle")] public int Bortle { get; set; }
            [JsonPropertyName("seeingArcsec")] public double SeeingArcsec { get; set; }
            [JsonPropertyName("tempC")] public double TempC { get; set; }
            [JsonPropertyName("dewPointC")] public double DewPointC { get; set; }
            [JsonPropertyName("expectedScore")] public int ExpectedScore { get; set; }
        }

        private sealed class GoldenFixture
        {
            [JsonPropertyName("cameraProjectionCases")] public List<CameraProjectionCase> CameraProjectionCases { get; set; } = new();
            [JsonPropertyName("starEqjToHorCases")] public List<StarEqjCase> StarEqjToHorCases { get; set; } = new();
            [JsonPropertyName("moonMetricsCase")] public MoonMetricsCase MoonMetricsCase { get; set; } = new();
            [JsonPropertyName("jupiterGalileanMoonsCase")] public JupiterGalileanCase JupiterGalileanMoonsCase { get; set; } = new();
            [JsonPropertyName("sgp4IssCase")] public Sgp4Case Sgp4IssCase { get; set; } = new();
            [JsonPropertyName("stargazingScoreCases")] public List<ScoreCase> StargazingScoreCases { get; set; } = new();
        }

        private static string ResolveRepoRoot()
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir != null; i++)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Tests", "Fixtures", "cosmos_golden_vectors.json")))
                    return dir.FullName;
                dir = dir.Parent;
            }
            throw new DirectoryNotFoundException("Repository root with Tests/Fixtures/cosmos_golden_vectors.json not found.");
        }

        private static GoldenFixture LoadFixture()
        {
            string path = Path.Combine(ResolveRepoRoot(), "Tests", "Fixtures", "cosmos_golden_vectors.json");
            return JsonSerializer.Deserialize<GoldenFixture>(File.ReadAllText(path))!;
        }

        [Fact]
        public void GoldenCameraProjectionAndStarEqjToHorParity()
        {
            var fx = LoadFixture();
            var svc = AstronomyService.Shared;

            foreach (var c in fx.CameraProjectionCases)
            {
                var actual = svc.ProjectHorizontal(c.TargetAz, c.TargetAlt, c.CamAz, c.CamAlt, c.Fov, c.Width, c.Height);
                if (c.Expected != null)
                {
                    Assert.NotNull(actual);
                    Assert.Equal(c.Expected.X, actual!.Value.x, 2);
                    Assert.Equal(c.Expected.Y, actual.Value.y, 2);
                }
                else
                {
                    Assert.Null(actual);
                }
            }

            foreach (var sc in fx.StarEqjToHorCases)
            {
                var utc = DateTimeOffset.Parse(sc.Utc, CultureInfo.InvariantCulture).UtcDateTime;
                var r = svc.StarHorizontalCoordinates(sc.RaHours, sc.DecDeg, utc, sc.Lat, sc.Lon, 0.0, true);
                Assert.Equal(sc.ExpectedAzDeg, r.AzimuthDegrees, 2);
                Assert.Equal(sc.ExpectedAltDeg, r.AltitudeDegrees, 2);
                Assert.Equal(sc.ExpectedHorNWZ[0], r.Hx, 4);
                Assert.Equal(sc.ExpectedHorNWZ[1], r.Hy, 4);
                Assert.Equal(sc.ExpectedHorNWZ[2], r.Hz, 4);
            }
        }

        [Fact]
        public void GoldenMoonDistanceBrightLimbGalileanSgp4AndCatalogs()
        {
            var fx = LoadFixture();
            var svc = AstronomyService.Shared;

            var mUtc = DateTimeOffset.Parse(fx.MoonMetricsCase.Utc, CultureInfo.InvariantCulture).UtcDateTime;
            var moon = svc.GetMoonPhase(mUtc, fx.MoonMetricsCase.Lat, fx.MoonMetricsCase.Lon);
            Assert.InRange(moon.DistanceKm, 350_000.0, 410_000.0);
            Assert.True(Math.Abs(fx.MoonMetricsCase.ExpectedGeoDistanceKm - moon.DistanceKm) <= 5.0);
            Assert.True(Math.Abs(fx.MoonMetricsCase.ExpectedTopoDistanceKm - moon.TopocentricDistanceKm!.Value) <= 5.0);
            Assert.Equal(fx.MoonMetricsCase.ExpectedBrightLimbDeg, moon.BrightLimbAngleDegrees, 1);

            var jUtc = DateTimeOffset.Parse(fx.JupiterGalileanMoonsCase.Utc, CultureInfo.InvariantCulture).UtcDateTime;
            var moons = svc.GetJupiterMoons(jUtc, fx.JupiterGalileanMoonsCase.Lat, fx.JupiterGalileanMoonsCase.Lon).All;
            for (int i = 0; i < 4; i++)
            {
                Assert.Equal(fx.JupiterGalileanMoonsCase.Moons[i].Name, moons[i].Name);
                Assert.Equal(fx.JupiterGalileanMoonsCase.Moons[i].OffsetRightRadii, moons[i].XRadius, 1);
                Assert.Equal(fx.JupiterGalileanMoonsCase.Moons[i].OffsetUpRadii, moons[i].YRadius, 1);
                Assert.Equal(fx.JupiterGalileanMoonsCase.Moons[i].DepthRadii, moons[i].DepthRadius, 1);
            }

            var sgp = fx.Sgp4IssCase;
            var teme0 = SGP4Propagator.PropagateTemeKm(sgp.Omm, 0.0);
            Assert.NotNull(teme0);
            Assert.True(Math.Abs(sgp.TemeAtEpochKm[0] - teme0!.Value.X) <= 0.1);
            var sUtc = DateTimeOffset.Parse(sgp.TopocentricPlus45Min.Utc, CultureInfo.InvariantCulture).UtcDateTime;
            var pos = SGP4Propagator.LivePosition(sgp.Omm, sUtc, sgp.TopocentricPlus45Min.Lat, sgp.TopocentricPlus45Min.Lon, sgp.TopocentricPlus45Min.ElevM);
            Assert.NotNull(pos);
            Assert.True(Math.Abs(sgp.TopocentricPlus45Min.AzDeg - pos!.AzimuthDegrees) <= 0.1);
            Assert.True(Math.Abs(sgp.TopocentricPlus45Min.AltDeg - pos.AltitudeDegrees) <= 0.1);

            foreach (var sc in fx.StargazingScoreCases)
            {
                int actual = AstronomyService.ComputeDeterministicSkyScore(
                    sc.CloudLow, sc.CloudMid, sc.CloudHigh, sc.MoonIllum, sc.MoonAltDeg,
                    sc.Bortle, sc.SeeingArcsec, sc.TempC, sc.DewPointC);
                Assert.Equal(sc.ExpectedScore, actual);
            }

            var repo = new CosmosCatalogRepository();
            repo.LoadSynchronously(Path.Combine(ResolveRepoRoot(), "WinUI", "Daily.WinUI", "Assets", "Cosmos"));
            Assert.True(repo.PackedStars.Count >= 15_000);
            Assert.Equal(88, repo.Constellations.Count);
            Assert.Equal(219, repo.DeepSkyObjects.Count);
            Assert.Equal(22, repo.MeteorShowers.Count);
            Assert.Equal(14, repo.Asterisms.Count);
            Assert.Equal(5, repo.MilkyWayLayers.Count);
        }
    }
}
