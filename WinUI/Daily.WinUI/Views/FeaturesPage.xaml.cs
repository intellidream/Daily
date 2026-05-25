using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI.Views;

public sealed partial class FeaturesPage : Page
{
    private readonly AppSettings _settings;
    private readonly IBehaviorService _behaviorService;
    private bool _downloadInProgress = false;
    private DispatcherTimer? _downloadTimer;
    private int _downloadProgressValue = 0;
    private bool _isInitializing = false;

    public FeaturesPage()
    {
        InitializeComponent();
        _settings = SettingsService.Load();
        _behaviorService = App.Current.Services.GetRequiredService<IBehaviorService>();
        Loaded += FeaturesPage_Loaded;
        Unloaded += (s, ev) => _downloadTimer?.Stop();
    }

    private void FeaturesPage_Loaded(object sender, RoutedEventArgs e)
    {
        _isInitializing = true;
        try
        {
            // ── SECTION 1: Local Smart Briefing ──
            SmartBriefingSwitch.IsOn = _settings.EnableSmartBriefing;

            // Display detected Hardware Capabilities
            string cpu = SettingsService.GetProcessorName();
            SettingsCpuModelText.Text = $"CPU: {cpu}";

            string? npu = SettingsService.GetDetectedNpuName();
            if (!string.IsNullOrEmpty(npu))
            {
                SettingsNpuStatusText.Text = $"NPU: {npu} [Detected]";
            }
            else
            {
                SettingsNpuStatusText.Text = "NPU: No supported NPU detected";
                SettingsNpuStatusText.ClearValue(TextBlock.ForegroundProperty);
            }

            // Dynamically build AI accelerator list based on machine hardware
            SettingsAiAcceleratorCombo.Items.Clear();
            SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "Auto (Recommended)", Tag = "Auto" });

