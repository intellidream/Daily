using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Composition;
using System;
using System.Threading.Tasks;
using Daily_WinUI.Services;

namespace Daily_WinUI.Controls;

[TemplatePart(Name = DirtOverlayPart, Type = typeof(Border))]
[TemplatePart(Name = NoiseOverlayPart, Type = typeof(Border))]
[TemplatePart(Name = WipeElementPart, Type = typeof(Border))]
[TemplatePart(Name = WipeTransformPart, Type = typeof(CompositeTransform))]
public sealed class GlassWidgetContainer : ContentControl
{
    private const string DirtOverlayPart = "DirtOverlay";
    private const string NoiseOverlayPart = "NoiseOverlay";
    private const string WipeElementPart = "WipeElement";
    private const string WipeTransformPart = "WipeTransform";

    private Border? _dirtOverlay;
    private Border? _noiseOverlay;
    private Border? _wipeElement;
    private CompositeTransform? _wipeTransform;

    private DispatcherTimer _agingTimer;
    private DateTime _lastRefreshedTime;
    private int _dirtIndex;
    private static readonly double MaxDirtOpacity = 0.75;
    private static readonly double MaxNoiseOpacity = 0.55;

    private static void LogToFile(string message)
    {
        try
        {
            var dir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Daily.WinUI");
            System.IO.Directory.CreateDirectory(dir);
            var path = System.IO.Path.Combine(dir, "debug_glass.log");
            System.IO.File.AppendAllText(path, $"[{DateTime.Now:HH:mm:ss.fff}] {message}{Environment.NewLine}");
        }
        catch { }
    }

    public GlassWidgetContainer()
    {
        LogToFile("Constructor starting.");
        _dirtIndex = Random.Shared.Next(1, 5);
        this.ActualThemeChanged += (s, e) => UpdateDirtBrush();
        this.SizeChanged += (s, e) =>
        {
            bool wasLarge = e.PreviousSize.Width > 320 || e.PreviousSize.Height > 240;
            bool isLarge = e.NewSize.Width > 320 || e.NewSize.Height > 240;
            if (wasLarge != isLarge || e.PreviousSize.Width == 0)
            {
                UpdateDirtBrush();
            }
        };

        // Explicitly resolve and apply the style from global resources to ensure 
        // the ControlTemplate is applied even outside Themes/Generic.xaml search paths.
        bool styleFound = false;
        if (Application.Current.Resources.TryGetValue("GlassWidgetContainerStyle", out var styleObj) && styleObj is Style styleByName)
        {
            this.Style = styleByName;
            styleFound = true;
            LogToFile("Style resolved by name key: GlassWidgetContainerStyle");
        }
        else if (Application.Current.Resources.TryGetValue(typeof(GlassWidgetContainer), out var styleObjType) && styleObjType is Style styleByType)
        {
            this.Style = styleByType;
            styleFound = true;
            LogToFile("Style resolved by Type key.");
        }

        if (!styleFound)
        {
            LogToFile("WARNING: Style was NOT found in Application.Current.Resources!");
        }

        _lastRefreshedTime = DateTime.Now;

        // Hook up the aging timer
        _agingTimer = new DispatcherTimer();
        _agingTimer.Interval = TimeSpan.FromSeconds(1); // Check every second for smooth updates
        _agingTimer.Tick += AgingTimer_Tick;
        _agingTimer.Start();
        LogToFile("Aging timer started.");
    }

    protected override void OnApplyTemplate()
    {
        base.OnApplyTemplate();
        _dirtOverlay = GetTemplateChild(DirtOverlayPart) as Border;
        _noiseOverlay = GetTemplateChild(NoiseOverlayPart) as Border;
        _wipeElement = GetTemplateChild(WipeElementPart) as Border;
        _wipeTransform = GetTemplateChild(WipeTransformPart) as CompositeTransform;

        LogToFile($"OnApplyTemplate called. DirtOverlay: {_dirtOverlay != null}, NoiseOverlay: {_noiseOverlay != null}, WipeElement: {_wipeElement != null}, WipeTransform: {_wipeTransform != null}");

        // Initialize state
        if (_dirtOverlay != null)
        {
            _dirtOverlay.Opacity = 0.0;
            UpdateDirtBrush();
        }
        if (_noiseOverlay != null)
        {
            _noiseOverlay.Opacity = 0.0;
        }
        if (_wipeElement != null)
        {
            _wipeElement.Opacity = 0.0;
        }
        if (_wipeTransform != null)
        {
            _wipeTransform.TranslateX = -250;
        }
    }

