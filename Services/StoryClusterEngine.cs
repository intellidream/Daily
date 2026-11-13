using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Daily.Models;

namespace Daily.Services
{
    public static class ArticleFramingAnalyzer
    {
        private static readonly string[] OpinionMarkers =
        {
            "opinion:", "opinion |", "editorial:", "commentary:", "op-ed", "column:",
            "opinie:", "editorial |", "comentariu:", "punct de vedere", "why ", "de ce "
        };

        private static readonly string[] InvestigativeMarkers =
        {
            "investigation", "exclusive:", "revealed:", "leaked", "whistleblower", "documents show",
            "ancheta", "anchetă", "investigatie", "investigație", "exclusiv:", "dezvaluire", "dezvăluire", "recorder"
        };

        private static readonly string[] AnalysisMarkers =
        {
            "analysis:", "explainer:", "what to know", "how ", "deep dive",
            "analiza:", "analiză:", "explicatie", "explicație", "ce inseamna", "ce înseamnă"
        };

        private static readonly string[] SensationalMarkers =
        {
            "shocking", "bombshell", "destroys", "slams", "melts down", "panic", "chaos", "urgent:", "breaking!",
            "halucinant", "bomba!", "bombă!", "nucleara", "nucleară", "scandal monstru", "incredibil!", "socant", "șocant", "dezastru total"
        };

        public static ArticleFramingTag Classify(string? title, string? description = null, string? url = null)
        {
            string t = (title ?? string.Empty).Trim();
            string lowerTitle = t.ToLowerInvariant();
            string lowerUrl = (url ?? string.Empty).ToLowerInvariant();
            string combined = $"{lowerTitle} {(description ?? string.Empty).ToLowerInvariant()}";

            if (lowerUrl.Contains("/opinion/") || lowerUrl.Contains("/opinii/") || lowerUrl.Contains("/editorial/"))
            {
                return ArticleFramingTag.Opinion;
            }

            if (InvestigativeMarkers.Any(m => combined.Contains(m, StringComparison.Ordinal)))
            {
                return ArticleFramingTag.Investigative;
            }

            if (OpinionMarkers.Any(m => lowerTitle.Contains(m, StringComparison.Ordinal)))
            {
                return ArticleFramingTag.Opinion;
            }

            int upperLetters = t.Count(char.IsUpper);
            int totalLetters = t.Count(char.IsLetter);
            bool shoutingCaps = totalLetters >= 16 && ((double)upperLetters / totalLetters) > 0.55;
            bool excessivePunct = t.Contains("?!") || t.Contains("!!") || t.Count(c => c == '!') >= 2;

            if (shoutingCaps || excessivePunct || SensationalMarkers.Any(m => lowerTitle.Contains(m, StringComparison.Ordinal)))
            {
                return ArticleFramingTag.Sensational;
            }

            if (AnalysisMarkers.Any(m => lowerTitle.Contains(m, StringComparison.Ordinal)))
            {
                return ArticleFramingTag.Analysis;
            }

            return ArticleFramingTag.StraightReporting;
        }
    }

    /// <summary>
    /// Zero-LLM deterministic bilingual (EN + RO) event clustering engine (< 8 ms for 300 articles).
    /// Groups articles covering the same underlying news event within a 54h temporal window,
    /// computes Left / Center / Right bias distribution, and flags Left / Right Blindspots.
    /// </summary>
    public static class StoryClusterEngine
    {
        private static readonly TimeSpan MaxTemporalGap = TimeSpan.FromHours(54);

        private static readonly HashSet<string> Stopwords = new(StringComparer.Ordinal)
        {
            // English
            "the", "and", "for", "that", "with", "from", "this", "have", "will", "after", "over",
            "into", "amid", "says", "said", "what", "when", "where", "which", "while", "about",
            "more", "than", "their", "there", "been", "were", "they", "them", "could", "would",
            "should", "under", "between", "against", "during", "before", "report", "reports",
            "news", "live", "update", "updates", "today", "week", "year", "years", "first", "new",
            // Romanian
            "care", "pentru", "dupa", "după", "prin", "este", "sunt", "fost", "avea", "acest",
            "aceasta", "această", "peste", "intre", "între", "fara", "fără", "doar", "foarte",
            "mai", "mult", "multe", "acum", "azi", "ieri", "spune", "anunta", "anunță", "potrivit",
            "romania", "românia", "stiri", "știri", "video", "foto", "ultima", "ora", "oră",
            "cadrul", "privind", "asupra", "catre", "către", "unde", "cand", "când", "cum"
        };

