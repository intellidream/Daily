using System;
using System.Collections.Generic;
using System.Linq;

namespace Daily.Models.Health
{
    public enum DeviceType
    {
        Smartwatch,
        SmartRing,
        HealthPlatform,
        Smartphone,
        Manual,
        Sensor
    }

    /// <summary>
    /// Canonical device source classification and normalization for multi-device biometrics.
    /// Parity with Swift (DeviceSource.swift) and Kotlin (DeviceSource.kt).
    /// </summary>
    public class DeviceSource : IEquatable<DeviceSource>
    {
        public string RawName { get; }
        public string DisplayName { get; }
        public DeviceType Type { get; }
        public string ColorHex => DeviceColorPalette.GetColor(DisplayName);

        public string SegoeGlyph => Type switch
        {
            DeviceType.Smartwatch => "\xE95E",      // Watch / Health icon
            DeviceType.SmartRing => "\xEA3B",       // Circle ring
            DeviceType.HealthPlatform => "\xEB51",  // Heart
            DeviceType.Smartphone => "\xE8EA",      // Phone
            DeviceType.Manual => "\xE70F",          // Edit / Pencil
            _ => "\xE957"                           // Sensor
        };

        public bool IsVirtualEngine
        {
            get
            {
                var lower = RawName.ToLowerInvariant();
                return lower.Contains("stresswatch") ||
                       lower.Contains("stress-engine") ||
                       lower.Contains("daily biometric") ||
                       lower.Contains("biometric engine") ||
                       lower.Contains("computed") ||
                       lower.Contains("bubbles") ||
                       lower == "unknown";
            }
        }

        public static bool IsVirtual(string? name) => DeviceSource.From(name).IsVirtualEngine;

        public DeviceSource(string rawName, string displayName, DeviceType type)
        {
            RawName = rawName;
            DisplayName = displayName;
            Type = type;
        }

