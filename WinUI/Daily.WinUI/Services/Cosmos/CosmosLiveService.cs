using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using Daily.Models;
using Daily.Services;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI.Services.Cosmos
{
    public class CosmosWeatherOverlay
    {
        public int CloudTotalPercent { get; set; }
        public int CloudLowPercent { get; set; }
        public int CloudMidPercent { get; set; }
        public int CloudHighPercent { get; set; }
        public double? VisibilityKm { get; set; }
        public double? TemperatureCelsius { get; set; }
        public double? DewPointCelsius { get; set; }
        public double? SeeingArcseconds { get; set; }
        public string? TransparencyLabel { get; set; }
        public DateTime CachedAtUtc { get; set; } = DateTime.UtcNow;
        public TelemetryProvenance Provenance { get; set; } = TelemetryProvenance.OfflineCalculated();
    }

    public class CosmosLiveBundle
    {
        public CosmosWeatherOverlay? WeatherOverlay { get; set; }
        public SpaceWeatherReport SpaceWeather { get; set; } = new();
        public ApodResponse? Apod { get; set; }
        public TelemetryProvenance ApodProvenance { get; set; } = TelemetryProvenance.Unavailable();
        public CelesTrakOmmRecord? IssOmm { get; set; }
        public LiveSatellitePosition? IssLivePosition { get; set; }
        public List<SatellitePass> IssPasses { get; set; } = new();
        public TelemetryProvenance IssProvenance { get; set; } = TelemetryProvenance.Unavailable();
    }

    public sealed class CosmosLiveService
    {
        private static readonly Lazy<CosmosLiveService> _instance = new(() => new CosmosLiveService());
        public static CosmosLiveService Shared => _instance.Value;

        private readonly HttpClient _http;
        private readonly string _cacheDir;
        private readonly JsonSerializerOptions _jsonOpts = new()
        {
            PropertyNameCaseInsensitive = true,
            WriteIndented = true
        };

        private CosmosLiveService()
        {
            _http = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            _http.DefaultRequestHeaders.UserAgent.ParseAdd("DailyObservatory/2.0 (Windows11-WinUI3)");
            _cacheDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Daily", "CosmosCache");
            Directory.CreateDirectory(_cacheDir);
        }

        // ── Preferences (NASA API Key, Weather Endpoint/Key, Alert Toggles) ────

        private string PreferencesPath => Path.Combine(_cacheDir, "cosmos_preferences.json");

        public CosmosLocalPreferences LoadPreferences()
        {
            try
            {
                if (File.Exists(PreferencesPath))
                {
                    return JsonSerializer.Deserialize<CosmosLocalPreferences>(File.ReadAllText(PreferencesPath), _jsonOpts)
                           ?? new CosmosLocalPreferences();
                }
            }
            catch { }
            return new CosmosLocalPreferences();
        }

        public void SavePreferences(CosmosLocalPreferences prefs)
        {
            try
            {
                File.WriteAllText(PreferencesPath, JsonSerializer.Serialize(prefs, _jsonOpts));
            }
            catch { }
        }

        // ── Parallel Live Bundle Fetch ─────────────────────────────────────────

        public async Task<CosmosLiveBundle> FetchLiveBundleAsync(double latitude, double longitude, double elevationMeters = 0.0)
        {
            var prefs = LoadPreferences();
            var weatherTask = FetchWeatherAndSeeingAsync(latitude, longitude, prefs);
            var spaceTask = FetchSpaceWeatherAsync();
            var apodTask = FetchApodAsync(prefs.NasaApiKey);
            var ommTask = FetchOrLoadIssOmmAsync();

            await Task.WhenAll(weatherTask, spaceTask, apodTask, ommTask).ConfigureAwait(false);

            var weather = await weatherTask.ConfigureAwait(false);
            var space = await spaceTask.ConfigureAwait(false);
            var (apod, apodProv) = await apodTask.ConfigureAwait(false);
            var (omm, issProv) = await ommTask.ConfigureAwait(false);

            DateTime nowUtc = DateTime.UtcNow;
            var livePos = omm != null ? SGP4Propagator.LivePosition(omm, nowUtc, latitude, longitude, elevationMeters) : null;
            var passes = omm != null
                ? SGP4Propagator.PredictVisiblePasses(omm, latitude, longitude, elevationMeters, nowUtc, 48, 10.0, true)
                : new List<SatellitePass>();

            EvaluateOptInSkyAlerts(prefs, latitude, longitude, weather, space, passes);

            return new CosmosLiveBundle
            {
                WeatherOverlay = weather,
                SpaceWeather = space,
                Apod = apod,
                ApodProvenance = apodProv,
                IssOmm = omm,
                IssLivePosition = livePos,
                IssPasses = passes,
                IssProvenance = issProv
            };
        }

        // ── 1. Open-Meteo UTC Multi-Layer Clouds + 7Timer ASTRO Seeing ─────────

        private async Task<CosmosWeatherOverlay?> FetchWeatherAndSeeingAsync(double lat, double lon, CosmosLocalPreferences prefs)
        {
            string cachePath = Path.Combine(_cacheDir, "sky_weather.json");
            var seeingTask = Fetch7TimerSeeingAsync(lat, lon);

            string baseEndpoint = string.IsNullOrWhiteSpace(prefs.WeatherEndpoint)
                ? "https://api.open-meteo.com/v1/forecast"
                : prefs.WeatherEndpoint.Trim();
            string apiKeyParam = string.IsNullOrWhiteSpace(prefs.WeatherApiKey) ? "" : $"&apikey={Uri.EscapeDataString(prefs.WeatherApiKey.Trim())}";
            string url = FormattableString.Invariant(
                $"{baseEndpoint}?latitude={lat:F4}&longitude={lon:F4}&hourly=cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,temperature_2m,dew_point_2m&forecast_days=2&timezone=UTC{apiKeyParam}");

            string? raw = await SafeGetStringAsync(url).ConfigureAwait(false);
            var (seeingArcsec, transLabel) = await seeingTask.ConfigureAwait(false);

            if (!string.IsNullOrWhiteSpace(raw))
            {
                var parsed = ParseOpenMeteoUtc(raw, seeingArcsec, transLabel);
                if (parsed != null)
                {
                    try { File.WriteAllText(cachePath, JsonSerializer.Serialize(parsed, _jsonOpts)); } catch { }
                    return parsed;
                }
            }

            if (File.Exists(cachePath))
            {
                try
                {
                    var cached = JsonSerializer.Deserialize<CosmosWeatherOverlay>(File.ReadAllText(cachePath), _jsonOpts);
                    if (cached != null)
                    {
                        long ageSec = Math.Max(1, (long)(DateTime.UtcNow - cached.CachedAtUtc).TotalSeconds);
                        cached.Provenance = TelemetryProvenance.Cached(ageSec, "Open-Meteo + 7Timer");
                        return cached;
                    }
                }
                catch { }
            }
            return null;
        }

        private static CosmosWeatherOverlay? ParseOpenMeteoUtc(string rawJson, double? seeingArcsec, string? transLabel)
        {
            try
            {
                using var doc = JsonDocument.Parse(rawJson);
                if (!doc.RootElement.TryGetProperty("hourly", out var hourly)) return null;
                if (!hourly.TryGetProperty("time", out var times) || times.GetArrayLength() == 0) return null;

                DateTime nowUtc = DateTime.UtcNow;
                int bestIdx = 0;
                double bestDiffSec = double.MaxValue;
                int len = times.GetArrayLength();
                for (int i = 0; i < len; i++)
                {
                    string? iso = times[i].GetString();
                    if (string.IsNullOrWhiteSpace(iso)) continue;
                    string norm = iso.EndsWith("Z", StringComparison.Ordinal) ? iso : iso + "Z";
                    if (DateTimeOffset.TryParse(norm, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dto))
                    {
                        double diff = Math.Abs((dto.UtcDateTime - nowUtc).TotalSeconds);
                        if (diff < bestDiffSec)
                        {
                            bestDiffSec = diff;
                            bestIdx = i;
                        }
                    }
                }

                int ReadInt(string key, int fallback)
                {
                    if (hourly.TryGetProperty(key, out var arr) && bestIdx < arr.GetArrayLength() && arr[bestIdx].ValueKind == JsonValueKind.Number)
                        return (int)Math.Round(arr[bestIdx].GetDouble());
                    return fallback;
                }
                double? ReadDouble(string key)
                {
                    if (hourly.TryGetProperty(key, out var arr) && bestIdx < arr.GetArrayLength() && arr[bestIdx].ValueKind == JsonValueKind.Number)
                        return arr[bestIdx].GetDouble();
                    return null;
                }

                int total = Math.Clamp(ReadInt("cloud_cover", 0), 0, 100);
                int low = Math.Clamp(ReadInt("cloud_cover_low", total / 3), 0, 100);
                int mid = Math.Clamp(ReadInt("cloud_cover_mid", total / 3), 0, 100);
                int high = Math.Clamp(ReadInt("cloud_cover_high", total / 3), 0, 100);
                double? visMeters = ReadDouble("visibility");

                return new CosmosWeatherOverlay
                {
                    CloudTotalPercent = total,
                    CloudLowPercent = low,
                    CloudMidPercent = mid,
                    CloudHighPercent = high,
                    VisibilityKm = visMeters.HasValue ? visMeters.Value / 1000.0 : null,
                    TemperatureCelsius = ReadDouble("temperature_2m"),
                    DewPointCelsius = ReadDouble("dew_point_2m"),
                    SeeingArcseconds = seeingArcsec,
                    TransparencyLabel = transLabel,
                    CachedAtUtc = DateTime.UtcNow,
                    Provenance = TelemetryProvenance.Live(seeingArcsec.HasValue ? "Open-Meteo UTC + 7Timer ASTRO" : "Open-Meteo UTC")
                };
            }
            catch
            {
                return null;
            }
        }

        private async Task<(double? SeeingArcsec, string? Transparency)> Fetch7TimerSeeingAsync(double lat, double lon)
        {
            string url = FormattableString.Invariant(
                $"https://www.7timer.info/bin/astro.php?lon={lon:F3}&lat={lat:F3}&ac=0&unit=metric&output=json&tzshift=0");
            string? raw = await SafeGetStringAsync(url).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(raw)) return (null, null);
            try
            {
                using var doc = JsonDocument.Parse(raw);
                if (!doc.RootElement.TryGetProperty("dataseries", out var ds) || ds.GetArrayLength() == 0)
                    return (null, null);
                var first = ds[0];
                double? seeing = null;
                string? trans = null;
                if (first.TryGetProperty("seeing", out var sEl) && sEl.ValueKind == JsonValueKind.Number)
                {
                    seeing = sEl.GetInt32() switch
                    {
                        1 => 0.7, 2 => 0.9, 3 => 1.1, 4 => 1.4,
                        5 => 1.8, 6 => 2.3, 7 => 3.0, 8 => 4.0,
                        _ => null
                    };
                }
                if (first.TryGetProperty("transparency", out var tEl) && tEl.ValueKind == JsonValueKind.Number)
                {
                    trans = tEl.GetInt32() switch
                    {
                        1 or 2 => "Crystal (<0.4 mag)",
                        3 => "Clear (0.5 mag)",
                        4 => "Moderate (0.7 mag)",
                        5 or 6 => "Hazy (1.0 mag)",
                        7 or 8 => "Poor (>1.2 mag)",
                        _ => null
                    };
                }
                return (seeing, trans);
            }
            catch
            {
                return (null, null);
            }
        }

        // ── 2. Real NOAA SWPC Space Weather ────────────────────────────────────

        private async Task<SpaceWeatherReport> FetchSpaceWeatherAsync()
        {
            string cachePath = Path.Combine(_cacheDir, "space_weather.json");
            var kpTask = SafeGetStringAsync("https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json");
            var magTask = SafeGetStringAsync("https://services.swpc.noaa.gov/json/rtsw/rtsw_mag_1m.json");
            var windTask = SafeGetStringAsync("https://services.swpc.noaa.gov/json/rtsw/rtsw_wind_1m.json");

            await Task.WhenAll(kpTask, magTask, windTask).ConfigureAwait(false);
            double? kp = ParseNoaaKp(await kpTask.ConfigureAwait(false));
            var (bt, bz) = ParseNoaaMag(await magTask.ConfigureAwait(false));
            var (speed, density) = ParseNoaaWind(await windTask.ConfigureAwait(false));

            if (kp.HasValue || bz.HasValue || speed.HasValue)
            {
                double kVal = kp ?? 2.0;
                bool alert = kVal >= 5.0 || (bz.HasValue && bz.Value <= -8.0 && kVal >= 4.0);
                string status = kVal >= 7.0
                    ? "Severe Geomagnetic Storm (G3+) — Mid-latitude aurora active!"
                    : kVal >= 5.0
                        ? "Geomagnetic Storm (G1–G2) — High-latitude aurora active."
                        : (bz.HasValue && bz.Value <= -5.0)
                            ? $"Southward IMF Bz ({bz.Value:F1} nT) — Substorm coupling favorable."
                            : $"Quiet magnetosphere (Kp {kVal:F1}) — Stable dark-sky conditions.";

                var report = new SpaceWeatherReport
                {
                    KpIndex = kp,
                    BtTotalFieldNt = bt,
                    BzMagneticFieldNt = bz,
                    SolarWindSpeedKmS = speed,
                    SolarWindDensityCm3 = density,
                    IsAuroraAlertActive = alert,
                    StatusMessage = status,
                    Provenance = TelemetryProvenance.Live("NOAA SWPC DSCOVR/Planetary-K")
                };
                try { File.WriteAllText(cachePath, JsonSerializer.Serialize(report, _jsonOpts)); } catch { }
                return report;
            }

            if (File.Exists(cachePath))
            {
                try
                {
                    var cached = JsonSerializer.Deserialize<SpaceWeatherReport>(File.ReadAllText(cachePath), _jsonOpts);
                    if (cached != null)
                    {
                        long ageSec = Math.Max(1, (long)(DateTime.UtcNow - File.GetLastWriteTimeUtc(cachePath)).TotalSeconds);
                        cached.Provenance = TelemetryProvenance.Cached(ageSec, "NOAA SWPC");
                        return cached;
                    }
                }
                catch { }
            }

            return new SpaceWeatherReport
            {
                StatusMessage = "NOAA SWPC live telemetry unavailable offline.",
                Provenance = TelemetryProvenance.Unavailable("Offline")
            };
        }

        private static double? ParseNoaaKp(string? raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return null;
            try
            {
                using var doc = JsonDocument.Parse(raw);
                if (doc.RootElement.ValueKind != JsonValueKind.Array) return null;
                for (int i = doc.RootElement.GetArrayLength() - 1; i >= 0; i--)
                {
                    var row = doc.RootElement[i];
                    if (row.ValueKind == JsonValueKind.Object)
                    {
                        foreach (string key in new[] { "Kp", "kp_index", "kp" })
                        {
                            if (row.TryGetProperty(key, out var prop))
                            {
                                if (prop.ValueKind == JsonValueKind.Number && prop.TryGetDouble(out double d))
                                    return d;
                                string? s = prop.ValueKind == JsonValueKind.String ? prop.GetString() : prop.ToString();
                                if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out double v))
                                    return v;
                            }
                        }
                    }
                    else if (i >= 1 && row.ValueKind == JsonValueKind.Array && row.GetArrayLength() >= 2)
                    {
                        string? s = row[1].ValueKind == JsonValueKind.String ? row[1].GetString() : row[1].ToString();
                        if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out double v))
                            return v;
                    }
                }
            }
            catch { }
            return null;
        }

        private static (double? Bt, double? Bz) ParseNoaaMag(string? raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return (null, null);
            try
            {
                using var doc = JsonDocument.Parse(raw);
                if (doc.RootElement.ValueKind != JsonValueKind.Array) return (null, null);
                for (int i = doc.RootElement.GetArrayLength() - 1; i >= 0; i--)
                {
                    var obj = doc.RootElement[i];
                    double? bt = obj.TryGetProperty("bt", out var btEl) && btEl.ValueKind == JsonValueKind.Number ? btEl.GetDouble() : null;
                    double? bz = obj.TryGetProperty("bz_gsm", out var bzEl) && bzEl.ValueKind == JsonValueKind.Number ? bzEl.GetDouble() : null;
                    if (bt.HasValue || bz.HasValue) return (bt, bz);
                }
            }
            catch { }
            return (null, null);
        }

        private static (double? Speed, double? Density) ParseNoaaWind(string? raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return (null, null);
            try
            {
                using var doc = JsonDocument.Parse(raw);
                if (doc.RootElement.ValueKind != JsonValueKind.Array) return (null, null);
                for (int i = doc.RootElement.GetArrayLength() - 1; i >= 0; i--)
                {
                    var obj = doc.RootElement[i];
                    double? sp = obj.TryGetProperty("proton_speed", out var s1) && s1.ValueKind == JsonValueKind.Number ? s1.GetDouble()
                               : obj.TryGetProperty("speed", out var s2) && s2.ValueKind == JsonValueKind.Number ? s2.GetDouble() : null;
                    double? dn = obj.TryGetProperty("proton_density", out var d1) && d1.ValueKind == JsonValueKind.Number ? d1.GetDouble()
                               : obj.TryGetProperty("density", out var d2) && d2.ValueKind == JsonValueKind.Number ? d2.GetDouble() : null;
                    if (sp.HasValue && sp.Value > 0.0) return (sp, dn);
                }
            }
            catch { }
            return (null, null);
        }

        // ── 3. CelesTrak ISS OMM + 7-Day Offline Cache (Zero Synthetic Passes) ─

        private async Task<(CelesTrakOmmRecord?, TelemetryProvenance)> FetchOrLoadIssOmmAsync()
        {
            string cachePath = Path.Combine(_cacheDir, "iss_omm.json");
            string? raw = await SafeGetStringAsync("https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=JSON").ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(raw))
            {
                try
                {
                    var list = JsonSerializer.Deserialize<List<CelesTrakOmmRecord>>(raw, _jsonOpts);
                    var first = list?.FirstOrDefault();
                    if (first != null)
                    {
                        File.WriteAllText(cachePath, JsonSerializer.Serialize(first, _jsonOpts));
                        return (first, TelemetryProvenance.Live("CelesTrak GP + SGP4"));
                    }
                }
                catch { }
            }

            if (File.Exists(cachePath))
            {
                try
                {
                    var age = DateTime.UtcNow - File.GetLastWriteTimeUtc(cachePath);
                    if (age.TotalDays <= 7.0)
                    {
                        var omm = JsonSerializer.Deserialize<CelesTrakOmmRecord>(File.ReadAllText(cachePath), _jsonOpts);
                        if (omm != null)
                        {
                            return (omm, TelemetryProvenance.Cached(Math.Max(1, (long)age.TotalSeconds), "Cached CelesTrak OMM + SGP4"));
                        }
                    }
                }
                catch { }
            }
            return (null, TelemetryProvenance.Unavailable("Download ISS orbital elements once while online"));
        }

        // ── 4. NASA APOD (Configurable Key + Cached Fallback) ──────────────────

        private async Task<(ApodResponse?, TelemetryProvenance)> FetchApodAsync(string configuredKey)
        {
            string cachePath = Path.Combine(_cacheDir, "nasa_apod.json");
            string key = string.IsNullOrWhiteSpace(configuredKey) ? "DEMO_KEY" : configuredKey.Trim();
            string? raw = await SafeGetStringAsync($"https://api.nasa.gov/planetary/apod?api_key={Uri.EscapeDataString(key)}").ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(raw))
            {
                try
                {
                    var apod = JsonSerializer.Deserialize<ApodResponse>(raw, _jsonOpts);
                    if (apod != null && !string.IsNullOrWhiteSpace(apod.Title))
                    {
                        File.WriteAllText(cachePath, JsonSerializer.Serialize(apod, _jsonOpts));
                        return (apod, TelemetryProvenance.Live("NASA APOD"));
                    }
                }
                catch { }
            }

            if (File.Exists(cachePath))
            {
                try
                {
                    var apod = JsonSerializer.Deserialize<ApodResponse>(File.ReadAllText(cachePath), _jsonOpts);
                    if (apod != null)
                    {
                        long ageSec = Math.Max(1, (long)(DateTime.UtcNow - File.GetLastWriteTimeUtc(cachePath)).TotalSeconds);
                        return (apod, TelemetryProvenance.Cached(ageSec, "NASA APOD"));
                    }
                }
                catch { }
            }
            return (null, TelemetryProvenance.Unavailable("Set a free NASA API key in Settings if rate-limited"));
        }

        // ── 5. Supabase Bookmarks & Observations + #sky TagDoS Quick Note ──────

        private string BookmarksCachePath => Path.Combine(_cacheDir, "cosmos_bookmarks.json");
        private string ObservationsCachePath => Path.Combine(_cacheDir, "cosmos_observations.json");

        public async Task<List<CosmosBookmarkRecord>> LoadBookmarksAsync()
        {
            var local = new List<CosmosBookmarkRecord>();
            if (File.Exists(BookmarksCachePath))
            {
                try { local = Newtonsoft.Json.JsonConvert.DeserializeObject<List<CosmosBookmarkRecord>>(File.ReadAllText(BookmarksCachePath)) ?? new(); }
                catch { }
            }

            string? uid = GetAuthenticatedUserId();
            Daily_WinUI.App.LogDiagnostic($"[CosmosLiveService] LoadBookmarksAsync started. uid='{uid}', SupabaseClient={(App.SupabaseClient != null)}, SessionUser='{App.SupabaseClient?.Auth?.CurrentSession?.User?.Id}'");
            if (App.SupabaseClient == null) return local;

            try
            {
                var table = App.SupabaseClient.From<CosmosBookmarkRecord>();
                var resp = !string.IsNullOrEmpty(uid)
                    ? await table.Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, uid).Get().ConfigureAwait(false)
                    : (App.SupabaseClient.Auth.CurrentSession != null
                        ? await table.Get().ConfigureAwait(false)
                        : null);

                Daily_WinUI.App.LogDiagnostic($"[CosmosLiveService] LoadBookmarksAsync query result count: {resp?.Models?.Count ?? -1}");
                if (resp?.Models != null && resp.Models.Count > 0)
                {
                    var remoteList = resp.Models;
                    var merged = remoteList.Concat(local)
                        .GroupBy(x => x.ObjectId, StringComparer.OrdinalIgnoreCase)
                        .Select(g => g.First())
                        .ToList();
                    File.WriteAllText(BookmarksCachePath, Newtonsoft.Json.JsonConvert.SerializeObject(merged, Newtonsoft.Json.Formatting.Indented));
                    return merged;
                }
            }
            catch (Exception ex)
            {
                Daily_WinUI.App.LogDiagnostic($"[CosmosLiveService] LoadBookmarksAsync exception: {ex}");
            }
            return local;
        }

        public async Task<List<CosmosBookmarkRecord>> ToggleBookmarkAsync(
            string objectId,
            string objectName,
            string category,
            double? raHours = null,
            double? decDeg = null,
            double? magnitude = null)
        {
            var list = await LoadBookmarksAsync().ConfigureAwait(false);
            string? uid = GetAuthenticatedUserId();
            var existing = list.FirstOrDefault(x => string.Equals(x.ObjectId, objectId, StringComparison.OrdinalIgnoreCase) ||
                                                    string.Equals(x.ObjectName, objectName, StringComparison.OrdinalIgnoreCase));
            if (existing != null)
            {
                list.RemoveAll(x => string.Equals(x.ObjectId, existing.ObjectId, StringComparison.OrdinalIgnoreCase));
                try { File.WriteAllText(BookmarksCachePath, Newtonsoft.Json.JsonConvert.SerializeObject(list, Newtonsoft.Json.Formatting.Indented)); } catch { }
                if (App.SupabaseClient != null)
                {
                    try
                    {
                        var table = App.SupabaseClient.From<CosmosBookmarkRecord>();
                        if (!string.IsNullOrEmpty(uid))
                        {
                            await table
                                .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, uid)
                                .Filter("object_id", Supabase.Postgrest.Constants.Operator.Equals, existing.ObjectId)
                                .Delete()
                                .ConfigureAwait(false);
                        }
                        else
                        {
                            await table
                                .Filter("object_id", Supabase.Postgrest.Constants.Operator.Equals, existing.ObjectId)
                                .Delete()
                                .ConfigureAwait(false);
                        }
                    }
                    catch { }
                }
            }
            else
            {
                var created = new CosmosBookmarkRecord
                {
                    Id = Guid.NewGuid().ToString(),
                    UserId = uid,
                    ObjectId = objectId,
                    ObjectName = objectName,
                    Category = category,
                    RaHours = raHours,
                    DecDeg = decDeg,
                    Magnitude = magnitude,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                };
                list.Insert(0, created);
                try { File.WriteAllText(BookmarksCachePath, Newtonsoft.Json.JsonConvert.SerializeObject(list, Newtonsoft.Json.Formatting.Indented)); } catch { }
                if (App.SupabaseClient != null)
                {
                    try { await App.SupabaseClient.From<CosmosBookmarkRecord>().Upsert(created).ConfigureAwait(false); }
                    catch { }
                }
            }
            return list;
        }

        public async Task<CosmosObservationRecord> LogSightingAndMirrorToTagdosAsync(
            string objectId,
            string objectName,
            string category,
            double latitude,
            double longitude,
            string locationName,
            double? azimuthDeg,
            double? altitudeDeg,
            int bortleClass,
            int stargazingScore,
            string optics = "Naked Eye",
            string notes = "")
        {
            string? uid = GetAuthenticatedUserId();
            string coordsLine = (azimuthDeg.HasValue && altitudeDeg.HasValue)
                ? $"Az {azimuthDeg.Value:F1}° · Alt {altitudeDeg.Value:+0.0;-0.0;0.0}°"
                : "Equatorial Sky Target";
            string noteTitle = $"🌌 Sky Sighting: {objectName}";
            string noteContent = $"{objectName} ({objectId}) observed from {(string.IsNullOrWhiteSpace(locationName) ? "Local Observatory" : locationName)}.\n" +
                                 $"{coordsLine} · Bortle {bortleClass} · Sky Score {stargazingScore}/100 · Optics: {optics}\n" +
                                 (string.IsNullOrWhiteSpace(notes) ? "" : $"{notes}\n") +
                                 "#sky #cosmos";

            string? tagdosNoteId = null;
            try
            {
                var tagdos = App.Current?.Services?.GetService<ITagdosService>();
                if (tagdos != null)
                {
                    var createdNote = await tagdos.CreateQuickNoteAsync(noteTitle, noteContent, false).ConfigureAwait(false);
                    tagdosNoteId = createdNote?.Id;
                }
            }
            catch { }

            var obs = new CosmosObservationRecord
            {
                Id = Guid.NewGuid().ToString(),
                UserId = uid,
                ObjectId = objectId,
                ObjectName = objectName,
                Category = category,
                ObservedAt = DateTime.UtcNow,
                Latitude = latitude,
                Longitude = longitude,
                LocationName = locationName,
                AzimuthDeg = azimuthDeg,
                AltitudeDeg = altitudeDeg,
                BortleClass = bortleClass,
                StargazingScore = stargazingScore,
                Optics = optics,
                Notes = notes,
                TagdosNoteId = tagdosNoteId,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            try
            {
                var local = File.Exists(ObservationsCachePath)
                    ? (Newtonsoft.Json.JsonConvert.DeserializeObject<List<CosmosObservationRecord>>(File.ReadAllText(ObservationsCachePath)) ?? new())
                    : new();
                local.Insert(0, obs);
                File.WriteAllText(ObservationsCachePath, Newtonsoft.Json.JsonConvert.SerializeObject(local, Newtonsoft.Json.Formatting.Indented));
            }
            catch { }

            if (!string.IsNullOrEmpty(uid) && App.SupabaseClient != null)
            {
                try { await App.SupabaseClient.From<CosmosObservationRecord>().Insert(obs).ConfigureAwait(false); }
                catch { }
            }

            return obs;
        }

        public async Task<List<CosmosObservationRecord>> LoadObservationsAsync()
        {
            var local = new List<CosmosObservationRecord>();
            if (File.Exists(ObservationsCachePath))
            {
                try { local = Newtonsoft.Json.JsonConvert.DeserializeObject<List<CosmosObservationRecord>>(File.ReadAllText(ObservationsCachePath)) ?? new(); }
                catch { }
            }

            string? uid = GetAuthenticatedUserId();
            if (App.SupabaseClient != null)
            {
                try
                {
                    var query = App.SupabaseClient.From<CosmosObservationRecord>();
                    var resp = !string.IsNullOrEmpty(uid)
                        ? await query.Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, uid)
                            .Order("observed_at", Supabase.Postgrest.Constants.Ordering.Descending)
                            .Limit(50)
                            .Get().ConfigureAwait(false)
                        : (App.SupabaseClient.Auth.CurrentSession != null
                            ? await query
                                .Order("observed_at", Supabase.Postgrest.Constants.Ordering.Descending)
                                .Limit(50)
                                .Get().ConfigureAwait(false)
                            : null);

                    if (resp?.Models != null && resp.Models.Count > 0)
                    {
                        var merged = resp.Models.Concat(local).DistinctBy(x => x.Id).OrderByDescending(x => x.ObservedAt).ToList();
                        File.WriteAllText(ObservationsCachePath, Newtonsoft.Json.JsonConvert.SerializeObject(merged, Newtonsoft.Json.Formatting.Indented));
                        return merged;
                    }
                }
                catch { }
            }
            return local;
        }

        public async Task DeleteObservationAsync(string id)
        {
            var list = await LoadObservationsAsync().ConfigureAwait(false);
            list.RemoveAll(x => x.Id == id);
            try { File.WriteAllText(ObservationsCachePath, Newtonsoft.Json.JsonConvert.SerializeObject(list, Newtonsoft.Json.Formatting.Indented)); } catch { }

            string? uid = GetAuthenticatedUserId();
            if (App.SupabaseClient != null)
            {
                try
                {
                    var table = App.SupabaseClient.From<CosmosObservationRecord>();
                    if (!string.IsNullOrEmpty(uid))
                    {
                        await table
                            .Filter("id", Supabase.Postgrest.Constants.Operator.Equals, id)
                            .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, uid)
                            .Delete().ConfigureAwait(false);
                    }
                    else
                    {
                        await table
                            .Filter("id", Supabase.Postgrest.Constants.Operator.Equals, id)
                            .Delete().ConfigureAwait(false);
                    }
                }
                catch { }
            }
        }

        private static string? GetAuthenticatedUserId()
        {
            try
            {
                var sessionUid = App.SupabaseClient?.Auth?.CurrentSession?.User?.Id;
                if (!string.IsNullOrWhiteSpace(sessionUid) && sessionUid != "guest")
                    return sessionUid;

                var settings = App.Current?.Services?.GetService<ISettingsService>();
                if (settings?.IsAuthenticated == true && !string.IsNullOrWhiteSpace(settings.CurrentUserId) && settings.CurrentUserId != "guest")
                    return settings.CurrentUserId;

                var auth = App.Current?.Services?.GetService<Daily_WinUI.Services.WinUIAuthService>();
                if (auth?.IsAuthenticated == true && !string.IsNullOrWhiteSpace(auth.CurrentUserId) && auth.CurrentUserId != "guest")
                    return auth.CurrentUserId;

                var userUid = App.SupabaseClient?.Auth?.CurrentUser?.Id;
                if (!string.IsNullOrWhiteSpace(userUid) && userUid != "guest")
                    return userUid;

                return null;
            }
            catch
            {
                return null;
            }
        }

        private static readonly HashSet<string> _dispatchedAlertIds = new();

        private static void EvaluateOptInSkyAlerts(
            CosmosLocalPreferences prefs,
            double latitude,
            double longitude,
            CosmosWeatherOverlay? weather,
            SpaceWeatherReport space,
            List<SatellitePass> passes)
        {
            if (!prefs.NotifyIssPasses && !prefs.NotifyAurora && !prefs.NotifyPristineSky)
                return;

            try
            {
                string todayKey = DateTime.UtcNow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

                if (prefs.NotifyIssPasses)
                {
                    var brightPass = passes.FirstOrDefault(p =>
                        p.IsSunlit &&
                        p.MaxAltitudeDegrees >= 40.0 &&
                        (p.StartTimeUtc - DateTime.UtcNow).TotalMinutes is > 5.0 and <= 90.0);
                    if (brightPass != null && _dispatchedAlertIds.Add($"iss_{brightPass.Id}"))
                    {
                        ShowWindowsNotification(
                            "Bright ISS Pass Approaching",
                            $"ISS rises at {brightPass.StartTimeUtc.ToLocalTime():HH:mm} ({brightPass.StartCompass}), peaking at {brightPass.MaxAltitudeDegrees:F0}° altitude.");
                    }
                }

                if (prefs.NotifyAurora && space.KpIndex is >= 5.0 && _dispatchedAlertIds.Add($"aurora_{todayKey}"))
                {
                    ShowWindowsNotification(
                        "Geomagnetic Storm & Aurora Alert",
                        $"NOAA SWPC planetary Kp reached {space.KpIndex.Value:F1}. Check northern horizon transparency.");
                }

                if (prefs.NotifyPristineSky && weather != null)
                {
                    var cond = AstronomyService.Shared.EvaluateStargazingConditions(
                        latitude, longitude, DateTime.UtcNow,
                        weather.CloudTotalPercent, weather.CloudLowPercent, weather.CloudMidPercent, weather.CloudHighPercent);
                    if (cond.Score >= 85 && _dispatchedAlertIds.Add($"pristine_{todayKey}"))
                    {
                        ShowWindowsNotification(
                            "Pristine Dark-Sky Window Tonight",
                            $"Stargazing Score is {cond.Score}/100 ({cond.Quality}). Optimal window: {cond.BestWindowDescription ?? "Tonight"}.");
                    }
                }
            }
            catch { }
        }

        private static void ShowWindowsNotification(string title, string body)
        {
            try
            {
                var notification = new Microsoft.Windows.AppNotifications.Builder.AppNotificationBuilder()
                    .AddText(title)
                    .AddText(body)
                    .BuildNotification();
                Microsoft.Windows.AppNotifications.AppNotificationManager.Default.Show(notification);
            }
            catch { }
        }

        private async Task<string?> SafeGetStringAsync(string url)
        {
            try
            {
                using var resp = await _http.GetAsync(url).ConfigureAwait(false);
                if (!resp.IsSuccessStatusCode) return null;
                return await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
            }
            catch
            {
                return null;
            }
        }
    }
}
