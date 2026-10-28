using System;
using System.Collections.Generic;
using CosineKitty;
using Daily.Models;

namespace Daily_WinUI.Services.Cosmos
{
    public interface IAstronomyService
    {
        CelestialCoordinates GetBodyCoordinates(CelestialBody body, DateTime utcTime, double latitude, double longitude, double elevationMeters = 0);
        List<CelestialCoordinates> GetAllVisibleBodies(DateTime utcTime, double latitude, double longitude, double elevationMeters = 0);
        MoonPhaseInfo GetMoonPhase(DateTime utcTime);
        (double azimuthDeg, double altitudeDeg) EquatorialToHorizontal(double raHours, double decDeg, DateTime utcTime, double latitude, double longitude);
        (double x, double y)? ProjectStereographic(double azimuthDeg, double altitudeDeg);
        StargazingConditions EvaluateStargazingQuality(double cloudCoverPercentage, double moonIlluminationFraction, int bortleScale = 4);
    }

    public class AstronomyService : IAstronomyService
    {
        private static readonly Lazy<AstronomyService> _instance = new(() => new AstronomyService());
        public static AstronomyService Shared => _instance.Value;

        public CelestialCoordinates GetBodyCoordinates(CelestialBody body, DateTime utcTime, double latitude, double longitude, double elevationMeters = 0)
        {
            var astroTime = new AstroTime(utcTime);
            var observer = new Observer(latitude, longitude, elevationMeters);
            var astroBody = ToAstroBody(body);

            var equator = Astronomy.Equator(astroBody, astroTime, observer, EquatorEpoch.OfDate, Aberration.None);
            var horizon = Astronomy.Horizon(astroTime, observer, equator.ra, equator.dec, Refraction.Normal);

            double? mag = null;
            try
            {
                if (body != CelestialBody.Sun)
                {
                    var illum = Astronomy.Illumination(astroBody, astroTime);
                    mag = illum.mag;
                }
            }
            catch
            {
                // Illumination calculation not supported for all bodies
            }

            return new CelestialCoordinates
            {
                Body = body,
                RightAscension = equator.ra,
                Declination = equator.dec,
                Azimuth = horizon.azimuth,
                Altitude = horizon.altitude,
                DistanceAu = equator.dist,
                Magnitude = mag
            };
        }

        public List<CelestialCoordinates> GetAllVisibleBodies(DateTime utcTime, double latitude, double longitude, double elevationMeters = 0)
        {
            var bodies = new[]
            {
                CelestialBody.Sun,
                CelestialBody.Moon,
                CelestialBody.Mercury,
                CelestialBody.Venus,
                CelestialBody.Mars,
                CelestialBody.Jupiter,
                CelestialBody.Saturn,
                CelestialBody.Uranus,
                CelestialBody.Neptune
            };

            var list = new List<CelestialCoordinates>();
            foreach (var b in bodies)
            {
                list.Add(GetBodyCoordinates(b, utcTime, latitude, longitude, elevationMeters));
            }
            return list;
        }

        public MoonPhaseInfo GetMoonPhase(DateTime utcTime)
        {
            var astroTime = new AstroTime(utcTime);
            double phaseAngle = Astronomy.MoonPhase(astroTime);
            var illum = Astronomy.Illumination(Body.Moon, astroTime);

            MoonPhaseQuarter quarter;
            string description;

            if (phaseAngle < 45.0 || phaseAngle >= 315.0)
            {
                quarter = MoonPhaseQuarter.NewMoon;
                description = phaseAngle < 45.0 ? "Semilună Crescătoare" : "Semilună Descrescătoare";
            }
            else if (phaseAngle < 135.0)
            {
                quarter = MoonPhaseQuarter.FirstQuarter;
                description = phaseAngle < 90.0 ? "Primul Pătrar" : "Lună Convexă Crescătoare";
            }
            else if (phaseAngle < 225.0)
            {
                quarter = MoonPhaseQuarter.FullMoon;
                description = "Lună Plină";
            }
            else
            {
                quarter = MoonPhaseQuarter.ThirdQuarter;
                description = phaseAngle < 270.0 ? "Lună Convexă Descrescătoare" : "Ultimul Pătrar";
            }

            return new MoonPhaseInfo
            {
                PhaseAngleDegrees = phaseAngle,
                IlluminatedFraction = illum.phase_fraction,
                Quarter = quarter,
                Description = description
            };
        }

