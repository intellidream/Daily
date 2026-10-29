using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using Daily.Models;

namespace Daily_WinUI.Services.Cosmos
{
    public class CosmosSearchResult
    {
        public string ObjectId { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Subtitle { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty; // "Star", "Constellation", "Asterism", "Deep-Sky Object", "Planet", "Meteor Shower", "Satellite"
        public double RaHours { get; set; }
        public double DecDegrees { get; set; }
        public double? Magnitude { get; set; }
        public string Details { get; set; } = string.Empty;
        public CelestialBody? Body { get; set; }
        public CosmosDeepSkyObject? Dso { get; set; }
        public int? Hip { get; set; }
    }

    public class CosmosCatalogRepository
    {
        private static readonly Lazy<CosmosCatalogRepository> _instance = new(() => new CosmosCatalogRepository());
        public static CosmosCatalogRepository Shared => _instance.Value;

        public PackedStarCatalog PackedStars { get; private set; } = PackedStarCatalog.Empty;
        public Dictionary<int, StarDesignationRecord> StarDesignationsByHip { get; private set; } = new();
        public List<CosmosStar> Stars { get; private set; } = new();
        public List<CosmosConstellation> Constellations { get; private set; } = new();
        public List<CosmosConstellationBorderArc> ConstellationBorders { get; private set; } = new();
        public List<CosmosAsterism> Asterisms { get; private set; } = new();
        public List<CosmosDeepSkyObject> DeepSkyObjects { get; private set; } = new();
        public List<MeteorShower> MeteorShowers { get; private set; } = new();
        public List<MilkyWayContourLayer> MilkyWayLayers { get; private set; } = new();

        private byte[]? _bortleBytes;
        private string? _resolvedCosmosDir;
        private bool _isLoaded;
        private readonly SemaphoreSlim _loadLock = new(1, 1);

        public bool IsLoaded => _isLoaded;

        public async Task EnsureLoadedAsync(string? explicitAssetsDir = null)
        {
            if (_isLoaded) return;
            await _loadLock.WaitAsync().ConfigureAwait(false);
            try
            {
                if (_isLoaded) return;
                await Task.Run(() => LoadFromDirectory(explicitAssetsDir)).ConfigureAwait(false);
            }
            finally
            {
                _loadLock.Release();
            }
        }

        public void LoadSynchronously(string? explicitAssetsDir = null)
        {
            if (_isLoaded) return;
            _loadLock.Wait();
            try
            {
                if (_isLoaded) return;
                LoadFromDirectory(explicitAssetsDir);
            }
            finally
            {
                _loadLock.Release();
            }
        }

        private void LoadFromDirectory(string? explicitAssetsDir)
        {
            string? cosmosDir = explicitAssetsDir;
            if (string.IsNullOrEmpty(cosmosDir) || !Directory.Exists(cosmosDir))
            {
                string basePath = AppDomain.CurrentDomain.BaseDirectory;
                cosmosDir = Path.Combine(basePath, "Assets", "Cosmos");
                if (!Directory.Exists(cosmosDir))
                {
#if WINUI_NATIVE
                    try
                    {
                        cosmosDir = Path.Combine(Windows.ApplicationModel.Package.Current.InstalledLocation.Path, "Assets", "Cosmos");
                    }
                    catch { }
#endif
                }
            }

            if (string.IsNullOrEmpty(cosmosDir) || !Directory.Exists(cosmosDir))
                return;

            _resolvedCosmosDir = cosmosDir;
            var jsonOpts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };

            string starsBinPath = Path.Combine(cosmosDir, "stars_mag70.bin");
            if (File.Exists(starsBinPath))
            {
                PackedStars = ParseBinaryStars(File.ReadAllBytes(starsBinPath));
            }

            string starNamesPath = Path.Combine(cosmosDir, "star_names_iau.json");
            if (File.Exists(starNamesPath))
            {
                var list = JsonSerializer.Deserialize<List<StarDesignationRecord>>(File.ReadAllText(starNamesPath), jsonOpts) ?? new();
                StarDesignationsByHip = list.GroupBy(x => x.Hip).ToDictionary(g => g.Key, g => g.First());
            }

            string constPath = Path.Combine(cosmosDir, "constellations_iau88.json");
            if (File.Exists(constPath))
            {
                Constellations = JsonSerializer.Deserialize<List<CosmosConstellation>>(File.ReadAllText(constPath), jsonOpts) ?? new();
            }

            string borderPath = Path.Combine(cosmosDir, "constellation_borders.json");
            if (File.Exists(borderPath))
            {
                ConstellationBorders = JsonSerializer.Deserialize<List<CosmosConstellationBorderArc>>(File.ReadAllText(borderPath), jsonOpts) ?? new();
            }

            string astPath = Path.Combine(cosmosDir, "asterisms.json");
            if (File.Exists(astPath))
            {
                Asterisms = JsonSerializer.Deserialize<List<CosmosAsterism>>(File.ReadAllText(astPath), jsonOpts) ?? new();
            }

            string dsoPath = Path.Combine(cosmosDir, "dso_catalog.json");
            if (File.Exists(dsoPath))
            {
                DeepSkyObjects = JsonSerializer.Deserialize<List<CosmosDeepSkyObject>>(File.ReadAllText(dsoPath), jsonOpts) ?? new();
            }

            string showerPath = Path.Combine(cosmosDir, "meteor_showers_iau.json");
            if (File.Exists(showerPath))
            {
                MeteorShowers = JsonSerializer.Deserialize<List<MeteorShower>>(File.ReadAllText(showerPath), jsonOpts) ?? new();
            }

            string mwPath = Path.Combine(cosmosDir, "milky_way_isophotes.json");
            if (File.Exists(mwPath))
            {
                MilkyWayLayers = ParseMilkyWayLayers(File.ReadAllText(mwPath), jsonOpts);
            }

            string bortlePath = Path.Combine(cosmosDir, "bortle_world_grid.bin");
            if (File.Exists(bortlePath))
            {
                _bortleBytes = File.ReadAllBytes(bortlePath);
            }

            Stars = BuildBrightStarList();
            _isLoaded = true;
        }

        public string? ResolveThumbnailFilePath(string? relativeThumbnail)
        {
            if (string.IsNullOrWhiteSpace(relativeThumbnail) || string.IsNullOrEmpty(_resolvedCosmosDir))
                return null;
            string normalized = relativeThumbnail.Replace('/', Path.DirectorySeparatorChar).TrimStart(Path.DirectorySeparatorChar);
            string full = Path.Combine(_resolvedCosmosDir, normalized);
            return File.Exists(full) ? full : null;
        }

        public int GetBortleClass(double latitude, double longitude)
        {
            var data = _bortleBytes;
            if (data == null || data.Length < 16 + 129_600) return 5;
            int y = Math.Clamp((int)Math.Floor((latitude + 90.0) * 2.0), 0, 359);
            double normLon = ((longitude + 180.0) % 360.0 + 360.0) % 360.0;
            int x = Math.Clamp((int)Math.Floor(normLon * 2.0), 0, 719);
            int cellIdx = y * 720 + x;
            int byteIdx = 16 + (cellIdx >> 1);
            int packed = data[byteIdx];
            int val = (cellIdx & 1) == 0 ? (packed >> 4) : (packed & 0x0F);
            return Math.Clamp(val, 1, 9);
        }

        public List<CosmosSearchResult> Search(string query)
        {
            if (string.IsNullOrWhiteSpace(query)) return new();
            string q = query.Trim().ToLowerInvariant();
            var results = new List<CosmosSearchResult>(25);

            if ("iss".Contains(q) || "station".Contains(q) || "zarya".Contains(q))
            {
                results.Add(new CosmosSearchResult
                {
                    ObjectId = "SAT-25544",
                    Title = "ISS (Zarya)",
                    Subtitle = "Low-Earth Orbit • NORAD 25544",
                    Category = "Satellite",
                    Details = "Real-time SGP4 orbital elements from CelesTrak"
                });
            }

            // Major Solar System Bodies
            foreach (CelestialBody body in Enum.GetValues<CelestialBody>())
            {
                if (body.DisplayName().ToLowerInvariant().Contains(q))
                {
                    results.Add(new CosmosSearchResult
                    {
                        ObjectId = $"BODY-{body}",
                        Title = $"{body.Symbol()} {body.DisplayName()}",
                        Subtitle = body == CelestialBody.Sun ? "Host Star (G2V)" :
                                   body == CelestialBody.Moon ? "Earth's Natural Satellite" : "Solar System Planet",
                        Category = "Planet",
                        Body = body,
                        Details = $"VSOP87 / ELP2000 high-precision ephemeris"
                    });
                }
            }

            // Named & Bright Stars
            foreach (var s in Stars)
            {
                if (s.Name.ToLowerInvariant().Contains(q) ||
                    (!string.IsNullOrEmpty(s.Bayer) && s.Bayer.ToLowerInvariant().Contains(q)) ||
                    s.Constellation.ToLowerInvariant().Contains(q) ||
                    $"hip {s.Hip}" == q)
                {
                    string bayerPart = !string.IsNullOrWhiteSpace(s.Bayer) ? $"{s.Bayer} {s.Constellation} • " : $"{s.Constellation} • ";
                    results.Add(new CosmosSearchResult
                    {
                        ObjectId = $"HIP-{s.Hip}",
                        Title = s.Name,
                        Subtitle = $"Star • {bayerPart}mag {s.Mag:F2}",
                        Category = "Star",
                        RaHours = s.RaHours,
                        DecDegrees = s.DecDegrees,
                        Magnitude = s.Mag,
                        Hip = s.Hip,
                        Details = $"HIP {s.Hip} • B-V {s.ColorIndexBV:+0.00;-0.00;0.00}"
                    });
                }
            }

            // 219 Messier + Caldwell Deep-Sky Objects
            foreach (var d in DeepSkyObjects)
            {
                if (d.Id.ToLowerInvariant().Contains(q) ||
                    d.Name.ToLowerInvariant().Contains(q) ||
                    (!string.IsNullOrEmpty(d.NgcIc) && d.NgcIc.ToLowerInvariant().Contains(q)) ||
                    d.Type.ToLowerInvariant().Contains(q))
                {
                    results.Add(new CosmosSearchResult
                    {
                        ObjectId = d.Id,
                        Title = $"{d.Id} · {d.Name}",
                        Subtitle = $"{d.Type} • {d.Constellation} • mag {d.VisualMag:F1}",
                        Category = "Deep-Sky Object",
                        RaHours = d.RaHours,
                        DecDegrees = d.DecDeg,
                        Magnitude = d.VisualMag,
                        Dso = d,
                        Details = $"{d.RecommendedOptics} | {d.Description}"
                    });
                }
            }

            // 88 Official IAU Constellations
            foreach (var c in Constellations)
            {
                if (c.NameLa.ToLowerInvariant().Contains(q) ||
                    c.NameEn.ToLowerInvariant().Contains(q) ||
                    c.Id.ToLowerInvariant() == q ||
                    c.Code.ToLowerInvariant() == q)
                {
                    results.Add(new CosmosSearchResult
                    {
                        ObjectId = $"CONST-{c.Id}",
                        Title = string.Equals(c.NameLa, c.NameEn, StringComparison.OrdinalIgnoreCase)
                            ? c.NameLa
                            : $"{c.NameLa} ({c.NameEn})",
                        Subtitle = $"IAU Constellation • {c.Code}",
                        Category = "Constellation",
                        RaHours = c.CenterRaHours,
                        DecDegrees = c.CenterDecDeg,
                        Details = c.Lore
                    });
                }
            }

            // 14 Asterisms
            foreach (var a in Asterisms)
            {
                if (a.Name.ToLowerInvariant().Contains(q) || a.Id.ToLowerInvariant().Contains(q))
                {
                    results.Add(new CosmosSearchResult
                    {
                        ObjectId = $"AST-{a.Id}",
                        Title = a.Name,
                        Subtitle = $"Asterism • {a.Season}",
                        Category = "Asterism",
                        RaHours = a.CenterRaHours,
                        DecDegrees = a.CenterDecDeg,
                        Details = a.Description
                    });
                }
            }

            // 22 Meteor Showers
            foreach (var m in MeteorShowers)
            {
                if (m.Name.ToLowerInvariant().Contains(q) || m.Id.ToLowerInvariant() == q)
                {
                    results.Add(new CosmosSearchResult
                    {
                        ObjectId = $"SHOWER-{m.Id}",
                        Title = $"{m.Name} Meteor Shower",
                        Subtitle = $"Peak {m.PeakDateLabel} • ZHR {m.Zhr}/hr",
                        Category = "Meteor Shower",
                        RaHours = m.RadiantRaHours,
                        DecDegrees = m.RadiantDecDeg,
                        Details = $"{m.ParentBody} • {m.VelocityKmS:F0} km/s • {m.Description}"
                    });
                }
            }

            return results.Take(25).ToList();
        }

        private static PackedStarCatalog ParseBinaryStars(byte[] raw)
        {
            if (raw.Length < 16) return PackedStarCatalog.Empty;
            if (raw[0] != (byte)'D' || raw[1] != (byte)'C' || raw[2] != (byte)'S' || raw[3] != (byte)'T')
                return PackedStarCatalog.Empty;

            ReadOnlySpan<byte> span = raw;
            int count = (int)BinaryPrimitives.ReadUInt32LittleEndian(span.Slice(8, 4));
            if (count <= 0 || raw.Length < 16 + count * 32)
                return PackedStarCatalog.Empty;

            var hipIds = new int[count];
            var ux = new float[count];
            var uy = new float[count];
            var uz = new float[count];
            var raH = new float[count];
            var decD = new float[count];
            var vMag = new float[count];
            var bv = new float[count];
            var constIdx = new ushort[count];
            var argb = new uint[count];
            var map = new Dictionary<int, int>(count);

            for (int i = 0; i < count; i++)
            {
                var rec = span.Slice(16 + i * 32, 32);
                int hip = (int)BinaryPrimitives.ReadUInt32LittleEndian(rec.Slice(0, 4));
                hipIds[i] = hip;
                ux[i] = BinaryPrimitives.ReadSingleLittleEndian(rec.Slice(4, 4));
                uy[i] = BinaryPrimitives.ReadSingleLittleEndian(rec.Slice(8, 4));
                uz[i] = BinaryPrimitives.ReadSingleLittleEndian(rec.Slice(12, 4));
                raH[i] = BinaryPrimitives.ReadSingleLittleEndian(rec.Slice(16, 4));
                decD[i] = BinaryPrimitives.ReadSingleLittleEndian(rec.Slice(20, 4));
                vMag[i] = BinaryPrimitives.ReadSingleLittleEndian(rec.Slice(24, 4));
                float bvVal = BinaryPrimitives.ReadInt16LittleEndian(rec.Slice(28, 2)) / 1000.0f;
                bv[i] = bvVal;
                constIdx[i] = BinaryPrimitives.ReadUInt16LittleEndian(rec.Slice(30, 2));
                var (r, g, b) = PackedStarCatalog.BallesterosRgb(bvVal);
                argb[i] = (0xFFu << 24) | ((uint)r << 16) | ((uint)g << 8) | b;
                if (hip > 0) map[hip] = i;
            }

            return new PackedStarCatalog(count, hipIds, ux, uy, uz, raH, decD, vMag, bv, constIdx, argb, map);
        }

        private List<CosmosStar> BuildBrightStarList()
        {
            var constCodeByIndex = Constellations.ToDictionary(c => (ushort)c.Index, c => c.Id);
            var list = new List<CosmosStar>(600);
            for (int i = 0; i < PackedStars.Count; i++)
            {
                int hip = PackedStars.HipIds[i];
                StarDesignationsByHip.TryGetValue(hip, out var desig);
                double mag = PackedStars.VMag[i];
                bool hasProper = !string.IsNullOrWhiteSpace(desig?.Name);
                if (hasProper || mag <= 3.0)
                {
                    string constCode = desig?.Constellation?.ToUpperInvariant()
                        ?? (constCodeByIndex.TryGetValue(PackedStars.ConstellationIndex[i], out var cc) ? cc : "SKY");
                    string name = hasProper ? desig!.Name! : (desig?.PrimaryLabel ?? $"HIP {hip}");
                    var (r, g, b) = PackedStarCatalog.BallesterosRgb(PackedStars.Bv[i]);
                    list.Add(new CosmosStar
                    {
                        Hip = hip,
                        Name = name,
                        Bayer = (desig?.Bayer != null && !desig.Bayer.Contains("undefined")) ? desig.Bayer : null,
                        Constellation = constCode,
                        RaHours = PackedStars.RaHours[i],
                        DecDegrees = PackedStars.DecDegrees[i],
                        Mag = mag,
                        ColorIndexBV = PackedStars.Bv[i],
                        ColorHex = $"#{r:X2}{g:X2}{b:X2}"
                    });
                }
            }
            list.Sort((a, b) => a.Mag.CompareTo(b.Mag));
            return list;
        }

        private sealed class RawMilkyWayLayer
        {
            [JsonPropertyName("level")]
            public int Level { get; set; }

            [JsonPropertyName("rings")]
            public List<List<List<double>>> Rings { get; set; } = new();
        }

        private static List<MilkyWayContourLayer> ParseMilkyWayLayers(string jsonText, JsonSerializerOptions opts)
        {
            var raw = JsonSerializer.Deserialize<List<RawMilkyWayLayer>>(jsonText, opts) ?? new();
            var layers = new List<MilkyWayContourLayer>(raw.Count);
            const double deg2rad = Math.PI / 180.0;
            foreach (var layer in raw)
            {
                var rUx = new float[layer.Rings.Count][];
                var rUy = new float[layer.Rings.Count][];
                var rUz = new float[layer.Rings.Count][];
                for (int r = 0; r < layer.Rings.Count; r++)
                {
                    var pts = layer.Rings[r];
                    int n = pts.Count;
                    var ux = new float[n];
                    var uy = new float[n];
                    var uz = new float[n];
                    for (int p = 0; p < n; p++)
                    {
                        if (pts[p].Count >= 2)
                        {
                            double raRad = pts[p][0] * 15.0 * deg2rad;
                            double decRad = pts[p][1] * deg2rad;
                            ux[p] = (float)(Math.Cos(decRad) * Math.Cos(raRad));
                            uy[p] = (float)(Math.Cos(decRad) * Math.Sin(raRad));
                            uz[p] = (float)Math.Sin(decRad);
                        }
                    }
                    rUx[r] = ux;
                    rUy[r] = uy;
                    rUz[r] = uz;
                }
                layers.Add(new MilkyWayContourLayer
                {
                    Level = layer.Level,
                    RingsUx = rUx,
                    RingsUy = rUy,
                    RingsUz = rUz
                });
            }
            return layers;
        }
    }
}