        private static readonly Dictionary<string, string> CrossLingualSynonyms = new(StringComparer.Ordinal)
        {
            { "bce", "ecb" },
            { "bnr", "bnr" },
            { "sua", "usa" },
            { "ue", "eu" },
            { "onu", "un" },
            { "fmi", "imf" },
            { "dobanda", "rate" },
            { "dobânda", "rate" },
            { "dobanzi", "rate" },
            { "dobânzi", "rate" },
            { "rates", "rate" },
            { "interest", "rate" },
            { "inflatia", "inflation" },
            { "inflatiei", "inflation" },
            { "inflatii", "inflation" },
            { "tarife", "tariffs" },
            { "tarifele", "tariffs" },
            { "tariff", "tariffs" },
            { "alegeri", "election" },
            { "alegerile", "election" },
            { "elections", "election" },
            { "razboi", "war" },
            { "ucraina", "ukraine" },
            { "rusia", "russia" },
            { "buget", "budget" },
            { "bugetul", "budget" },
            { "guvern", "government" },
            { "guvernul", "government" },
            { "parlament", "parliament" },
            { "parlamentul", "parliament" },
            { "cuts", "cut" },
            { "scade", "cut" },
            { "reduce", "cut" },
            { "reduces", "cut" }
        };

        private sealed class PreparedCandidate
        {
            public RssItem Article { get; init; } = new();
            public MediaOutletProfile Outlet { get; init; } = new();
            public ArticleFramingTag Framing { get; init; }
            public bool IsFromSubscription { get; init; }
            public HashSet<string> Tokens { get; init; } = new(StringComparer.Ordinal);
            public HashSet<string> Entities { get; init; } = new(StringComparer.Ordinal);
        }

        private sealed class WorkingCluster
        {
            public List<PreparedCandidate> Members { get; } = new();
            public HashSet<string> UnionTokens { get; } = new(StringComparer.Ordinal);
            public HashSet<string> UnionEntities { get; } = new(StringComparer.Ordinal);
            public HashSet<string> SeenUrls { get; } = new(StringComparer.OrdinalIgnoreCase);
            public DateTime LatestDate { get; set; }
        }

