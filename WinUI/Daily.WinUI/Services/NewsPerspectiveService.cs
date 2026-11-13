using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using System.Xml.Linq;
using Daily.Models;
using Daily.Services;

namespace Daily_WinUI.Services
{
    public sealed class NewsPerspectiveService
    {
        private const string PrimaryGeminiModel = "gemini-2.5-flash";

        private static readonly Supabase.Postgrest.QueryOptions MinimalReturnOptions =
            new() { Returning = Supabase.Postgrest.QueryOptions.ReturnType.Minimal };

        private readonly Supabase.Client _supabase;
        private readonly ISmartIntelligenceService _smartIntelligence;
        private readonly HttpClient _httpClient;

        private readonly ConcurrentDictionary<string, StoryCluster> _expandedCache = new(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentDictionary<string, PerspectiveComparison> _comparisonCache = new(StringComparer.OrdinalIgnoreCase);

        private readonly object _stateLock = new();
        private readonly string _stateFilePath;
        private LocalIntelligenceState _localState;
        private DateTime _lastGdeltCallUtc = DateTime.MinValue;
        private CancellationTokenSource? _dietFlushCts;

        private sealed class LocalIntelligenceState
        {
            public DateTime? LastCatalogSyncUtc { get; set; }
            public HashSet<string> CountedArticleUrls { get; set; } = new(StringComparer.OrdinalIgnoreCase);
            public MediaDietSnapshot CurrentDiet { get; set; } = new()
            {
                PeriodMonth = DateTime.UtcNow.ToString("yyyy-MM")
            };
        }

        public NewsPerspectiveService(
            Supabase.Client supabase,
            ISmartIntelligenceService smartIntelligence)
        {
            _supabase = supabase;
            _smartIntelligence = smartIntelligence;
            _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(9) };
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) DailyNews/2.0");

            string appDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Daily.WinUI");
            Directory.CreateDirectory(appDir);
            _stateFilePath = Path.Combine(appDir, "media_intelligence_state.json");
            _localState = LoadLocalState();
        }

        private LocalIntelligenceState LoadLocalState()
        {
            try
            {
                if (File.Exists(_stateFilePath))
                {
                    var json = File.ReadAllText(_stateFilePath);
                    var loaded = JsonSerializer.Deserialize<LocalIntelligenceState>(json);
                    if (loaded != null)
                    {
                        string monthNow = DateTime.UtcNow.ToString("yyyy-MM");
                        if (!string.Equals(loaded.CurrentDiet?.PeriodMonth, monthNow, StringComparison.Ordinal))
                        {
                            loaded.CurrentDiet = new MediaDietSnapshot { PeriodMonth = monthNow };
                            loaded.CountedArticleUrls.Clear();
                        }
                        return loaded;
                    }
                }
            }
            catch { }

            return new LocalIntelligenceState
            {
                CurrentDiet = new MediaDietSnapshot { PeriodMonth = DateTime.UtcNow.ToString("yyyy-MM") }
            };
        }

        private void SaveLocalState()
        {
            try
            {
                string json;
                lock (_stateLock)
                {
                    json = JsonSerializer.Serialize(_localState, new JsonSerializerOptions { WriteIndented = true });
                }
                File.WriteAllText(_stateFilePath, json);
            }
            catch { }
        }

        // ── 1. 24h Delta Watermark Sync for Outlet Metadata (Zero Raw RSS Egress) ──

        public async Task RefreshOutletCatalogIfStaleAsync(CancellationToken ct = default)
        {
            DateTime? lastSync;
            lock (_stateLock)
            {
                lastSync = _localState.LastCatalogSyncUtc;
            }

            if (lastSync.HasValue && (DateTime.UtcNow - lastSync.Value) < TimeSpan.FromHours(24))
            {
                return;
            }

            try
            {
                var query = _supabase.From<RemoteMediaOutletProfileRow>();
                Supabase.Postgrest.Responses.ModeledResponse<RemoteMediaOutletProfileRow> resp;
                if (lastSync.HasValue)
                {
                    string iso = lastSync.Value.ToString("O");
                    resp = await query
                        .Filter("updated_at", Supabase.Postgrest.Constants.Operator.GreaterThan, iso)
                        .Limit(250)
                        .Get(ct)
                        .ConfigureAwait(false);
                }
                else
                {
                    resp = await query
                        .Limit(250)
                        .Get(ct)
                        .ConfigureAwait(false);
                }

                if (resp?.Models != null && resp.Models.Count > 0)
                {
                    MediaIntelligenceRegistry.Shared.MergeRemoteRows(resp.Models);
                }

                lock (_stateLock)
                {
                    _localState.LastCatalogSyncUtc = DateTime.UtcNow;
                }
                SaveLocalState();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[NewsPerspectiveService] Delta catalog check skipped: {ex.Message}");
            }
        }

