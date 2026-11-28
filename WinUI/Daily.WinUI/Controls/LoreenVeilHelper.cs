using System;
using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI;
using Windows.UI.Text;

namespace Daily_WinUI.Controls;

public static class LoreenVeilHelper
{
    public static readonly FontFamily LoreenFont = new("ms-appx:///Assets/Fonts/Loreen-Regular.ttf#Loreen");
    public static readonly FontFamily LatinFont = new("Segoe UI Variable Text");

    public static void ApplyVeil(TextBlock textBlock, bool isVeiled, FontFamily? latinFallback = null)
    {
        textBlock.FontFamily = isVeiled ? LoreenFont : (latinFallback ?? LatinFont);
        textBlock.CharacterSpacing = isVeiled ? 60 : 0;
    }

    public static void ApplyVeil(TextBox textBox, bool isVeiled, FontFamily? latinFallback = null)
    {
        textBox.FontFamily = isVeiled ? LoreenFont : (latinFallback ?? LatinFont);
    }
}

/// <summary>
/// Reusable TextBlock wrapper that performs a lightweight 440ms GPU-composed
/// "Movie Password Decrypt" sparkle &amp; micro-dot sweep on Loreen &lt;-&gt; Latin transitions,
/// with zero overlay overhead at rest.
/// </summary>
public sealed class LoreenVeilTextBlock : Grid
{
    private readonly TextBlock _textBlock;
    private readonly Canvas _sparkleOverlay;
    private readonly Stopwatch _animWatch = new();
    private bool _isVeiled;
    private bool _fontSwappedForCycle;
    private bool _hasRenderedOnce;
    private bool _isAnimating;
    private FontFamily _latinFont = LoreenVeilHelper.LatinFont;

    public LoreenVeilTextBlock()
    {
        _textBlock = new TextBlock
        {
            FontFamily = _latinFont,
            VerticalAlignment = VerticalAlignment.Center
        };
        _sparkleOverlay = new Canvas
        {
            IsHitTestVisible = false
        };
        Children.Add(_textBlock);
        Children.Add(_sparkleOverlay);
        SizeChanged += (_, e) =>
        {
            _sparkleOverlay.Clip = new RectangleGeometry
            {
                Rect = new Rect(0, 0, Math.Max(0, e.NewSize.Width), Math.Max(0, e.NewSize.Height))
            };
        };
        Unloaded += (_, __) => StopSparkleAnimation();
    }

    public string Text
    {
        get => _textBlock.Text;
        set => _textBlock.Text = value ?? string.Empty;
    }

    public bool IsVeiled
    {
        get => _isVeiled;
        set => SetVeiled(value, animate: true);
    }

    public void SetVeiled(bool value, bool animate)
    {
        if (_hasRenderedOnce && _isVeiled == value) return;
        bool wasFirst = !_hasRenderedOnce;
        _hasRenderedOnce = true;
        _isVeiled = value;

        if (!animate || wasFirst)
        {
            StopSparkleAnimation();
            LoreenVeilHelper.ApplyVeil(_textBlock, value, _latinFont);
            return;
        }

        _fontSwappedForCycle = false;
        _animWatch.Restart();
        if (!_isAnimating)
        {
            _isAnimating = true;
            CompositionTarget.Rendering += OnCompositionRendering;
        }
    }

    public FontFamily LatinFontFamily
    {
        get => _latinFont;
        set
        {
            _latinFont = value ?? LoreenVeilHelper.LatinFont;
            if (!_isVeiled) _textBlock.FontFamily = _latinFont;
        }
    }

    public double FontSize
    {
        get => _textBlock.FontSize;
        set => _textBlock.FontSize = value;
    }

    public FontWeight FontWeight
    {
        get => _textBlock.FontWeight;
        set => _textBlock.FontWeight = value;
    }

    public Brush Foreground
    {
        get => _textBlock.Foreground;
        set => _textBlock.Foreground = value;
    }