        public static List<StoryCluster> ClusterArticles(
            IEnumerable<RssItem> articles,
            MediaIntelligenceRegistry? registry = null)
        {
            var reg = registry ?? MediaIntelligenceRegistry.Shared;
            var candidates = new List<PreparedCandidate>();
            var globalSeenUrls = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var item in articles.OrderByDescending(a => a.PublishDate))
            {
                string normUrl = NormalizeArticleUrl(item.Link);
                if (!string.IsNullOrEmpty(normUrl) && !globalSeenUrls.Add(normUrl))
                {
                    continue;
                }

                var outlet = reg.ResolveArticle(item);
                var framing = ArticleFramingAnalyzer.Classify(item.Title, item.Description, item.Link);
                ExtractFeatures(item.Title, item.Description, out var tokens, out var entities);

                var primary = new PreparedCandidate
                {
                    Article = item,
                    Outlet = outlet,
                    Framing = framing,
                    IsFromSubscription = true,
                    Tokens = tokens,
                    Entities = entities
                };
                candidates.Add(primary);

                // If the RSS item carried unpacked Google News siblings (<ol><li>), create linked cluster candidates
                if (item.GoogleNewsSiblings != null && item.GoogleNewsSiblings.Count > 0)
                {
                    var seededGroup = new List<PreparedCandidate> { primary };
                    foreach (var sib in item.GoogleNewsSiblings)
                    {
                        string sibNormUrl = NormalizeArticleUrl(sib.Url);
                        if (string.IsNullOrEmpty(sibNormUrl) || !globalSeenUrls.Add(sibNormUrl))
                            continue;

                        var sibItem = new RssItem
                        {
                            Title = sib.Title,
                            Link = sib.Url,
                            PublishDate = sib.PublishedAt ?? item.PublishDate,
                            PublicationName = sib.PublisherName,
                            ImageUrl = item.ImageUrl
                        };
                        var sibOutlet = reg.Resolve(sib.Url, sib.Url, sib.PublisherName, null);
                        var sibFraming = ArticleFramingAnalyzer.Classify(sib.Title, null, sib.Url);
                        ExtractFeatures(sib.Title, null, out var sibTokens, out var sibEntities);
                        // Ensure Google News native siblings share anchor entities with primary
                        foreach (var ent in entities.Take(3))
                        {
                            sibEntities.Add(ent);
                        }
                        seededGroup.Add(new PreparedCandidate
                        {
                            Article = sibItem,
                            Outlet = sibOutlet,
                            Framing = sibFraming,
                            IsFromSubscription = true,
                            Tokens = sibTokens,
                            Entities = sibEntities
                        });
                    }
                    // Skip first since already added; append remaining right after so greedy clustering merges them cleanly
                    for (int idx = 1; idx < seededGroup.Count; idx++)
                    {
                        candidates.Add(seededGroup[idx]);
                    }
                }
            }

            var working = new List<WorkingCluster>();

            foreach (var cand in candidates)
            {
                WorkingCluster? bestCluster = null;
                double bestScore = 0.0;

                foreach (var wc in working)
                {
                    if (Math.Abs((wc.LatestDate - cand.Article.PublishDate).TotalHours) > MaxTemporalGap.TotalHours)
                    {
                        continue;
                    }

                    double score = ComputeMatchScore(cand, wc);
                    if (score > bestScore)
                    {
                        bestScore = score;
                        bestCluster = wc;
                    }
                }

                if (bestCluster != null && bestScore >= 1.0)
                {
                    AddToWorkingCluster(bestCluster, cand);
                }
                else
                {
                    var fresh = new WorkingCluster { LatestDate = cand.Article.PublishDate };
                    AddToWorkingCluster(fresh, cand);
                    working.Add(fresh);
                }
            }

            return working
                .Select(wc => FinalizeCluster(wc, isExpandedExternal: false))
                .OrderByDescending(c => c.HasMultipleSources ? 1 : 0)
                .ThenByDescending(c => c.UniqueOutletCount)
                .ThenByDescending(c => c.LatestPublishedAt)
                .ToList();
        }

        public static StoryCluster MergeExpandedArticles(
            StoryCluster baseCluster,
            IEnumerable<RssItem> externalArticles,
            MediaIntelligenceRegistry? registry = null)
        {
            var reg = registry ?? MediaIntelligenceRegistry.Shared;
            var wc = new WorkingCluster { LatestDate = baseCluster.LatestPublishedAt };

            foreach (var cov in baseCluster.Coverage)
            {
                ExtractFeatures(cov.Article.Title, cov.Article.Description, out var t, out var e);
                AddToWorkingCluster(wc, new PreparedCandidate
                {
                    Article = cov.Article,
                    Outlet = cov.Outlet,
                    Framing = cov.Framing,
                    IsFromSubscription = cov.IsFromSubscription,
                    Tokens = t,
                    Entities = e
                });
            }

            foreach (var ext in externalArticles)
            {
                string normUrl = NormalizeArticleUrl(ext.Link);
                if (!string.IsNullOrEmpty(normUrl) && wc.SeenUrls.Contains(normUrl))
                    continue;

                // Reject unrelated noisy search hits unless they share at least 1 anchor token/entity
                ExtractFeatures(ext.Title, ext.Description, out var extTokens, out var extEntities);
                int tokenOverlap = extTokens.Count(tok => wc.UnionTokens.Contains(tok));
                int entityOverlap = extEntities.Count(ent => wc.UnionEntities.Contains(ent));
                if (tokenOverlap < 1 && entityOverlap < 1)
                    continue;

                var outlet = reg.ResolveArticle(ext);
                var framing = ArticleFramingAnalyzer.Classify(ext.Title, ext.Description, ext.Link);
                AddToWorkingCluster(wc, new PreparedCandidate
                {
                    Article = ext,
                    Outlet = outlet,
                    Framing = framing,
                    IsFromSubscription = false,
                    Tokens = extTokens,
                    Entities = extEntities
                });
            }

            return FinalizeCluster(wc, isExpandedExternal: true, preserveClusterId: baseCluster.Id);
        }