        // ── 2. On-Demand Cross-Spectrum Coverage Discovery (Google News RSS + GDELT DOC 2.0) ──

        public async Task<StoryCluster> ExpandCoverageAsync(StoryCluster cluster, CancellationToken ct = default)
        {
            if (_expandedCache.TryGetValue(cluster.Id, out var cached))
            {
                return cached;
            }

            string query = StoryClusterEngine.BuildDiscoveryQuery(cluster);
            if (string.IsNullOrWhiteSpace(query))
            {
                return cluster;
            }

            bool isRomanian = cluster.Coverage.Any(c =>
                string.Equals(c.Outlet.CountryCode, "RO", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(c.Outlet.LanguageCode, "ro", StringComparison.OrdinalIgnoreCase));

            var discovered = new List<RssItem>();

            try
            {
                var gnewsItems = await SearchGoogleNewsRssAsync(query, isRomanian, ct).ConfigureAwait(false);
                discovered.AddRange(gnewsItems);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[NewsPerspectiveService] Google News search warning: {ex.Message}");
            }

            // GDELT DOC 2.0 fallback if < 4 external items found, respecting >= 6s polite rate limit
            if (discovered.Count < 4)
            {
                bool allowGdelt = false;
                lock (_stateLock)
                {
                    if ((DateTime.UtcNow - _lastGdeltCallUtc).TotalSeconds >= 6.0)
                    {
                        _lastGdeltCallUtc = DateTime.UtcNow;
                        allowGdelt = true;
                    }
                }

                if (allowGdelt)
                {
                    try
                    {
                        var gdeltItems = await SearchGdeltDocApiAsync(query, ct).ConfigureAwait(false);
                        discovered.AddRange(gdeltItems);
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[NewsPerspectiveService] GDELT fallback warning: {ex.Message}");
                    }
                }
            }

            var merged = discovered.Count > 0
                ? StoryClusterEngine.MergeExpandedArticles(cluster, discovered)
                : cluster;

            _expandedCache[cluster.Id] = merged;
            return merged;
        }

        private async Task<List<RssItem>> SearchGoogleNewsRssAsync(string query, bool preferRomanian, CancellationToken ct)
        {
            var results = new List<RssItem>();
            string encoded = Uri.EscapeDataString($"{query} when:3d");
            string localeParams = preferRomanian
                ? "hl=ro&gl=RO&ceid=RO:ro"
                : "hl=en-US&gl=US&ceid=US:en";
            string url = $"https://news.google.com/rss/search?q={encoded}&{localeParams}";

            string xml = await _httpClient.GetStringAsync(url, ct).ConfigureAwait(false);
            var doc = XDocument.Parse(xml);

            foreach (var item in doc.Descendants().Where(e => e.Name.LocalName == "item").Take(24))
            {
                string rawTitle = item.Elements().FirstOrDefault(e => e.Name.LocalName == "title")?.Value ?? string.Empty;
                string link = item.Elements().FirstOrDefault(e => e.Name.LocalName == "link")?.Value ?? string.Empty;
                string pubDateStr = item.Elements().FirstOrDefault(e => e.Name.LocalName == "pubDate")?.Value ?? string.Empty;
                var sourceEl = item.Elements().FirstOrDefault(e => e.Name.LocalName == "source");
                string sourceName = (sourceEl?.Value ?? string.Empty).Trim();
                string? sourceUrl = sourceEl?.Attribute("url")?.Value;

                if (string.IsNullOrWhiteSpace(rawTitle) || string.IsNullOrWhiteSpace(link)) continue;

                // Strip trailing " - Publisher" from Google News title
                if (!string.IsNullOrEmpty(sourceName))
                {
                    string suffix = " - " + sourceName;
                    if (rawTitle.EndsWith(suffix, StringComparison.OrdinalIgnoreCase) && rawTitle.Length > suffix.Length + 8)
                    {
                        rawTitle = rawTitle.Substring(0, rawTitle.Length - suffix.Length).Trim();
                    }
                }

                string faviconHost = MediaIntelligenceRegistry.ExtractHost(sourceUrl ?? link);
                string iconUrl = !string.IsNullOrEmpty(faviconHost)
                    ? $"https://www.google.com/s2/favicons?domain={faviconHost}&sz=64"
                    : string.Empty;

                results.Add(new RssItem
                {
                    Title = System.Net.WebUtility.HtmlDecode(rawTitle),
                    Link = link,
                    PublishDate = DateTime.TryParse(pubDateStr, out var dt) ? dt : DateTime.UtcNow,
                    PublicationName = !string.IsNullOrEmpty(sourceName) ? sourceName : faviconHost,
                    PublicationIconUrl = iconUrl,
                    SourcePublisherUrl = sourceUrl
                });
            }

            return results;
        }

        private async Task<List<RssItem>> SearchGdeltDocApiAsync(string query, CancellationToken ct)
        {
            var results = new List<RssItem>();
            string encoded = Uri.EscapeDataString(query);
            string url = $"https://api.gdeltproject.org/api/v2/doc/doc?query={encoded}&mode=artlist&maxrecords=18&timespan=3d&format=json";

            string json = await _httpClient.GetStringAsync(url, ct).ConfigureAwait(false);
            var root = JsonNode.Parse(json);
            if (root?["articles"] is not JsonArray arr) return results;

            foreach (var node in arr)
            {
                if (node == null) continue;
                string title = node["title"]?.ToString() ?? string.Empty;
                string articleUrl = node["url"]?.ToString() ?? string.Empty;
                string domain = node["domain"]?.ToString() ?? string.Empty;
                if (string.IsNullOrWhiteSpace(title) || string.IsNullOrWhiteSpace(articleUrl)) continue;

                results.Add(new RssItem
                {
                    Title = title.Trim(),
                    Link = articleUrl.Trim(),
                    PublishDate = DateTime.UtcNow,
                    PublicationName = domain,
                    PublicationIconUrl = !string.IsNullOrEmpty(domain) ? $"https://www.google.com/s2/favicons?domain={domain}&sz=64" : string.Empty,
                    SourcePublisherUrl = !string.IsNullOrEmpty(domain) ? $"https://{domain}" : null
                });
            }

            return results;
        }

        // ── 3. Multi-Tier Framing Comparison (Supabase 72h Cache -> Gemini 2.5 Flash -> Phi-Silica NPU -> Deterministic) ──

        public async Task<PerspectiveComparison> ComparePerspectivesAsync(StoryCluster cluster, CancellationToken ct = default)
        {
            string cacheKey = $"{cluster.Id}:{cluster.UniqueOutletCount}";
            if (_comparisonCache.TryGetValue(cacheKey, out var memCached))
            {
                return memCached;
            }

            // Tier 0: Check shared 72h Supabase news_perspective_cache
            try
            {
                var resp = await _supabase.From<RemotePerspectiveCacheRow>()
                    .Filter("cluster_hash", Supabase.Postgrest.Constants.Operator.Equals, cluster.Id)
                    .Limit(1)
                    .Get(ct)
                    .ConfigureAwait(false);

                var row = resp?.Models?.FirstOrDefault();
                if (row != null && row.ExpiresAt > DateTime.UtcNow && row.SourceCount >= Math.Max(2, cluster.UniqueOutletCount - 2))
                {
                    var parsed = JsonSerializer.Deserialize<PerspectiveComparison>(row.ComparisonJson);
                    if (parsed != null && parsed.SharedFacts.Count > 0)
                    {
                        _comparisonCache[cacheKey] = parsed;
                        return parsed;
                    }
                }
            }
            catch { }

            PerspectiveComparison? synthesized = null;

            // Tier 1: Gemini 2.5 Flash if configured
            var settings = SettingsService.Load();
            string? geminiKey = !string.IsNullOrWhiteSpace(settings.PrismGeminiApiKey)
                ? settings.PrismGeminiApiKey
                : Environment.GetEnvironmentVariable("GEMINI_API_KEY");

            if (!string.IsNullOrWhiteSpace(geminiKey) && cluster.Coverage.Count >= 2)
            {
                synthesized = await TrySynthesizeWithGeminiAsync(cluster, geminiKey!, ct).ConfigureAwait(false);
            }

            // Tier 2: Windows 11 On-Device Hardware NPU (Phi-Silica 45 TOPS) or Local GGUF AI
            if (synthesized == null && cluster.Coverage.Count >= 2)
            {
                synthesized = await TrySynthesizeWithLocalNpuAsync(cluster, ct).ConfigureAwait(false);
            }

            // Tier 3: Instant < 1ms Deterministic Synthesis
            synthesized ??= BuildDeterministicComparison(cluster);

            _comparisonCache[cacheKey] = synthesized;

            // Persist to shared 72h Supabase cache with Prefer: return=minimal (zero response egress) if authenticated & AI-generated
            if (_supabase.Auth.CurrentSession != null && synthesized.EngineBadge != "Deterministic Lens")
            {
                _ = Task.Run(async () =>
                {
                    try
                    {
                        var cacheRow = new RemotePerspectiveCacheRow
                        {
                            ClusterHash = cluster.Id,
                            LanguageCode = cluster.Coverage.Any(c => c.Outlet.CountryCode == "RO") ? "ro" : "en",
                            SourceCount = cluster.UniqueOutletCount,
                            ComparisonJson = JsonSerializer.Serialize(synthesized),
                            ExpiresAt = DateTime.UtcNow.AddHours(72)
                        };
                        await _supabase.From<RemotePerspectiveCacheRow>()
                            .Upsert(cacheRow, MinimalReturnOptions)
                            .ConfigureAwait(false);
                    }
                    catch { }
                });
            }

            return synthesized;
        }

        private async Task<PerspectiveComparison?> TrySynthesizeWithGeminiAsync(
            StoryCluster cluster,
            string apiKey,
            CancellationToken ct)
        {
            try
            {
                string endpoint = $"https://generativelanguage.googleapis.com/v1beta/models/{PrimaryGeminiModel}:generateContent?key={Uri.EscapeDataString(apiKey.Trim())}";
                string digest = BuildHeadlinesDigest(cluster, maxItems: 14);
                string prompt =
                    "Analyze how different news outlets frame the following story. Respond in the primary language of the headlines (Romanian if mostly Romanian, otherwise English). " +
                    "Return ONLY valid JSON matching exact keys: " +
                    "{\"sharedFacts\": [\"...\"], \"framingDifferences\": [{\"side\": \"Left / Lean Left\", \"emphasis\": \"...\", \"toneNote\": \"...\"}], \"omissionsNote\": \"...\"}.\n\n" +
                    digest;

                var payload = new
                {
                    contents = new[]
                    {
                        new { parts = new[] { new { text = prompt } } }
                    },
                    generationConfig = new
                    {
                        temperature = 0.2,
                        maxOutputTokens = 700,
                        responseMimeType = "application/json"
                    }
                };

                using var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                using var resp = await _httpClient.PostAsync(endpoint, content, ct).ConfigureAwait(false);
                if (!resp.IsSuccessStatusCode) return null;

                string body = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
                var root = JsonNode.Parse(body);
                string? rawJson = root?["candidates"]?[0]?["content"]?["parts"]?[0]?["text"]?.ToString();
                if (string.IsNullOrWhiteSpace(rawJson)) return null;

                return ParseModelComparisonJson(rawJson!, cluster.Id, "Gemini 2.5 Flash");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[NewsPerspectiveService] Gemini synthesis warning: {ex.Message}");
                return null;
            }
        }

        private async Task<PerspectiveComparison?> TrySynthesizeWithLocalNpuAsync(
            StoryCluster cluster,
            CancellationToken ct)
        {
            try
            {
                if (!await _smartIntelligence.IsModelReadyAsync().ConfigureAwait(false))
                {
                    return null;
                }

                await _smartIntelligence.InitializeAsync().ConfigureAwait(false);
                string sysPrompt =
                    "You are a neutral media analyst. Output ONLY compact valid JSON with keys: " +
                    "\"sharedFacts\" (array of 3 concise strings), \"framingDifferences\" (array of objects with \"side\", \"emphasis\", \"toneNote\"), and \"omissionsNote\" (string).";
                string digest = BuildHeadlinesDigest(cluster, maxItems: 10);
                string raw = await _smartIntelligence.GenerateResponseAsync(sysPrompt, digest, ct).ConfigureAwait(false);
                if (string.IsNullOrWhiteSpace(raw)) return null;

                int firstBrace = raw.IndexOf('{');
                int lastBrace = raw.LastIndexOf('}');
                if (firstBrace >= 0 && lastBrace > firstBrace)
                {
                    string slice = raw.Substring(firstBrace, lastBrace - firstBrace + 1);
                    string badge = _smartIntelligence.IsPhiSilicaActive
                        ? "Phi-Silica NPU"
                        : _smartIntelligence.ActiveEngineName;
                    var parsed = ParseModelComparisonJson(slice, cluster.Id, badge);
                    if (parsed != null) return parsed;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[NewsPerspectiveService] Local NPU synthesis fallback: {ex.Message}");
            }
            return null;
        }

        private static PerspectiveComparison? ParseModelComparisonJson(string rawJson, string clusterId, string engineBadge)
        {
            try
            {
                var node = JsonNode.Parse(rawJson);
                if (node == null) return null;

                var facts = new List<string>();
                if (node["sharedFacts"] is JsonArray fArr)
                {
                    foreach (var f in fArr)
                    {
                        var s = f?.ToString()?.Trim();
                        if (!string.IsNullOrEmpty(s)) facts.Add(s!);
                    }
                }

                var diffs = new List<FramingDifferenceItem>();
                if (node["framingDifferences"] is JsonArray dArr)
                {
                    foreach (var d in dArr)
                    {
                        if (d == null) continue;
                        string side = d["side"]?.ToString()?.Trim() ?? string.Empty;
                        string emphasis = d["emphasis"]?.ToString()?.Trim() ?? string.Empty;
                        string tone = d["toneNote"]?.ToString()?.Trim() ?? string.Empty;
                        if (!string.IsNullOrEmpty(side) && !string.IsNullOrEmpty(emphasis))
                        {
                            diffs.Add(new FramingDifferenceItem
                            {
                                Side = side,
                                Emphasis = emphasis,
                                ToneNote = tone
                            });
                        }
                    }
                }

                if (facts.Count == 0 && diffs.Count == 0) return null;

                return new PerspectiveComparison
                {
                    ClusterHash = clusterId,
                    SharedFacts = facts,
                    FramingDifferences = diffs,
                    OmissionsNote = node["omissionsNote"]?.ToString()?.Trim(),
                    EngineBadge = engineBadge,
                    GeneratedAt = DateTime.UtcNow
                };
            }
            catch
            {
                return null;
            }
        }

        private static string BuildHeadlinesDigest(StoryCluster cluster, int maxItems)
        {
            var sb = new StringBuilder();
            sb.AppendLine($"Canonical Topic: {cluster.CanonicalTitle}");
            sb.AppendLine($"Spectrum: {cluster.Distribution.SummaryLabel}");
            sb.AppendLine("Headlines by Outlet:");
            foreach (var item in cluster.Coverage.Take(maxItems))
            {
                sb.AppendLine($"- [{item.Outlet.Bias.DisplayLabel()} | Factuality: {item.Outlet.Factuality.DisplayLabel()} | {item.Outlet.DisplayName}] {item.Article.Title}");
            }
            return sb.ToString();
        }

        public static PerspectiveComparison BuildDeterministicComparison(StoryCluster cluster)
        {
            var facts = new List<string>
            {
                $"Covered across {cluster.UniqueOutletCount} distinct publications ({cluster.Distribution.SummaryLabel}).",
                $"Lead reporting: \"{cluster.CanonicalTitle}\"."
            };

            int highFactCount = cluster.Coverage.Count(c =>
                c.Outlet.Factuality == FactualityTier.VeryHigh || c.Outlet.Factuality == FactualityTier.High);
            if (highFactCount > 0)
            {
                facts.Add($"{highFactCount} of {cluster.Coverage.Count} articles originate from High / Very High factuality newsrooms.");
            }

            var diffs = new List<FramingDifferenceItem>();
            void AppendGroup(string label, Func<MediaBias, bool> predicate)
            {
                var group = cluster.Coverage.Where(c => predicate(c.Outlet.Bias)).ToList();
                if (group.Count == 0) return;
                var sampleOutlets = string.Join(", ", group.Select(g => g.Outlet.DisplayName).Distinct().Take(3));
                var leadHeadline = group[0].Article.Title;
                var dominantFraming = group
                    .GroupBy(g => g.Framing)
                    .OrderByDescending(k => k.Count())
                    .First().Key.DisplayLabel();

                diffs.Add(new FramingDifferenceItem
                {
                    Side = label,
                    Emphasis = $"{sampleOutlets}: \"{leadHeadline}\"",
                    ToneNote = $"Dominant format: {dominantFraming}"
                });
            }

            AppendGroup("Left & Lean Left", b => b == MediaBias.Left || b == MediaBias.LeanLeft);
            AppendGroup("Center", b => b == MediaBias.Center);
            AppendGroup("Lean Right & Right", b => b == MediaBias.LeanRight || b == MediaBias.Right);
            AppendGroup("Independent Creators", b => b == MediaBias.Independent);

            string? omission = cluster.Blindspot?.Explanation();
            if (string.IsNullOrEmpty(omission))
            {
                if (cluster.Distribution.LeftWingTotal == 0 && cluster.Distribution.RightWingTotal > 0)
                    omission = "No Left or Lean Left outlets are present in this cluster yet.";
                else if (cluster.Distribution.RightWingTotal == 0 && cluster.Distribution.LeftWingTotal > 0)
                    omission = "No Right or Lean Right outlets are present in this cluster yet.";
            }

            return new PerspectiveComparison
            {
                ClusterHash = cluster.Id,
                SharedFacts = facts,
                FramingDifferences = diffs,
                OmissionsNote = omission,
                EngineBadge = "Deterministic Lens",
                GeneratedAt = DateTime.UtcNow
            };
        }

        // ── 4. Media Diet Tracking (1 Row / Month / User, 60s Debounced Minimal Upsert) ──

        public MediaDietSnapshot GetCurrentDietSnapshot()
        {
            lock (_stateLock)
            {
                string monthNow = DateTime.UtcNow.ToString("yyyy-MM");
                if (!string.Equals(_localState.CurrentDiet.PeriodMonth, monthNow, StringComparison.Ordinal))
                {
                    _localState.CurrentDiet = new MediaDietSnapshot { PeriodMonth = monthNow };
                    _localState.CountedArticleUrls.Clear();
                }

                var d = _localState.CurrentDiet;
                return new MediaDietSnapshot
                {
                    PeriodMonth = d.PeriodMonth,
                    LeftCount = d.LeftCount,
                    LeanLeftCount = d.LeanLeftCount,
                    CenterCount = d.CenterCount,
                    LeanRightCount = d.LeanRightCount,
                    RightCount = d.RightCount,
                    IndependentCount = d.IndependentCount,
                    UnratedCount = d.UnratedCount,
                    HighFactualityCount = d.HighFactualityCount,
                    TotalArticlesCount = d.TotalArticlesCount
                };
            }
        }

        public void RecordArticleRead(RssItem item)
        {
            if (item == null || string.IsNullOrWhiteSpace(item.Link)) return;
            string normUrl = StoryClusterEngine.NormalizeArticleUrl(item.Link);
            if (string.IsNullOrEmpty(normUrl)) return;

            var profile = MediaIntelligenceRegistry.Shared.ResolveArticle(item);

            lock (_stateLock)
            {
                string monthNow = DateTime.UtcNow.ToString("yyyy-MM");
                if (!string.Equals(_localState.CurrentDiet.PeriodMonth, monthNow, StringComparison.Ordinal))
                {
                    _localState.CurrentDiet = new MediaDietSnapshot { PeriodMonth = monthNow };
                    _localState.CountedArticleUrls.Clear();
                }

                if (!_localState.CountedArticleUrls.Add(normUrl))
                {
                    return; // Already counted this month
                }

                var diet = _localState.CurrentDiet;
                diet.TotalArticlesCount++;
                if (profile.Factuality == FactualityTier.VeryHigh || profile.Factuality == FactualityTier.High)
                {
                    diet.HighFactualityCount++;
                }

                switch (profile.Bias)
                {
                    case MediaBias.Left: diet.LeftCount++; break;
                    case MediaBias.LeanLeft: diet.LeanLeftCount++; break;
                    case MediaBias.Center: diet.CenterCount++; break;
                    case MediaBias.LeanRight: diet.LeanRightCount++; break;
                    case MediaBias.Right: diet.RightCount++; break;
                    case MediaBias.Independent: diet.IndependentCount++; break;
                    default: diet.UnratedCount++; break;
                }
            }

            SaveLocalState();
            ScheduleDebouncedDietSync();
        }

        public async Task PullRemoteDietIfAvailableAsync(CancellationToken ct = default)
        {
            var userIdStr = _supabase.Auth.CurrentSession?.User?.Id;
            if (string.IsNullOrEmpty(userIdStr) || !Guid.TryParse(userIdStr, out _)) return;

            try
            {
                string monthNow = DateTime.UtcNow.ToString("yyyy-MM");
                var resp = await _supabase.From<RemoteNewsReadingStatsRow>()
                    .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userIdStr)
                    .Filter("period_month", Supabase.Postgrest.Constants.Operator.Equals, monthNow)
                    .Limit(1)
                    .Get(ct)
                    .ConfigureAwait(false);

                var remote = resp?.Models?.FirstOrDefault();
                if (remote == null) return;

                bool changed = false;
                lock (_stateLock)
                {
                    var d = _localState.CurrentDiet;
                    if (remote.TotalArticlesCount > d.TotalArticlesCount)
                    {
                        d.LeftCount = Math.Max(d.LeftCount, remote.LeftCount);
                        d.LeanLeftCount = Math.Max(d.LeanLeftCount, remote.LeanLeftCount);
                        d.CenterCount = Math.Max(d.CenterCount, remote.CenterCount);
                        d.LeanRightCount = Math.Max(d.LeanRightCount, remote.LeanRightCount);
                        d.RightCount = Math.Max(d.RightCount, remote.RightCount);
                        d.IndependentCount = Math.Max(d.IndependentCount, remote.IndependentCount);
                        d.UnratedCount = Math.Max(d.UnratedCount, remote.UnratedCount);
                        d.HighFactualityCount = Math.Max(d.HighFactualityCount, remote.HighFactualityCount);
                        d.TotalArticlesCount = d.LeftCount + d.LeanLeftCount + d.CenterCount + d.LeanRightCount + d.RightCount + d.IndependentCount + d.UnratedCount;
                        changed = true;
                    }
                }

                if (changed) SaveLocalState();
            }
            catch { }
        }

        private void ScheduleDebouncedDietSync()
        {
            CancellationToken token;
            lock (_stateLock)
            {
                _dietFlushCts?.Cancel();
                _dietFlushCts?.Dispose();
                _dietFlushCts = new CancellationTokenSource();
                token = _dietFlushCts.Token;
            }

            _ = Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(60), token).ConfigureAwait(false);
                    var userIdStr = _supabase.Auth.CurrentSession?.User?.Id;
                    if (string.IsNullOrEmpty(userIdStr) || !Guid.TryParse(userIdStr, out var userGuid))
                        return;

                    var snap = GetCurrentDietSnapshot();
                    var row = new RemoteNewsReadingStatsRow
                    {
                        UserId = userGuid,
                        PeriodMonth = snap.PeriodMonth,
                        LeftCount = snap.LeftCount,
                        LeanLeftCount = snap.LeanLeftCount,
                        CenterCount = snap.CenterCount,
                        LeanRightCount = snap.LeanRightCount,
                        RightCount = snap.RightCount,
                        IndependentCount = snap.IndependentCount,
                        UnratedCount = snap.UnratedCount,
                        HighFactualityCount = snap.HighFactualityCount,
                        TotalArticlesCount = snap.TotalArticlesCount,
                        UpdatedAt = DateTime.UtcNow
                    };

                    await _supabase.From<RemoteNewsReadingStatsRow>().Upsert(
                        row,
                        new Supabase.Postgrest.QueryOptions
                        {
                            OnConflict = "user_id,period_month",
                            Returning = Supabase.Postgrest.QueryOptions.ReturnType.Minimal
                        }).ConfigureAwait(false);
                }
                catch { }
            }, token);
        }
    }
}
