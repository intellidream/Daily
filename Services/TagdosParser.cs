using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using Daily.Models;

namespace Daily.Services
{
    public static class TagdosParser
    {
        private static readonly Regex DigitOrTimeRegex = new(@"\d+|(\b\d+[hmkHMK]\b)|(\b\d+:\d+\b)", RegexOptions.Compiled);

        public static TagDoPillType ClassifyPill(string text, bool isCompleted = false)
        {
            if (isCompleted)
                return TagDoPillType.Completed;

            if (text.Contains('$') || text.Contains('€'))
                return TagDoPillType.Financial;

            if (text.Contains('!'))
                return TagDoPillType.Urgent;

            if (DigitOrTimeRegex.IsMatch(text))
                return TagDoPillType.TemporalOrMetric;

            return TagDoPillType.Standard;
        }

        public static TagDoStream ParseStream(
            string rawText,
            int orderIndex,
            string title,
            DateTime? reminderTime = null,
            string activeMemos = "",
            string attachmentsJson = "[]",
            string? customTitle = null,
            TagDoStream? existingStream = null)
        {
            var stream = new TagDoStream
            {
                OrderIndex = orderIndex,
                Title = title,
                CustomTitle = customTitle,
                RawText = rawText,
                StreamReminder = reminderTime,
                ActiveMemos = activeMemos,
                AttachmentsJson = attachmentsJson,
                Clusters = new List<TagDoCluster>()
            };

            if (string.IsNullOrWhiteSpace(rawText))
            {
                return stream;
            }

            var usedClusterIds = new HashSet<string>(StringComparer.Ordinal);
            var usedPillIds = new HashSet<string>(StringComparer.Ordinal);
            var existingPills = existingStream?.AllPills.ToList() ?? new List<TagDoPill>();

            // Split by " & " or "&" for clusters
            var rawClusters = rawText.Split('&', StringSplitOptions.TrimEntries);
            int clusterIdx = 0;
            foreach (var rawCluster in rawClusters)
            {
                if (string.IsNullOrWhiteSpace(rawCluster)) continue;

                var cluster = new TagDoCluster();
                // Split cluster by "/" for individual pills
                var rawPills = rawCluster.Split('/', StringSplitOptions.TrimEntries);

                foreach (var rawPill in rawPills)
                {
                    if (string.IsNullOrWhiteSpace(rawPill)) continue;

                    bool isCompleted = rawPill.StartsWith('~') || rawPill.StartsWith('-');
                    string cleanText = isCompleted ? rawPill.TrimStart('~', '-').Trim() : rawPill;

                    var existingPill = existingPills.FirstOrDefault(p =>
                        !usedPillIds.Contains(p.Id) &&
                        string.Equals(p.Text, cleanText, StringComparison.Ordinal));

                    if (existingPill != null)
                    {
                        usedPillIds.Add(existingPill.Id);
                        bool finalDone = isCompleted || existingPill.IsCompleted;
                        cluster.Pills.Add(new TagDoPill
                        {
                            Id = existingPill.Id,
                            Text = cleanText,
                            Type = ClassifyPill(cleanText, finalDone),
                            IsCompleted = finalDone
                        });
                    }
                    else
                    {
                        var type = ClassifyPill(cleanText, isCompleted);
                        cluster.Pills.Add(new TagDoPill
                        {
                            Text = cleanText,
                            Type = type,
                            IsCompleted = isCompleted
                        });
                    }
                }

                if (cluster.Pills.Count > 0)
                {
                    if (existingStream != null)
                    {
                        var pillIdSet = cluster.Pills.Select(p => p.Id).ToHashSet(StringComparer.Ordinal);
                        var matched = existingStream.Clusters.FirstOrDefault(c =>
                                !usedClusterIds.Contains(c.Id) &&
                                c.Pills.Any(p => pillIdSet.Contains(p.Id)))
                            ?? (clusterIdx < existingStream.Clusters.Count && !usedClusterIds.Contains(existingStream.Clusters[clusterIdx].Id)
                                ? existingStream.Clusters[clusterIdx]
                                : null);

                        if (matched != null)
                        {
                            usedClusterIds.Add(matched.Id);
                            cluster.Id = matched.Id;
                            cluster.ClusterReminder = matched.ClusterReminder;
                        }
                    }

                    stream.Clusters.Add(cluster);
                    clusterIdx++;
                }
            }

            return stream;
        }

