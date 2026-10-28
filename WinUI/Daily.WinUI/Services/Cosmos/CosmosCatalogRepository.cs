using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Daily.Models;

namespace Daily_WinUI.Services.Cosmos
{
    public class CosmosSearchResult
    {
        public string Title { get; set; } = string.Empty;
        public string Subtitle { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty; // "Star", "Constellation", "DSO", "Planet"
        public double RaHours { get; set; }
        public double DecDegrees { get; set; }
        public double? Magnitude { get; set; }
        public string Details { get; set; } = string.Empty;
    }

    public class CosmosCatalogRepository
    {
        private static readonly Lazy<CosmosCatalogRepository> _instance = new(() => new CosmosCatalogRepository());
        public static CosmosCatalogRepository Shared => _instance.Value;

        public List<CosmosStar> Stars { get; private set; } = new();
        public List<CosmosConstellation> Constellations { get; private set; } = new();
        public List<CosmosDeepSkyObject> DeepSkyObjects { get; private set; } = new();
        public List<MeteorShower> MeteorShowers { get; private set; } = new();

        private bool _isLoaded;
        private readonly TaskCompletionSource<bool> _loadTcs = new();

        public async Task EnsureLoadedAsync()
        {
            if (_isLoaded) return;

            await Task.Run(() =>
            {
                try
                {
                    string basePath = AppDomain.CurrentDomain.BaseDirectory;
                    string cosmosDir = Path.Combine(basePath, "Assets", "Cosmos");

                    if (!Directory.Exists(cosmosDir))
                    {
                        try
                        {
                            cosmosDir = Path.Combine(Windows.ApplicationModel.Package.Current.InstalledLocation.Path, "Assets", "Cosmos");
                        }
                        catch { }
                    }

                    if (Directory.Exists(cosmosDir))
                    {
                        string starsPath = Path.Combine(cosmosDir, "bright_stars.json");
                        if (File.Exists(starsPath))
                        {
                            var json = File.ReadAllText(starsPath);
                            Stars = JsonSerializer.Deserialize<List<CosmosStar>>(json) ?? new();
                        }

                        string constPath = Path.Combine(cosmosDir, "constellations_iau88.json");
                        if (File.Exists(constPath))
                        {
                            var json = File.ReadAllText(constPath);
                            Constellations = JsonSerializer.Deserialize<List<CosmosConstellation>>(json) ?? new();
                        }

                        string dsoPath = Path.Combine(cosmosDir, "dso_messier.json");
                        if (File.Exists(dsoPath))
                        {
                            var json = File.ReadAllText(dsoPath);
                            DeepSkyObjects = JsonSerializer.Deserialize<List<CosmosDeepSkyObject>>(json) ?? new();
                        }

                        string showerPath = Path.Combine(cosmosDir, "meteor_showers.json");
                        if (File.Exists(showerPath))
                        {
                            var json = File.ReadAllText(showerPath);
                            MeteorShowers = JsonSerializer.Deserialize<List<MeteorShower>>(json) ?? new();
                        }
                    }

                    _isLoaded = true;
                    _loadTcs.TrySetResult(true);
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[CosmosCatalogRepository] Error loading catalogs: {ex}");
                    _loadTcs.TrySetResult(false);
                }
            });
        }

        public List<CosmosSearchResult> Search(string query)
        {
            if (string.IsNullOrWhiteSpace(query)) return new();
            var q = query.Trim().ToLowerInvariant();
            var results = new List<CosmosSearchResult>();

            // 1. Stars
            foreach (var s in Stars)
            {
                if (s.Name.ToLowerInvariant().Contains(q) ||
                    (!string.IsNullOrEmpty(s.Bayer) && s.Bayer.ToLowerInvariant().Contains(q)) ||
                    s.Constellation.ToLowerInvariant().Contains(q))
                {
                    results.Add(new CosmosSearchResult
                    {
                        Title = s.Name,
                        Subtitle = $"{s.Bayer ?? ""} • {s.Constellation} (Mag: {s.Mag:F1})",
                        Category = "Stea",
                        RaHours = s.RaHours,
                        DecDegrees = s.DecDegrees,
                        Magnitude = s.Mag,
                        Details = $"Index B-V: {s.ColorIndexBV:F2} | Culoare: {s.ColorHex}"
                    });
                }
            }

            // 2. Deep Sky Objects (Messier)
            foreach (var d in DeepSkyObjects)
            {
                if (d.Id.ToLowerInvariant().Contains(q) ||
                    d.Name.ToLowerInvariant().Contains(q) ||
                    d.Constellation.ToLowerInvariant().Contains(q) ||
                    d.Type.ToLowerInvariant().Contains(q))
                {
                    results.Add(new CosmosSearchResult
                    {
                        Title = $"{d.Id} - {d.Name}",
                        Subtitle = $"{d.Type} • {d.Constellation} (Mag: {d.VisualMag:F1})",
                        Category = "Obiect Deep-Sky",
                        RaHours = d.RaHours,
                        DecDegrees = d.DecDegrees,
                        Magnitude = d.VisualMag,
                        Details = $"{d.Optics} | {d.DescRo}"
                    });
                }
            }

            // 3. Constellations
            foreach (var c in Constellations)
            {
                if (c.NameRo.ToLowerInvariant().Contains(q) ||
                    c.NameLa.ToLowerInvariant().Contains(q) ||
                    c.NameEn.ToLowerInvariant().Contains(q) ||
                    c.Id.ToLowerInvariant().Contains(q))
                {
                    results.Add(new CosmosSearchResult
                    {
                        Title = $"{c.NameRo} ({c.NameLa})",
                        Subtitle = $"Constelație IAU • {c.NameEn}",
                        Category = "Constelație",
                        RaHours = c.CenterRa,
                        DecDegrees = c.CenterDec,
                        Magnitude = null,
                        Details = $"Stele principale: {string.Join(", ", c.Stars)}"
                    });
                }
            }

            return results.Take(25).ToList();
        }
    }
}