    private void UpdateDirtBrush()
    {
        if (_dirtOverlay == null)
        {
            LogToFile("UpdateDirtBrush skipped: _dirtOverlay is null.");
            return;
        }

        string themeStr = this.ActualTheme == ElementTheme.Light ? "light" : "dark";
        bool isLarge = ActualWidth > 320 || ActualHeight > 240;
        string largeStr = isLarge ? "_large" : "";
        string uriStr = $"ms-appx:///Assets/glass_smudges_{themeStr}{largeStr}_{_dirtIndex}.svg";

        try
        {
            var source = new SvgImageSource(new Uri(uriStr))
            {
                RasterizePixelWidth = isLarge ? 800 : 500,
                RasterizePixelHeight = isLarge ? 600 : 400
            };
            var brush = new ImageBrush
            {
                ImageSource = source,
                Stretch = Stretch.Fill
            };
            _dirtOverlay.Background = brush;
            LogToFile($"UpdateDirtBrush: theme={themeStr}, index={_dirtIndex}, isLarge={isLarge}, uri={uriStr}");
        }
        catch (Exception ex)
        {
            LogToFile($"ERROR updating dirt brush: {ex.Message}");
        }
    }

    private void AgingTimer_Tick(object? sender, object e)
    {
        if (_dirtOverlay == null)
        {
            LogToFile("Timer tick ignored: _dirtOverlay is null.");
            return;
        }

        var settings = SettingsService.Load();
        if (!settings.WidgetAgingEnabled)
        {
            _dirtOverlay.Opacity = 0.0;
            if (_noiseOverlay != null)
            {
                _noiseOverlay.Opacity = 0.0;
            }
            return;
        }

        int durationSeconds = settings.WidgetAgingDurationSeconds;
        if (durationSeconds <= 0) durationSeconds = 30; // Fallback to 30s default
        double grainIntensity = settings.WidgetAgingGrainIntensity;

        var elapsed = DateTime.Now - _lastRefreshedTime;
        double ratio = Math.Min(1.0, elapsed.TotalSeconds / durationSeconds);

        // Apply a non-linear ease-in to the dirt accumulation so it starts slowly then speeds up
        double dirtiness = Math.Pow(ratio, 1.5);

        _dirtOverlay.Opacity = dirtiness * MaxDirtOpacity;

        if (_noiseOverlay != null)
        {
            _noiseOverlay.Opacity = dirtiness * MaxNoiseOpacity * (grainIntensity / 100.0);
        }

        LogToFile($"Timer tick. Elapsed: {elapsed.TotalSeconds:F1}s / {durationSeconds}s. Ratio: {ratio:F2}. Opacity: {_dirtOverlay.Opacity:F3}. GrainOpacity: {_noiseOverlay?.Opacity ?? 0.0:F3}. Container Size: {ActualWidth}x{ActualHeight}. DirtOverlay Size: {_dirtOverlay.ActualWidth}x{_dirtOverlay.ActualHeight}");
    }

    public async void RefreshWithAnimation(Func<Task> refreshAction)
    {
        // 1. Start clean/wipe visual sequence
        StartWipeAnimation();

        // 2. Perform actual refresh task
        try
        {
            await refreshAction();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[GlassWidgetContainer] Refresh failed: {ex}");
        }
    }

    private static float SolveCubicEaseInOut(double targetY)
    {
        double low = 0.0;
        double high = 1.0;
        for (int i = 0; i < 20; i++)
        {
            double mid = (low + high) / 2.0;
            double y = mid < 0.5 ? 4.0 * mid * mid * mid : 1.0 - 4.0 * Math.Pow(1.0 - mid, 3);
            if (y < targetY)
                low = mid;
            else
                high = mid;
        }
        return (float)((low + high) / 2.0);
    }

    private static double CubicEaseInOut(double t)
    {
        return t < 0.5 ? 4.0 * t * t * t : 1.0 - 4.0 * Math.Pow(1.0 - t, 3);
    }

