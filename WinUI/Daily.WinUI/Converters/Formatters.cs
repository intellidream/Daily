using Microsoft.UI.Xaml.Data;
using System;

namespace Daily_WinUI.Converters;

public class CurrencyConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal d)
            return d.ToString("C2");
        if (value is double db)
            return db.ToString("C2");
        return value?.ToString();
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class PercentConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is decimal d)
            return (d > 0 ? "+" : "") + d.ToString("F2") + "%";
        if (value is double db)
            return (db > 0 ? "+" : "") + db.ToString("F2") + "%";
        return value?.ToString();
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class StringToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return (value is string s && !string.IsNullOrEmpty(s)) 
            ? Microsoft.UI.Xaml.Visibility.Visible 
            : Microsoft.UI.Xaml.Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class WidgetAgingDurationTooltipConverter : IValueConverter
{
    private static readonly string[] AgingLabels = { "10s", "30s", "1m", "2m", "5m", "10m", "30m", "1h", "2h", "3h" };

    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is double d)
        {
            int idx = (int)Math.Round(d);
            if (idx >= 0 && idx < AgingLabels.Length)
            {
                return AgingLabels[idx];
            }
        }
        return value?.ToString() ?? "";
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class EmptyVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is int count)
        {
            return count == 0 ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;
        }
        return Microsoft.UI.Xaml.Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class InverseBooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is bool b)
        {
            return b ? Microsoft.UI.Xaml.Visibility.Collapsed : Microsoft.UI.Xaml.Visibility.Visible;
        }
        return Microsoft.UI.Xaml.Visibility.Visible;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class BooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is bool b)
        {
            return b ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;
        }
        return Microsoft.UI.Xaml.Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class IsTodayToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is DateTime dt)
        {
            return dt.Date == DateTime.Today ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;
        }
        return Microsoft.UI.Xaml.Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class IsTodayToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is DateTime dt && dt.Date == DateTime.Today)
        {
            return new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White);
        }
        return Microsoft.UI.Xaml.Application.Current.Resources.TryGetValue("AppFgColorBrush", out var res) && res is Microsoft.UI.Xaml.Media.Brush b ? b : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Black);
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class TodayBackgroundGlowConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is DateTime dt && dt.Date == DateTime.Today)
        {
            var baseBrush = CalendarColorHelper.GetLightAccentBrush();
            if (baseBrush is Microsoft.UI.Xaml.Media.SolidColorBrush solidBrush)
            {
                return new Microsoft.UI.Xaml.Media.SolidColorBrush(solidBrush.Color) { Opacity = 0.04 };
            }
            return new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.RoyalBlue) { Opacity = 0.04 };
        }
        return new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public class TodayCircleBadgeBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        if (value is DateTime dt && dt.Date == DateTime.Today)
        {
            return CalendarColorHelper.GetLightAccentBrush();
        }
        return new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}

public static class CalendarColorHelper
{
    public static Microsoft.UI.Xaml.Media.Brush GetLightAccentBrush()
    {
        foreach (var dictKey in new[] { "Dark", "Default" })
        {
            if (Microsoft.UI.Xaml.Application.Current.Resources.ThemeDictionaries.TryGetValue(dictKey, out var dictObj) && 
                dictObj is Microsoft.UI.Xaml.ResourceDictionary themeDict)
            {
                if (themeDict.TryGetValue("SystemAccentColorLight2", out var resColor) && resColor is Windows.UI.Color color)
                {
                    return new Microsoft.UI.Xaml.Media.SolidColorBrush(color);
                }
                if (themeDict.TryGetValue("SystemAccentColorLight2Brush", out var resBrush) && resBrush is Microsoft.UI.Xaml.Media.Brush brush)
                {
                    return brush;
                }
            }
        }

        if (Microsoft.UI.Xaml.Application.Current.Resources.TryGetValue("SystemAccentColorLight2", out var globalColor) && globalColor is Windows.UI.Color gColor)
        {
            return new Microsoft.UI.Xaml.Media.SolidColorBrush(gColor);
        }

        if (Microsoft.UI.Xaml.Application.Current.Resources.TryGetValue("SystemAccentColor", out var sysColorRes) && sysColorRes is Windows.UI.Color sysColor)
        {
            return new Microsoft.UI.Xaml.Media.SolidColorBrush(sysColor);
        }

        return new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.RoyalBlue);
    }
}