    public TextWrapping TextWrapping
    {
        get => _textBlock.TextWrapping;
        set => _textBlock.TextWrapping = value;
    }

    public TextTrimming TextTrimming
    {
        get => _textBlock.TextTrimming;
        set => _textBlock.TextTrimming = value;
    }

    public int MaxLines
    {
        get => _textBlock.MaxLines;
        set => _textBlock.MaxLines = value;
    }

    public TextDecorations TextDecorations
    {
        get => _textBlock.TextDecorations;
        set => _textBlock.TextDecorations = value;
    }

    private void OnCompositionRendering(object? sender, object e)
    {
        const double durationMs = 440.0;
        double t = _animWatch.Elapsed.TotalMilliseconds / durationMs;

        if (!_fontSwappedForCycle && t >= 0.45)
        {
            _fontSwappedForCycle = true;
            LoreenVeilHelper.ApplyVeil(_textBlock, _isVeiled, _latinFont);
        }

        if (t >= 1.0)
        {
            LoreenVeilHelper.ApplyVeil(_textBlock, _isVeiled, _latinFont);
            StopSparkleAnimation();
            return;
        }

        DrawSparkles((float)t);
    }

    private void DrawSparkles(float progress)
    {
        _sparkleOverlay.Children.Clear();
        double w = ActualWidth > 4 ? ActualWidth : 120;
        double h = ActualHeight > 4 ? ActualHeight : 20;
        int particleCount = Math.Clamp(_textBlock.Text.Length * 2, 10, 26);

        var accent = _isVeiled
            ? Color.FromArgb(0xFF, 0xAF, 0x52, 0xDE)
            : Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF);

        for (int i = 0; i < particleCount; i++)
        {
            float h1 = Hash01(i * 19 + 3);
            float h2 = Hash01(i * 31 + 11);
            float h3 = Hash01(i * 47 + 7);
            float startT = h1 * 0.56f;
            float localT = (progress - startT) / 0.44f;
            if (localT <= 0f || localT >= 1f) continue;

            float twinkle = MathF.Sin(localT * MathF.PI);
            byte alpha = (byte)Math.Clamp(twinkle * 235f, 0f, 255f);
            var fill = new SolidColorBrush(Color.FromArgb(alpha, accent.R, accent.G, accent.B));

            double px = h1 * w;
            double py = (0.15 + 0.70 * h2) * h - twinkle * 4.5;

            if (i % 3 == 0)
            {
                double r = (2.8 + 2.8 * h3) * twinkle;
                double inner = r * 0.28;
                var star = new Polygon { Fill = fill };
                star.Points.Add(new Point(px, py - r));
                star.Points.Add(new Point(px + inner, py - inner));
                star.Points.Add(new Point(px + r, py));
                star.Points.Add(new Point(px + inner, py + inner));
                star.Points.Add(new Point(px, py + r));
                star.Points.Add(new Point(px - inner, py + inner));
                star.Points.Add(new Point(px - r, py));
                star.Points.Add(new Point(px - inner, py - inner));
                _sparkleOverlay.Children.Add(star);
            }
            else
            {
                double d = (3.2 + 2.6 * h3) * twinkle;
                var dot = new Ellipse { Width = d, Height = d, Fill = fill };
                Canvas.SetLeft(dot, px - d * 0.5);
                Canvas.SetTop(dot, py - d * 0.5);
                _sparkleOverlay.Children.Add(dot);
            }
        }
    }

    private void StopSparkleAnimation()
    {
        if (_isAnimating)
        {
            _isAnimating = false;
            CompositionTarget.Rendering -= OnCompositionRendering;
        }
        _sparkleOverlay.Children.Clear();
    }

    private static float Hash01(int seed)
    {
        unchecked
        {
            ulong x = (ulong)(uint)seed * 0x9E3779B97F4A7C15UL;
            x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9UL;
            x = (x ^ (x >> 27)) * 0x94D049BB133111EBUL;
            x ^= x >> 31;
            return (x & 0xFFFFUL) / 65535f;
        }
    }
}
