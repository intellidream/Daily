using System;
using System.Text.Json.Serialization;

namespace Daily_WinUI.DesktopWidgets
{
    public enum DesktopWidgetType
    {
        Combined,
        Bubbles,
        Smokes,
        Money,
        Sleep,
        Stress,
        Cosmos,
        TagDos,
        Weather
    }

    public enum DesktopWidgetSize
    {
        Small,   // 170 x 170 pt
        Medium,  // 360 x 170 pt
        Large    // 360 x 360 pt
    }

    public enum DesktopBackdropType
    {
        Acrylic,
        MicaAlt
    }

    public class DesktopWidgetModel
    {
        public string Id { get; set; } = Guid.NewGuid().ToString("N");
        
        [JsonConverter(typeof(JsonStringEnumConverter))]
        public DesktopWidgetType Type { get; set; } = DesktopWidgetType.Combined;

        [JsonConverter(typeof(JsonStringEnumConverter))]
        public DesktopWidgetSize Size { get; set; } = DesktopWidgetSize.Medium;

        [JsonConverter(typeof(JsonStringEnumConverter))]
        public DesktopBackdropType Backdrop { get; set; } = DesktopBackdropType.MicaAlt;

        public int X { get; set; } = 100;
        public int Y { get; set; } = 100;
        public bool IsLocked { get; set; } = false;
        public double Opacity { get; set; } = 1.0;
        public string? MonitorId { get; set; }
    }
}
