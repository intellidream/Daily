using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

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
        Neptune,
        Pluto
    }

    public enum MoonPhaseQuarter
    {
        NewMoon,
        FirstQuarter,
        FullMoon,
        ThirdQuarter
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
        public bool IsAboveHorizon => Altitude > 0;
    }

    public class MoonPhaseInfo
    {
        public double PhaseAngleDegrees { get; set; }
        public double IlluminatedFraction { get; set; }
        public MoonPhaseQuarter Quarter { get; set; }
        public string Description { get; set; } = string.Empty;
    }

    public class StargazingConditions
    {
        public StargazingQuality Quality { get; set; } = StargazingQuality.Fair;
        public int Score { get; set; }
        public double CloudCover { get; set; }
        public double MoonIllumination { get; set; }
        public string Seeing { get; set; } = string.Empty;
        public string Transparency { get; set; } = string.Empty;
        public int LightPollutionBortle { get; set; } = 4;
        public string Summary { get; set; } = string.Empty;
    }

    public class CosmosStar
    {
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
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("nameLa")]
        public string NameLa { get; set; } = string.Empty;

        [JsonPropertyName("nameEn")]
        public string NameEn { get; set; } = string.Empty;

        [JsonPropertyName("nameRo")]
        public string NameRo { get; set; } = string.Empty;

        [JsonPropertyName("centerRa")]
        public double CenterRa { get; set; }

        [JsonPropertyName("centerDec")]
        public double CenterDec { get; set; }

        [JsonPropertyName("stars")]
        public List<string> Stars { get; set; } = new();
    }

    public class CosmosDeepSkyObject
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("constellation")]
        public string Constellation { get; set; } = string.Empty;

        [JsonPropertyName("raHours")]
        public double RaHours { get; set; }

        [JsonPropertyName("decDegrees")]
        public double DecDegrees { get; set; }

        [JsonPropertyName("type")]
        public string Type { get; set; } = string.Empty;

        [JsonPropertyName("visualMag")]
        public double VisualMag { get; set; }

        [JsonPropertyName("optics")]
        public string Optics { get; set; } = string.Empty;

        [JsonPropertyName("descRo")]
        public string DescRo { get; set; } = string.Empty;
    }

    public class MeteorShower
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("peakDate")]
        public string PeakDate { get; set; } = string.Empty;

        [JsonPropertyName("zenithHourlyRate")]
        public int ZenithHourlyRate { get; set; }

        [JsonPropertyName("radiantConstellation")]
        public string RadiantConstellation { get; set; } = string.Empty;

        [JsonPropertyName("velocityKmS")]
        public double VelocityKmS { get; set; }
    }
}