        public static string SerializeStream(TagDoStream stream)
        {
            var clusterStrings = new List<string>();
            foreach (var cluster in stream.Clusters)
            {
                var pillStrings = cluster.Pills.Select(p => p.IsCompleted ? $"~{p.Text}" : p.Text);
                clusterStrings.Add(string.Join("/", pillStrings));
            }
            return string.Join(" & ", clusterStrings);
        }

        public static void TogglePillCompletion(TagDoStream stream, string pillId)
        {
            foreach (var cluster in stream.Clusters)
            {
                var pill = cluster.Pills.FirstOrDefault(p => p.Id == pillId);
                if (pill != null)
                {
                    pill.IsCompleted = !pill.IsCompleted;
                    pill.Type = ClassifyPill(pill.Text, pill.IsCompleted);
                    stream.RawText = SerializeStream(stream);
                    return;
                }
            }
        }

        public static void RecyclePillToBack(TagDoStream stream, string pillId)
        {
            TagDoPill? targetPill = null;
            TagDoCluster? sourceCluster = null;

            foreach (var cluster in stream.Clusters)
            {
                targetPill = cluster.Pills.FirstOrDefault(p => p.Id == pillId);
                if (targetPill != null)
                {
                    sourceCluster = cluster;
                    break;
                }
            }

            if (targetPill != null && sourceCluster != null)
            {
                sourceCluster.Pills.Remove(targetPill);
                targetPill.IsCompleted = false;
                targetPill.Type = ClassifyPill(targetPill.Text, false);

                // Add to last cluster or end of stream
                if (stream.Clusters.Count > 0)
                {
                    stream.Clusters[^1].Pills.Add(targetPill);
                }
                else
                {
                    var newCluster = new TagDoCluster();
                    newCluster.Pills.Add(targetPill);
                    stream.Clusters.Add(newCluster);
                }

                // Clean empty source cluster if it has no pills left
                if (sourceCluster.Pills.Count == 0 && stream.Clusters.Count > 1)
                {
                    stream.Clusters.Remove(sourceCluster);
                }

                stream.RawText = SerializeStream(stream);
            }
        }

        public static void MovePillToFront(TagDoStream stream, string pillId)
        {
            TagDoPill? targetPill = null;
            TagDoCluster? sourceCluster = null;

            foreach (var cluster in stream.Clusters)
            {
                targetPill = cluster.Pills.FirstOrDefault(p => p.Id == pillId);
                if (targetPill != null)
                {
                    sourceCluster = cluster;
                    break;
                }
            }

            if (targetPill != null && sourceCluster != null)
            {
                sourceCluster.Pills.Remove(targetPill);
                targetPill.IsCompleted = false;
                targetPill.Type = ClassifyPill(targetPill.Text, false);

                if (stream.Clusters.Count > 0)
                {
                    stream.Clusters[0].Pills.Insert(0, targetPill);
                }
                else
                {
                    var newCluster = new TagDoCluster();
                    newCluster.Pills.Add(targetPill);
                    stream.Clusters.Add(newCluster);
                }

                if (sourceCluster.Pills.Count == 0 && stream.Clusters.Count > 1)
                {
                    stream.Clusters.Remove(sourceCluster);
                }

                stream.RawText = SerializeStream(stream);
            }
        }