        public static string BuildDiscoveryQuery(StoryCluster cluster)
        {
            var terms = new List<string>();
            foreach (var ent in cluster.SharedEntities)
            {
                if (ent.Length >= 2 && terms.Count < 4)
                {
                    terms.Add(ent.Replace('_', '.'));
                }
            }

            if (terms.Count < 4)
            {
                ExtractFeatures(cluster.CanonicalTitle, null, out var titleTokens, out _);
                foreach (var tok in titleTokens.OrderByDescending(t => t.Length))
                {
                    if (!terms.Contains(tok, StringComparer.OrdinalIgnoreCase))
                    {
                        terms.Add(tok.Replace('_', '.'));
                        if (terms.Count >= 5) break;
                    }
                }
            }

            return string.Join(" ", terms.Take(5));
        }

        private static double ComputeMatchScore(PreparedCandidate cand, WorkingCluster wc)
        {
            if (cand.Tokens.Count == 0 || wc.UnionTokens.Count == 0) return 0.0;

            var lead = wc.Members[0];

            // Compute overlap against lead member so clusters don't drift via transitive chaining
            int sharedTokensLead = cand.Tokens.Count(t => lead.Tokens.Contains(t));
            int unionTokensLead = cand.Tokens.Count + lead.Tokens.Count - sharedTokensLead;
            double jaccard = unionTokensLead > 0 ? (double)sharedTokensLead / unionTokensLead : 0.0;
            double dice = (cand.Tokens.Count + lead.Tokens.Count) > 0
                ? (2.0 * sharedTokensLead) / (cand.Tokens.Count + lead.Tokens.Count)
                : 0.0;

            int sharedEntities = cand.Entities.Count(e => wc.UnionEntities.Contains(e));
            int specificEntities = cand.Entities.Count(e =>
                wc.UnionEntities.Contains(e) &&
                (e.Any(char.IsDigit) || e.Length >= 3));

            if (sharedEntities >= 2 && (jaccard >= 0.20 || dice >= 0.30))
                return 1.35 + jaccard;

            if (specificEntities >= 1 && sharedTokensLead >= 2 && (jaccard >= 0.16 || dice >= 0.26))
                return 1.15 + dice;

            if (jaccard >= 0.34 && sharedTokensLead >= 3)
                return 1.05 + jaccard;

            return jaccard;
        }

        private static void AddToWorkingCluster(WorkingCluster wc, PreparedCandidate cand)
        {
            string normUrl = NormalizeArticleUrl(cand.Article.Link);
            if (!string.IsNullOrEmpty(normUrl))
            {
                wc.SeenUrls.Add(normUrl);
            }
            wc.Members.Add(cand);
            foreach (var t in cand.Tokens) wc.UnionTokens.Add(t);
            foreach (var e in cand.Entities) wc.UnionEntities.Add(e);
            if (cand.Article.PublishDate > wc.LatestDate)
            {
                wc.LatestDate = cand.Article.PublishDate;
            }
        }

