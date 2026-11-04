using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily_WinUI.DesktopWidgets;
using Daily_WinUI.Services;

namespace Daily_WinUI.Views;

public sealed partial class AppearanceSettingsPage : Page
{
    private AppSettings _settings;

    public AppearanceSettingsPage()
    {
        InitializeComponent();
        _settings = SettingsService.Load();
        Loaded += AppearanceSettingsPage_Loaded;
        Unloaded += AppearanceSettingsPage_Unloaded;
    }

    private void AppearanceSettingsPage_Loaded(object sender, RoutedEventArgs e)
    {
        DesktopWidgetManager.Instance.StateChanged -= OnDesktopWidgetsStateChanged;
        DesktopWidgetManager.Instance.StateChanged += OnDesktopWidgetsStateChanged;
        SyncControlsFromState();
    }

    private void AppearanceSettingsPage_Unloaded(object sender, RoutedEventArgs e)
    {
        DesktopWidgetManager.Instance.StateChanged -= OnDesktopWidgetsStateChanged;
    }

    private void OnDesktopWidgetsStateChanged(object? sender, EventArgs e)
    {
        DispatcherQueue?.TryEnqueue(SyncControlsFromState);
    }

    private void SyncControlsFromState()
    {
        _settings = SettingsService.Load();

        CloseToTraySwitch.Toggled -= CloseToTraySwitch_Toggled;
        CloseToTraySwitch.IsOn = _settings.CloseToTray;
        CloseToTraySwitch.Toggled += CloseToTraySwitch_Toggled;

        bool widgetsOn = DesktopWidgetManager.Instance.AreWidgetsVisible || (_settings.DesktopWidgetsEnabled && DesktopWidgetManager.Instance.ActiveWidgets.Count > 0);
        DesktopWidgetsEnabledSwitch.Toggled -= DesktopWidgetsEnabledSwitch_Toggled;
        DesktopWidgetsEnabledSwitch.IsOn = widgetsOn;
        DesktopWidgetsEnabledSwitch.Toggled += DesktopWidgetsEnabledSwitch_Toggled;

        DesktopWidgetsLockedSwitch.Toggled -= DesktopWidgetsLockedSwitch_Toggled;
        DesktopWidgetsLockedSwitch.IsOn = _settings.DesktopWidgetsLocked;
        DesktopWidgetsLockedSwitch.Toggled += DesktopWidgetsLockedSwitch_Toggled;

        int count = DesktopWidgetManager.Instance.ActiveWidgets.Count;
        ActiveWidgetsCountText.Text = widgetsOn && count > 0
            ? $"{count} active desktop widget{(count == 1 ? "" : "s")} pinned on screen."
            : "Display floating telemetry widgets on the desktop layer.";
    }

    private void CloseToTraySwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_settings == null || CloseToTraySwitch == null) return;
        _settings.CloseToTray = CloseToTraySwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void DesktopWidgetsEnabledSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (DesktopWidgetsEnabledSwitch.IsOn)
        {
            DesktopWidgetManager.Instance.ShowAll();
        }
        else
        {
            DesktopWidgetManager.Instance.HideAll();
        }
        SyncControlsFromState();
    }

    private void DesktopWidgetsLockedSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        DesktopWidgetManager.Instance.SetAllLocked(DesktopWidgetsLockedSwitch.IsOn);
        SyncControlsFromState();
    }

    private void AddDesktopWidget_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem item && item.Tag is string tagStr &&
            Enum.TryParse<DesktopWidgetType>(tagStr, ignoreCase: true, out var widgetType))
        {
            var defaultSize = (widgetType == DesktopWidgetType.Bubbles ||
                               widgetType == DesktopWidgetType.Smokes ||
                               widgetType == DesktopWidgetType.Stress ||
                               widgetType == DesktopWidgetType.Cosmos)
                ? DesktopWidgetSize.Small
                : DesktopWidgetSize.Medium;

            DesktopWidgetManager.Instance.AddWidget(widgetType, defaultSize, 100, 100);
            SyncControlsFromState();
        }
    }

    private void RefreshDesktopWidgetsButton_Click(object sender, RoutedEventArgs e)
    {
        DesktopWidgetManager.Instance.RefreshAllWidgets();
    }

    private void ResetDesktopWidgetsButton_Click(object sender, RoutedEventArgs e)
    {
        DesktopWidgetManager.Instance.ResetToDefaults();
        SyncControlsFromState();
    }

    private void ToggleThemeButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.Current.MainWindow is MainWindow mw)
        {
            mw.TitleBarTheme_Click(sender, e);
        }
    }
}
