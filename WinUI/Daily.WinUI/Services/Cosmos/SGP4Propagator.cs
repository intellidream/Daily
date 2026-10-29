using System;
using System.Collections.Generic;
using System.Globalization;
using CosineKitty;
using Daily.Models;

namespace Daily_WinUI.Services.Cosmos
{
    /// <summary>
    /// Native NORAD / Vallado SGP4 near-Earth orbital propagator + WGS84 topocentric observer pass solver.
    /// Zero synthetic sine-wave passes — every position, Earth umbra check, and pass window is analytically derived.
    /// </summary>
    public static class SGP4Propagator
    {
        private const double Xke = 0.0743669161331734132;
        private const double ReKm = 6378.135;
        private const double J2 = 0.001082616;
        private const double J3 = -0.00000253881;
        private const double J4 = -0.00000165597;
        private const double Deg2Rad = Math.PI / 180.0;
        private const double Rad2Deg = 180.0 / Math.PI;
        private const double TwoPi = 2.0 * Math.PI;
        private const double Wgs84A = 6378.137;
        private const double Wgs84E2 = 0.00669437999014;

        public static DateTime? ParseOmmEpochUtc(string epochString)
        {
            if (string.IsNullOrWhiteSpace(epochString)) return null;
            string s = epochString.Trim();
            if (!s.EndsWith("Z", StringComparison.OrdinalIgnoreCase) && !s.Contains("+"))
                s += "Z";
            if (DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dto))
                return dto.UtcDateTime;
            return null;
        }

