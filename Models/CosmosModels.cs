using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models
{
    public enum CelestialBody
    {
        Sun,
        Moon,
        Mercury,
        Venus,
        Mars,
        Jupiter,
        Saturn,
        Uranus,
        Neptune
    }

    public static class CelestialBodyExtensions
    {
        public static readonly CelestialBody[] MajorPlanets =
        {
            CelestialBody.Mercury,
            CelestialBody.Venus,
            CelestialBody.Mars,
            CelestialBody.Jupiter,
            CelestialBody.Saturn,
            CelestialBody.Uranus,
            CelestialBody.Neptune
        };

        public static string DisplayName(this CelestialBody body) => body.ToString();

        public static string Symbol(this CelestialBody body) => body switch
        {
            CelestialBody.Sun => "☉",
            CelestialBody.Moon => "☽",
            CelestialBody.Mercury => "☿",
            CelestialBody.Venus => "♀",
            CelestialBody.Mars => "♂",
            CelestialBody.Jupiter => "♃",
            CelestialBody.Saturn => "♄",
            CelestialBody.Uranus => "♅",
            CelestialBody.Neptune => "♆",
            _ => "★"
        };
    }

    public enum TelemetryProvenanceKind
    {
        Live,
        Cached,
        OfflineCalculated,
        Unavailable
    }

    public class TelemetryProvenance
    {
        public TelemetryProvenanceKind Kind { get; set; } = TelemetryProvenanceKind.OfflineCalculated;
        public long? AgeSeconds { get; set; }
        public string SourceName { get; set; } = string.Empty;

        public string BadgeText => Kind switch
        {
            TelemetryProvenanceKind.Live => "LIVE",
            TelemetryProvenanceKind.Cached => AgeSeconds is long s
                ? (s < 3600 ? $"CACHED {Math.Max(1, s / 60)}m" : $"CACHED {s / 3600}h")
                : "CACHED",
            TelemetryProvenanceKind.OfflineCalculated => "EPHEMERIS",
            _ => "OFFLINE"
        };

        public static TelemetryProvenance Live(string source = "") =>
            new() { Kind = TelemetryProvenanceKind.Live, SourceName = source };

        public static TelemetryProvenance Cached(long ageSeconds, string source = "") =>
            new() { Kind = TelemetryProvenanceKind.Cached, AgeSeconds = ageSeconds, SourceName = source };

        public static TelemetryProvenance OfflineCalculated(string source = "Offline Ephemeris") =>
            new() { Kind = TelemetryProvenanceKind.OfflineCalculated, SourceName = source };

        public static TelemetryProvenance Unavailable(string reason = "") =>
            new() { Kind = TelemetryProvenanceKind.Unavailable, SourceName = reason };
    }

    public enum MoonPhaseQuarter
    {
        NewMoon,
        WaxingCrescent,
        FirstQuarter,
        WaxingGibbous,
        FullMoon,
        WaningGibbous,
        ThirdQuarter,
        WaningCrescent
    }

    public enum StargazingQuality
    {
        Excellent,
        Good,
        Fair,
        Poor
    }

    public class CelestialCoordinates
    {
        public CelestialBody Body { get; set; }
        public double RightAscension { get; set; }
        public double Declination { get; set; }
        public double Azimuth { get; set; }
        public double Altitude { get; set; }
        public double DistanceAu { get; set; }
        public double? Magnitude { get; set; }
        public double? IlluminatedFraction { get; set; }
        public double? BrightLimbAngleDegrees { get; set; }
        public double? AngularDiameterArcsec { get; set; }
        public bool IsAboveHorizon => Altitude > 0.0;
    }

    public class RiseTransitSetTimes
    {
        public DateTime? RiseTimeUtc { get; set; }
        public DateTime? TransitTimeUtc { get; set; }
        public DateTime? SetTimeUtc { get; set; }
    }

    public class MoonPhaseInfo
    {
        public double PhaseAngleDegrees { get; set; }
        public double IlluminatedFraction { get; set; }
        public MoonPhaseQuarter Quarter { get; set; }
        public string Description { get; set; } = string.Empty;
        public double AgeDays { get; set; }
        public bool IsWaxing { get; set; }
        public double DistanceKm { get; set; }
        public double? TopocentricDistanceKm { get; set; }
        public double BrightLimbAngleDegrees { get; set; }
        public int IlluminationPercent => (int)Math.Round(IlluminatedFraction * 100.0);
    }

    public class SunTimes
    {
        public DateTime? DawnAstronomicalUtc { get; set; }
        public DateTime? DawnNauticalUtc { get; set; }
        public DateTime? DawnCivilUtc { get; set; }
        public DateTime? SunriseUtc { get; set; }
        public DateTime? SolarNoonUtc { get; set; }
        public DateTime? SunsetUtc { get; set; }
        public DateTime? DuskCivilUtc { get; set; }
        public DateTime? DuskNauticalUtc { get; set; }
        public DateTime? DuskAstronomicalUtc { get; set; }
    }

    public class CircadianSkyContext
    {
        public DateTime? TrueDarknessOnsetUtc { get; set; }
        public double NaturalMoonlightLux { get; set; }
        public string Summary { get; set; } = string.Empty;
    }

    public class MoonVector2D
    {
        public string Name { get; set; } = string.Empty;
        public double XRadius { get; set; }
        public double YRadius { get; set; }
        public double DepthRadius { get; set; }
        public bool IsFrontOfPlanet { get; set; }
        public bool IsTransiting => (XRadius * XRadius + YRadius * YRadius < 1.0) && IsFrontOfPlanet;
        public bool IsOcculted => (XRadius * XRadius + YRadius * YRadius < 1.0) && !IsFrontOfPlanet;
    }

    public class JupiterMoonsState
    {
        public MoonVector2D Io { get; set; } = new();
        public MoonVector2D Europa { get; set; } = new();
        public MoonVector2D Ganymede { get; set; } = new();
        public MoonVector2D Callisto { get; set; } = new();
        public IReadOnlyList<MoonVector2D> All => new[] { Io, Europa, Ganymede, Callisto };
    }

    public class StargazingConditions
    {
        public StargazingQuality Quality { get; set; } = StargazingQuality.Fair;
        public int Score { get; set; }
        public double CloudCover { get; set; }
        public int? CloudCoverTotalPercent { get; set; }
        public int? CloudCoverLowPercent { get; set; }
        public int? CloudCoverMidPercent { get; set; }
        public int? CloudCoverHighPercent { get; set; }
        public double MoonIllumination { get; set; }
        public bool IsMoonAboveHorizon { get; set; }
        public double? SeeingArcseconds { get; set; }
        public string Seeing { get; set; } = "Unavailable offline";
        public string Transparency { get; set; } = "Estimated from Bortle";
        public double? DewPointDepressionCelsius { get; set; }
        public int LightPollutionBortle { get; set; } = 5;
        public double LimitingMagnitude { get; set; } = 5.8;
        public string? BestWindowDescription { get; set; }
        public string Summary { get; set; } = string.Empty;
        public TelemetryProvenance Provenance { get; set; } = TelemetryProvenance.OfflineCalculated();
    }

    // ── Satellites (SGP4), Space Weather & APOD ──────────────────────────────

    public class CelesTrakOmmRecord
    {
        [JsonPropertyName("OBJECT_NAME")]
        public string ObjectName { get; set; } = "ISS (ZARYA)";

        [JsonPropertyName("OBJECT_ID")]
        public string? ObjectId { get; set; }

        [JsonPropertyName("NORAD_CAT_ID")]
        public int NoradCatId { get; set; } = 25544;

        [JsonPropertyName("EPOCH")]
        public string Epoch { get; set; } = string.Empty;

        [JsonPropertyName("MEAN_MOTION")]
        public double MeanMotion { get; set; }

        [JsonPropertyName("ECCENTRICITY")]
        public double Eccentricity { get; set; }

        [JsonPropertyName("INCLINATION")]
        public double Inclination { get; set; }

        [JsonPropertyName("RA_OF_ASC_NODE")]
        public double RaOfAscNode { get; set; }

        [JsonPropertyName("ARG_OF_PERICENTER")]
        public double ArgOfPericenter { get; set; }

        [JsonPropertyName("MEAN_ANOMALY")]
        public double MeanAnomaly { get; set; }

        [JsonPropertyName("BSTAR")]
        public double? Bstar { get; set; }
    }

    public class SatelliteTrajectorySample
    {
        public DateTime TimestampUtc { get; set; }
        public double AzimuthDegrees { get; set; }
        public double AltitudeDegrees { get; set; }
        public bool IsSunlit { get; set; }
    }

    public class SatellitePass
    {
        public string Id { get; set; } = string.Empty;
        public string SatelliteName { get; set; } = "ISS (ZARYA)";
        public int NoradCatalogNumber { get; set; } = 25544;
        public DateTime StartTimeUtc { get; set; }
        public DateTime MaxAltitudeTimeUtc { get; set; }
        public DateTime EndTimeUtc { get; set; }
        public double MaxAltitudeDegrees { get; set; }
        public double StartAzimuthDegrees { get; set; }
        public double MaxAzimuthDegrees { get; set; }
        public double EndAzimuthDegrees { get; set; }
        public string StartCompass { get; set; } = string.Empty;
        public string EndCompass { get; set; } = string.Empty;
        public double PeakMagnitude { get; set; }
        public bool IsSunlit { get; set; }
        public List<SatelliteTrajectorySample> Trajectory { get; set; } = new();
        public int DurationMinutes => Math.Max(1, (int)Math.Round((EndTimeUtc - StartTimeUtc).TotalMinutes));
    }

    public class LiveSatellitePosition
    {
        public string SatelliteName { get; set; } = "ISS (ZARYA)";
        public int NoradCatalogNumber { get; set; } = 25544;
        public DateTime TimestampUtc { get; set; }
        public double AzimuthDegrees { get; set; }
        public double AltitudeDegrees { get; set; }
        public double RangeKm { get; set; }
        public double OrbitalAltitudeKm { get; set; }
        public double SubSatelliteLatitude { get; set; }
        public double SubSatelliteLongitude { get; set; }
        public bool IsSunlit { get; set; }
        public double EstimatedMagnitude { get; set; }
    }

    public class SpaceWeatherReport
    {
        public double? KpIndex { get; set; }
        public double? BtTotalFieldNt { get; set; }
        public double? BzMagneticFieldNt { get; set; }
        public double? SolarWindSpeedKmS { get; set; }
        public double? SolarWindDensityCm3 { get; set; }
        public int? OvationProbabilityPercent { get; set; }
        public bool IsAuroraAlertActive { get; set; }
        public string StatusMessage { get; set; } = "Space weather unavailable offline.";
        public TelemetryProvenance Provenance { get; set; } = TelemetryProvenance.Unavailable("Offline");
    }

    public class ApodResponse
    {
        [JsonPropertyName("date")]
        public string Date { get; set; } = string.Empty;

        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("explanation")]
        public string Explanation { get; set; } = string.Empty;

        [JsonPropertyName("url")]
        public string Url { get; set; } = string.Empty;

        [JsonPropertyName("hdurl")]
        public string? HdUrl { get; set; }

        [JsonPropertyName("media_type")]
        public string MediaType { get; set; } = "image";

        [JsonPropertyName("copyright")]
        public string? Copyright { get; set; }
    }

    // ── Canonical Sky Catalog Records ────────────────────────────────────────

    public sealed class PackedStarCatalog
    {
        public static readonly PackedStarCatalog Empty = new(
            0, Array.Empty<int>(), Array.Empty<float>(), Array.Empty<float>(), Array.Empty<float>(),
            Array.Empty<float>(), Array.Empty<float>(), Array.Empty<float>(), Array.Empty<float>(),
            Array.Empty<ushort>(), Array.Empty<uint>(), new Dictionary<int, int>()
        );

        public int Count { get; }
        public int[] HipIds { get; }
        public float[] Ux { get; }
        public float[] Uy { get; }
        public float[] Uz { get; }
        public float[] RaHours { get; }
        public float[] DecDegrees { get; }
        public float[] VMag { get; }
        public float[] Bv { get; }
        public ushort[] ConstellationIndex { get; }
        public uint[] PackedArgbColors { get; }
        public IReadOnlyDictionary<int, int> IndexByHip { get; }

        public PackedStarCatalog(
            int count,
            int[] hipIds,
            float[] ux,
            float[] uy,
            float[] uz,
            float[] raHours,
            float[] decDegrees,
            float[] vMag,
            float[] bv,
            ushort[] constellationIndex,
            uint[] packedArgbColors,
            IReadOnlyDictionary<int, int> indexByHip)
        {
            Count = count;
            HipIds = hipIds;
            Ux = ux;
            Uy = uy;
            Uz = uz;
            RaHours = raHours;
            DecDegrees = decDegrees;
            VMag = vMag;
            Bv = bv;
            ConstellationIndex = constellationIndex;
            PackedArgbColors = packedArgbColors;
            IndexByHip = indexByHip;
        }

        public static (byte R, byte G, byte B) BallesterosRgb(double bv)
        {
            double c = Math.Clamp(bv, -0.40, 2.00);
            double t = 4600.0 * (1.0 / (0.92 * c + 1.7) + 1.0 / (0.92 * c + 0.62));
            double tk = t / 100.0;
            double r, g, b;
            if (tk <= 66.0)
            {
                r = 1.0;
                g = Math.Clamp(0.3900815787690196 * Math.Log(Math.Max(1.0, tk)) - 0.6318414437886275, 0.0, 1.0);
                b = tk <= 19.0
                    ? 0.0
                    : Math.Clamp(0.5432067891101961 * Math.Log(Math.Max(1.0, tk - 10.0)) - 1.19625408914, 0.0, 1.0);
            }
            else
            {
                r = Math.Clamp(1.292936186062745 * Math.Pow(tk - 60.0, -0.1332047592), 0.0, 1.0);
                g = Math.Clamp(1.129890860895294 * Math.Pow(tk - 60.0, -0.0755148492), 0.0, 1.0);
                b = 1.0;
            }
            return (
                (byte)Math.Clamp((int)Math.Round(r * 255.0), 0, 255),
                (byte)Math.Clamp((int)Math.Round(g * 255.0), 0, 255),
                (byte)Math.Clamp((int)Math.Round(b * 255.0), 0, 255)
            );
        }
    }

    public class StarDesignationRecord
    {
        [JsonPropertyName("hip")]
        public int Hip { get; set; }

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("bayer")]
        public string? Bayer { get; set; }

        [JsonPropertyName("flam")]
        public string? Flam { get; set; }

        [JsonPropertyName("hd")]
        public string? Hd { get; set; }

        [JsonPropertyName("constellation")]
        public string? Constellation { get; set; }

        public string PrimaryLabel
        {
            get
            {
                if (!string.IsNullOrWhiteSpace(Name)) return Name;
                if (!string.IsNullOrWhiteSpace(Bayer) && !Bayer.Contains("undefined") && !string.IsNullOrWhiteSpace(Constellation))
                    return $"{Bayer} {Constellation}";
                if (!string.IsNullOrWhiteSpace(Flam) && !string.IsNullOrWhiteSpace(Constellation))
                    return $"{Flam} {Constellation}";
                return $"HIP {Hip}";
            }
        }
    }

    public class CosmosStar
    {
        public int Hip { get; set; }

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("bayer")]
        public string? Bayer { get; set; }

        [JsonPropertyName("constellation")]
        public string Constellation { get; set; } = string.Empty;

        [JsonPropertyName("raHours")]
        public double RaHours { get; set; }

        [JsonPropertyName("decDegrees")]
        public double DecDegrees { get; set; }

        [JsonPropertyName("mag")]
        public double Mag { get; set; }

        [JsonPropertyName("colorIndexBV")]
        public double ColorIndexBV { get; set; }

        [JsonPropertyName("colorHex")]
        public string ColorHex { get; set; } = "#FFFFFF";
    }

    public class CosmosConstellation
    {
        [JsonPropertyName("index")]
        public int Index { get; set; }

        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("code")]
        public string Code { get; set; } = string.Empty;

        [JsonPropertyName("nameLa")]
        public string NameLa { get; set; } = string.Empty;

        [JsonPropertyName("nameEn")]
        public string NameEn { get; set; } = string.Empty;

        [JsonPropertyName("genitive")]
        public string Genitive { get; set; } = string.Empty;

        [JsonPropertyName("centerRaHours")]
        public double CenterRaHours { get; set; }

        [JsonPropertyName("centerDecDeg")]
        public double CenterDecDeg { get; set; }

        [JsonPropertyName("rank")]
        public int Rank { get; set; } = 2;

        [JsonPropertyName("lore")]
        public string Lore { get; set; } = string.Empty;

        [JsonPropertyName("segments")]
        public List<List<int>> Segments { get; set; } = new();

        public double CenterRa => CenterRaHours;
        public double CenterDec => CenterDecDeg;
    }

    public class CosmosConstellationBorderArc
    {
        [JsonPropertyName("ids")]
        public List<string> Ids { get; set; } = new();

        [JsonPropertyName("points")]
        public List<List<double>> Points { get; set; } = new();
    }

    public class CosmosAsterism
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("season")]
        public string Season { get; set; } = string.Empty;

        [JsonPropertyName("description")]
        public string Description { get; set; } = string.Empty;

        [JsonPropertyName("centerRaHours")]
        public double CenterRaHours { get; set; }

        [JsonPropertyName("centerDecDeg")]
        public double CenterDecDeg { get; set; }

        [JsonPropertyName("segments")]
        public List<List<int>> Segments { get; set; } = new();
    }

    public class CosmosDeepSkyObject
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("catalog")]
        public string Catalog { get; set; } = "Messier";

        [JsonPropertyName("ngcIc")]
        public string? NgcIc { get; set; }

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("constellation")]
        public string Constellation { get; set; } = string.Empty;

        [JsonPropertyName("type")]
        public string Type { get; set; } = string.Empty;

        [JsonPropertyName("typeCode")]
        public string TypeCode { get; set; } = "DSO";

        [JsonPropertyName("raHours")]
        public double RaHours { get; set; }

        [JsonPropertyName("decDeg")]
        public double DecDeg { get; set; }

        [JsonPropertyName("visualMag")]
        public double VisualMag { get; set; }

        [JsonPropertyName("majorAxisArcmin")]
        public double MajorAxisArcmin { get; set; } = 10.0;

        [JsonPropertyName("minorAxisArcmin")]
        public double MinorAxisArcmin { get; set; } = 10.0;

        [JsonPropertyName("recommendedOptics")]
        public string RecommendedOptics { get; set; } = "Binoculars 7x50";

        [JsonPropertyName("thumbnail")]
        public string? Thumbnail { get; set; }

        [JsonPropertyName("description")]
        public string Description { get; set; } = string.Empty;

        public double DecDegrees => DecDeg;
        public string Optics => RecommendedOptics;

        public (float Ux, float Uy, float Uz) UnitVectorJ2000
        {
            get
            {
                double raRad = RaHours * 15.0 * (Math.PI / 180.0);
                double decRad = DecDeg * (Math.PI / 180.0);
                return (
                    (float)(Math.Cos(decRad) * Math.Cos(raRad)),
                    (float)(Math.Cos(decRad) * Math.Sin(raRad)),
                    (float)Math.Sin(decRad)
                );
            }
        }
    }

    public class MeteorShower
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("constellation")]
        public string Constellation { get; set; } = string.Empty;

        [JsonPropertyName("startMonth")]
        public int StartMonth { get; set; }

        [JsonPropertyName("startDay")]
        public int StartDay { get; set; }

        [JsonPropertyName("endMonth")]
        public int EndMonth { get; set; }

        [JsonPropertyName("endDay")]
        public int EndDay { get; set; }

        [JsonPropertyName("peakMonth")]
        public int PeakMonth { get; set; }

        [JsonPropertyName("peakDay")]
        public int PeakDay { get; set; }

        [JsonPropertyName("peakSolarLongitudeDeg")]
        public double PeakSolarLongitudeDeg { get; set; }

        [JsonPropertyName("radiantRaHours")]
        public double RadiantRaHours { get; set; }

        [JsonPropertyName("radiantDecDeg")]
        public double RadiantDecDeg { get; set; }

        [JsonPropertyName("driftRaPerDay")]
        public double DriftRaPerDay { get; set; }

        [JsonPropertyName("driftDecPerDay")]
        public double DriftDecPerDay { get; set; }

        [JsonPropertyName("zhr")]
        public int Zhr { get; set; }

        [JsonPropertyName("velocityKmS")]
        public double VelocityKmS { get; set; }

        [JsonPropertyName("parentBody")]
        public string ParentBody { get; set; } = string.Empty;

        [JsonPropertyName("description")]
        public string Description { get; set; } = string.Empty;

        public int ZenithHourlyRate => Zhr;
        public string RadiantConstellation => Constellation;
        public string PeakDateLabel
        {
            get
            {
                string[] m = { "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
                string mStr = (PeakMonth >= 1 && PeakMonth <= 12) ? m[PeakMonth] : "Peak";
                return $"{mStr} {PeakDay}";
            }
        }

        public bool IsActiveOn(DateTime date)
        {
            int cur = date.Month * 100 + date.Day;
            int s = StartMonth * 100 + StartDay;
            int e = EndMonth * 100 + EndDay;
            return s <= e ? (cur >= s && cur <= e) : (cur >= s || cur <= e);
        }
    }

    public sealed class MilkyWayContourLayer
    {
        public int Level { get; init; }
        public float[][] RingsUx { get; init; } = Array.Empty<float[]>();
        public float[][] RingsUy { get; init; } = Array.Empty<float[]>();
        public float[][] RingsUz { get; init; } = Array.Empty<float[]>();
    }

    // ── Zero-Trig Frame Projection Matrix ────────────────────────────────────

    public readonly struct ProjectedSkyPoint
    {
        public readonly double X;
        public readonly double Y;
        public readonly double Cz;
        public readonly bool IsVisible;

        public ProjectedSkyPoint(double x, double y, double cz, bool isVisible)
        {
            X = x;
            Y = y;
            Cz = cz;
            IsVisible = isVisible;
        }
    }

    public sealed class SkyProjectionMatrix
    {
        public readonly double M00, M01, M02;
        public readonly double M10, M11, M12;
        public readonly double M20, M21, M22;
        public readonly double Rx, Ry, Rz;
        public readonly double Ux, Uy, Uz;
        public readonly double Fx, Fy, Fz;
        public readonly double H00, H01, H02;
        public readonly double H10, H11, H12;
        public readonly double H20, H21, H22;
        public readonly double ViewportWidth;
        public readonly double ViewportHeight;
        public readonly double HalfWidth;
        public readonly double HalfHeight;
        public readonly double FovDegrees;
        public readonly double Scale;

        public SkyProjectionMatrix(
            double m00, double m01, double m02,
            double m10, double m11, double m12,
            double m20, double m21, double m22,
            double rx, double ry, double rz,
            double ux, double uy, double uz,
            double fx, double fy, double fz,
            double h00, double h01, double h02,
            double h10, double h11, double h12,
            double h20, double h21, double h22,
            double viewportWidth,
            double viewportHeight,
            double fovDegrees)
        {
            M00 = m00; M01 = m01; M02 = m02;
            M10 = m10; M11 = m11; M12 = m12;
            M20 = m20; M21 = m21; M22 = m22;
            Rx = rx; Ry = ry; Rz = rz;
            Ux = ux; Uy = uy; Uz = uz;
            Fx = fx; Fy = fy; Fz = fz;
            H00 = h00; H01 = h01; H02 = h02;
            H10 = h10; H11 = h11; H12 = h12;
            H20 = h20; H21 = h21; H22 = h22;
            ViewportWidth = viewportWidth;
            ViewportHeight = viewportHeight;
            HalfWidth = viewportWidth * 0.5;
            HalfHeight = viewportHeight * 0.5;
            FovDegrees = fovDegrees;
            double clampedFov = Math.Clamp(fovDegrees, 0.4, 150.0);
            Scale = (Math.Min(viewportWidth, viewportHeight) * 0.5) /
                    Math.Max(1e-6, Math.Tan(clampedFov * 0.25 * (Math.PI / 180.0)));
        }

        public ProjectedSkyPoint? ProjectEQJUnitVector(double vx, double vy, double vz, double margin = 60.0)
        {
            double cx = M00 * vx + M01 * vy + M02 * vz;
            double cy = M10 * vx + M11 * vy + M12 * vz;
            double cz = M20 * vx + M21 * vy + M22 * vz;
            double denom = 1.0 + cz;
            if (denom < 0.08) return null;
            double inv = Scale / denom;
            double sx = HalfWidth + cx * inv;
            double sy = HalfHeight - cy * inv;
            bool vis = sx >= -margin && sx <= ViewportWidth + margin && sy >= -margin && sy <= ViewportHeight + margin;
            return new ProjectedSkyPoint(sx, sy, cz, vis);
        }

        public ProjectedSkyPoint? ProjectHorizontal(double azimuthDegrees, double altitudeDegrees, double margin = 60.0)
        {
            double az = azimuthDegrees * (Math.PI / 180.0);
            double alt = altitudeDegrees * (Math.PI / 180.0);
            double cosAlt = Math.Cos(alt);
            double hx = cosAlt * Math.Cos(az);
            double hy = -cosAlt * Math.Sin(az);
            double hz = Math.Sin(alt);
            double cx = Rx * hx + Ry * hy + Rz * hz;
            double cy = Ux * hx + Uy * hy + Uz * hz;
            double cz = Fx * hx + Fy * hy + Fz * hz;
            double denom = 1.0 + cz;
            if (denom < 0.08) return null;
            double inv = Scale / denom;
            double sx = HalfWidth + cx * inv;
            double sy = HalfHeight - cy * inv;
            bool vis = sx >= -margin && sx <= ViewportWidth + margin && sy >= -margin && sy <= ViewportHeight + margin;
            return new ProjectedSkyPoint(sx, sy, cz, vis);
        }

        public (double AzimuthDeg, double AltitudeDeg)? UnprojectToHorizontal(double screenX, double screenY)
        {
            if (Scale <= 1e-6) return null;
            double xp = (screenX - HalfWidth) / Scale;
            double yp = (HalfHeight - screenY) / Scale;
            double r2 = xp * xp + yp * yp;
            double inv = 1.0 / (1.0 + r2);
            double cx = 2.0 * xp * inv;
            double cy = 2.0 * yp * inv;
            double cz = (1.0 - r2) * inv;
            double hx = cx * Rx + cy * Ux + cz * Fx;
            double hy = cx * Ry + cy * Uy + cz * Fy;
            double hz = cx * Rz + cy * Uz + cz * Fz;
            double altDeg = Math.Asin(Math.Clamp(hz, -1.0, 1.0)) * (180.0 / Math.PI);
            double azDeg = ((Math.Atan2(-hy, hx) * (180.0 / Math.PI)) + 360.0) % 360.0;
            return (azDeg, altDeg);
        }
    }

    // ── Supabase Bookmarks & Sky Observations ────────────────────────────────

    [Table("cosmos_bookmarks")]
    public class CosmosBookmarkRecord : BaseModel
    {
        [PrimaryKey("id", false)]
        [JsonPropertyName("id")]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [Column("user_id")]
        [JsonPropertyName("user_id")]
        public string? UserId { get; set; }

        [Column("object_id")]
        [JsonPropertyName("object_id")]
        public string ObjectId { get; set; } = string.Empty;

        [Column("object_name")]
        [JsonPropertyName("object_name")]
        public string ObjectName { get; set; } = string.Empty;

        [Column("category")]
        [JsonPropertyName("category")]
        public string Category { get; set; } = "star";

        [Column("ra_hours")]
        [JsonPropertyName("ra_hours")]
        public double? RaHours { get; set; }

        [Column("dec_deg")]
        [JsonPropertyName("dec_deg")]
        public double? DecDeg { get; set; }

        [Column("magnitude")]
        [JsonPropertyName("magnitude")]
        public double? Magnitude { get; set; }

        [Column("constellation")]
        [JsonPropertyName("constellation")]
        public string? Constellation { get; set; }

        [Column("notes")]
        [JsonPropertyName("notes")]
        public string Notes { get; set; } = string.Empty;

        [Column("created_at")]
        [JsonPropertyName("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("updated_at")]
        [JsonPropertyName("updated_at")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }

    [Table("cosmos_observations")]
    public class CosmosObservationRecord : BaseModel
    {
        [PrimaryKey("id", false)]
        [JsonPropertyName("id")]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [Column("user_id")]
        [JsonPropertyName("user_id")]
        public string? UserId { get; set; }

        [Column("object_id")]
        [JsonPropertyName("object_id")]
        public string ObjectId { get; set; } = string.Empty;

        [Column("object_name")]
        [JsonPropertyName("object_name")]
        public string ObjectName { get; set; } = string.Empty;

        [Column("category")]
        [JsonPropertyName("category")]
        public string Category { get; set; } = "star";

        [Column("observed_at")]
        [JsonPropertyName("observed_at")]
        public DateTime ObservedAt { get; set; } = DateTime.UtcNow;

        [Column("latitude")]
        [JsonPropertyName("latitude")]
        public double Latitude { get; set; }

        [Column("longitude")]
        [JsonPropertyName("longitude")]
        public double Longitude { get; set; }

        [Column("location_name")]
        [JsonPropertyName("location_name")]
        public string LocationName { get; set; } = string.Empty;

        [Column("azimuth_deg")]
        [JsonPropertyName("azimuth_deg")]
        public double? AzimuthDeg { get; set; }

        [Column("altitude_deg")]
        [JsonPropertyName("altitude_deg")]
        public double? AltitudeDeg { get; set; }

        [Column("bortle_class")]
        [JsonPropertyName("bortle_class")]
        public int? BortleClass { get; set; }

        [Column("stargazing_score")]
        [JsonPropertyName("stargazing_score")]
        public int? StargazingScore { get; set; }

        [Column("optics")]
        [JsonPropertyName("optics")]
        public string Optics { get; set; } = "Naked Eye";

        [Column("notes")]
        [JsonPropertyName("notes")]
        public string Notes { get; set; } = string.Empty;

        [Column("tagdos_note_id")]
        [JsonPropertyName("tagdos_note_id")]
        public string? TagdosNoteId { get; set; }

        [Column("created_at")]
        [JsonPropertyName("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("updated_at")]
        [JsonPropertyName("updated_at")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }

    public class CosmosLocalPreferences
    {
        public string NasaApiKey { get; set; } = string.Empty;
        public string WeatherEndpoint { get; set; } = string.Empty;
        public string WeatherApiKey { get; set; } = string.Empty;
        public bool NotifyIssPasses { get; set; } = false;
        public bool NotifyAurora { get; set; } = false;
        public bool NotifyPristineSky { get; set; } = false;
    }
}
