using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;
using System;
using Microsoft.UI;

namespace Daily_WinUI.Converters;

public class IndicatorBackgroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal val)
        {
            return val >= 0 
                ? new SolidColorBrush(Windows.UI.Color.FromArgb((byte)(255 * 0.05), 76, 175, 80)) 
                : new SolidColorBrush(Windows.UI.Color.FromArgb((byte)(255 * 0.05), 244, 67, 54));
        }
        return new SolidColorBrush(Colors.Transparent);
    }
    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class IndicatorBorderConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal val)
        {
            return val >= 0 
                ? new SolidColorBrush(Windows.UI.Color.FromArgb((byte)(255 * 0.2), 76, 175, 80)) 
                : new SolidColorBrush(Windows.UI.Color.FromArgb((byte)(255 * 0.2), 244, 67, 54));
        }
        return new SolidColorBrush(Colors.Transparent);
    }
    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class IndicatorForegroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal val)
        {
            return val >= 0 
                ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 76, 175, 80)) 
                : new SolidColorBrush(Windows.UI.Color.FromArgb(255, 244, 67, 54));
        }
        return new SolidColorBrush(Colors.White);
    }
    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class IndicatorIconConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal val)
        {
            // Up arrow: &#xE70E; (ChevronUp) or &#xE010; (Up)
            // Down arrow: &#xE70D; (ChevronDown) or &#xE011; (Down)
            // Actually, Segoe Fluent Icons:
            // Arrow up: &#xE898; 
            // Arrow down: &#xE896;
            // Let's use Triangle up/down for solid look: 
            // &#xE74A; (Up) &#xE74B; (Down) 
            return val >= 0 ? "\uE74A" : "\uE74B";
        }
        return "";
    }
    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class CountryFlagConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is string countryCode && countryCode.Length == 2)
        {
            // Convert to regional indicator symbols
            int offset = 0x1F1E6 - 'A';
            int char1 = char.ToUpper(countryCode[0]) + offset;
            int char2 = char.ToUpper(countryCode[1]) + offset;
            return char.ConvertFromUtf32(char1) + char.ConvertFromUtf32(char2);
        }
        return "🌐";
    }
    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public static class HeatmapColors
{
    public static (int r, int g, int b) HeatRgb(decimal rate)
    {
        var c = Math.Max(-10, Math.Min(10, (double)rate));
        var n = (c + 10) / 20.0;
        int r, g, b;
        if (n < 0.5) 
        { 
            r = 244; 
            g = (int)(67 + 188 * (n / 0.5)); 
            b = (int)(54 * (1 - n / 0.5)); 
        }
        else 
        { 
            r = (int)(255 * (1 - (n - 0.5) / 0.5)); 
            g = (int)(175 + 80 * ((n - 0.5) / 0.5)); 
            b = (int)(80 * ((n - 0.5) / 0.5)); 
        }
        return (r, g, b);
    }
}

public class HeatmapBackgroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal val)
        {
            var (r, g, b) = HeatmapColors.HeatRgb(val);
            return new SolidColorBrush(Windows.UI.Color.FromArgb((byte)(255 * 0.08), (byte)r, (byte)g, (byte)b));
        }
        return new SolidColorBrush(Colors.Transparent);
    }
    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class HeatmapBorderConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal val)
        {
            var (r, g, b) = HeatmapColors.HeatRgb(val);
            return new SolidColorBrush(Windows.UI.Color.FromArgb((byte)(255 * 0.3), (byte)r, (byte)g, (byte)b));
        }
        return new SolidColorBrush(Colors.Transparent);
    }
    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class HeatmapForegroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal val)
        {
            var (r, g, b) = HeatmapColors.HeatRgb(val);
            return new SolidColorBrush(Windows.UI.Color.FromArgb(255, (byte)r, (byte)g, (byte)b));
        }
        return new SolidColorBrush(Colors.White);
    }
    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}