        private static StoryCluster FinalizeCluster(
            WorkingCluster wc,
            bool isExpandedExternal,
            string? preserveClusterId = null)
        {
            // Deduplicate per outlet when counting bias distribution (1 vote per unique outlet domain/displayName)
            var orderedMembers = wc.Members
                .OrderByDescending(m => m.IsFromSubscription ? 1 : 0)
                .ThenByDescending(m => m.Outlet.FactualityScore)
                .ThenByDescending(m => m.Article.PublishDate)
                .ToList();

            var lead = orderedMembers[0];
            string? heroImage = orderedMembers
                .Select(m => m.Article.ImageUrl)
                .FirstOrDefault(img => !string.IsNullOrWhiteSpace(img));

            int left = 0, leanLeft = 0, center = 0, leanRight = 0, right = 0, independent = 0, unrated = 0;
            var countedOutlets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var m in orderedMembers)
            {
                string outletKey = !string.IsNullOrEmpty(m.Outlet.Domain) && m.Outlet.Domain != "unknown"
                    ? m.Outlet.Domain
                    : m.Outlet.DisplayName;
                if (!countedOutlets.Add(outletKey)) continue;

                switch (m.Outlet.Bias)
                {
                    case MediaBias.Left: left++; break;
                    case MediaBias.LeanLeft: leanLeft++; break;
                    case MediaBias.Center: center++; break;
                    case MediaBias.LeanRight: leanRight++; break;
                    case MediaBias.Right: right++; break;
                    case MediaBias.Independent: independent++; break;
                    default: unrated++; break;
                }
            }

            var dist = new BiasDistribution
            {
                LeftCount = left,
                LeanLeftCount = leanLeft,
                CenterCount = center,
                LeanRightCount = leanRight,
                RightCount = right,
                IndependentCount = independent,
                UnratedCount = unrated
            };

            BlindspotType? blindspot = DetectBlindspot(dist);

            var coverage = orderedMembers.Select((m, idx) => new ClusterCoverageItem
            {
                Id = $"{NormalizeArticleUrl(m.Article.Link)}#{idx}",
                Article = m.Article,
                Outlet = m.Outlet,
                Framing = m.Framing,
                IsFromSubscription = m.IsFromSubscription
            }).ToList();

            var topEntities = wc.UnionEntities
                .OrderByDescending(ent => wc.Members.Count(m => m.Entities.Contains(ent)))
                .ThenByDescending(ent => ent.Length)
                .Take(6)
                .ToList();

            string clusterId = preserveClusterId ?? ComputeClusterHash(topEntities, lead.Tokens, wc.LatestDate);