    private void StartWipeAnimation()
    {
        double width = ActualWidth;
        if (width <= 0) width = 450; // Dynamic fallback

        if (_wipeTransform == null || _wipeElement == null || _dirtOverlay == null)
        {
            // If template isn't applied yet, just reset timer
            _lastRefreshedTime = DateTime.Now;
            return;
        }

        // Setup TranslateX animation for squeegee glide (sweeping diagonal glare)
        var translateAnim = new DoubleAnimation
        {
            From = -250,
            To = width + 250,
            Duration = new Duration(TimeSpan.FromSeconds(1.2)),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        Storyboard.SetTarget(translateAnim, _wipeTransform);
        Storyboard.SetTargetProperty(translateAnim, "TranslateX");

        // Setup WipeElement fade (in at beginning, out at end of sweep) using KeyFrames
        var wipeFade = new DoubleAnimationUsingKeyFrames();
        Storyboard.SetTarget(wipeFade, _wipeElement);
        Storyboard.SetTargetProperty(wipeFade, "Opacity");
        wipeFade.KeyFrames.Add(new LinearDoubleKeyFrame { Value = 0.0, KeyTime = KeyTime.FromTimeSpan(TimeSpan.Zero) });
        wipeFade.KeyFrames.Add(new LinearDoubleKeyFrame { Value = 0.45, KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(0.25)) });
        wipeFade.KeyFrames.Add(new LinearDoubleKeyFrame { Value = 0.45, KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(0.95)) });
        wipeFade.KeyFrames.Add(new LinearDoubleKeyFrame { Value = 0.0, KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(1.2)) });

        var sb = new Storyboard();
        sb.Children.Add(translateAnim);
        sb.Children.Add(wipeFade);

        // Retrieve Composition Visuals for the overlays and apply InsetClip to them
        Visual? dirtVisual = ElementCompositionPreview.GetElementVisual(_dirtOverlay);
        Visual? noiseVisual = _noiseOverlay != null ? ElementCompositionPreview.GetElementVisual(_noiseOverlay) : null;

        InsetClip? dirtClip = null;
        InsetClip? noiseClip = null;

        if (dirtVisual != null)
        {
            var compositor = dirtVisual.Compositor;
            dirtClip = compositor.CreateInsetClip();
            dirtClip.LeftInset = 0.0f;
            dirtVisual.Clip = dirtClip;
        }

        if (noiseVisual != null)
        {
            var compositor = noiseVisual.Compositor;
            noiseClip = compositor.CreateInsetClip();
            noiseClip.LeftInset = 0.0f;
            noiseVisual.Clip = noiseClip;
        }

        if (dirtClip != null || noiseClip != null)
        {
            var compositor = (dirtVisual ?? noiseVisual)!.Compositor;
            double totalDistance = width + 500.0;
            var linearEase = compositor.CreateLinearEasingFunction();
            var clipAnim = compositor.CreateScalarKeyFrameAnimation();
            clipAnim.Duration = TimeSpan.FromSeconds(1.2);

            for (int i = 0; i <= 20; i++)
            {
                float t = i / 20.0f;
                double eased = CubicEaseInOut(t);
                double posX = -250.0 + eased * totalDistance;
                double clampedX = Math.Clamp(posX, 0.0, width);
                clipAnim.InsertKeyFrame(t, (float)clampedX, linearEase);
            }

            if (dirtClip != null)
            {
                dirtClip.StartAnimation("LeftInset", clipAnim);
            }
            if (noiseClip != null)
            {
                noiseClip.StartAnimation("LeftInset", clipAnim);
            }
        }

        // When animation finishes, reset last refresh time to clear the dirt logic
        sb.Completed += (s, e) =>
        {
            _lastRefreshedTime = DateTime.Now;
            if (_dirtOverlay != null)
            {
                _dirtOverlay.Opacity = 0.0;
            }
            if (_noiseOverlay != null)
            {
                _noiseOverlay.Opacity = 0.0;
            }

            // Remove the clips so that the overlays are fully visible when the widget ages again
            if (dirtVisual != null)
            {
                dirtVisual.Clip = null;
            }
            if (noiseVisual != null)
            {
                noiseVisual.Clip = null;
            }

            sb.Stop();
        };

        sb.Begin();
    }
}
