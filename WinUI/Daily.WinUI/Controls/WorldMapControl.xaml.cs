using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using System;
using System.Collections.Generic;
using System.Linq;
using Daily.Models.Finances;
using Microsoft.UI;

namespace Daily_WinUI.Controls;

public sealed partial class WorldMapControl : UserControl
{
    public static readonly DependencyProperty DataProperty =
        DependencyProperty.Register("Data", typeof(IEnumerable<CountryEconomicData>), typeof(WorldMapControl), new PropertyMetadata(null, OnDataChanged));

    public IEnumerable<CountryEconomicData> Data
    {
        get => (IEnumerable<CountryEconomicData>)GetValue(DataProperty);
        set => SetValue(DataProperty, value);
    }

    private SolidColorBrush DefaultFill = new SolidColorBrush(Windows.UI.Color.FromArgb(23, 128, 128, 128));

    public WorldMapControl()
    {
        this.InitializeComponent();
    }

    private void UserControl_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        // No-op
    }

    private static void OnDataChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is WorldMapControl control)
        {
            control.UpdateMap();
        }
    }

    private void UpdateMap()
    {
        if (Data == null || !Data.Any()) return;

        var dataMap = Data.ToDictionary(d => d.CountryCode, d => d);

        var trackedCountries = new[] { "US", "CA", "MX", "BR", "AR", "GB", "SE", "FR", "DE", "CH", "PL", "RO", "TR", "EG", "SA", "AE", "NG", "ZA", "IN", "CN", "TH", "KR", "JP", "ID", "AU" };

        foreach (var cc in trackedCountries)
        {
            var path = MapCanvas.FindName(cc) as Microsoft.UI.Xaml.Shapes.Path;
            if (path == null) continue;

            if (dataMap.TryGetValue(cc, out var d))
            {
                var (r, g, b) = HeatRgb(d.RealRate);
                path.Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(230, (byte)r, (byte)g, (byte)b));
                ToolTipService.SetToolTip(path, $"{d.CountryName}: {d.RealRate:F1}% real rate ({d.InterestRate:F1}% rate - {d.InflationRate:F1}% inflation)");
            }
            else
            {
                path.Fill = DefaultFill;
            }
        }
    }

    private (int r, int g, int b) HeatRgb(decimal rate)
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
