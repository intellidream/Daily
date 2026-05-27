using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Windows.AI;
using Microsoft.Windows.AI.Text;

namespace Daily_WinUI.Views;

public sealed partial class FeaturesPage : Page
{
    private readonly AppSettings _settings;
    private readonly IBehaviorService _behaviorService;
    private bool _isInitializing = false;

    public FeaturesPage()
    {
        InitializeComponent();
        _settings = SettingsService.Load();
        _behaviorService = App.Current.Services.GetRequiredService<IBehaviorService>();
        Loaded += FeaturesPage_Loaded;
        Unloaded += FeaturesPage_Unloaded;
    }

    private void FeaturesPage_Loaded(object sender, RoutedEventArgs e)
    {
        _isInitializing = true;
        try
        {
            var downloadManager = App.Current.Services.GetRequiredService<ModelDownloadManager>();
            downloadManager.ProgressChanged += DownloadManager_ProgressChanged;
            downloadManager.StatusChanged += DownloadManager_StatusChanged;
            downloadManager.DownloadCompleted += DownloadManager_DownloadCompleted;
            downloadManager.DownloadFailed += DownloadManager_DownloadFailed;

            if (downloadManager.IsDownloading)
            {
                SettingsDownloadModelBtn.Visibility = Visibility.Collapsed;
                SettingsDownloadProgressGrid.Visibility = Visibility.Visible;
                if (downloadManager.LastProgress != null)
                {
                    DownloadManager_ProgressChanged(downloadManager, downloadManager.LastProgress);
                }
                else
                {
                    SettingsDownloadStatusText.Text = downloadManager.StatusText;
                    SettingsDownloadProgressBar.Value = downloadManager.Percentage;
                }
            }
            else
            {
                SettingsDownloadProgressGrid.Visibility = Visibility.Collapsed;
            }

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
            SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "Fallback Template Engine", Tag = "Fallback" });

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
        
        bool phiSilicaAvailable = false;
        try
        {
            phiSilicaAvailable = LanguageModel.GetReadyState() == AIFeatureReadyState.Ready;
        }
        catch { }

        bool onnxModelReady = false;
        bool cpuFallbackActive = false;
        try
        {
            var onnxService = App.Current.Services.GetRequiredService<OnnxGenAiSmartService>();
            onnxModelReady = Task.Run(async () => await onnxService.IsModelReadyAsync()).GetAwaiter().GetResult();
            cpuFallbackActive = onnxService.IsUsingCpuFallback;
        }
        catch { }

        // Automatically correct settings state based on actual files on disk
        if (_settings.LocalAiModelDownloaded != onnxModelReady)
        {
            _settings.LocalAiModelDownloaded = onnxModelReady;
            SettingsService.Save(_settings);
        }

        // Determine the best hardware engine for the current machine
        string bestEngineName;
        string bestEngineTag;
        bool bestEngineReady;

