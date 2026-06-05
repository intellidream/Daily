using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using System;
using System.Threading.Tasks;
using Daily_WinUI.Services;

namespace Daily_WinUI.Controls;

[TemplatePart(Name = DirtOverlayPart, Type = typeof(Border))]
[TemplatePart(Name = WipeElementPart, Type = typeof(Border))]
[TemplatePart(Name = WipeTransformPart, Type = typeof(CompositeTransform))]
public sealed class GlassWidgetContainer : ContentControl
{
    private const string DirtOverlayPart = "DirtOverlay";
    private const string WipeElementPart = "WipeElement";
    private const string WipeTransformPart = "WipeTransform";

    private Border? _dirtOverlay;
    private Border? _wipeElement;
    private CompositeTransform? _wipeTransform;

    private DispatcherTimer _agingTimer;
    private DateTime _lastRefreshedTime;
    private static readonly double MaxDirtOpacity = 0.75;

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
        _wipeElement = GetTemplateChild(WipeElementPart) as Border;
        _wipeTransform = GetTemplateChild(WipeTransformPart) as CompositeTransform;

        LogToFile($"OnApplyTemplate called. DirtOverlay: {_dirtOverlay != null}, WipeElement: {_wipeElement != null}, WipeTransform: {_wipeTransform != null}");

        // Initialize state
        if (_dirtOverlay != null)
        {
            _dirtOverlay.Opacity = 0.0;
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

    private void AgingTimer_Tick(object? sender, object e)
    {
        if (_dirtOverlay == null)
        {
            LogToFile("Timer tick ignored: _dirtOverlay is null.");
            return;
        }

        var settings = SettingsService.Load();
        int durationSeconds = settings.WidgetAgingDurationSeconds;
        if (durationSeconds <= 0) durationSeconds = 30; // Fallback to 30s default

        var elapsed = DateTime.Now - _lastRefreshedTime;
        double ratio = Math.Min(1.0, elapsed.TotalSeconds / durationSeconds);

        // Apply a non-linear ease-in to the dirt accumulation so it starts slowly then speeds up
        double dirtiness = Math.Pow(ratio, 1.5);

        _dirtOverlay.Opacity = dirtiness * MaxDirtOpacity;

        LogToFile($"Timer tick. Elapsed: {elapsed.TotalSeconds:F1}s / {durationSeconds}s. Ratio: {ratio:F2}. Opacity: {_dirtOverlay.Opacity:F3}. Container Size: {ActualWidth}x{ActualHeight}. DirtOverlay Size: {_dirtOverlay.ActualWidth}x{_dirtOverlay.ActualHeight}");
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
        wipeFade.KeyFrames.Add(new LinearDoubleKeyFrame { Value = 1.0, KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(0.25)) });
        wipeFade.KeyFrames.Add(new LinearDoubleKeyFrame { Value = 1.0, KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(0.95)) });
        wipeFade.KeyFrames.Add(new LinearDoubleKeyFrame { Value = 0.0, KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(1.2)) });

        // Fade out the dirt layer over the sweep duration
        var dirtFade = new DoubleAnimation
        {
            To = 0.0,
            Duration = new Duration(TimeSpan.FromSeconds(1.0)),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(dirtFade, _dirtOverlay);
        Storyboard.SetTargetProperty(dirtFade, "Opacity");

        var sb = new Storyboard();
        sb.Children.Add(translateAnim);
        sb.Children.Add(wipeFade);
        sb.Children.Add(dirtFade);

        // When animation finishes, reset last refresh time to clear the dirt logic
        sb.Completed += (s, e) =>
        {
            _lastRefreshedTime = DateTime.Now;
            if (_dirtOverlay != null)
            {
                _dirtOverlay.Opacity = 0.0;
            }
        };

        sb.Begin();
    }
}