        public static DeviceSource From(string? name)
        {
            var clean = name?.Trim();
            if (string.IsNullOrEmpty(clean))
            {
                return new DeviceSource("Unknown", "Unknown", DeviceType.Sensor);
            }

            // Normalize compound key if already qualified with host device (e.g. "Schmitz - Oura Ring", "TRAPPER - com.fitbit.FitbitMobile")
            if (clean.Contains(" - "))
            {
                var parts = clean.Split(new[] { " - " }, 2, StringSplitOptions.None);
                if (parts.Length == 2)
                {
                    var host = parts[0].Trim();
                    var sensor = parts[1].Trim();
                    var resolvedSensor = From(sensor);
                    return new DeviceSource(clean, $"{host} - {resolvedSensor.DisplayName}", resolvedSensor.Type);
                }
            }

            var lower = clean.ToLowerInvariant();
            if (lower.Contains("fitbit")) return new DeviceSource(clean, "Fitbit", DeviceType.Smartwatch);
            if (lower.Contains("shealth") || lower.Contains("samsung") || lower.Contains("galaxy watch")) return new DeviceSource(clean, "Samsung Health", DeviceType.Smartwatch);
            if (lower.Contains("pixel watch") || lower.Contains("wear.companion") || lower.Contains("google.android.wearable")) return new DeviceSource(clean, "Pixel Watch", DeviceType.Smartwatch);
            if (lower.Contains("google fit") || lower.Contains("google.android.apps.fitness")) return new DeviceSource(clean, "Health Connect", DeviceType.HealthPlatform);
            if (lower.Contains("garmin")) return new DeviceSource(clean, "Garmin", DeviceType.Smartwatch);
            if (lower.Contains("whoop")) return new DeviceSource(clean, "WHOOP", DeviceType.Smartwatch);
            if (lower.Contains("withings")) return new DeviceSource(clean, "Withings", DeviceType.Smartwatch);
            if (lower.Contains("polar")) return new DeviceSource(clean, "Polar", DeviceType.Smartwatch);
            if (lower.Contains("oura")) return new DeviceSource(clean, "Oura Ring", DeviceType.SmartRing);
            if (lower.Contains("healthkit") || lower.Contains("apple health") || lower == "ios") return new DeviceSource(clean, "Apple Health", DeviceType.HealthPlatform);
            if (lower.Contains("apple") || lower.Contains("watchos")) return new DeviceSource(clean, "Apple Watch", DeviceType.Smartwatch);
            if (lower.Contains("zepp") || lower.Contains("amazfit") || lower.Contains("balance")) return new DeviceSource(clean, "Amazfit Balance", DeviceType.Smartwatch);
            if (lower.Contains("oneplus") || lower.Contains("wearos") || lower.Contains("heytap") || lower.Contains("oppo")) return new DeviceSource(clean, "OnePlus Watch", DeviceType.Smartwatch);
            if (lower.Contains("huawei") || lower.Contains("harmony") || lower.Contains("gt5")) return new DeviceSource(clean, "Huawei Watch", DeviceType.Smartwatch);
            if (lower.Contains("health connect") || lower.Contains("healthconnect") || lower == "android") return new DeviceSource(clean, "Health Connect", DeviceType.HealthPlatform);
            if (lower.Contains("manual")) return new DeviceSource(clean, "Manual Entry", DeviceType.Manual);

            if (clean.StartsWith("com.") || clean.StartsWith("org."))
            {
                var lastSegment = clean.Split('.').Last();
                if (!string.IsNullOrEmpty(lastSegment))
                {
                    var capitalized = char.ToUpperInvariant(lastSegment[0]) + (lastSegment.Length > 1 ? lastSegment.Substring(1) : "");
                    return new DeviceSource(clean, capitalized, DeviceType.Sensor);
                }
            }

            // Infer device type from string
            var inferredType = DeviceType.Sensor;
            if (lower.Contains("watch") || lower.Contains("band")) inferredType = DeviceType.Smartwatch;
            else if (lower.Contains("ring")) inferredType = DeviceType.SmartRing;
            else if (lower.Contains("phone") || lower.Contains("iphone") || lower.Contains("pixel") || lower.Contains("samsung")) inferredType = DeviceType.Smartphone;
            else if (lower.Contains("health")) inferredType = DeviceType.HealthPlatform;

            return new DeviceSource(clean, clean, inferredType);
        }

        /// <summary>
        /// Suppresses bare un-prefixed duplicates when a compound source is present
        /// (e.g. if 'Schmitz - Apple Health' exists, suppress bare 'Apple Health').
        /// </summary>
        public static List<DeviceSource> FilterBareDuplicates(IEnumerable<string> rawNames)
        {
            var sources = rawNames
                .Where(n => !string.IsNullOrWhiteSpace(n))
                .Select(From)
                .Where(s => !s.IsVirtualEngine)
                .GroupBy(s => s.DisplayName)
                .Select(g => g.First())
                .ToList();

            var compoundSources = sources.Where(s => s.DisplayName.Contains(" - ")).ToList();
            if (!compoundSources.Any()) return sources;

            var sensorNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var cs in compoundSources)
            {
                var parts = cs.DisplayName.Split(new[] { " - " }, 2, StringSplitOptions.None);
                if (parts.Length == 2)
                {
                    sensorNames.Add(parts[1].Trim());
                }
            }

            return sources.Where(s => !sensorNames.Contains(s.DisplayName)).ToList();
        }

        public bool Equals(DeviceSource? other) => other != null && string.Equals(DisplayName, other.DisplayName, StringComparison.OrdinalIgnoreCase);
        public override bool Equals(object? obj) => obj is DeviceSource other && Equals(other);
        public override int GetHashCode() => StringComparer.OrdinalIgnoreCase.GetHashCode(DisplayName);
        public override string ToString() => DisplayName;
    }
}
