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
        MoonPhaseInfo GetMoonPhase(DateTime utcTime, double latitude = 44.4323, double longitude = 26.1063);
        (double azimuthDeg, double altitudeDeg) EquatorialToHorizontal(double raHours, double decDeg, DateTime utcTime, double latitude, double longitude, bool includeRefraction = true);
        (double x, double y)? ProjectHorizontal(double azimuthDeg, double altitudeDeg, double cameraAzimuthDeg, double cameraAltitudeDeg, double fovDegrees, double viewportWidth, double viewportHeight, double cameraRollDeg = 0.0);
        SkyProjectionMatrix MakeProjectionMatrix(double latitude, double longitude, double elevationMeters, DateTime utcTime, double cameraAzimuthDeg, double cameraAltitudeDeg, double cameraRollDeg, double fovDegrees, double viewportWidth, double viewportHeight);
        JupiterMoonsState GetJupiterMoons(DateTime utcTime, double latitude = 44.4323, double longitude = 26.1063);
        double GetSaturnRingTiltDegrees(DateTime utcTime);
        RiseTransitSetTimes GetRiseTransitSet(CelestialBody body, DateTime utcTime, double latitude, double longitude, double elevationMeters = 0.0);
        SunTimes GetSunTimes(DateTime utcTime, double latitude, double longitude, double elevationMeters = 0.0);
        CircadianSkyContext GetCircadianContext(DateTime utcTime, double latitude, double longitude);
        StargazingConditions EvaluateStargazingConditions(
            double latitude,
            double longitude,
            DateTime utcTime,
            int? cloudCoverTotal = null,
            int? cloudCoverLow = null,
            int? cloudCoverMid = null,
            int? cloudCoverHigh = null,
            int bortleClass = 5,
            double? seeingArcseconds = null,
            string? transparencyLabel = null,
            double? temperatureCelsius = null,
            double? dewPointCelsius = null,
            TelemetryProvenance? provenance = null);
    }

    public class AstronomyService : IAstronomyService
    {
        private static readonly Lazy<AstronomyService> _instance = new(() => new AstronomyService());
        public static AstronomyService Shared => _instance.Value;

        private const double AuInKm = 149_597_870.7;
        private const double SpeedOfLightAuPerDay = 173.1446326846693;
        private const double Deg2Rad = Math.PI / 180.0;
        private const double Rad2Deg = 180.0 / Math.PI;

        public CelestialCoordinates GetBodyCoordinates(
            CelestialBody body,
            DateTime utcTime,
            double latitude,
            double longitude,
            double elevationMeters = 0)
        {
            var astroTime = new AstroTime(utcTime.ToUniversalTime());
            var observer = new Observer(latitude, longitude, elevationMeters);
            var astroBody = ToAstroBody(body);

            var equator = Astronomy.Equator(astroBody, astroTime, observer, EquatorEpoch.OfDate, Aberration.Corrected);
            var horizon = Astronomy.Horizon(astroTime, observer, equator.ra, equator.dec, Refraction.Normal);

            double? mag = null;
            double? phaseFrac = null;
            try
            {
                var illum = Astronomy.Illumination(astroBody, astroTime);
                mag = illum.mag;
                phaseFrac = illum.phase_fraction;
            }
            catch { }

            double? limbDeg = body == CelestialBody.Sun
                ? null
                : ComputeBrightLimbAngleDegrees(body, astroTime, latitude, longitude);

            double eqRadiusKm = body switch
            {
                CelestialBody.Sun => 695_700.0,
                CelestialBody.Moon => 1_737.4,
                CelestialBody.Mercury => 2_439.7,
                CelestialBody.Venus => 6_051.8,
                CelestialBody.Mars => 3_389.5,
                CelestialBody.Jupiter => 71_492.0,
                CelestialBody.Saturn => 60_268.0,
                CelestialBody.Uranus => 25_559.0,
                CelestialBody.Neptune => 24_764.0,
                _ => 1_000.0
            };
            double distKm = Math.Max(1.0, equator.dist * AuInKm);
            double angDiamArcsec = 2.0 * Math.Atan(eqRadiusKm / distKm) * Rad2Deg * 3600.0;

            return new CelestialCoordinates
            {
                Body = body,
                RightAscension = equator.ra,
                Declination = equator.dec,
                Azimuth = horizon.azimuth,
                Altitude = horizon.altitude,
                DistanceAu = equator.dist,
                Magnitude = mag,
                IlluminatedFraction = phaseFrac,
                BrightLimbAngleDegrees = limbDeg,
                AngularDiameterArcsec = angDiamArcsec
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

            var list = new List<CelestialCoordinates>(bodies.Length);
            foreach (var b in bodies)
            {
                list.Add(GetBodyCoordinates(b, utcTime, latitude, longitude, elevationMeters));
            }
            return list;
        }

        public MoonPhaseInfo GetMoonPhase(DateTime utcTime, double latitude = 44.4323, double longitude = 26.1063)
        {
            var astroTime = new AstroTime(utcTime.ToUniversalTime());
            double phaseAngle = Astronomy.MoonPhase(astroTime);
            var illum = Astronomy.Illumination(Body.Moon, astroTime);

            var geoMoon = Astronomy.GeoMoon(astroTime);
            double geoDistKm = geoMoon.Length() * AuInKm;

            var observer = new Observer(latitude, longitude, 0.0);
            var topoEq = Astronomy.Equator(Body.Moon, astroTime, observer, EquatorEpoch.OfDate, Aberration.Corrected);
            double topoDistKm = topoEq.dist * AuInKm;
            double limbDeg = ComputeBrightLimbAngleDegrees(CelestialBody.Moon, astroTime, latitude, longitude);

            (MoonPhaseQuarter quarter, string description) = phaseAngle switch
            {
                < 6.5 or >= 353.5 => (MoonPhaseQuarter.NewMoon, "New Moon"),
                < 83.5 => (MoonPhaseQuarter.WaxingCrescent, "Waxing Crescent"),
                < 96.5 => (MoonPhaseQuarter.FirstQuarter, "First Quarter"),
                < 173.5 => (MoonPhaseQuarter.WaxingGibbous, "Waxing Gibbous"),
                < 186.5 => (MoonPhaseQuarter.FullMoon, "Full Moon"),
                < 263.5 => (MoonPhaseQuarter.WaningGibbous, "Waning Gibbous"),
                < 276.5 => (MoonPhaseQuarter.ThirdQuarter, "Third Quarter"),
                _ => (MoonPhaseQuarter.WaningCrescent, "Waning Crescent")
            };

            return new MoonPhaseInfo
            {
                PhaseAngleDegrees = phaseAngle,
                IlluminatedFraction = illum.phase_fraction,
                Quarter = quarter,
                Description = description,
                AgeDays = (phaseAngle / 360.0) * 29.530588853,
                IsWaxing = phaseAngle < 180.0,
                DistanceKm = geoDistKm,
                TopocentricDistanceKm = topoDistKm,
                BrightLimbAngleDegrees = limbDeg
            };
        }

        public double ComputeBrightLimbAngleDegrees(CelestialBody body, AstroTime astroTime, double latitude, double longitude)
        {
            if (body == CelestialBody.Sun) return 0.0;
            var obs = new Observer(latitude, longitude, 0.0);
            var rot = Astronomy.Rotation_EQJ_HOR(astroTime, obs);

            var bodyEqj = Astronomy.GeoVector(ToAstroBody(body), astroTime, Aberration.Corrected);
            var sunEqj = Astronomy.GeoVector(Body.Sun, astroTime, Aberration.Corrected);
            var mh = Astronomy.RotateVector(rot, bodyEqj);
            var sh = Astronomy.RotateVector(rot, sunEqj);

            double ml = mh.Length();
            double sl = sh.Length();
            if (ml <= 1e-12 || sl <= 1e-12) return 0.0;

            double bx = mh.x / ml, by = mh.y / ml, bz = mh.z / ml;
            double sx = sh.x / sl, sy = sh.y / sl, sz = sh.z / sl;

            double dot = sx * bx + sy * by + sz * bz;
            double tx = sx - dot * bx;
            double ty = sy - dot * by;
            double tz = sz - dot * bz;

            double rLen = Math.Sqrt(by * by + bx * bx);
            double rx = rLen > 1e-9 ? by / rLen : 0.0;
            double ry = rLen > 1e-9 ? -bx / rLen : -1.0;
            double rz = 0.0;

            double ux = ry * bz - rz * by;
            double uy = rz * bx - rx * bz;
            double uz = rx * by - ry * bx;

            double tr = tx * rx + ty * ry + tz * rz;
            double tu = tx * ux + ty * uy + tz * uz;
            return Math.Atan2(tr, tu) * Rad2Deg;
        }

        public (double azimuthDeg, double altitudeDeg) EquatorialToHorizontal(
            double raHours,
            double decDeg,
            DateTime utcTime,
            double latitude,
            double longitude,
            bool includeRefraction = true)
        {
            var r = StarHorizontalCoordinates(raHours, decDeg, utcTime, latitude, longitude, 0.0, includeRefraction);
            return (r.AzimuthDegrees, r.AltitudeDegrees);
        }

        public (double AzimuthDegrees, double AltitudeDegrees, double Hx, double Hy, double Hz) StarHorizontalCoordinates(
            double raHours,
            double decDeg,
            DateTime utcTime,
            double latitude,
            double longitude,
            double elevationMeters = 0.0,
            bool includeRefraction = true)
        {
            var astroTime = new AstroTime(utcTime.ToUniversalTime());
            var obs = new Observer(latitude, longitude, elevationMeters);
            var rot = Astronomy.Rotation_EQJ_HOR(astroTime, obs);
            double raRad = raHours * 15.0 * Deg2Rad;
            double decRad = decDeg * Deg2Rad;
            var eqj = new AstroVector(
                Math.Cos(decRad) * Math.Cos(raRad),
                Math.Cos(decRad) * Math.Sin(raRad),
                Math.Sin(decRad),
                astroTime
            );
            var hor = Astronomy.RotateVector(rot, eqj);
            double azDeg = (Math.Atan2(-hor.y, hor.x) * Rad2Deg + 360.0) % 360.0;
            double altDeg = Math.Asin(Math.Clamp(hor.z, -1.0, 1.0)) * Rad2Deg;
            if (includeRefraction && altDeg >= -90.0 && altDeg <= 90.0)
            {
                double hd = Math.Max(-1.0, altDeg);
                double refr = (1.02 / Math.Tan((hd + 10.3 / (hd + 5.11)) * Deg2Rad)) / 60.0;
                if (altDeg < -1.0)
                    refr *= (altDeg + 90.0) / 89.0;
                altDeg += refr;
            }
            return (azDeg, altDeg, hor.x, hor.y, hor.z);
        }

        // ── Unified Singularity-Free 3D Camera Basis & Stereographic Projection ─

        public static (double Rx, double Ry, double Rz, double Ux, double Uy, double Uz, double Fx, double Fy, double Fz) CameraBasisNWZ(
            double cameraAzimuthDegrees,
            double cameraAltitudeDegrees,
            double cameraRollDegrees = 0.0)
        {
            double az = cameraAzimuthDegrees * Deg2Rad;
            double alt = cameraAltitudeDegrees * Deg2Rad;
            double roll = cameraRollDegrees * Deg2Rad;

            double cosAz = Math.Cos(az);
            double sinAz = Math.Sin(az);
            double cosAlt = Math.Cos(alt);
            double sinAlt = Math.Sin(alt);

            double fx = cosAlt * cosAz;
            double fy = -cosAlt * sinAz;
            double fz = sinAlt;

            double r0x = -sinAz;
            double r0y = -cosAz;
            double r0z = 0.0;

            double u0x = -sinAlt * cosAz;
            double u0y = sinAlt * sinAz;
            double u0z = cosAlt;

            double cr = Math.Cos(roll);
            double sr = Math.Sin(roll);

            double rx = cr * r0x + sr * u0x;
            double ry = cr * r0y + sr * u0y;
            double rz = cr * r0z + sr * u0z;

            double ux = -sr * r0x + cr * u0x;
            double uy = -sr * r0y + cr * u0y;
            double uz = -sr * r0z + cr * u0z;

            return (rx, ry, rz, ux, uy, uz, fx, fy, fz);
        }

        public SkyProjectionMatrix MakeProjectionMatrix(
            double latitude,
            double longitude,
            double elevationMeters,
            DateTime utcTime,
            double cameraAzimuthDeg,
            double cameraAltitudeDeg,
            double cameraRollDeg,
            double fovDegrees,
            double viewportWidth,
            double viewportHeight)
        {
            var astroTime = new AstroTime(utcTime.ToUniversalTime());
            var obs = new Observer(latitude, longitude, elevationMeters);
            var rot = Astronomy.Rotation_EQJ_HOR(astroTime, obs);

            double h00 = rot.rot[0, 0], h01 = rot.rot[1, 0], h02 = rot.rot[2, 0];
            double h10 = rot.rot[0, 1], h11 = rot.rot[1, 1], h12 = rot.rot[2, 1];
            double h20 = rot.rot[0, 2], h21 = rot.rot[1, 2], h22 = rot.rot[2, 2];

            var b = CameraBasisNWZ(cameraAzimuthDeg, cameraAltitudeDeg, cameraRollDeg);

            double m00 = b.Rx * h00 + b.Ry * h10 + b.Rz * h20;
            double m01 = b.Rx * h01 + b.Ry * h11 + b.Rz * h21;
            double m02 = b.Rx * h02 + b.Ry * h12 + b.Rz * h22;

            double m10 = b.Ux * h00 + b.Uy * h10 + b.Uz * h20;
            double m11 = b.Ux * h01 + b.Uy * h11 + b.Uz * h21;
            double m12 = b.Ux * h02 + b.Uy * h12 + b.Uz * h22;

            double m20 = b.Fx * h00 + b.Fy * h10 + b.Fz * h20;
            double m21 = b.Fx * h01 + b.Fy * h11 + b.Fz * h21;
            double m22 = b.Fx * h02 + b.Fy * h12 + b.Fz * h22;

            return new SkyProjectionMatrix(
                m00, m01, m02,
                m10, m11, m12,
                m20, m21, m22,
                b.Rx, b.Ry, b.Rz,
                b.Ux, b.Uy, b.Uz,
                b.Fx, b.Fy, b.Fz,
                h00, h01, h02,
                h10, h11, h12,
                h20, h21, h22,
                viewportWidth, viewportHeight, fovDegrees
            );
        }

        public (double x, double y)? ProjectHorizontal(
            double azimuthDeg,
            double altitudeDeg,
            double cameraAzimuthDeg,
            double cameraAltitudeDeg,
            double fovDegrees,
            double viewportWidth,
            double viewportHeight,
            double cameraRollDeg = 0.0)
        {
            var b = CameraBasisNWZ(cameraAzimuthDeg, cameraAltitudeDeg, cameraRollDeg);
            double az = azimuthDeg * Deg2Rad;
            double alt = altitudeDeg * Deg2Rad;
            double cosAlt = Math.Cos(alt);
            double hx = cosAlt * Math.Cos(az);
            double hy = -cosAlt * Math.Sin(az);
            double hz = Math.Sin(alt);

            double cx = b.Rx * hx + b.Ry * hy + b.Rz * hz;
            double cy = b.Ux * hx + b.Uy * hy + b.Uz * hz;
            double cz = b.Fx * hx + b.Fy * hy + b.Fz * hz;

            double denom = 1.0 + cz;
            if (denom < 0.08) return null;

            double clampedFov = Math.Clamp(fovDegrees, 0.4, 150.0);
            double scale = (Math.Min(viewportWidth, viewportHeight) * 0.5) /
                           Math.Max(1e-6, Math.Tan(clampedFov * 0.25 * Deg2Rad));

            double sx = viewportWidth * 0.5 + (cx / denom) * scale;
            double sy = viewportHeight * 0.5 - (cy / denom) * scale;
            return (sx, sy);
        }

        // ── Galilean Moons, Saturn Rings, Rise/Transit/Set & Twilight ──────────

        public JupiterMoonsState GetJupiterMoons(DateTime utcTime, double latitude = 44.4323, double longitude = 26.1063)
        {
            var astroTime = new AstroTime(utcTime.ToUniversalTime());
            var obs = new Observer(latitude, longitude, 0.0);
            var rot = Astronomy.Rotation_EQJ_HOR(astroTime, obs);

            var jupEqj = Astronomy.GeoVector(Body.Jupiter, astroTime, Aberration.Corrected);
            double distAu = jupEqj.Length();
            var tRet = astroTime.AddDays(-distAu / SpeedOfLightAuPerDay);
            var jm = Astronomy.JupiterMoons(tRet);

            var jh = Astronomy.RotateVector(rot, jupEqj);
            double jl = Math.Max(1e-9, jh.Length());
            double bx = jh.x / jl, by = jh.y / jl, bz = jh.z / jl;

            double rLen = Math.Sqrt(by * by + bx * bx);
            double rx = rLen > 1e-9 ? by / rLen : 0.0;
            double ry = rLen > 1e-9 ? -bx / rLen : -1.0;
            double rz = 0.0;

            double ux = ry * bz - rz * by;
            double uy = rz * bx - rx * bz;
            double uz = rx * by - ry * bx;

            const double jupRadiusAu = 71_492.0 / AuInKm;

            MoonVector2D ProjectMoon(string name, StateVector sv)
            {
                var mvEqj = new AstroVector(sv.x, sv.y, sv.z, astroTime);
                var mh = Astronomy.RotateVector(rot, mvEqj);
                double xRad = (mh.x * rx + mh.y * ry + mh.z * rz) / jupRadiusAu;
                double yRad = (mh.x * ux + mh.y * uy + mh.z * uz) / jupRadiusAu;
                double depthRad = (mh.x * bx + mh.y * by + mh.z * bz) / jupRadiusAu;
                return new MoonVector2D
                {
                    Name = name,
                    XRadius = xRad,
                    YRadius = yRad,
                    DepthRadius = depthRad,
                    IsFrontOfPlanet = depthRad < 0.0
                };
            }

            return new JupiterMoonsState
            {
                Io = ProjectMoon("Io", jm.io),
                Europa = ProjectMoon("Europa", jm.europa),
                Ganymede = ProjectMoon("Ganymede", jm.ganymede),
                Callisto = ProjectMoon("Callisto", jm.callisto)
            };
        }

        public double GetSaturnRingTiltDegrees(DateTime utcTime)
        {
            var astroTime = new AstroTime(utcTime.ToUniversalTime());
            var axis = Astronomy.RotationAxis(Body.Saturn, astroTime);
            var satVec = Astronomy.GeoVector(Body.Saturn, astroTime, Aberration.Corrected);
            double len = satVec.Length();
            if (len <= 1e-9) return 0.0;
            double dot = -(satVec.x * axis.north.x + satVec.y * axis.north.y + satVec.z * axis.north.z) / len;
            return Math.Asin(Math.Clamp(dot, -1.0, 1.0)) * Rad2Deg;
        }

        public RiseTransitSetTimes GetRiseTransitSet(
            CelestialBody body,
            DateTime utcTime,
            double latitude,
            double longitude,
            double elevationMeters = 0.0)
        {
            var start = new AstroTime(utcTime.ToUniversalTime());
            var obs = new Observer(latitude, longitude, elevationMeters);
            var b = ToAstroBody(body);
            DateTime? rise = null, transit = null, set = null;
            try
            {
                var r = Astronomy.SearchRiseSet(b, obs, Direction.Rise, start, 1.2);
                rise = r?.ToUtcDateTime();
            }
            catch { }
            try
            {
                var tr = Astronomy.SearchHourAngle(b, obs, 0.0, start, +1);
                transit = tr.time.ToUtcDateTime();
            }
            catch { }
            try
            {
                var s = Astronomy.SearchRiseSet(b, obs, Direction.Set, start, 1.2);
                set = s?.ToUtcDateTime();
            }
            catch { }
            return new RiseTransitSetTimes { RiseTimeUtc = rise, TransitTimeUtc = transit, SetTimeUtc = set };
        }

        public RiseTransitSetTimes GetRiseTransitSetStar(
            double raHours,
            double decDeg,
            DateTime utcTime,
            double latitude,
            double longitude,
            double elevationMeters = 0.0)
        {
            var baseUtc = utcTime.ToUniversalTime();
            var astroTime = new AstroTime(baseUtc);
            double gmstHours = Astronomy.SiderealTime(astroTime);
            double lstHours = ((gmstHours + longitude / 15.0) % 24.0 + 24.0) % 24.0;
            double deltaHours = ((raHours - lstHours + 24.0) % 24.0) / 1.00273790935;
            DateTime transit = baseUtc.AddHours(deltaHours);

            double latRad = latitude * Deg2Rad;
            double decRad = decDeg * Deg2Rad;
            double h0Rad = -0.5667 * Deg2Rad;
            double cosH = (Math.Sin(h0Rad) - Math.Sin(latRad) * Math.Sin(decRad)) /
                          Math.Max(1e-9, Math.Cos(latRad) * Math.Cos(decRad));

            if (cosH < -1.0 || cosH > 1.0)
            {
                return new RiseTransitSetTimes { RiseTimeUtc = null, TransitTimeUtc = transit, SetTimeUtc = null };
            }

            double halfArcHours = (Math.Acos(Math.Clamp(cosH, -1.0, 1.0)) * Rad2Deg / 15.0) / 1.00273790935;
            DateTime rise = transit.AddHours(-halfArcHours);
            if (rise < baseUtc) rise = rise.AddHours(24.0 / 1.00273790935);
            DateTime set = transit.AddHours(halfArcHours);
            if (set < baseUtc) set = set.AddHours(24.0 / 1.00273790935);

            return new RiseTransitSetTimes { RiseTimeUtc = rise, TransitTimeUtc = transit, SetTimeUtc = set };
        }

        public SunTimes GetSunTimes(DateTime utcTime, double latitude, double longitude, double elevationMeters = 0.0)
        {
            var d = utcTime.ToUniversalTime().Date;
            var start = new AstroTime(d);
            var obs = new Observer(latitude, longitude, elevationMeters);

            DateTime? Alt(Direction dir, double deg)
            {
                try { return Astronomy.SearchAltitude(Body.Sun, obs, dir, start, 1.1, deg)?.ToUtcDateTime(); }
                catch { return null; }
            }
            DateTime? RiseSet(Direction dir)
            {
                try { return Astronomy.SearchRiseSet(Body.Sun, obs, dir, start, 1.1)?.ToUtcDateTime(); }
                catch { return null; }
            }
            DateTime? noon = null;
            try { noon = Astronomy.SearchHourAngle(Body.Sun, obs, 0.0, start, +1).time.ToUtcDateTime(); }
            catch { }

            return new SunTimes
            {
                DawnAstronomicalUtc = Alt(Direction.Rise, -18.0),
                DawnNauticalUtc = Alt(Direction.Rise, -12.0),
                DawnCivilUtc = Alt(Direction.Rise, -6.0),
                SunriseUtc = RiseSet(Direction.Rise),
                SolarNoonUtc = noon,
                SunsetUtc = RiseSet(Direction.Set),
                DuskCivilUtc = Alt(Direction.Set, -6.0),
                DuskNauticalUtc = Alt(Direction.Set, -12.0),
                DuskAstronomicalUtc = Alt(Direction.Set, -18.0)
            };
        }

        public CircadianSkyContext GetCircadianContext(DateTime utcTime, double latitude, double longitude)
        {
            var sun = GetSunTimes(utcTime, latitude, longitude);
            var moon = GetMoonPhase(utcTime, latitude, longitude);
            var moonCoord = GetBodyCoordinates(CelestialBody.Moon, utcTime, latitude, longitude);
            double lux = moonCoord.Altitude > 0.0
                ? Math.Pow(moon.IlluminatedFraction, 2.2) * Math.Sin(moonCoord.Altitude * Deg2Rad) * 0.26
                : 0.0;

            string duskStr = sun.DuskAstronomicalUtc.HasValue
                ? sun.DuskAstronomicalUtc.Value.ToLocalTime().ToString("HH:mm")
                : "polar twilight";
            string summary = lux > 0.08
                ? $"Astronomical darkness starts at {duskStr}; bright {moon.IlluminationPercent}% moonlight (~{lux:F2} lx) illuminates the landscape."
                : $"True astronomical darkness begins at {duskStr} with minimal natural lunar skyglow (~{lux:F3} lx).";

            return new CircadianSkyContext
            {
                TrueDarknessOnsetUtc = sun.DuskAstronomicalUtc,
                NaturalMoonlightLux = lux,
                Summary = summary
            };
        }

        // ── Unified Deterministic Stargazing Score & 15-Min Dark Window ─────────

        public static int ComputeDeterministicSkyScore(
            double cloudLow,
            double cloudMid,
            double cloudHigh,
            double moonIlluminatedFraction,
            double moonAltitudeDegrees,
            int bortleClass,
            double seeingArcsec,
            double temperatureC,
            double dewPointC)
        {
            double effCloud = Math.Min(
                100.0,
                Math.Max(cloudLow, Math.Max(cloudMid, 0.7 * cloudLow + 0.3 * cloudMid)) * 0.92 +
                cloudHigh * 0.25);
            double cloudPenalty = effCloud * 0.58;
            double moonPenalty = moonAltitudeDegrees > -2.0
                ? moonIlluminatedFraction * Math.Max(0.0, Math.Sin(moonAltitudeDegrees * Deg2Rad)) * 22.0
                : 0.0;
            double bortlePenalty = Math.Max(0, Math.Min(9, bortleClass) - 1) * 2.5;
            double seeingPenalty = Math.Max(0.0, (seeingArcsec - 1.2) * 3.0);
            double dewPenalty = (temperatureC - dewPointC) < 2.0 ? 5.0 : 0.0;
            double raw = 100.0 - cloudPenalty - moonPenalty - bortlePenalty - seeingPenalty - dewPenalty;
            return Math.Clamp((int)Math.Round(raw), 0, 100);
        }

        public StargazingConditions EvaluateStargazingConditions(
            double latitude,
            double longitude,
            DateTime utcTime,
            int? cloudCoverTotal = null,
            int? cloudCoverLow = null,
            int? cloudCoverMid = null,
            int? cloudCoverHigh = null,
            int bortleClass = 5,
            double? seeingArcseconds = null,
            string? transparencyLabel = null,
            double? temperatureCelsius = null,
            double? dewPointCelsius = null,
            TelemetryProvenance? provenance = null)
        {
            var moon = GetMoonPhase(utcTime, latitude, longitude);
            var moonCoords = GetBodyCoordinates(CelestialBody.Moon, utcTime, latitude, longitude);
            var sunCoords = GetBodyCoordinates(CelestialBody.Sun, utcTime, latitude, longitude);

            double cLow = cloudCoverLow ?? cloudCoverTotal ?? 0;
            double cMid = cloudCoverMid ?? cloudCoverTotal ?? 0;
            double cHigh = cloudCoverHigh ?? cloudCoverTotal ?? 0;
            double seeingVal = seeingArcseconds ?? 1.4;
            double tempVal = temperatureCelsius ?? 12.0;
            double dewVal = dewPointCelsius ?? 6.0;

            int score = ComputeDeterministicSkyScore(
                cLow, cMid, cHigh,
                moon.IlluminatedFraction, moonCoords.Altitude,
                bortleClass, seeingVal, tempVal, dewVal);

            if (sunCoords.Altitude > -6.0)
            {
                var sunT = GetSunTimes(utcTime, latitude, longitude);
                var duskRef = sunT.DuskAstronomicalUtc ?? sunT.DuskNauticalUtc ?? sunT.SunsetUtc;
                if (duskRef.HasValue)
                {
                    var sampleNight = duskRef.Value.AddHours(1.0);
                    var nightMoonC = GetBodyCoordinates(CelestialBody.Moon, sampleNight, latitude, longitude);
                    var nightMoonP = GetMoonPhase(sampleNight, latitude, longitude);
                    score = ComputeDeterministicSkyScore(
                        cLow, cMid, cHigh,
                        nightMoonP.IlluminatedFraction, nightMoonC.Altitude,
                        bortleClass, seeingVal, tempVal, dewVal);
                }
            }

            var quality = score switch
            {
                >= 80 => StargazingQuality.Excellent,
                >= 60 => StargazingQuality.Good,
                >= 40 => StargazingQuality.Fair,
                _ => StargazingQuality.Poor
            };

            double[] baseNelm = { 7.8, 7.8, 7.3, 6.8, 6.3, 5.8, 5.2, 4.6, 4.1, 3.6 };
            double nelm = baseNelm[Math.Clamp(bortleClass, 1, 9)];
            if (moonCoords.IsAboveHorizon) nelm -= moon.IlluminatedFraction * 1.45;
            nelm = Math.Clamp(nelm, 2.5, 7.8);

            string? bestWindow = SolveBestDarkWindow(utcTime, latitude, longitude);
            double? dewDep = (temperatureCelsius.HasValue && dewPointCelsius.HasValue)
                ? Math.Max(0.0, temperatureCelsius.Value - dewPointCelsius.Value)
                : null;

            string advice;
            if (!cloudCoverTotal.HasValue)
            {
                advice = $"Offline ephemeris mode (Bortle {bortleClass}, NELM {nelm:F1}). Connect once to include live cloud layers and atmospheric seeing.";
            }
            else
            {
                int cTotal = cloudCoverTotal.Value;
                advice = quality switch
                {
                    StargazingQuality.Excellent => bestWindow != null
                        ? $"Pristine deep-sky window ({bestWindow}) — galaxies & nebulae down to mag {nelm:F1}."
                        : $"Pristine dark sky — faint Messier & Caldwell targets visible down to mag {nelm:F1}.",
                    StargazingQuality.Good => bestWindow != null
                        ? $"Good observing conditions; darkest sky window {bestWindow} (NELM {nelm:F1})."
                        : $"Good clear sky for star clusters, planets, and bright nebulae (NELM {nelm:F1}).",
                    StargazingQuality.Fair => cTotal > 45
                        ? $"Partly cloudy ({cTotal}% cover) — target bright planets, double stars, and lunar craters."
                        : $"Moderate skyglow ({moon.IlluminationPercent}% Moon, Bortle {bortleClass}) — ideal for planets & open clusters.",
                    _ => cTotal >= 75
                        ? $"Heavy cloud cover ({cTotal}%) restricts direct sky viewing tonight."
                        : "Elevated glare or haze — stick to Lunar and planetary observation."
                };
            }

            return new StargazingConditions
            {
                Quality = quality,
                Score = score,
                CloudCover = cloudCoverTotal ?? 0,
                CloudCoverTotalPercent = cloudCoverTotal,
                CloudCoverLowPercent = cloudCoverLow,
                CloudCoverMidPercent = cloudCoverMid,
                CloudCoverHighPercent = cloudCoverHigh,
                MoonIllumination = moon.IlluminatedFraction,
                IsMoonAboveHorizon = moonCoords.IsAboveHorizon,
                SeeingArcseconds = seeingArcseconds,
                Seeing = seeingArcseconds.HasValue ? $"{seeingArcseconds.Value:F1}\" FWHM" : "Unavailable offline",
                Transparency = transparencyLabel ?? $"Bortle {bortleClass} (NELM {nelm:F1})",
                DewPointDepressionCelsius = dewDep,
                LightPollutionBortle = Math.Clamp(bortleClass, 1, 9),
                LimitingMagnitude = nelm,
                BestWindowDescription = bestWindow,
                Summary = advice,
                Provenance = provenance ?? TelemetryProvenance.OfflineCalculated()
            };
        }

        private string? SolveBestDarkWindow(DateTime utcTime, double latitude, double longitude)
        {
            var obs = new Observer(latitude, longitude, 0.0);
            var startSearch = new AstroTime(utcTime.ToUniversalTime().AddHours(-12));
            AstroTime? sunset;
            AstroTime? sunrise;
            try
            {
                sunset = Astronomy.SearchRiseSet(Body.Sun, obs, Direction.Set, startSearch, 1.5);
                if (sunset == null) return null;
                sunrise = Astronomy.SearchRiseSet(Body.Sun, obs, Direction.Rise, sunset, 1.2);
                if (sunrise == null) return null;
            }
            catch { return null; }

            DateTime t0 = sunset.ToUtcDateTime();
            DateTime t1 = sunrise.ToUtcDateTime();
            if (t1 <= t0) return null;

            DateTime? winStart = null;
            DateTime? winEnd = null;
            DateTime? bestStart = null;
            DateTime? bestEnd = null;

            for (DateTime cur = t0; cur <= t1; cur = cur.AddMinutes(15))
            {
                var at = new AstroTime(cur);
                var sunEq = Astronomy.Equator(Body.Sun, at, obs, EquatorEpoch.OfDate, Aberration.Corrected);
                var sunHor = Astronomy.Horizon(at, obs, sunEq.ra, sunEq.dec, Refraction.Normal);
                var moonEq = Astronomy.Equator(Body.Moon, at, obs, EquatorEpoch.OfDate, Aberration.Corrected);
                var moonHor = Astronomy.Horizon(at, obs, moonEq.ra, moonEq.dec, Refraction.Normal);
                double moonIllum = Astronomy.Illumination(Body.Moon, at).phase_fraction;

                bool isDark = sunHor.altitude <= -12.0 && (moonHor.altitude <= 5.0 || moonIllum < 0.35);
                if (isDark)
                {
                    winStart ??= cur;
                    winEnd = cur;
                    if (!bestStart.HasValue || (winEnd.Value - winStart.Value) > (bestEnd!.Value - bestStart.Value))
                    {
                        bestStart = winStart;
                        bestEnd = winEnd;
                    }
                }
                else
                {
                    winStart = null;
                    winEnd = null;
                }
            }

            if (bestStart.HasValue && bestEnd.HasValue && (bestEnd.Value - bestStart.Value).TotalMinutes >= 30)
            {
                return $"{bestStart.Value.ToLocalTime():HH:mm}–{bestEnd.Value.ToLocalTime():HH:mm}";
            }
            return null;
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
            _ => Body.Sun
        };
    }
}
