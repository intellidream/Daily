using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Daily.Models;

namespace Daily.Services
{
    /// <summary>
    /// Thread-safe, zero-egress local registry of 200+ international, European, and Romanian media outlets,
    /// backed by embedded media_intelligence_seed.json with optional 24h delta watermark merge from Supabase.
    /// </summary>
    public sealed class MediaIntelligenceRegistry
    {
        public static MediaIntelligenceRegistry Shared { get; } = new MediaIntelligenceRegistry();

        private static readonly HashSet<string> AggregatorHosts = new(StringComparer.OrdinalIgnoreCase)
        {
            "news.google.com", "google.com", "bing.com", "msn.com",
            "feedly.com", "cloud.feedly.com", "feedburner.com", "feeds.feedburner.com",
            "apple.news", "flipboard.com", "smartnews.com"
        };

        private readonly object _syncRoot = new();
        private readonly Dictionary<string, MediaOutletProfile> _byDomain = new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, MediaOutletProfile> _byNormalizedName = new(StringComparer.OrdinalIgnoreCase);

        public MediaIntelligenceRegistry()
        {
            LoadEmbeddedSeedCatalog();
        }

        public int CatalogCount
        {
            get
            {
                lock (_syncRoot) return _byDomain.Count;
            }
        }

        private void LoadEmbeddedSeedCatalog()
        {
            try
            {
                var asm = typeof(MediaIntelligenceRegistry).Assembly;
                Stream? stream = asm.GetManifestResourceStream("media_intelligence_seed.json");
                if (stream == null)
                {
                    var matchName = asm.GetManifestResourceNames()
                        .FirstOrDefault(n => n.EndsWith("media_intelligence_seed.json", StringComparison.OrdinalIgnoreCase));
                    if (matchName != null)
                    {
                        stream = asm.GetManifestResourceStream(matchName);
                    }
                }

                if (stream == null)
                {
                    var fallbackPath = Path.Combine(AppContext.BaseDirectory, "Models", "Resources", "media_intelligence_seed.json");
                    if (File.Exists(fallbackPath))
                    {
                        stream = File.OpenRead(fallbackPath);
                    }
                }

                if (stream == null) return;

                using (stream)
                {
                    var entries = JsonSerializer.Deserialize<List<SeedOutletEntryDto>>(stream);
                    if (entries == null) return;

                    lock (_syncRoot)
                    {
                        foreach (var dto in entries)
                        {
                            var domain = NormalizeHost(dto.Domain);
                            if (string.IsNullOrEmpty(domain)) continue;
                            var profile = new MediaOutletProfile
                            {
                                Domain = domain,
                                DisplayName = dto.DisplayName,
                                CountryCode = dto.CountryCode,
                                LanguageCode = dto.LanguageCode,
                                Bias = MediaBiasExtensions.Parse(dto.Bias),
                                BiasScore = dto.BiasScore,
                                BiasContext = dto.BiasContext,
                                Factuality = FactualityTierExtensions.Parse(dto.Factuality),
                                FactualityScore = dto.FactualityScore,
                                OwnerName = dto.OwnerName,
                                OwnershipType = OwnershipCategoryExtensions.Parse(dto.OwnershipType),
                                FundingSummary = dto.FundingSummary,
                                IsVerified = true
                            };
                            _byDomain[domain] = profile;
                            var normName = NormalizePublisherName(dto.DisplayName);
                            if (!string.IsNullOrEmpty(normName))
                            {
                                _byNormalizedName[normName] = profile;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MediaIntelligenceRegistry] Seed load error: {ex.Message}");
            }
        }

        public void MergeRemoteRows(IEnumerable<RemoteMediaOutletProfileRow> rows)
        {
            lock (_syncRoot)
            {
                foreach (var row in rows)
                {
                    var domain = NormalizeHost(row.Domain);
                    if (string.IsNullOrEmpty(domain)) continue;
                    var profile = new MediaOutletProfile
                    {
                        Domain = domain,
                        DisplayName = row.DisplayName,
                        CountryCode = row.CountryCode,
                        LanguageCode = row.LanguageCode,
                        Bias = MediaBiasExtensions.Parse(row.BiasRating),
                        BiasScore = row.BiasScore,
                        BiasContext = row.BiasContext,
                        Factuality = FactualityTierExtensions.Parse(row.FactualityRating),
                        FactualityScore = row.FactualityScore,
                        OwnerName = row.OwnerName,
                        OwnershipType = OwnershipCategoryExtensions.Parse(row.OwnershipType),
                        FundingSummary = row.FundingSummary,
                        IsVerified = true
                    };
                    _byDomain[domain] = profile;
                    var normName = NormalizePublisherName(row.DisplayName);
                    if (!string.IsNullOrEmpty(normName))
                    {
                        _byNormalizedName[normName] = profile;
                    }
                }
            }
        }

        public MediaOutletProfile ResolveArticle(RssItem item)
        {
            return Resolve(
                url: item.SourcePublisherUrl ?? item.Link,
                fallbackUrl: item.Link,
                publisherName: item.PublicationName,
                author: item.Author);
        }

        public MediaOutletProfile Resolve(
            string? url,
            string? fallbackUrl = null,
            string? publisherName = null,
            string? author = null)
        {
            string host = ExtractHost(url);
            if (string.IsNullOrEmpty(host) || AggregatorHosts.Contains(host))
            {
                string altHost = ExtractHost(fallbackUrl);
                if (!string.IsNullOrEmpty(altHost) && !AggregatorHosts.Contains(altHost))
                {
                    host = altHost;
                }
            }

            lock (_syncRoot)
            {
                // 1. Direct & parent-domain match (unless aggregator host)
                if (!string.IsNullOrEmpty(host) && !AggregatorHosts.Contains(host))
                {
                    if (_byDomain.TryGetValue(host, out var exact))
                    {
                        return exact;
                    }

                    // Walk parent domains (e.g. edition.cnn.com -> cnn.com, news.bbc.co.uk -> bbc.co.uk)
                    var parts = host.Split('.');
                    for (int i = 1; i <= parts.Length - 2; i++)
                    {
                        string candidate = string.Join(".", parts.Skip(i));
                        if (candidate.Equals("substack.com", StringComparison.OrdinalIgnoreCase) ||
                            candidate.Equals("medium.com", StringComparison.OrdinalIgnoreCase) ||
                            candidate.Equals("co.uk", StringComparison.OrdinalIgnoreCase) ||
                            candidate.Equals("com.au", StringComparison.OrdinalIgnoreCase))
                        {
                            continue;
                        }
                        if (_byDomain.TryGetValue(candidate, out var parentMatch))
                        {
                            return parentMatch;
                        }
                    }
                }

                // 2. Substack / Medium Independent Creator synthesis
                if (IsSubstackOrMedium(host, url, fallbackUrl, publisherName))
                {
                    string display = CleanPublisherDisplayName(publisherName, author, host);
                    string creatorOwner = !string.IsNullOrWhiteSpace(author) ? author!.Trim() : display;
                    bool isSubstack = (host?.Contains("substack.com", StringComparison.OrdinalIgnoreCase) ?? false) ||
                                      (url?.Contains("substack.com", StringComparison.OrdinalIgnoreCase) ?? false) ||
                                      (publisherName?.Contains("Substack", StringComparison.OrdinalIgnoreCase) ?? false);
                    return new MediaOutletProfile
                    {
                        Domain = !string.IsNullOrEmpty(host) ? host : (isSubstack ? "substack.com" : "medium.com"),
                        DisplayName = display,
                        CountryCode = "INT",
                        LanguageCode = "en",
                        Bias = MediaBias.Independent,
                        BiasScore = 0.0,
                        BiasContext = isSubstack ? "Independent Substack Publication" : "Independent Creator Essay",
                        Factuality = FactualityTier.MostlyFactual,
                        FactualityScore = 76,
                        OwnerName = creatorOwner,
                        OwnershipType = OwnershipCategory.IndependentCreator,
                        FundingSummary = isSubstack
                            ? "Reader-funded independent newsletter via Substack subscriptions."
                            : "Independent writer publishing on the Medium partner platform.",
                        IsVerified = true
                    };
                }

                // 3. Normalized publisher name lookup (critical for Google News unpacked items!)
                if (!string.IsNullOrWhiteSpace(publisherName))
                {
                    string normPub = NormalizePublisherName(publisherName);
                    if (!string.IsNullOrEmpty(normPub) && _byNormalizedName.TryGetValue(normPub, out var byName))
                    {
                        return byName;
                    }

                    // Secondary prefix/token check for "Reuters.com", "HotNews.ro", "BBC News"
                    string strippedTld = NormalizeHost(publisherName);
                    if (!string.IsNullOrEmpty(strippedTld) && _byDomain.TryGetValue(strippedTld, out var byDomName))
                    {
                        return byDomName;
                    }
                }
            }

            // 4. Graceful Unrated fallback
            string fallbackDomain = !string.IsNullOrEmpty(host) && !AggregatorHosts.Contains(host)
                ? host
                : (!string.IsNullOrWhiteSpace(publisherName) ? NormalizePublisherName(publisherName) : "unknown");
            string fallbackDisplay = !string.IsNullOrWhiteSpace(publisherName)
                ? publisherName!.Trim()
                : (!string.IsNullOrEmpty(host) ? host : "External Source");

            return new MediaOutletProfile
            {
                Domain = fallbackDomain,
                DisplayName = fallbackDisplay,
                CountryCode = "INT",
                LanguageCode = "en",
                Bias = MediaBias.Unrated,
                BiasScore = 0.0,
                BiasContext = "Unrated Publication",
                Factuality = FactualityTier.Mixed,
                FactualityScore = 60,
                OwnerName = fallbackDisplay,
                OwnershipType = OwnershipCategory.CorporateConglomerate,
                FundingSummary = "Editorial bias and ownership profile not yet verified in local catalog.",
                IsVerified = false
            };
        }

        private static bool IsSubstackOrMedium(string? host, string? url, string? fallbackUrl, string? publisherName)
        {
            if (!string.IsNullOrEmpty(host) &&
                (host.EndsWith(".substack.com", StringComparison.OrdinalIgnoreCase) ||
                 host.Equals("substack.com", StringComparison.OrdinalIgnoreCase) ||
                 host.Equals("open.substack.com", StringComparison.OrdinalIgnoreCase) ||
                 host.EndsWith(".medium.com", StringComparison.OrdinalIgnoreCase) ||
                 host.Equals("medium.com", StringComparison.OrdinalIgnoreCase)))
            {
                return true;
            }
            string combined = $"{url} {fallbackUrl} {publisherName}";
            return combined.Contains("substack.com", StringComparison.OrdinalIgnoreCase) ||
                   combined.Contains("medium.com", StringComparison.OrdinalIgnoreCase);
        }

        private static string CleanPublisherDisplayName(string? publisherName, string? author, string? host)
        {
            if (!string.IsNullOrWhiteSpace(publisherName) &&
                !publisherName.Equals("Substack Inbox", StringComparison.OrdinalIgnoreCase) &&
                !publisherName.Equals("Medium Reading List", StringComparison.OrdinalIgnoreCase))
            {
                return publisherName.Trim();
            }
            if (!string.IsNullOrWhiteSpace(author))
            {
                return author.Trim();
            }
            if (!string.IsNullOrEmpty(host) && host.EndsWith(".substack.com", StringComparison.OrdinalIgnoreCase))
            {
                return host.Substring(0, host.Length - ".substack.com".Length);
            }
            return !string.IsNullOrEmpty(host) ? host : "Independent Author";
        }

        public static string ExtractHost(string? url)
        {
            if (string.IsNullOrWhiteSpace(url)) return string.Empty;
            string candidate = url.Trim();
            if (!candidate.Contains("://") && candidate.Contains('.'))
            {
                candidate = "https://" + candidate;
            }
            if (Uri.TryCreate(candidate, UriKind.Absolute, out var uri))
            {
                return NormalizeHost(uri.Host);
            }
            return string.Empty;
        }

        public static string NormalizeHost(string? host)
        {
            if (string.IsNullOrWhiteSpace(host)) return string.Empty;
            string h = host.Trim().ToLowerInvariant();
            string[] prefixes = { "www.", "m.", "mobile.", "amp.", "edition." };
            foreach (var p in prefixes)
            {
                if (h.StartsWith(p, StringComparison.Ordinal))
                {
                    h = h.Substring(p.Length);
                    break;
                }
            }
            return h.TrimEnd('/');
        }

        public static string NormalizePublisherName(string? name)
        {
            if (string.IsNullOrWhiteSpace(name)) return string.Empty;
            var chars = name.Trim().ToLowerInvariant()
                .Where(c => char.IsLetterOrDigit(c))
                .ToArray();
            return new string(chars);
        }
    }
}