            return new StoryCluster
            {
                Id = clusterId,
                CanonicalTitle = lead.Article.Title,
                LatestPublishedAt = wc.LatestDate,
                HeroImageUrl = heroImage,
                LeadArticle = lead.Article,
                Coverage = coverage,
                Distribution = dist,
                Blindspot = blindspot,
                SharedEntities = topEntities,
                IsExpandedExternal = isExpandedExternal,
                UniqueOutletCount = countedOutlets.Count
            };
        }

        public static BlindspotType? DetectBlindspot(BiasDistribution dist)
        {
            if (dist.TotalSources < 3 || dist.RatedSpectrumTotal < 3)
                return null;

            if (dist.LeftRatio < 0.12 && dist.RightRatio > 0.55)
                return BlindspotType.LeftBlindspot;

            if (dist.RightRatio < 0.12 && dist.LeftRatio > 0.55)
                return BlindspotType.RightBlindspot;

            return null;
        }

        private static string ComputeClusterHash(List<string> entities, HashSet<string> leadTokens, DateTime date)
        {
            var sig = entities.Count >= 2
                ? entities.OrderBy(x => x, StringComparer.Ordinal).Take(4)
                : leadTokens.OrderBy(x => x, StringComparer.Ordinal).Take(5);
            string bucket = $"{date:yyyy-MM-dd}|{string.Join(":", sig)}";
            byte[] bytes = SHA256.HashData(Encoding.UTF8.GetBytes(bucket));
            return Convert.ToHexString(bytes).Substring(0, 20).ToLowerInvariant();
        }

        private static void ExtractFeatures(
            string? title,
            string? description,
            out HashSet<string> tokens,
            out HashSet<string> entities)
        {
            tokens = new HashSet<string>(StringComparer.Ordinal);
            entities = new HashSet<string>(StringComparer.Ordinal);

            string rawTitle = PreprocessHeadlineText(title ?? string.Empty);
            string snippet = (description ?? string.Empty);
            if (snippet.Length > 180) snippet = snippet.Substring(0, 180);
            string rawCombined = $"{rawTitle} {PreprocessHeadlineText(snippet)}";

            // Extract capitalized proper nouns & acronyms from original title (skip index 0 unless acronym/known)
            var rawWords = Regex.Matches(rawTitle, @"[\p{L}\p{N}_]+");
            for (int i = 0; i < rawWords.Count; i++)
            {
                string w = rawWords[i].Value;
                if (w.Length < 2) continue;

                bool hasDigit = w.Any(char.IsDigit);
                bool isAcronym = w.Length >= 2 && w.Length <= 6 && w.All(c => !char.IsLetter(c) || char.IsUpper(c));
                bool isCapitalizedMidSentence = i > 0 && char.IsUpper(w[0]) && w.Length >= 3;

                string folded = FoldDiacritics(w).ToLowerInvariant();
                if (CrossLingualSynonyms.TryGetValue(folded, out var syn))
                {
                    folded = syn;
                }

                if (!Stopwords.Contains(folded) && (hasDigit || isAcronym || isCapitalizedMidSentence))
                {
                    entities.Add(folded);
                }
            }

            // Tokenize title + short lead
            foreach (Match m in Regex.Matches(rawCombined, @"[\p{L}\p{N}_]+"))
            {
                string folded = FoldDiacritics(m.Value).ToLowerInvariant();
                if (CrossLingualSynonyms.TryGetValue(folded, out var syn))
                {
                    folded = syn;
                }

                if (folded.Length < 3 && !folded.Any(char.IsDigit) && folded != "eu" && folded != "un" && folded != "uk" && folded != "us" && folded != "ai")
                {
                    continue;
                }

                if (Stopwords.Contains(folded)) continue;
                tokens.Add(folded);

                if (folded.Any(char.IsDigit))
                {
                    entities.Add(folded);
                }
            }
        }

        private static string PreprocessHeadlineText(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return string.Empty;
            string s = text;
            // Unify decimal numbers (2.25% / 2,25% -> 2_25)
            s = Regex.Replace(s, @"(\d+)[.,](\d+)", "$1_$2");
            // Collapse multi-word institutions to canonical cross-lingual tokens
            s = Regex.Replace(s, @"\bEuropean Central Bank\b", "ECB", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bBanca Central[aă] European[aă]\b", "ECB", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bBanca Na[tț]ional[aă] a Rom[aâ]niei\b", "BNR", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bEuropean Union\b", "EU", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bUniunea European[aă]\b", "EU", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bUnited States\b", "USA", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bStatele Unite\b", "USA", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bWhite House\b", "WhiteHouse", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bCasa Alb[aă]\b", "WhiteHouse", RegexOptions.IgnoreCase);
            s = Regex.Replace(s, @"\bFederal Reserve\b", "Fed", RegexOptions.IgnoreCase);
            return s;
        }

        private static string FoldDiacritics(string input)
        {
            string normalized = input.Normalize(NormalizationForm.FormD);
            var sb = new StringBuilder(normalized.Length);
            foreach (char c in normalized)
            {
                if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                {
                    sb.Append(c);
                }
            }
            return sb.ToString().Normalize(NormalizationForm.FormC);
        }

        public static string NormalizeArticleUrl(string? url)
        {
            if (string.IsNullOrWhiteSpace(url)) return string.Empty;
            string trimmed = url.Trim();
            int hashIdx = trimmed.IndexOf('#');
            if (hashIdx >= 0) trimmed = trimmed.Substring(0, hashIdx);
            int qIdx = trimmed.IndexOf('?');
            if (qIdx >= 0 && !trimmed.Contains("news.google.com", StringComparison.OrdinalIgnoreCase))
            {
                trimmed = trimmed.Substring(0, qIdx);
            }
            return trimmed.TrimEnd('/').ToLowerInvariant();
        }
    }
}