        public static void AddPill(TagDoStream stream, int clusterIndex, string pillText)
        {
            if (string.IsNullOrWhiteSpace(pillText)) return;

            string clean = pillText.Trim().ToUpperInvariant();
            var pill = new TagDoPill(clean, ClassifyPill(clean, false), false);

            if (clusterIndex >= 0 && clusterIndex < stream.Clusters.Count)
            {
                stream.Clusters[clusterIndex].Pills.Add(pill);
            }
            else
            {
                var newCluster = new TagDoCluster();
                newCluster.Pills.Add(pill);
                stream.Clusters.Add(newCluster);
            }

            stream.RawText = SerializeStream(stream);
        }

        public static void RemovePill(TagDoStream stream, string pillId)
        {
            foreach (var cluster in stream.Clusters)
            {
                var pill = cluster.Pills.FirstOrDefault(p => p.Id == pillId);
                if (pill != null)
                {
                    cluster.Pills.Remove(pill);
                    if (cluster.Pills.Count == 0 && stream.Clusters.Count > 1)
                    {
                        stream.Clusters.Remove(cluster);
                    }
                    stream.RawText = SerializeStream(stream);
                    return;
                }
            }
        }

        public static bool UpdatePillText(TagDoStream stream, string pillId, string newText)
        {
            string cleanText = (newText ?? string.Empty).Trim()
                .Replace("/", "-")
                .Replace("&", "+");
            if (string.IsNullOrWhiteSpace(cleanText)) return false;

            foreach (var cluster in stream.Clusters)
            {
                var pill = cluster.Pills.FirstOrDefault(p => p.Id == pillId);
                if (pill != null)
                {
                    pill.Text = cleanText;
                    pill.Type = ClassifyPill(cleanText, pill.IsCompleted);
                    stream.RawText = SerializeStream(stream);
                    return true;
                }
            }
            return false;
        }

        public static string AutoDetectStreamTitle(string rawText, int orderIndex)
        {
            int streamNum = orderIndex + 1;
            string upperText = (rawText ?? string.Empty).ToUpperInvariant();

            if (upperText.Contains("WRK") || upperText.Contains("PRJ") || upperText.Contains("CODE") ||
                upperText.Contains("BUG") || upperText.Contains("DEV") || upperText.Contains("MET"))
            {
                return $"Stream {streamNum}: Work & Code";
            }
            if (upperText.Contains("FIT") || upperText.Contains("GYM") || upperText.Contains("RUN") ||
                upperText.Contains("PROT") || upperText.Contains("SLP") || upperText.Contains("CREAT"))
            {
                return $"Stream {streamNum}: Health & Fitness";
            }
            if (upperText.Contains("FIN") || upperText.Contains("CARD") || upperText.Contains("CASH") ||
                upperText.Contains("INV") || upperText.Contains("STK") || upperText.Contains("C$T") || upperText.Contains("EUR"))
            {
                return $"Stream {streamNum}: Finances & Bills";
            }
            if (upperText.Contains("HOM") || upperText.Contains("ORD") || upperText.Contains("CLN") ||
                upperText.Contains("BUY") || upperText.Contains("MKT") || upperText.Contains("GROC"))
            {
                return $"Stream {streamNum}: Home & Life";
            }
            if (upperText.Contains("MG") || upperText.Contains("GM") || upperText.Contains("TG") ||
                upperText.Contains("FSH") || upperText.Contains("LDL"))
            {
                return $"Stream {streamNum}: Daily Ops";
            }

            var parsed = ParseStream(rawText ?? string.Empty, orderIndex, $"Stream {streamNum}");
            var driving = parsed.DrivingPill?.Text;
            if (!string.IsNullOrWhiteSpace(driving))
            {
                return $"Stream {streamNum}: {driving} Focus";
            }

            return streamNum switch
            {
                1 => "Stream 1: Daily Ops",
                2 => "Stream 2: Work & Code",
                3 => "Stream 3: Health & Fitness",
                4 => "Stream 4: Finances & Bills",
                5 => "Stream 5: Home & Life",
                _ => $"Stream {streamNum}"
            };
        }