        public (double azimuthDeg, double altitudeDeg) EquatorialToHorizontal(double raHours, double decDeg, DateTime utcTime, double latitude, double longitude)
        {
            var astroTime = new AstroTime(utcTime);
            var observer = new Observer(latitude, longitude, 0);
            var hor = Astronomy.Horizon(astroTime, observer, raHours, decDeg, Refraction.Normal);
            return (hor.azimuth, hor.altitude);
        }

        public (double x, double y)? ProjectStereographic(double azimuthDeg, double altitudeDeg)
        {
            if (altitudeDeg < -10.0) return null;

            // Stereographic conformal projection: r = tan((90 - alt) / 2)
            double zenithAngleRad = (90.0 - altitudeDeg) * (Math.PI / 180.0);
            double r = Math.Tan(zenithAngleRad / 2.0);

            // Azimuth: 0 = North (Up / -Y), 90 = East (Right / +X), 180 = South (Down / +Y), 270 = West (Left / -X)
            double azRad = azimuthDeg * (Math.PI / 180.0);
            double x = r * Math.Sin(azRad);
            double y = -r * Math.Cos(azRad);

            return (x, y);
        }

        public StargazingConditions EvaluateStargazingQuality(double cloudCoverPercentage, double moonIlluminationFraction, int bortleScale = 4)
        {
            // Clear sky (cloud < 20%): 60 pts
            double cloudScore = Math.Max(0.0, 60.0 * (1.0 - (cloudCoverPercentage / 100.0)));
            // Dark moon (illumination < 25%): 25 pts
            double moonScore = 25.0 * (1.0 - (moonIlluminationFraction * 0.75));
            // Light pollution (Bortle 1-9): 15 pts
            double bortleScore = Math.Max(0.0, 15.0 * (1.0 - (bortleScale - 1) / 8.0));

            int totalScore = (int)Math.Clamp(Math.Round(cloudScore + moonScore + bortleScore), 0, 100);

            StargazingQuality quality;
            string summary;

            if (totalScore >= 80)
            {
                quality = StargazingQuality.Excellent;
                summary = "Condiții perfecte de observare stelară";
            }
            else if (totalScore >= 60)
            {
                quality = StargazingQuality.Good;
                summary = "Cer favorabil cu detalii vizibile clare";
            }
            else if (totalScore >= 40)
            {
                quality = StargazingQuality.Fair;
                summary = "Observare acceptabilă pentru planete și lună";
            }
            else
            {
                quality = StargazingQuality.Poor;
                summary = "Nori sau luminozitate ridicată";
            }

            return new StargazingConditions
            {
                Quality = quality,
                Score = totalScore,
                CloudCover = cloudCoverPercentage,
                MoonIllumination = moonIlluminationFraction,
                Seeing = totalScore >= 70 ? "Excelent (0.8\")" : "Mediu (1.5\")",
                Transparency = totalScore >= 70 ? "Foarte Bună" : "Moderată",
                LightPollutionBortle = bortleScale,
                Summary = summary
            };
        }

        private static Body ToAstroBody(CelestialBody body) => body switch
        {
            CelestialBody.Sun => Body.Sun,
            CelestialBody.Moon => Body.Moon,
            CelestialBody.Mercury => Body.Mercury,
            CelestialBody.Venus => Body.Venus,
            CelestialBody.Mars => Body.Mars,
            CelestialBody.Jupiter => Body.Jupiter,
            CelestialBody.Saturn => Body.Saturn,
            CelestialBody.Uranus => Body.Uranus,
            CelestialBody.Neptune => Body.Neptune,
            CelestialBody.Pluto => Body.Pluto,
            _ => Body.Sun
        };
    }
}
