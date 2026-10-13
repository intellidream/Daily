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
    }
}