        public static (double X, double Y, double Z)? PropagateTemeKm(CelesTrakOmmRecord omm, double tsinceMinutes)
        {
            double e0 = omm.Eccentricity;
            if (e0 < 0.0 || e0 >= 1.0 || omm.MeanMotion <= 0.0) return null;

            double xno = omm.MeanMotion * TwoPi / 1440.0;
            double xincl = omm.Inclination * Deg2Rad;
            double xnodeo = omm.RaOfAscNode * Deg2Rad;
            double omegao = omm.ArgOfPericenter * Deg2Rad;
            double xmo = omm.MeanAnomaly * Deg2Rad;
            double bstar = omm.Bstar ?? 0.0001;

            double k2 = 0.5 * J2;
            double k4 = -0.375 * J4;
            double a3ovk2 = -J3 / k2;

            double a1 = Math.Pow(Xke / xno, 2.0 / 3.0);
            double cosio = Math.Cos(xincl);
            double theta2 = cosio * cosio;
            double x3thm1 = 3.0 * theta2 - 1.0;
            double eosq = e0 * e0;
            double betao2 = 1.0 - eosq;
            double betao = Math.Sqrt(betao2);

            double del1 = 1.5 * k2 * x3thm1 / (a1 * a1 * betao * betao2);
            double ao = a1 * (1.0 - del1 * (1.0 / 3.0 + del1 * (1.0 + 134.0 / 81.0 * del1)));
            double delo = 1.5 * k2 * x3thm1 / (ao * ao * betao * betao2);
            double xnodp = xno / (1.0 + delo);
            double aodp = ao / (1.0 - delo);

            double s = 1.0 + 78.0 / ReKm;
            double qoms2t = Math.Pow((120.0 - 78.0) / ReKm, 4.0);
            double perige = (aodp * (1.0 - e0) - 1.0) * ReKm;
            if (perige < 156.0)
            {
                double sfour = perige - 78.0;
                if (perige <= 98.0) sfour = 20.0;
                qoms2t = Math.Pow((120.0 - sfour) / ReKm, 4.0);
                s = sfour / ReKm + 1.0;
            }

            double pinvsq = 1.0 / (aodp * aodp * betao2 * betao2);
            double tsi = 1.0 / (aodp - s);
            double eta = aodp * e0 * tsi;
            double etasq = eta * eta;
            double eeta = e0 * eta;
            double psisq = Math.Abs(1.0 - etasq);
            double coef = qoms2t * Math.Pow(tsi, 4.0);
            double coef1 = coef / Math.Pow(psisq, 3.5);

            double c2 = coef1 * xnodp * (aodp * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq)) +
                        0.75 * k2 * tsi / psisq * x3thm1 * (8.0 + 3.0 * etasq * (8.0 + etasq)));
            double c1 = bstar * c2;
            double sinio = Math.Sin(xincl);
            double x1mth2 = 1.0 - theta2;
            double c4 = 2.0 * xnodp * coef1 * aodp * betao2 * (
                        eta * (2.0 + 0.5 * etasq) + e0 * (0.5 + 2.0 * etasq) -
                        2.0 * k2 * tsi / (aodp * psisq) * (
                            -3.0 * x3thm1 * (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta)) +
                            0.75 * x1mth2 * (2.0 * etasq - eeta * (1.0 + etasq)) * Math.Cos(2.0 * omegao)
                        ));

            double theta4 = theta2 * theta2;
            double temp1 = 3.0 * k2 * pinvsq * xnodp;
            double temp2 = temp1 * k2 * pinvsq;
            double temp3 = 1.25 * k4 * pinvsq * pinvsq * xnodp;

            double xmdot = xnodp + 0.5 * temp1 * betao * x3thm1 +
                           0.0625 * temp2 * betao * (13.0 - 78.0 * theta2 + 137.0 * theta4);
            double x1m5th = 1.0 - 5.0 * theta2;
            double omgdot = -0.5 * temp1 * x1m5th +
                            0.0625 * temp2 * (7.0 - 114.0 * theta2 + 395.0 * theta4) +
                            temp3 * (3.0 - 36.0 * theta2 + 49.0 * theta4);
            double xhdot1 = -temp1 * cosio;
            double xnodot = xhdot1 + (0.5 * temp2 * (4.0 - 19.0 * theta2) + 2.0 * temp3 * (3.0 - 7.0 * theta2)) * cosio;
            double xnodcf = 3.5 * betao2 * xhdot1 * c1;
            double t2cof = 1.5 * c1;
            double xlcof = Math.Abs(1.0 + cosio) > 1.5e-12
                ? 0.125 * (J3 / k2) * sinio * (3.0 + 5.0 * cosio) / (1.0 + cosio)
                : 0.0;
            double aycof = 0.25 * (J3 / k2) * sinio;

            double xmdf = xmo + xmdot * tsinceMinutes;
            double omgadf = omegao + omgdot * tsinceMinutes;
            double xnoddf = xnodeo + xnodot * tsinceMinutes;
            double tsq = tsinceMinutes * tsinceMinutes;
            double xnode = xnoddf + xnodcf * tsq;
            double tempa = 1.0 - c1 * tsinceMinutes;
            double tempe = bstar * c4 * tsinceMinutes;
            double templ = t2cof * tsq;

            double a = aodp * tempa * tempa;
            double e = Math.Clamp(e0 - tempe, 1e-6, 0.999);
            double xl = xmdf + omgadf + xnode + xnodp * templ;

            double beta = Math.Sqrt(1.0 - e * e);
            double xn = Xke / Math.Pow(a, 1.5);
            double axn = e * Math.Cos(omgadf);
            double temp = 1.0 / (a * beta * beta);
            double xll = temp * xlcof * axn;
            double aynl = temp * aycof;
            double xlt = xl + xll;
            double ayn = e * Math.Sin(omgadf) + aynl;

            double capu = ((xlt - xnode) % TwoPi + TwoPi) % TwoPi;
            double epw = capu;
            for (int iter = 0; iter < 10; iter++)
            {
                double sinepw = Math.Sin(epw);
                double cosepw = Math.Cos(epw);
                double epwNew = epw + (capu - ayn * cosepw + axn * sinepw - epw) / (1.0 - cosepw * axn - sinepw * ayn);
                if (Math.Abs(epwNew - epw) < 1e-12)
                {
                    epw = epwNew;
                    break;
                }
                epw = epwNew;
            }

            double sinepwF = Math.Sin(epw);
            double cosepwF = Math.Cos(epw);
            double ecose = axn * cosepwF + ayn * sinepwF;
            double esine = axn * sinepwF - ayn * cosepwF;
            double elsq = axn * axn + ayn * ayn;
            double tempL = 1.0 - elsq;
            double pl = a * tempL;
            if (pl < 0.0) return null;

            double r = a * (1.0 - ecose);
            double temp2L = a / r;
            double betal = Math.Sqrt(tempL);
            double temp3L = 1.0 / (1.0 + betal);
            double cosu = temp2L * (cosepwF - axn + ayn * esine * temp3L);
            double sinu = temp2L * (sinepwF - ayn - axn * esine * temp3L);
            double u = Math.Atan2(sinu, cosu);
            double sin2u = 2.0 * sinu * cosu;
            double cos2u = 2.0 * cosu * cosu - 1.0;

            double tempP = 1.0 / pl;
            double temp1P = k2 * tempP;
            double temp2P = temp1P * tempP;

            double rk = r * (1.0 - 1.5 * temp2P * betal * x3thm1) + 0.5 * temp1P * x1mth2 * cos2u;
            double uk = u - 0.25 * temp2P * (7.0 * theta2 - 1.0) * sin2u;
            double xnodek = xnode + 1.5 * temp2P * cosio * sin2u;
            double xinck = xincl + 1.5 * temp2P * cosio * sinio * cos2u;

            double sinuk = Math.Sin(uk);
            double cosuk = Math.Cos(uk);
            double sinik = Math.Sin(xinck);
            double cosik = Math.Cos(xinck);
            double sinnok = Math.Sin(xnodek);
            double cosnok = Math.Cos(xnodek);

            double xmx = -sinnok * cosik;
            double xmy = cosnok * cosik;
            double ux = xmx * sinuk + cosnok * cosuk;
            double uy = xmy * sinuk + sinnok * cosuk;
            double uz = sinik * sinuk;

            double rKm = rk * ReKm;
            return (rKm * ux, rKm * uy, rKm * uz);
        }

        private static double GmstRadians(DateTime utcTime)
        {
            double unixDays = (utcTime.ToUniversalTime() - DateTime.UnixEpoch).TotalDays;
            double jd = unixDays + 2440587.5;
            double t = (jd - 2451545.0) / 36525.0;
            double gmstDeg = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t - (t * t * t) / 38710000.0;
            double norm = (gmstDeg % 360.0 + 360.0) % 360.0;
            return norm * Deg2Rad;
        }

        private static (double X, double Y, double Z) ObserverEcefKm(double latDeg, double lonDeg, double elevMeters)
        {
            double lat = latDeg * Deg2Rad;
            double lon = lonDeg * Deg2Rad;
            double sinLat = Math.Sin(lat);
            double cosLat = Math.Cos(lat);
            double n = Wgs84A / Math.Sqrt(1.0 - Wgs84E2 * sinLat * sinLat);
            double hKm = elevMeters / 1000.0;
            return (
                (n + hKm) * cosLat * Math.Cos(lon),
                (n + hKm) * cosLat * Math.Sin(lon),
                (n * (1.0 - Wgs84E2) + hKm) * sinLat
            );
        }

        private static bool IsSatelliteSunlit((double X, double Y, double Z) temeKm, DateTime utcTime)
        {
            var sunEqj = Astronomy.GeoVector(Body.Sun, new AstroTime(utcTime), Aberration.None);
            double auKm = 149_597_870.7;
            double sx = sunEqj.x * auKm;
            double sy = sunEqj.y * auKm;
            double sz = sunEqj.z * auKm;
            double sNorm = Math.Sqrt(sx * sx + sy * sy + sz * sz);
            if (sNorm <= 1e-6) return true;
            double ux = sx / sNorm;
            double uy = sy / sNorm;
            double uz = sz / sNorm;

            double proj = temeKm.X * ux + temeKm.Y * uy + temeKm.Z * uz;
            if (proj >= 0.0) return true;

            double px = temeKm.X - proj * ux;
            double py = temeKm.Y - proj * uy;
            double pz = temeKm.Z - proj * uz;
            double perpDist = Math.Sqrt(px * px + py * py + pz * pz);
            return perpDist > Wgs84A;
        }

        public static LiveSatellitePosition? LivePosition(
            CelesTrakOmmRecord omm,
            DateTime utcTime,
            double latitude,
            double longitude,
            double elevationMeters = 0.0)
        {
            var epoch = ParseOmmEpochUtc(omm.Epoch);
            if (!epoch.HasValue) return null;
            double tsinceMin = (utcTime.ToUniversalTime() - epoch.Value).TotalMinutes;
            var teme = PropagateTemeKm(omm, tsinceMin);
            if (!teme.HasValue) return null;

            double gmst = GmstRadians(utcTime);
            double cosG = Math.Cos(gmst);
            double sinG = Math.Sin(gmst);

            double ex = cosG * teme.Value.X + sinG * teme.Value.Y;
            double ey = -sinG * teme.Value.X + cosG * teme.Value.Y;
            double ez = teme.Value.Z;

            var obs = ObserverEcefKm(latitude, longitude, elevationMeters);
            double dx = ex - obs.X;
            double dy = ey - obs.Y;
            double dz = ez - obs.Z;
            double rangeKm = Math.Sqrt(dx * dx + dy * dy + dz * dz);
            if (rangeKm <= 1e-6) return null;

            double lat = latitude * Deg2Rad;
            double lon = longitude * Deg2Rad;
            double sinLat = Math.Sin(lat);
            double cosLat = Math.Cos(lat);
            double sinLon = Math.Sin(lon);
            double cosLon = Math.Cos(lon);

            double south = sinLat * cosLon * dx + sinLat * sinLon * dy - cosLat * dz;
            double east = -sinLon * dx + cosLon * dy;
            double up = cosLat * cosLon * dx + cosLat * sinLon * dy + sinLat * dz;

            double altDeg = Math.Asin(Math.Clamp(up / rangeKm, -1.0, 1.0)) * Rad2Deg;
            double azDeg = (Math.Atan2(east, -south) * Rad2Deg + 360.0) % 360.0;

            double rEcef = Math.Sqrt(ex * ex + ey * ey + ez * ez);
            double subLatDeg = Math.Asin(Math.Clamp(ez / Math.Max(1.0, rEcef), -1.0, 1.0)) * Rad2Deg;
            double subLonDeg = Math.Atan2(ey, ex) * Rad2Deg;
            double orbAltKm = rEcef - Wgs84A;

            bool sunlit = IsSatelliteSunlit(teme.Value, utcTime);
            double estMag = sunlit
                ? Math.Clamp(-1.8 + 5.0 * Math.Log10(Math.Max(100.0, rangeKm) / 1000.0), -3.9, 4.5)
                : 12.0;

            return new LiveSatellitePosition
            {
                SatelliteName = omm.ObjectName,
                NoradCatalogNumber = omm.NoradCatId,
                TimestampUtc = utcTime.ToUniversalTime(),
                AzimuthDegrees = azDeg,
                AltitudeDegrees = altDeg,
                RangeKm = rangeKm,
                OrbitalAltitudeKm = orbAltKm,
                SubSatelliteLatitude = subLatDeg,
                SubSatelliteLongitude = subLonDeg,
                IsSunlit = sunlit,
                EstimatedMagnitude = estMag
            };
        }

        public static List<SatellitePass> PredictVisiblePasses(
            CelesTrakOmmRecord omm,
            double latitude,
            double longitude,
            double elevationMeters = 0.0,
            DateTime? startUtc = null,
            int hoursAhead = 48,
            double minPeakAltitudeDeg = 10.0,
            bool requireSunlitAndDarkSky = true)
        {
            DateTime start = (startUtc ?? DateTime.UtcNow).ToUniversalTime();
            var passes = new List<SatellitePass>();
            const double stepSec = 30.0;
            int totalSteps = (int)((hoursAhead * 3600.0) / stepSec);
            var observer = new Observer(latitude, longitude, elevationMeters);

            bool inPass = false;
            DateTime passStartUtc = start;
            double startAz = 0.0;
            DateTime maxUtc = start;
            double maxAlt = -90.0;
            double maxAz = 0.0;
            double bestMag = 4.0;
            bool anySunlit = false;
            bool darkSkyAtPeak = false;
            var samples = new List<SatelliteTrajectorySample>();

            for (int i = 0; i <= totalSteps; i++)
            {
                DateTime t = start.AddSeconds(i * stepSec);
                var pos = LivePosition(omm, t, latitude, longitude, elevationMeters);
                if (pos == null) continue;

                if (pos.AltitudeDegrees >= 0.0)
                {
                    if (!inPass)
                    {
                        inPass = true;
                        passStartUtc = t;
                        startAz = pos.AzimuthDegrees;
                        maxUtc = t;
                        maxAlt = pos.AltitudeDegrees;
                        maxAz = pos.AzimuthDegrees;
                        bestMag = pos.IsSunlit ? pos.EstimatedMagnitude : 12.0;
                        anySunlit = pos.IsSunlit && pos.AltitudeDegrees >= 10.0;
                        darkSkyAtPeak = false;
                        samples = new List<SatelliteTrajectorySample>();
                    }
                    samples.Add(new SatelliteTrajectorySample
                    {
                        TimestampUtc = t,
                        AzimuthDegrees = pos.AzimuthDegrees,
                        AltitudeDegrees = pos.AltitudeDegrees,
                        IsSunlit = pos.IsSunlit
                    });
                    if (pos.IsSunlit && pos.AltitudeDegrees >= 10.0)
                    {
                        anySunlit = true;
                        if (pos.EstimatedMagnitude < bestMag) bestMag = pos.EstimatedMagnitude;
                    }
                    if (pos.AltitudeDegrees > maxAlt)
                    {
                        maxAlt = pos.AltitudeDegrees;
                        maxUtc = t;
                        maxAz = pos.AzimuthDegrees;
                        var at = new AstroTime(t);
                        var sunEq = Astronomy.Equator(Body.Sun, at, observer, EquatorEpoch.OfDate, Aberration.Corrected);
                        var sunHor = Astronomy.Horizon(at, observer, sunEq.ra, sunEq.dec, Refraction.Normal);
                        darkSkyAtPeak = sunHor.altitude <= -6.0;
                    }
                }
                else if (inPass)
                {
                    inPass = false;
                    var lastSample = samples.Count > 0 ? samples[^1] : null;
                    DateTime endUtc = lastSample?.TimestampUtc ?? t;
                    double endAz = lastSample?.AzimuthDegrees ?? pos.AzimuthDegrees;
                    bool qualifies = maxAlt >= minPeakAltitudeDeg && (!requireSunlitAndDarkSky || (anySunlit && bestMag < 5.0 && darkSkyAtPeak));
                    if (qualifies)
                    {
                        passes.Add(new SatellitePass
                        {
                            Id = $"{omm.NoradCatId}-{new DateTimeOffset(passStartUtc).ToUnixTimeSeconds()}",
                            SatelliteName = omm.ObjectName,
                            NoradCatalogNumber = omm.NoradCatId,
                            StartTimeUtc = passStartUtc,
                            MaxAltitudeTimeUtc = maxUtc,
                            EndTimeUtc = endUtc,
                            MaxAltitudeDegrees = maxAlt,
                            StartAzimuthDegrees = startAz,
                            MaxAzimuthDegrees = maxAz,
                            EndAzimuthDegrees = endAz,
                            StartCompass = CompassDirection(startAz),
                            EndCompass = CompassDirection(endAz),
                            PeakMagnitude = bestMag,
                            IsSunlit = anySunlit,
                            Trajectory = samples
                        });
                        if (passes.Count >= 8) break;
                    }
                }
            }

            return passes;
        }

        public static string CompassDirection(double azimuthDegrees)
        {
            string[] dirs = { "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" };
            double norm = (azimuthDegrees % 360.0 + 360.0) % 360.0;
            int idx = (int)Math.Round(norm / 22.5) % 16;
            return dirs[idx];
        }
    }
}
