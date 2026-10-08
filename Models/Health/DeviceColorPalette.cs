using System;
using System.Collections.Generic;

namespace Daily.Models.Health
{
    /// <summary>
    /// Deterministic 9-color palette based on 31-multiplier polynomial UTF-8 hash.
    /// Parity with Swift (DeviceColorPalette.swift) and Kotlin (DeviceColorPalette.kt).
    /// </summary>
    public static class DeviceColorPalette
    {
        public static readonly IReadOnlyList<string> Palette = new List<string>
        {
            "#00D09C", // 0: Emerald (Oura green)
            "#3897F0", // 1: Electric Blue (Pixel / Google)
            "#FF6B4A", // 2: Coral / Orange (Activity)
            "#AF52DE", // 3: Violet / Purple (HealthKit)
            "#FF2D55", // 4: Rose / Crimson
            "#34C759", // 5: Apple Green
            "#FF9500", // 6: Amber
            "#5856D6", // 7: Indigo
            "#00C7BE"  // 8: Cyan / Teal
        };

        public static string GetColor(string? sourceKey)
        {
            if (string.IsNullOrWhiteSpace(sourceKey))
            {
                return "#3897F0";
            }

            int hash = 0;
            byte[] bytes = System.Text.Encoding.UTF8.GetBytes(sourceKey);
            foreach (byte b in bytes)
            {
                unchecked
                {
                    hash = 31 * hash + b;
                }
            }

            long positiveHash = Math.Abs((long)hash);
            return Palette[(int)(positiveHash % Palette.Count)];
        }

        public static Windows.UI.Color ParseColor(string hex)
        {
            if (string.IsNullOrEmpty(hex)) return Windows.UI.Color.FromArgb(255, 56, 151, 240);
            var clean = hex.TrimStart('#');
            if (clean.Length == 6)
            {
                byte r = Convert.ToByte(clean.Substring(0, 2), 16);
                byte g = Convert.ToByte(clean.Substring(2, 2), 16);
                byte b = Convert.ToByte(clean.Substring(4, 2), 16);
                return Windows.UI.Color.FromArgb(255, r, g, b);
            }
            if (clean.Length == 8)
            {
                byte a = Convert.ToByte(clean.Substring(0, 2), 16);
                byte r = Convert.ToByte(clean.Substring(2, 2), 16);
                byte g = Convert.ToByte(clean.Substring(4, 2), 16);
                byte b = Convert.ToByte(clean.Substring(6, 2), 16);
                return Windows.UI.Color.FromArgb(a, r, g, b);
            }
            return Windows.UI.Color.FromArgb(255, 56, 151, 240);
        }
    }
}