        if (phiSilicaAvailable && !string.IsNullOrEmpty(npu) && npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
        {
            bestEngineName = "Qualcomm Hexagon NPU";
            bestEngineTag = "NPU";
            bestEngineReady = true;
        }
        else
        {
            // For x64 systems, DirectML GPU is the recommended, most stable, and high-performance target.
            bestEngineName = "DirectML GPU Accelerator";
            bestEngineTag = "GPU";
            bestEngineReady = onnxModelReady;
        }

        string recommendedOption = bestEngineName;
        string activeLabel;
        string description = "";
        bool needsDownload = false;

        if (cpuFallbackActive)
        {
            activeLabel = "DirectML CPU (Llama 3.2 ONNX) (Safe Fallback)";
            description = "The system encountered a graphics card driver error or compatibility issue and automatically fell back to CPU mode for stability. You can restart the application or choose a different accelerator to try again.";
        }
        else if (activeDevice == "Auto")
        {
            if (bestEngineReady)
            {
                if (bestEngineTag == "NPU")
                {
                    activeLabel = $"Auto -> {bestEngineName} (Phi Silica) (Active)";
                    description = $"System automatically resolved execution to the built-in Microsoft Copilot Runtime (Phi Silica) utilizing the NPU. Recommendation: {bestEngineName}.";
                }
                else
                {
                    activeLabel = $"Auto -> {bestEngineName} (Llama 3.2 ONNX) (Active)";
                    description = $"System automatically resolved execution to the custom Llama 3.2 1B ONNX model running on the {bestEngineName}.";
                }
                needsDownload = false;
            }
            else
            {
                activeLabel = $"Auto -> {bestEngineName} (Llama 3.2 ONNX) (Requires Download)";
                description = $"No local AI engine is currently ready. System resolved target to the {bestEngineName}. The local model files must be downloaded first.";
                needsDownload = true;
            }
        }
        else if (activeDevice == "NPU")
        {
            activeLabel = "Qualcomm Hexagon NPU (Phi Silica)";
            description = "Uses the built-in Microsoft Copilot Runtime (Phi Silica 3.3B) accelerated by the Qualcomm NPU. Zero download required.";
            if (!phiSilicaAvailable)
            {
                description += " WARNING: Phi Silica is NOT ready or supported on this system. Falling back to template.";
            }
        }
        else if (activeDevice == "NPU_IntelAmd")
        {
            string npuName = (npu != null && (npu.Contains("AMD", StringComparison.OrdinalIgnoreCase) || npu.Contains("Ryzen", StringComparison.OrdinalIgnoreCase)))
                ? "AMD Ryzen AI NPU"
                : "Intel(R) AI Boost NPU";
            activeLabel = $"{npuName} (Llama 3.2 ONNX)";
            description = $"Uses the custom Llama 3.2 1B model running locally on the {npuName} via ONNX Runtime GenAI.";
            if (!onnxModelReady)
            {
                description += " (Requires Model Download)";
                needsDownload = true;
            }
        }
        else if (activeDevice == "GPU")
        {
            activeLabel = "DirectML GPU (Llama 3.2 ONNX)";
            description = "Uses the custom Llama 3.2 1B model running locally via DirectML on your graphics card. Offers excellent generation speed.";
            if (!onnxModelReady)
            {
                description += " (Requires Model Download)";
                needsDownload = true;
            }
        }
        else if (activeDevice == "CPU")
        {
            activeLabel = "DirectML CPU (Llama 3.2 ONNX)";
            description = "Uses the custom Llama 3.2 1B model running locally on your processor. Note: CPU generation will be slower and use more battery.";
            if (!onnxModelReady)
            {
                description += " (Requires Model Download)";
                needsDownload = true;
            }
        }
        else // Fallback
        {
            activeLabel = "Fallback Template Engine";
            description = "Uses procedural templates to generate daily briefings. No local AI model execution is performed.";
            needsDownload = false;
        }

        SettingsAiDeviceStatusText.Text = $"Active Engine: {activeLabel}";
        SettingsAiAcceleratorDescriptionText.Text = description;

        if (needsDownload)
        {
            SettingsDownloadModelBtn.Visibility = Visibility.Visible;
        }
        else
        {
            SettingsDownloadModelBtn.Visibility = Visibility.Collapsed;
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

    private void SettingsCancelDownloadBtn_Click(object sender, RoutedEventArgs e)
    {
        var downloadManager = App.Current.Services.GetRequiredService<ModelDownloadManager>();
        downloadManager.CancelDownload();
    }

    private void SettingsDownloadModelBtn_Click(object sender, RoutedEventArgs e)
    {
        var downloadManager = App.Current.Services.GetRequiredService<ModelDownloadManager>();
        if (downloadManager.IsDownloading) return;

        SettingsDownloadModelBtn.Visibility = Visibility.Collapsed;
        SettingsDownloadProgressGrid.Visibility = Visibility.Visible;
        SettingsDownloadProgressBar.Value = 0;
        SettingsDownloadStatusText.Text = "Connecting to ONNX AI Model Repository...";

        downloadManager.StartDownload();
    }

    private void FeaturesPage_Unloaded(object sender, RoutedEventArgs e)
    {
        try
        {
            var downloadManager = App.Current.Services.GetRequiredService<ModelDownloadManager>();
            downloadManager.ProgressChanged -= DownloadManager_ProgressChanged;
            downloadManager.StatusChanged -= DownloadManager_StatusChanged;
            downloadManager.DownloadCompleted -= DownloadManager_DownloadCompleted;
            downloadManager.DownloadFailed -= DownloadManager_DownloadFailed;
        }
        catch { }
    }

    private void DownloadManager_ProgressChanged(object? sender, DownloadProgressEventArgs args)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            SettingsDownloadProgressBar.Value = args.Percentage;
            SettingsDownloadStatusText.Text = $"Downloading: {args.CurrentFileName} ({args.DownloadedMBs:F1}/{args.TotalMBs:F1} MB) | Speed: {args.SpeedMBs:F2} MB/s | Remaining: {args.TimeRemaining:mm\\:ss}";
        });
    }

    private void DownloadManager_StatusChanged(object? sender, string status)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            SettingsDownloadStatusText.Text = status;
        });
    }

    private void DownloadManager_DownloadCompleted(object? sender, EventArgs e)
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            SettingsDownloadProgressGrid.Visibility = Visibility.Collapsed;
            UpdateModelStatus();

            ContentDialog dialog = new ContentDialog
            {
                Title = "Model Download Complete",
                Content = "The local Llama 3.2 1B ONNX model has been successfully downloaded and verified. Local AI accelerator is now active.",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            try { await dialog.ShowAsync(); } catch { }
        });
    }

    private void DownloadManager_DownloadFailed(object? sender, Exception ex)
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            SettingsDownloadProgressGrid.Visibility = Visibility.Collapsed;
            UpdateModelStatus();

            if (ex is OperationCanceledException)
            {
                SettingsDownloadStatusText.Text = "Download canceled by user.";
            }
            else
            {
                ContentDialog dialog = new ContentDialog
                {
                    Title = "Download Failed",
                    Content = $"An error occurred while downloading the model: {ex.Message}",
                    CloseButtonText = "OK",
                    XamlRoot = this.XamlRoot
                };
                try { await dialog.ShowAsync(); } catch { }
            }
        });
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
