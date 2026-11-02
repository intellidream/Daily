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
    /// 1:1 parity with Swift (HealthModels.swift) and Kotlin (HealthModels.kt) — 7 canonical physical devices.
    /// </summary>
    public class DeviceSource : IEquatable<DeviceSource>
    {
        public string RawName { get; }
        public string DisplayName { get; }
        public DeviceType Type { get; }
        public int SortPriority { get; }
        public bool IsWearable { get; }
        public string ColorHex => DeviceColorPalette.GetColor(DisplayName);

        public string SegoeGlyph => Type switch
        {
            DeviceType.Smartwatch => "\xE95E",      // Watch
            DeviceType.SmartRing => "\xEA3B",       // Ring
            DeviceType.HealthPlatform => "\xEB51",  // Heart
            DeviceType.Smartphone => "\xE8EA",      // Phone
            DeviceType.Manual => "\xE70F",          // Edit / Pencil
            _ => "\xE957"                           // Sensor
        };

        public bool IsVirtualEngine
        {
            get
            {
                var lower = DisplayName.ToLowerInvariant();
                var rawLower = RawName.ToLowerInvariant();
                return lower == "unknown" ||
                       lower == "canonical" ||
                       lower == "apple health" ||
                       lower == "health connect" ||
                       lower == "google fit" ||
                       lower == "mac" ||
                       lower == "windows" ||
                       rawLower.Contains("stresswatch") ||
                       rawLower.Contains("stress-engine") ||
                       rawLower.Contains("daily biometric") ||
                       rawLower.Contains("biometric engine") ||
                       rawLower.Contains("computed") ||
                       rawLower.Contains("canonical") ||
                       rawLower.Contains("bubbles") ||
                       rawLower == "mac" ||
                       rawLower == "macos" ||
                       rawLower == "windows" ||
                       rawLower == "winui" ||
                       rawLower == "unknown";
            }
        }

        public static bool IsVirtual(string? name) => From(name).IsVirtualEngine;

        public DeviceSource(string rawName, string displayName, DeviceType type, int sortPriority = 10, bool isWearable = false)
        {
            RawName = rawName;
            DisplayName = displayName;
            Type = type;
            SortPriority = sortPriority;
            IsWearable = isWearable;
        }

        public static DeviceSource From(string? name)
        {
            var clean = name?.Trim();
            if (string.IsNullOrEmpty(clean))
            {
                return new DeviceSource("Unknown", "Unknown", DeviceType.Sensor, 0, false);
            }

            // Unwrap legacy "Host - Sensor" compound strings into bare canonical hardware names
            if (clean.Contains(" - "))
            {
                var parts = clean.Split(new[] { " - " }, 2, StringSplitOptions.None);
                var host = parts[0].Trim();
                var sensor = parts.Length > 1 ? parts[1].Trim() : "";
                var sLower = sensor.ToLowerInvariant();

                if (sLower.Contains("oura"))
                    return new DeviceSource(clean, "Oura Ring", DeviceType.SmartRing, 100, true);
                if (sLower.Contains("pixel watch") || sLower.Contains("fitbit") || sLower.Contains("wear.companion") || sLower.Contains("google.android.wearable"))
                    return new DeviceSource(clean, "Pixel Watch 5", DeviceType.Smartwatch, 90, true);
                if (sLower.Contains("apple watch") || sLower.Contains("watchos") || sLower.Contains("ultra"))
                    return new DeviceSource(clean, "Apple Watch Ultra 2", DeviceType.Smartwatch, 90, true);
                if (sLower.Contains("oneplus") || sLower.Contains("heytap") || sLower.Contains("oppo") || sLower.Contains("wearos"))
                    return new DeviceSource(clean, "OnePlus Watch 3", DeviceType.Smartwatch, 85, true);

                // Otherwise it's a host phone sensor or obfuscated pedometer package on the host phone
                return ResolveHostPhone(host, clean);
            }

            var lower = clean.ToLowerInvariant();

            if (lower == "canonical" || lower == "mac" || lower == "macos" || lower == "windows" || lower == "winui" ||
                lower.Contains("stresswatch") || lower.Contains("stress-engine") || lower.Contains("biometric engine") ||
                lower.Contains("daily biometric") || lower.Contains("computed") || lower.Contains("bubbles"))
            {
                return new DeviceSource(clean, "Unknown", DeviceType.Sensor, 0, false);
            }

            if (lower.Contains("oura"))
                return new DeviceSource(clean, "Oura Ring", DeviceType.SmartRing, 100, true);

            if (lower.Contains("pixel watch") || lower.Contains("fitbit") || lower.Contains("wear.companion") || lower.Contains("google.android.wearable"))
                return new DeviceSource(clean, "Pixel Watch 5", DeviceType.Smartwatch, 90, true);

            if (lower.Contains("apple watch") || lower.Contains("watchos") || lower.Contains("watch ultra"))
                return new DeviceSource(clean, "Apple Watch Ultra 2", DeviceType.Smartwatch, 90, true);

            if (lower.Contains("oneplus") || lower.Contains("heytap") || lower.Contains("oppo") || lower.Contains("wearos"))
                return new DeviceSource(clean, "OnePlus Watch 3", DeviceType.Smartwatch, 85, true);

            if (lower.Contains("zepp") || lower.Contains("amazfit") || lower.Contains("balance"))
                return new DeviceSource(clean, "Amazfit Balance", DeviceType.Smartwatch, 75, true);

            if (lower.Contains("huawei") || lower.Contains("harmony") || lower.Contains("gt5"))
                return new DeviceSource(clean, "Huawei Watch", DeviceType.Smartwatch, 75, true);

            if (lower.Contains("schmitz") || lower.Contains("iphone"))
                return new DeviceSource(clean, "Schmitz (iPhone)", DeviceType.Smartphone, 40, false);

            if (lower.Contains("trapper") || lower.Contains("pixel 9"))
                return new DeviceSource(clean, "Trapper (Pixel 9 Pro)", DeviceType.Smartphone, 40, false);

            if (lower.Contains("radar") || lower.Contains("fold") || lower.Contains("shealth") || lower.Contains("samsung") || lower.Contains("galaxy"))
                return new DeviceSource(clean, "Radar (Galaxy Z Fold 8)", DeviceType.Smartphone, 40, false);

            if (lower.Contains("healthkit") || lower.Contains("apple health") || lower == "ios")
                return new DeviceSource(clean, "Apple Health", DeviceType.HealthPlatform, 0, false);

            if (lower.Contains("health connect") || lower.Contains("healthconnect") || lower.Contains("google fit") || lower == "android")
                return new DeviceSource(clean, "Health Connect", DeviceType.HealthPlatform, 0, false);

            if (lower.Contains("manual"))
                return new DeviceSource(clean, "Manual Entry", DeviceType.Manual, 10, false);

            return new DeviceSource(clean, "Unknown", DeviceType.Sensor, 0, false);
        }

        private static DeviceSource ResolveHostPhone(string host, string raw)
        {
            var hLower = host.ToLowerInvariant();
            if (hLower.Contains("schmitz") || hLower.Contains("iphone"))
                return new DeviceSource(raw, "Schmitz (iPhone)", DeviceType.Smartphone, 40, false);
            if (hLower.Contains("radar") || hLower.Contains("fold") || hLower.Contains("samsung") || hLower.Contains("galaxy"))
                return new DeviceSource(raw, "Radar (Galaxy Z Fold 8)", DeviceType.Smartphone, 40, false);
            if (hLower.Contains("trapper") || hLower.Contains("pixel"))
                return new DeviceSource(raw, "Trapper (Pixel 9 Pro)", DeviceType.Smartphone, 40, false);
            return new DeviceSource(raw, "Unknown", DeviceType.Sensor, 0, false);
        }

        public static List<DeviceSource> FilterBareDuplicates(IEnumerable<string> rawNames)
        {
            return rawNames
                .Where(n => !string.IsNullOrWhiteSpace(n))
                .Select(From)
                .Where(s => !s.IsVirtualEngine)
                .GroupBy(s => s.DisplayName, StringComparer.OrdinalIgnoreCase)
                .Select(g => g.First())
                .OrderByDescending(s => s.SortPriority)
                .ThenBy(s => s.DisplayName, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        public bool Equals(DeviceSource? other) => other != null && string.Equals(DisplayName, other.DisplayName, StringComparison.OrdinalIgnoreCase);
        public override bool Equals(object? obj) => obj is DeviceSource other && Equals(other);
        public override int GetHashCode() => StringComparer.OrdinalIgnoreCase.GetHashCode(DisplayName);
        public override string ToString() => DisplayName;
    }
}
