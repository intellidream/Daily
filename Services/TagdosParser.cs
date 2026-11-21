using System;
using System.Collections.Generic;
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

        public static TagDoStream ParseStream(string rawText, int orderIndex, string title, DateTime? reminderTime = null, string activeMemos = "", string attachmentsJson = "[]", string? customTitle = null)
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

            // Split by " & " or "&" for clusters
            var rawClusters = rawText.Split('&', StringSplitOptions.TrimEntries);
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

                    var type = ClassifyPill(cleanText, isCompleted);
                    cluster.Pills.Add(new TagDoPill
                    {
                        Text = cleanText,
                        Type = type,
                        IsCompleted = isCompleted
                    });
                }

                if (cluster.Pills.Count > 0)
                {
                    stream.Clusters.Add(cluster);
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

        public static bool IsAlreadyTagdosDsl(string text)
        {
            var trimmed = (text ?? string.Empty).Trim();
            if (string.IsNullOrEmpty(trimmed)) return false;

            if (trimmed.Contains('/') || trimmed.Contains('&'))
            {
                var clusters = trimmed.Split('&', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                if (clusters.Length == 0) return false;
                int totalTokens = 0;
                foreach (var cluster in clusters)
                {
                    var tokens = cluster.Split('/', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                    if (tokens.Length == 0) return false;
                    foreach (var token in tokens)
                    {
                        if (token.Any(char.IsWhiteSpace) || token.Length > 16) return false;
                        totalTokens++;
                    }
                }
                return totalTokens >= 1;
            }

            if (trimmed.Any(char.IsWhiteSpace) || trimmed.Length > 10) return false;
            var lower = trimmed.ToLowerInvariant();
            if (lower.StartsWith("http://") || lower.StartsWith("https://") || lower.Contains(".com"))
            {
                return false;
            }

            bool hasSemanticGlyph = trimmed.Contains('$') || trimmed.Contains('€') || trimmed.Contains('!') || trimmed.Any(char.IsDigit);
            if (hasSemanticGlyph) return true;

            var lettersOnly = trimmed.Where(char.IsLetter).ToArray();
            bool isAllCaps = lettersOnly.Length > 0 && lettersOnly.All(char.IsUpper);
            return isAllCaps || trimmed.Length <= 4;
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
            string cleanNotes = (notes ?? string.Empty).Trim();
            bool isDsl = IsAlreadyTagdosDsl(cleanTitle);
            string tag = isDsl ? cleanTitle : ProposeMnemonic(cleanTitle, isHighImportance);

            if (isDsl)
            {
                string? memo = string.IsNullOrEmpty(cleanNotes) ? null : $"• [{tag}] {cleanNotes}";
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
    }
}
