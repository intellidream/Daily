using System;
using System.Collections.Generic;

namespace Daily.Models.Health
{
    /// <summary>
    /// Deterministic canonical color palette matching Swift & Kotlin DeviceColorPalette.
    /// </summary>
    public static class DeviceColorPalette
    {
        public static readonly IReadOnlyList<string> Palette = new List<string>
        {
            "#00D09C", // 0: Emerald (Oura Ring)
            "#3897F0", // 1: Electric Blue (Pixel Watch 5)
            "#FF6B4A", // 2: Coral / Orange (Apple Watch Ultra 2)
            "#AF52DE", // 3: Violet / Purple (Schmitz iPhone)
            "#FF2D55", // 4: Rose / Crimson (OnePlus Watch 3)
            "#34C759", // 5: Apple Green
            "#FF9500", // 6: Amber
            "#5856D6", // 7: Indigo (Trapper Pixel 9 Pro)
            "#00C7BE"  // 8: Cyan / Teal (Radar Galaxy Z Fold 8)
        };

        public static string GetColor(string? sourceKey)
        {
            if (string.IsNullOrWhiteSpace(sourceKey))
            {
                return "#3897F0";
            }

            var canon = DeviceSource.From(sourceKey).DisplayName;
            return canon switch
            {
                "Oura Ring" => "#00D09C",
                "Pixel Watch 5" => "#3897F0",
                "Apple Watch Ultra 2" => "#FF6B4A",
                "OnePlus Watch 3" => "#FF2D55",
                "Schmitz (iPhone)" => "#AF52DE",
                "Trapper (Pixel 9 Pro)" => "#5856D6",
                "Radar (Galaxy Z Fold 8)" => "#00C7BE",
                _ => HashFallback(canon)
            };
        }

        private static string HashFallback(string key)
        {
            int hash = 0;
            byte[] bytes = System.Text.Encoding.UTF8.GetBytes(key);
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

#if WINUI_NATIVE
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
#endif
    }
}