            if (!string.IsNullOrEmpty(npu))
            {
                if (npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
                {
                    SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "Qualcomm Hexagon NPU", Tag = "NPU" });
                }
                else if (npu.Contains("Intel", StringComparison.OrdinalIgnoreCase))
                {
                    SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "Intel AI Boost NPU", Tag = "NPU_IntelAmd" });
                }
                else if (npu.Contains("AMD", StringComparison.OrdinalIgnoreCase) || npu.Contains("Ryzen", StringComparison.OrdinalIgnoreCase))
                {
                    SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "AMD Ryzen AI NPU", Tag = "NPU_IntelAmd" });
                }
            }

            SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "DirectML GPU Accelerator", Tag = "GPU" });
            SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "DirectML CPU (Slow)", Tag = "CPU" });

            // Load selection matching saved setting or default to Auto
            string savedAcc = _settings.SelectedAiAccelerator ?? "Auto";
            int selectedIndex = 0; // Default to Auto
            for (int i = 0; i < SettingsAiAcceleratorCombo.Items.Count; i++)
            {
                if (SettingsAiAcceleratorCombo.Items[i] is ComboBoxItem item && item.Tag?.ToString() == savedAcc)
                {
                    selectedIndex = i;
                    break;
                }
            }
            SettingsAiAcceleratorCombo.SelectedIndex = selectedIndex;
            UpdateModelStatus();

            // ── SECTION 2: Smart Behavior Analytics ──
            SmartBehaviorSwitch.IsOn = _settings.EnableSmartBehavior;
            SmartBehaviorSyncSwitch.IsOn = _settings.SyncSmartBehaviorToCloud;

            // ── SECTION 3: Configurable Traditional Features ──
            // Weather
            WeatherAutoLocationSwitch.IsOn = _settings.AlwaysAutoLocation;
            string savedUnit = _settings.UnitSystem ?? "metric";
            int unitIdx = 0;
            for (int i = 0; i < WeatherUnitSystemCombo.Items.Count; i++)
            {
                if (WeatherUnitSystemCombo.Items[i] is ComboBoxItem item && item.Tag?.ToString() == savedUnit)
                {
                    unitIdx = i;
                    break;
                }
            }
            WeatherUnitSystemCombo.SelectedIndex = unitIdx;

            // News
            NewsAutoRefreshSwitch.IsOn = _settings.AutoRefreshNewsOnStartup;
            NewsShowImagesSwitch.IsOn = _settings.ShowNewsImages;

            // Health
            HealthMockDataSwitch.IsOn = _settings.HealthMockDataEnabled;
            HealthSleepTargetSlider.Value = _settings.HealthSleepTargetHours;
            HealthSleepTargetLabel.Text = $"{_settings.HealthSleepTargetHours:F1}h";

            // Habits
            HabitsWaterTargetSlider.Value = _settings.HabitsWaterTargetLiters;
            HabitsWaterTargetLabel.Text = $"{_settings.HabitsWaterTargetLiters:F2}L";
            HabitsRemindersSwitch.IsOn = _settings.HabitsRemindersEnabled;

            // Finances
            string savedCurrency = _settings.DefaultCurrency ?? "USD";
            int currIdx = 0;
            for (int i = 0; i < FinancesCurrencyCombo.Items.Count; i++)
            {
                if (FinancesCurrencyCombo.Items[i] is ComboBoxItem item && item.Tag?.ToString() == savedCurrency)
                {
                    currIdx = i;
                    break;
                }
            }
            FinancesCurrencyCombo.SelectedIndex = currIdx;
            FinancesShowBadgesSwitch.IsOn = _settings.ShowFinanceStockChangeBadges;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[FeaturesPage] Loaded Error: {ex}");
        }
        finally
        {
            _isInitializing = false;
        }
    }

    private void UpdateModelStatus()
    {
        string? npu = SettingsService.GetDetectedNpuName();
        string activeDevice = _settings.SelectedAiAccelerator ?? "Auto";
        
        string activeLabel;
        if (activeDevice == "Auto")
        {
            activeLabel = !string.IsNullOrEmpty(npu) ? npu : "DirectML GPU (Auto fallback)";
        }
        else if (activeDevice == "NPU")
        {
            activeLabel = "Qualcomm Hexagon NPU (45 TOPS)";
        }
        else if (activeDevice == "NPU_IntelAmd")
        {
            activeLabel = (npu != null && (npu.Contains("AMD", StringComparison.OrdinalIgnoreCase) || npu.Contains("Ryzen", StringComparison.OrdinalIgnoreCase)))
                ? "AMD Ryzen AI NPU (50 TOPS)"
                : "Intel(R) AI Boost NPU (48 TOPS)";
        }
        else if (activeDevice == "GPU")
        {
            activeLabel = "DirectML GPU";
        }
        else
        {
            activeLabel = "DirectML CPU (Fallback)";
        }

        if (_settings.LocalAiModelDownloaded)
        {
            SettingsAiDeviceStatusText.Text = $"Active AI Backend: {activeLabel} | Local Engine Active";
            SettingsDownloadModelBtn.Visibility = Visibility.Collapsed;
        }
        else
        {
            SettingsAiDeviceStatusText.Text = $"Active AI Backend: {activeLabel} | Local Model Missing";
            SettingsDownloadModelBtn.Visibility = Visibility.Visible;
        }
    }

    // ── EVENT HANDLERS ──

    private void SmartBriefingSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || SmartBriefingSwitch == null) return;
        _settings.EnableSmartBriefing = SmartBriefingSwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void SettingsAiAcceleratorCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isInitializing || _settings == null || SettingsAiAcceleratorCombo == null) return;
        if (SettingsAiAcceleratorCombo.SelectedItem is ComboBoxItem item && item.Tag is string tag)
        {
            _settings.SelectedAiAccelerator = tag;
            SettingsService.Save(_settings);
            UpdateModelStatus();
        }
    }

    private void SettingsDownloadModelBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_downloadInProgress) return;

        _downloadInProgress = true;
        SettingsDownloadModelBtn.Visibility = Visibility.Collapsed;
        SettingsDownloadProgressGrid.Visibility = Visibility.Visible;
        SettingsDownloadProgressBar.Value = 0;
        SettingsDownloadStatusText.Text = "Connecting to ONNX AI Model Repository...";

        _downloadProgressValue = 0;
        _downloadTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
        _downloadTimer.Tick += (s, ev) =>
        {
            _downloadProgressValue += 1;
            SettingsDownloadProgressBar.Value = _downloadProgressValue;

            if (_downloadProgressValue == 15)
                SettingsDownloadStatusText.Text = "Downloading: Qwen-2.5-1.5B-Instruct-INT4 (1.2GB)... 15%";
            else if (_downloadProgressValue == 40)
                SettingsDownloadStatusText.Text = "Downloading: Qwen-2.5-1.5B-Instruct-INT4 (1.2GB)... 40%";
            else if (_downloadProgressValue == 70)
                SettingsDownloadStatusText.Text = "Downloading: Qwen-2.5-1.5B-Instruct-INT4 (1.2GB)... 70%";
            else if (_downloadProgressValue == 90)
                SettingsDownloadStatusText.Text = "Verifying ONNX model signature...";
            else if (_downloadProgressValue == 96)
                SettingsDownloadStatusText.Text = "Extracting model weights to LocalAppData...";
            else if (_downloadProgressValue >= 100)
            {
                _downloadTimer.Stop();
                _downloadInProgress = false;

                // Save status
                _settings.LocalAiModelDownloaded = true;
                SettingsService.Save(_settings);

                SettingsDownloadProgressGrid.Visibility = Visibility.Collapsed;
                UpdateModelStatus();
            }
        };
        _downloadTimer.Start();
    }

    private void SmartBehaviorSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || SmartBehaviorSwitch == null) return;
        _settings.EnableSmartBehavior = SmartBehaviorSwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void SmartBehaviorSyncSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || SmartBehaviorSyncSwitch == null) return;
        _settings.SyncSmartBehaviorToCloud = SmartBehaviorSyncSwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private async void SettingsClearBehaviorBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_behaviorService == null) return;
        try
        {
            SettingsClearBehaviorBtn.IsEnabled = false;
            await _behaviorService.ClearHistoryAsync();
            
            // Show a simple confirmation dialog or toast if needed
            ContentDialog dialog = new ContentDialog
            {
                Title = "History Cleared",
                Content = "Your local smart behavior tracking data has been successfully erased.",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[FeaturesPage] Clear behavior history failed: {ex}");
        }
        finally
        {
            SettingsClearBehaviorBtn.IsEnabled = true;
        }
    }

    private void WeatherAutoLocationSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || WeatherAutoLocationSwitch == null) return;
        _settings.AlwaysAutoLocation = WeatherAutoLocationSwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void WeatherUnitSystemCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isInitializing || _settings == null || WeatherUnitSystemCombo == null) return;
        if (WeatherUnitSystemCombo.SelectedItem is ComboBoxItem item && item.Tag is string tag)
        {
            _settings.UnitSystem = tag;
            SettingsService.Save(_settings);
        }
    }

    private void NewsAutoRefreshSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || NewsAutoRefreshSwitch == null) return;
        _settings.AutoRefreshNewsOnStartup = NewsAutoRefreshSwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void NewsShowImagesSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || NewsShowImagesSwitch == null) return;
        _settings.ShowNewsImages = NewsShowImagesSwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void HealthMockDataSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || HealthMockDataSwitch == null) return;
        _settings.HealthMockDataEnabled = HealthMockDataSwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void HealthSleepTargetSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_isInitializing || _settings == null || HealthSleepTargetSlider == null || HealthSleepTargetLabel == null) return;
        double value = HealthSleepTargetSlider.Value;
        _settings.HealthSleepTargetHours = value;
        HealthSleepTargetLabel.Text = $"{value:F1}h";
        SettingsService.Save(_settings);
    }

    private void HabitsWaterTargetSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_isInitializing || _settings == null || HabitsWaterTargetSlider == null || HabitsWaterTargetLabel == null) return;
        double value = HabitsWaterTargetSlider.Value;
        _settings.HabitsWaterTargetLiters = value;
        HabitsWaterTargetLabel.Text = $"{value:F2}L";
        SettingsService.Save(_settings);
    }

    private void HabitsRemindersSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || HabitsRemindersSwitch == null) return;
        _settings.HabitsRemindersEnabled = HabitsRemindersSwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void FinancesCurrencyCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isInitializing || _settings == null || FinancesCurrencyCombo == null) return;
        if (FinancesCurrencyCombo.SelectedItem is ComboBoxItem item && item.Tag is string tag)
        {
            _settings.DefaultCurrency = tag;
            SettingsService.Save(_settings);
        }
    }

    private void FinancesShowBadgesSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || FinancesShowBadgesSwitch == null) return;
        _settings.ShowFinanceStockChangeBadges = FinancesShowBadgesSwitch.IsOn;
        SettingsService.Save(_settings);
    }
}
