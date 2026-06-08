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