        public static bool IsAlreadyTagdosDsl(string text)
        {
            var trimmed = (text ?? string.Empty).Trim();
            if (string.IsNullOrEmpty(trimmed)) return false;

            var lower = trimmed.ToLowerInvariant();
            if (lower.Contains("http://") || lower.Contains("https://") || lower.Contains("www."))
            {
                return false;
            }

            if (trimmed.Contains('/') || trimmed.Contains('&'))
            {
                var clusters = trimmed.Split('&', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                if (clusters.Length == 0) return false;

                if (trimmed.Contains('/'))
                {
                    int totalTokens = 0;
                    bool hasSpaceInsideToken = false;
                    bool hasMnemonicSignal = false;
                    foreach (var cluster in clusters)
                    {
                        var tokens = cluster.Split('/', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                        if (tokens.Length == 0) return false;
                        foreach (var token in tokens)
                        {
                            var words = token.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                            if (token.Length > 24 || words.Length > 3) return false;
                            if (words.Length > 1)
                            {
                                hasSpaceInsideToken = true;
                            }
                            if (token.Contains('$') || token.Contains('€') || token.Contains('!'))
                            {
                                hasMnemonicSignal = true;
                            }
                            foreach (var w in words)
                            {
                                var wLetters = w.Where(char.IsLetter).ToArray();
                                if (wLetters.Length >= 2 && wLetters.All(char.IsUpper))
                                {
                                    hasMnemonicSignal = true;
                                }
                            }
                            totalTokens++;
                        }
                    }
                    if (totalTokens < 2 && clusters.Length < 2) return false;
                    return !hasSpaceInsideToken || hasMnemonicSignal;
                }
                else
                {
                    if (clusters.Length < 2) return false;
                    bool hasMnemonicSignal = false;
                    foreach (var cluster in clusters)
                    {
                        var words = cluster.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                        if (cluster.Length > 24 || words.Length > 3) return false;
                        var lettersOnly = cluster.Where(char.IsLetter).ToArray();
                        bool isAllCaps = lettersOnly.Length > 0 && lettersOnly.All(char.IsUpper);
                        bool hasGlyph = cluster.Contains('$') || cluster.Contains('€') || cluster.Contains('!') || cluster.Any(char.IsDigit);
                        if (hasGlyph || isAllCaps || cluster.Length <= 5)
                        {
                            hasMnemonicSignal = true;
                        }
                    }
                    return hasMnemonicSignal;
                }
            }

            if (trimmed.Any(char.IsWhiteSpace) || trimmed.Length > 12) return false;
            if (lower.Contains(".com"))
            {
                return false;
            }

            bool hasSemanticGlyph = trimmed.Contains('$') || trimmed.Contains('€') || trimmed.Contains('!') || trimmed.Any(char.IsDigit);
            if (hasSemanticGlyph) return true;

            var singleLetters = trimmed.Where(char.IsLetter).ToArray();
            bool singleAllCaps = singleLetters.Length > 0 && singleLetters.All(char.IsUpper);
            return singleAllCaps || trimmed.Length <= 4;
        }

        private static readonly HashSet<string> StopWords = new(StringComparer.OrdinalIgnoreCase)
        {
            "the", "a", "an", "to", "for", "of", "in", "on", "at", "and", "or", "with", "my", "this", "that",
            "la", "de", "si", "cu", "pt", "pentru", "pe", "din", "un", "o", "sa"
        };

        private static readonly HashSet<string> FinancialWords = new(StringComparer.OrdinalIgnoreCase)
        {
            "pay", "bill", "bills", "invoice", "tax", "taxes", "bank", "card", "budget", "buy", "rent",
            "salary", "transfer", "money", "cost", "price", "fee", "plata", "factura", "bani", "buget", "eur", "usd", "ron"
        };

        private static readonly HashSet<string> UrgentWords = new(StringComparer.OrdinalIgnoreCase)
        {
            "urgent", "asap", "important", "deadline", "critical", "immediately"
        };

        public static string ProposeMnemonic(string title, bool isHighImportance = false)
        {
            var trimmed = (title ?? string.Empty).Trim();
            if (string.IsNullOrEmpty(trimmed)) return isHighImportance ? "TASK!" : "TASK";
            if (IsAlreadyTagdosDsl(trimmed))
            {
                return (isHighImportance && !trimmed.Contains('!') && !trimmed.Contains('/') && !trimmed.Contains('&'))
                    ? $"{trimmed}!"
                    : trimmed;
            }

            var rawTokens = Regex.Split(trimmed, @"[^A-Za-z0-9]+")
                .Where(t => !string.IsNullOrEmpty(t))
                .ToArray();
            var significant = rawTokens.Where(t => !StopWords.Contains(t)).ToArray();
            var words = significant.Length > 0 ? significant : rawTokens;

            bool hasEuro = trimmed.Contains('€') || rawTokens.Any(t => t.Equals("eur", StringComparison.OrdinalIgnoreCase) || t.Equals("euro", StringComparison.OrdinalIgnoreCase));
            bool hasDollar = trimmed.Contains('$') || rawTokens.Any(t => FinancialWords.Contains(t));
            bool isUrgent = isHighImportance || trimmed.Contains('!') || rawTokens.Any(t => UrgentWords.Contains(t));

            string baseTag;
            if (words.Length == 0)
            {
                baseTag = "TASK";
            }
            else if (words.Length == 1)
            {
                baseTag = words[0][..Math.Min(5, words[0].Length)].ToUpperInvariant();
            }
            else if (words.Length == 2)
            {
                string combined = words[0][..Math.Min(3, words[0].Length)] + words[1][..Math.Min(3, words[1].Length)];
                baseTag = combined[..Math.Min(6, combined.Length)].ToUpperInvariant();
            }
            else
            {
                string combined = words[0][..Math.Min(2, words[0].Length)]
                    + words[1][..Math.Min(2, words[1].Length)]
                    + words[2][..Math.Min(2, words[2].Length)];
                baseTag = combined[..Math.Min(6, combined.Length)].ToUpperInvariant();
            }

            if (hasEuro && !baseTag.Contains('€'))
            {
                baseTag += "€";
            }
            else if (hasDollar && !baseTag.Contains('$'))
            {
                baseTag += "$";
            }

            if (isUrgent && !baseTag.Contains('!'))
            {
                baseTag += "!";
            }

            return baseTag;
        }

        public static (string TagOrDsl, bool IsAlreadyDsl, string? MemoEntry) PrepareImportItem(
            string title,
            string? notes = null,
            bool isHighImportance = false)
        {
            string cleanTitle = (title ?? string.Empty).Trim();
            string rawNotes = (notes ?? string.Empty).Trim();
            string cleanNotes = rawNotes.Equals(cleanTitle, StringComparison.OrdinalIgnoreCase) ? string.Empty : rawNotes;
            bool isDsl = IsAlreadyTagdosDsl(cleanTitle);
            string tag = isDsl ? cleanTitle : ProposeMnemonic(cleanTitle, isHighImportance);

            if (isDsl)
            {
                // Plain notes only without any [DSL] prefix or title duplication
                string? memo = string.IsNullOrEmpty(cleanNotes) ? null : cleanNotes;
                return (tag, true, memo);
            }
            else
            {
                string memo = string.IsNullOrEmpty(cleanNotes)
                    ? $"• [{tag}] {cleanTitle}"
                    : $"• [{tag}] {cleanTitle} — {cleanNotes}";
                return (tag, false, memo);
            }
        }

        // ── Zero-Egress Stream & Cluster Reminder Spec ("HH:mm|0=08:45,1=14:15") ──

        public static string EncodeClusterSpecOnly(TagDoStream stream)
        {
            if (stream?.Clusters == null || stream.Clusters.Count == 0)
                return string.Empty;

            var parts = new List<string>();
            for (int i = 0; i < stream.Clusters.Count; i++)
            {
                var cr = stream.Clusters[i].ClusterReminder;
                if (cr.HasValue)
                {
                    parts.Add($"{i}={cr.Value.Hour:D2}:{cr.Value.Minute:D2}");
                }
            }
            return string.Join(",", parts);
        }

        public static void ApplyClusterRemindersSpec(TagDoStream stream, string? clusterSpec)
        {
            if (stream?.Clusters == null || string.IsNullOrWhiteSpace(clusterSpec))
                return;

            var now = DateTime.UtcNow;
            foreach (var pair in clusterSpec.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                var kv = pair.Split('=', 2, StringSplitOptions.TrimEntries);
                if (kv.Length == 2 &&
                    int.TryParse(kv[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out int idx) &&
                    idx >= 0 && idx < stream.Clusters.Count &&
                    TryParseHhMm(kv[1], now, out var dt))
                {
                    stream.Clusters[idx].ClusterReminder = dt;
                }
            }
        }

        public static string? EncodeReminderSpec(long? streamReminderTicks, string? clusterSpec)
        {
            string streamPart = string.Empty;
            if (streamReminderTicks.HasValue)
            {
                var dt = new DateTime(streamReminderTicks.Value, DateTimeKind.Utc);
                streamPart = $"{dt.Hour:D2}:{dt.Minute:D2}";
            }
            string cleanCluster = (clusterSpec ?? string.Empty).Trim();

            if (string.IsNullOrEmpty(streamPart) && string.IsNullOrEmpty(cleanCluster))
                return null;
            if (string.IsNullOrEmpty(cleanCluster))
                return streamPart;
            return $"{streamPart}|{cleanCluster}";
        }

        public static (long? StreamReminderTicks, string ClusterSpec) DecodeReminderSpec(string? raw)
        {
            if (string.IsNullOrWhiteSpace(raw))
                return (null, string.Empty);

            var trimmed = raw.Trim();
            var sections = trimmed.Split('|', 2);
            var now = DateTime.UtcNow;

            long? streamTicks = null;
            var streamToken = sections[0].Trim();
            if (!string.IsNullOrEmpty(streamToken))
            {
                if (TryParseHhMm(streamToken, now, out var dt))
                {
                    streamTicks = dt.Ticks;
                }
                else if (DateTime.TryParse(streamToken, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var parsedDt))
                {
                    streamTicks = parsedDt.ToUniversalTime().Ticks;
                }
            }

            string clusterSpec = string.Empty;
            if (sections.Length > 1 && !string.IsNullOrWhiteSpace(sections[1]))
            {
                var validPairs = new List<string>();
                foreach (var pair in sections[1].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    var kv = pair.Split('=', 2, StringSplitOptions.TrimEntries);
                    if (kv.Length == 2 &&
                        int.TryParse(kv[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out int idx) &&
                        idx >= 0 &&
                        TryParseHhMm(kv[1], now, out var dt))
                    {
                        validPairs.Add($"{idx}={dt.Hour:D2}:{dt.Minute:D2}");
                    }
                }
                clusterSpec = string.Join(",", validPairs);
            }

            return (streamTicks, clusterSpec);
        }

        private static bool TryParseHhMm(string token, DateTime refUtc, out DateTime result)
        {
            result = default;
            var parts = token.Trim().Split(':');
            if (parts.Length >= 2 &&
                int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out int h) &&
                int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out int m) &&
                h >= 0 && h < 24 && m >= 0 && m < 60)
            {
                result = new DateTime(refUtc.Year, refUtc.Month, refUtc.Day, h, m, 0, DateTimeKind.Utc);
                return true;
            }
            return false;
        }
    }
}
