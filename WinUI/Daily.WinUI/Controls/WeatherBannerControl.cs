using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace Daily_WinUI.Controls;

/// <summary>
/// Weather banner that overlays decorative atmospheric shapes over Mica.
/// Uses a Viewbox so the inner Canvas (fixed coordinate space) scales to any window width.
/// No solid backgrounds — Mica remains fully visible through the transparent overlay.
/// </summary>
public sealed class WeatherBannerControl : Grid
{
    // Inner canvas coordinate space — shapes are authored at this size then scaled by Viewbox
    private const double VW = 1400;
    private const double VH = 110;

    private readonly Canvas _canvas;

    public WeatherBannerControl()
    {
        IsHitTestVisible = false;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        VerticalAlignment   = VerticalAlignment.Top;
        Height = VH;
        Opacity = 0.85;
        Background = null; // keep Grid itself transparent

        _canvas = new Canvas
        {
            Width  = VW,
            Height = VH,
            IsHitTestVisible = false,
        };

        var viewbox = new Viewbox
        {
            Stretch              = Stretch.Fill,
            HorizontalAlignment  = HorizontalAlignment.Stretch,
            VerticalAlignment    = VerticalAlignment.Stretch,
            Child                = _canvas,
        };

        Children.Add(viewbox);
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public void SetCondition(string iconCode)
    {
        _canvas.Children.Clear();
        if (string.IsNullOrWhiteSpace(iconCode)) return;

        bool night = iconCode.EndsWith("n", StringComparison.OrdinalIgnoreCase);
        string group = iconCode.Length >= 2 ? iconCode[..2] : "01";

        switch (group)
        {
            case "01": if (night) DrawClearNight(); else DrawClearDay(); break;
            case "02": if (night) DrawFewCloudsNight(); else DrawFewCloudsDay(); break;
            case "03": if (night) DrawCloudyNight(); else DrawCloudyDay(); break;
            case "04": DrawBrokenClouds(); break;
            case "09": DrawShowerRain(); break;
            case "10": if (night) DrawRain(dark: true); else DrawRain(dark: false); break;
            case "11": DrawThunderstorm(); break;
            case "13": DrawSnow(); break;
            case "50": DrawFog(); break;
            default:   if (night) DrawClearNight(); else DrawClearDay(); break;
        }
    }

    // ── Shape helpers ─────────────────────────────────────────────────────────

    // Semi-transparent tint that tints the Mica slightly toward the sky colour
    private void TintRect(Color color, double opacity)
    {
        var r = new Rectangle { Width = VW, Height = VH, Opacity = opacity };
        r.Fill = new SolidColorBrush(color);
        _canvas.Children.Add(r);
    }

    private void Add(UIElement e) => _canvas.Children.Add(e);

    private static Ellipse Cloud(double cx, double cy, double rx, double ry, Color fill, double opacity)
    {
        var e = new Ellipse { Width = rx * 2, Height = ry * 2, Opacity = opacity };
        e.Fill = new SolidColorBrush(fill);
        Canvas.SetLeft(e, cx - rx);
        Canvas.SetTop(e,  cy - ry);
        return e;
    }

    private static Ellipse Circle(double cx, double cy, double r, Color fill, double opacity)
        => Cloud(cx, cy, r, r, fill, opacity);

    private static Line Stroke(double x1, double y1, double x2, double y2,
                                Color color, double thick, double opacity)
    {
        var l = new Line
        {
            X1 = x1, Y1 = y1, X2 = x2, Y2 = y2,
            StrokeThickness = thick,
            Opacity = opacity,
            Stroke  = new SolidColorBrush(color),
        };
        return l;
    }

    private static Rectangle Band(double y, double height, Color fill, double opacity)
    {
        var r = new Rectangle { Width = VW, Height = height, Opacity = opacity };
        r.Fill = new SolidColorBrush(fill);
        Canvas.SetTop(r, y);
        return r;
    }

    private static Color Hex(string h)
    {
        h = h.TrimStart('#');
        byte r = Convert.ToByte(h[0..2], 16);
        byte g = Convert.ToByte(h[2..4], 16);
        byte b = Convert.ToByte(h[4..6], 16);
        return Color.FromArgb(255, r, g, b);
    }

    private static Color HexA(byte a, string h)
    {
        var c = Hex(h);
        return Color.FromArgb(a, c.R, c.G, c.B);
    }

    // ── Scenes — no solid backgrounds, only translucent overlays ─────────────

    private void DrawClearDay()
    {
        // Very faint warm sky tint so Mica still shows
        TintRect(HexA(28, "#1a6fa8"), 1.0);

        // Sun glow (radial fade)
        var glowBrush = new RadialGradientBrush();
        glowBrush.GradientStops.Add(new GradientStop { Color = HexA(90, "#fff9c4"),  Offset = 0 });
        glowBrush.GradientStops.Add(new GradientStop { Color = HexA(0,  "#fff9c4"),  Offset = 1 });
        var glow = new Ellipse { Width = 140, Height = 140, Fill = glowBrush };
        Canvas.SetLeft(glow, 1120); Canvas.SetTop(glow, -30);
        Add(glow);

        // Sun disc
        Add(Circle(1190, 33, 22, HexA(210, "#fff9c4"), 1.0));

        // Halo rings
        foreach (var (rad, op) in new[] { (38.0, 0.18), (55.0, 0.09) })
        {
            var ring = new Ellipse { Width = rad * 2, Height = rad * 2, Opacity = op, StrokeThickness = 3 };
            ring.Stroke = new SolidColorBrush(Hex("#ffd54f"));
            ring.Fill   = null;
            Canvas.SetLeft(ring, 1190 - rad); Canvas.SetTop(ring, 33 - rad);
            Add(ring);
        }

        // Bottom horizon shimmer
        Add(Band(90, 20, HexA(30, "#a8dff5"), 1.0));
    }

    private void DrawClearNight()
    {
        TintRect(HexA(55, "#060d1a"), 1.0);

        // Stars
        (double x, double y, double r, double op)[] stars =
            [(120,18,1.5,.70),(340,30,1,.50),(580,14,1.5,.80),(760,25,1,.60),
             (950,12,1.5,.70),(1050,40,1,.50),(220,45,1,.40),(670,42,1.5,.60),(870,48,1,.50)];
        foreach (var (x, y, r, op) in stars)
            Add(Circle(x, y, r, Colors.White, op));

        // Crescent moon
        Add(Circle(1180, 36, 16, HexA(220, "#e8eaf6"), 1.0));
        Add(Circle(1193, 29, 13, HexA(200, "#060d1a"), 1.0));
    }

    private void DrawFewCloudsDay()
    {
        TintRect(HexA(28, "#2176ae"), 1.0);

        Add(Circle(1120, 28, 18, HexA(200, "#fffde7"), 1.0));

        Add(Cloud(420, 58, 110, 28, HexA(90, "#ffffff"), 1.0));
        Add(Cloud(470, 46,  70, 24, HexA(80, "#ffffff"), 1.0));
        Add(Cloud(350, 52,  60, 20, HexA(70, "#ffffff"), 1.0));

        Add(Cloud(900, 64,  80, 20, HexA(65, "#ffffff"), 1.0));
        Add(Cloud(950, 53,  52, 18, HexA(55, "#ffffff"), 1.0));
    }

    private void DrawFewCloudsNight()
    {
        TintRect(HexA(50, "#07101f"), 1.0);

        Add(Circle(1150, 32, 14, HexA(200, "#dde3f0"), 1.0));
        Add(Circle(1162, 25, 12, HexA(190, "#07101f"), 1.0));

        Add(Cloud(500, 62, 100, 24, HexA(35, "#c9d4e8"), 1.0));
        Add(Cloud(550, 50,  68, 20, HexA(28, "#c9d4e8"), 1.0));

        (double x, double y, double r, double op)[] stars =
            [(200,20,1.2,.55),(650,15,1.5,.60),(900,28,1,.50)];
        foreach (var (x, y, r, op) in stars)
            Add(Circle(x, y, r, Colors.White, op));
    }

    private void DrawCloudyDay()
    {
        TintRect(HexA(35, "#6e8fa8"), 1.0);
        Add(Cloud(200,  62, 160, 36, HexA(75, "#ffffff"), 1.0));
        Add(Cloud(300,  48, 110, 30, HexA(65, "#ffffff"), 1.0));
        Add(Cloud(700,  57, 200, 38, HexA(70, "#ffffff"), 1.0));
        Add(Cloud(820,  42, 130, 28, HexA(60, "#ffffff"), 1.0));
        Add(Cloud(1200, 60, 160, 34, HexA(65, "#ffffff"), 1.0));
        Add(Cloud(1280, 44, 100, 26, HexA(50, "#ffffff"), 1.0));
    }

    private void DrawCloudyNight()
    {
        TintRect(HexA(60, "#151e2a"), 1.0);
        Add(Cloud(250,  60, 150, 32, HexA(100, "#4a5568"), 1.0));
        Add(Cloud(350,  46, 100, 26, HexA( 80, "#4a5568"), 1.0));
        Add(Cloud(750,  54, 190, 34, HexA( 90, "#4a5568"), 1.0));
        Add(Cloud(1250, 58, 150, 30, HexA( 95, "#4a5568"), 1.0));
    }

    private void DrawBrokenClouds()
    {
        TintRect(HexA(40, "#4a6070"), 1.0);
        Add(Cloud(180,  67, 180, 40, HexA(85, "#d0d8e0"), 1.0));
        Add(Cloud(290,  50, 120, 32, HexA(70, "#d0d8e0"), 1.0));
        Add(Cloud(640,  62, 220, 42, HexA(75, "#d0d8e0"), 1.0));
        Add(Cloud(760,  44, 150, 30, HexA(65, "#d0d8e0"), 1.0));
        Add(Cloud(1100, 64, 180, 38, HexA(70, "#d0d8e0"), 1.0));
        Add(Cloud(1220, 48, 120, 28, HexA(60, "#d0d8e0"), 1.0));
    }

    private void DrawShowerRain()  => DrawRainScene(HexA(60, "#3a4a58"), 0.55);
    private void DrawRain(bool dark) => DrawRainScene(
        dark ? HexA(75, "#0e1820") : HexA(60, "#3d5060"),
        dark ? 0.42 : 0.50);

    private void DrawRainScene(Color tint, double cloudOpacity)
    {
        TintRect(tint, 1.0);
        Add(Cloud(400,  52, 280, 38, HexA((byte)(cloudOpacity * 255), "#8090a0"), 1.0));
        Add(Cloud(900,  48, 320, 36, HexA((byte)(cloudOpacity * 240), "#8090a0"), 1.0));
        int[] xs = [80, 160, 260, 380, 460, 560, 660, 740, 840, 940, 1040, 1140, 1240, 1320];
        foreach (var x in xs)
        {
            int y1 = 65 + (x % 18);
            Add(Stroke(x,      y1,     x - 5,  y1 + 22, HexA(140, "#a8d0e8"), 1.2, 1.0));
            Add(Stroke(x + 28, y1 + 4, x + 23, y1 + 20, HexA(100, "#a8d0e8"), 1.0, 1.0));
        }
    }

    private void DrawThunderstorm()
    {
        TintRect(HexA(80, "#1a1a2e"), 1.0);

        var glowBrush = new RadialGradientBrush();
        glowBrush.GradientStops.Add(new GradientStop { Color = HexA(30,  "#fff9c4"), Offset = 0 });
        glowBrush.GradientStops.Add(new GradientStop { Color = HexA(0,   "#fff9c4"), Offset = 1 });
        var glow = new Ellipse { Width = 800, Height = 300, Fill = glowBrush };
        Canvas.SetLeft(glow, 300); Canvas.SetTop(glow, -80);
        Add(glow);

        Add(Cloud(350,  54, 260, 38, HexA(178, "#2a2a40"), 1.0));
        Add(Cloud(800,  50, 300, 36, HexA(165, "#2a2a40"), 1.0));
        Add(Cloud(1150, 56, 220, 34, HexA(153, "#2a2a40"), 1.0));

        Add(Stroke(560, 40, 548, 64, HexA(230, "#fff59d"), 2.5, 1.0));
        Add(Stroke(548, 64, 558, 64, HexA(230, "#fff59d"), 2.5, 1.0));
        Add(Stroke(558, 64, 542, 88, HexA(230, "#fff59d"), 2.5, 1.0));
        Add(Stroke(860, 38, 848, 60, HexA(178, "#fff59d"), 2.0, 1.0));
        Add(Stroke(848, 60, 857, 60, HexA(178, "#fff59d"), 2.0, 1.0));
        Add(Stroke(857, 60, 840, 85, HexA(178, "#fff59d"), 2.0, 1.0));

        foreach (var x in new[] { 400, 650, 950, 1100 })
            Add(Stroke(x, 72, x - 6, 90, HexA(128, "#90b8d0"), 1.2, 1.0));
    }

    private void DrawSnow()
    {
        TintRect(HexA(30, "#7890a0"), 1.0);
        Add(Cloud(500,  48, 300, 34, HexA(122, "#e8eef4"), 1.0));
        Add(Cloud(1000, 46, 280, 32, HexA(112, "#e8eef4"), 1.0));
        (double x, double y)[] flakes =
            [(100,75),(200,82),(320,68),(430,88),(560,72),(680,90),
             (780,70),(890,84),(1010,74),(1130,86),(1240,70),(1360,80)];
        foreach (var (x, y) in flakes)
        {
            Add(Stroke(x-5, y, x+5, y, HexA(178, "#ffffff"), 1.5, 1.0));
            Add(Stroke(x, y-5, x, y+5, HexA(178, "#ffffff"), 1.5, 1.0));
            Add(Stroke(x-4, y-4, x+4, y+4, HexA(115, "#ffffff"), 1.0, 1.0));
            Add(Stroke(x+4, y-4, x-4, y+4, HexA(115, "#ffffff"), 1.0, 1.0));
        }
    }

    private void DrawFog()
    {
        TintRect(HexA(35, "#6a7880"), 1.0);
        foreach (var (y, h, a) in new[] { (30.0,14.0,(byte)46), (52.0,12.0,(byte)36),
                                          (72.0,10.0,(byte)30), (90.0,10.0,(byte)25) })
            Add(Band(y, h, HexA(a, "#ffffff"), 1.0));
    }
}
