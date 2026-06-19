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
    private readonly Daily.Services.IRssFeedService _rssService;
    private readonly System.Collections.ObjectModel.ObservableCollection<SubscriptionItemViewModel> _feedsList = new();
    private bool _isInitializing = false;
    private bool _isUpdatingFeedsList = false;
    private System.Threading.CancellationTokenSource? _reorderDts;

    private static readonly int[] AgingIntervals = { 10, 30, 60, 120, 300, 600, 1800, 3600, 7200, 10800 };
    private static readonly string[] AgingLabels = { "10s", "30s", "1m", "2m", "5m", "10m", "30m", "1h", "2h", "3h" };

    public FeaturesPage()
    {
        InitializeComponent();
        _settings = SettingsService.Load();
        _behaviorService = App.Current.Services.GetRequiredService<IBehaviorService>();
        _rssService = App.Current.Services.GetRequiredService<Daily.Services.IRssFeedService>();
        _rssService.OnFeedChanged += RssService_OnFeedChanged;
        _feedsList.CollectionChanged += FeedsList_CollectionChanged;
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
                    SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "Intel AI Boost NPU (Unsupported)", Tag = "NPU_IntelAmd", IsEnabled = false });
                }
                else if (npu.Contains("AMD", StringComparison.OrdinalIgnoreCase) || npu.Contains("Ryzen", StringComparison.OrdinalIgnoreCase))
                {
                    SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "AMD Ryzen AI NPU (Unsupported)", Tag = "NPU_IntelAmd", IsEnabled = false });
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
            UseInternalAiCheckBox.IsChecked = _settings.UseWindowsInternalAi;
            
            UpdateModelStatus();
            UpdateModelListUi();

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

            // Widget Glass Aging Settings
            WidgetAgingSwitch.IsOn = _settings.WidgetAgingEnabled;
            WidgetAgingSlider.IsEnabled = _settings.WidgetAgingEnabled;
            WidgetGrainIntensitySlider.IsEnabled = _settings.WidgetAgingEnabled;

            int closestIdx = 0;
            int minDiff = int.MaxValue;
            for (int i = 0; i < AgingIntervals.Length; i++)
            {
                int diff = Math.Abs(_settings.WidgetAgingDurationSeconds - AgingIntervals[i]);
                if (diff < minDiff)
                {
                    minDiff = diff;
                    closestIdx = i;
                }
            }
            WidgetAgingSlider.Value = closestIdx;
            WidgetAgingLabel.Text = AgingLabels[closestIdx];

            WidgetGrainIntensitySlider.Value = _settings.WidgetAgingGrainIntensity;
            WidgetGrainIntensityLabel.Text = $"{_settings.WidgetAgingGrainIntensity:F0}%";

            // Load Subscribed Feeds list
            _ = LoadFeedsListAsync();
            UpdateMediumUi();
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
        bool phiSilicaSupported = false;
        if (!string.IsNullOrEmpty(npu) && npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var state = LanguageModel.GetReadyState();
                phiSilicaAvailable = state == AIFeatureReadyState.Ready;
                phiSilicaSupported = state == AIFeatureReadyState.Ready || state == AIFeatureReadyState.NotReady;
            }
            catch { }
        }

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

        // Configure checkbox visibility and state based on platform compatibility
        if (phiSilicaSupported)
        {
            UseInternalAiCheckBox.Visibility = Visibility.Visible;
            bool savedIsInitializing = _isInitializing;
            _isInitializing = true;
            try
            {
                if (activeDevice == "Auto" || activeDevice == "NPU")
                {
                    UseInternalAiCheckBox.IsEnabled = true;
                    UseInternalAiCheckBox.IsChecked = _settings.UseWindowsInternalAi;
                }
                else
                {
                    UseInternalAiCheckBox.IsEnabled = false;
                    UseInternalAiCheckBox.IsChecked = false;
                }
            }
            finally
            {
                _isInitializing = savedIsInitializing;
            }
        }
        else
        {
            UseInternalAiCheckBox.Visibility = Visibility.Collapsed;
            bool savedIsInitializing = _isInitializing;
            _isInitializing = true;
            try
            {
                UseInternalAiCheckBox.IsEnabled = false;
                UseInternalAiCheckBox.IsChecked = false;
            }
            finally
            {
                _isInitializing = savedIsInitializing;
            }
        }

        // Determine the best hardware engine for the current machine
        bool useInternalAi = _settings.UseWindowsInternalAi && phiSilicaSupported;
        string bestEngineName;
        string bestEngineTag;
        bool bestEngineReady;

        var aiManager = App.Current.Services.GetRequiredService<Daily_WinUI.Services.AIManager>();
        bool hasGpu = aiManager.HasDedicatedGpu;

        if (useInternalAi && !string.IsNullOrEmpty(npu) && npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
        {
            bestEngineName = "Qualcomm Hexagon NPU";
            bestEngineTag = "NPU";
            bestEngineReady = true;
        }
        else if (hasGpu)
        {
            bestEngineName = "DirectML GPU Accelerator";
            bestEngineTag = "GPU";
            bestEngineReady = onnxModelReady;
        }
        else
        {
            bestEngineName = "DirectML CPU";
            bestEngineTag = "CPU";
            bestEngineReady = onnxModelReady;
        }

        string selectedModelId = _settings.SelectedLocalAiModel ?? "llama32_1b";
        string modelName = selectedModelId switch
        {
            "llama32_1b" => "Llama 3.2 1B Instruct",
            "qwen25_15b" => "Qwen 2.5 1.5B Instruct",
            "gemma3_1b" => "Gemma 3 1B Instruct",
            "phi35_mini" => "Phi 3.5 Mini Instruct",
            _ => "Llama 3.2 1B Instruct"
        };

        string recommendedOption = bestEngineName;
        string activeLabel;
        string description = "";

        if (cpuFallbackActive)
        {
            activeLabel = $"DirectML CPU ({modelName}) (Safe Fallback)";
            description = "The system encountered a graphics card driver error or compatibility issue and automatically fell back to CPU mode for stability. You can restart the application or choose a different accelerator to try again.";
        }
        else if (activeDevice == "Auto")
        {
            if (bestEngineReady)
            {
                if (bestEngineTag == "NPU")
                {
                    if (phiSilicaAvailable)
                    {
                        activeLabel = $"Auto -> {bestEngineName} (Phi Silica) (Active)";
                        description = $"System automatically resolved execution to the built-in Microsoft Copilot Runtime (Phi Silica) utilizing the NPU. Recommendation: {bestEngineName}.";
                    }
                    else
                    {
                        activeLabel = $"Auto -> {bestEngineName} (Phi Silica) (Requires Download)";
                        description = $"System automatically resolved execution to the built-in Microsoft Copilot Runtime (Phi Silica). Note: Model components need to be downloaded. Running your first Smart Briefing will trigger provisioning in the background.";
                    }
                }
                else
                {
                    activeLabel = $"Auto -> {bestEngineName} ({modelName}) (Active)";
                    description = $"System automatically resolved execution to the custom {modelName} model running on the {bestEngineName}.";
                }
            }
            else
            {
                activeLabel = $"Auto -> {bestEngineName} ({modelName}) (Requires Download)";
                description = $"No local AI engine is currently ready. System resolved target to the {bestEngineName}. The local model files must be downloaded first.";
            }
        }
        else if (activeDevice == "NPU")
        {
            if (_settings.UseWindowsInternalAi && phiSilicaSupported)
            {
                activeLabel = "Qualcomm Hexagon NPU (Phi Silica)";
                description = "Uses the built-in Microsoft Copilot Runtime (Phi Silica 3.3B) accelerated by the Qualcomm NPU. Zero download required.";
                if (!phiSilicaAvailable)
                {
                    var isUnpackaged = false;
                    try
                    {
                        var p = global::Windows.ApplicationModel.Package.Current;
                    }
                    catch (InvalidOperationException)
                    {
                        isUnpackaged = true;
                    }

                    if (isUnpackaged)
                    {
                        description += "\n\nCRITICAL WARNING: Access Denied. The application is running in unpackaged mode. Windows Copilot Runtime (Phi Silica) APIs strictly require MSIX package identity and the 'systemAIModels' capability to run. Please run the application using a Packaged launch profile to use Phi Silica.";
                    }
                    else
                    {
                        try
                        {
                            var state = LanguageModel.GetReadyState();
                            if (state == AIFeatureReadyState.NotReady)
                            {
                                description += "\n\nWARNING: Phi Silica is supported on this machine but is not ready/downloaded. Please ensure that Windows Update has finished downloading the Copilot model components, or trigger provisioning.";
                            }
                            else if (state == AIFeatureReadyState.NotSupportedOnCurrentSystem)
                            {
                                description += "\n\nWARNING: The hardware or OS version on this machine does not support the Windows Copilot Runtime. Ensure this is a Copilot+ PC running Windows 11 version 24H2 or higher.";
                            }
                            else if (state == AIFeatureReadyState.DisabledByUser)
                            {
                                description += "\n\nWARNING: The Copilot AI features have been disabled by system policy or user preferences.";
                            }
                            else
                            {
                                description += $"\n\nWARNING: Phi Silica is not ready. Current State: {state}";
                            }
                        }
                        catch (Exception ex)
                        {
                            description += $"\n\nWARNING: Failed to query model state: {ex.Message}";
                        }
                    }
                }
            }
            else
            {
                activeLabel = $"Qualcomm Hexagon NPU -> DirectML GPU ({modelName})";
                if (onnxModelReady)
                {
                    description = $"Uses the custom {modelName} model running locally via DirectML on your graphics card. (Routed from Hexagon NPU because built-in AI is disabled)";
                }
                else
                {
                    description = $"Uses the custom {modelName} model running locally via DirectML on your graphics card. Note: The custom model must be downloaded first. (Routed from Hexagon NPU because built-in AI is disabled)";
                }
            }
        }
        else if (activeDevice == "NPU_IntelAmd")
        {
            string npuName = (npu != null && (npu.Contains("AMD", StringComparison.OrdinalIgnoreCase) || npu.Contains("Ryzen", StringComparison.OrdinalIgnoreCase)))
                ? "AMD Ryzen AI NPU"
                : "Intel(R) AI Boost NPU";
            activeLabel = $"{npuName} ({modelName}) (Unsupported)";
            description = $"Intel/AMD NPUs are not directly supported for custom local models yet. Under Route 4, execution falls back to DirectML CPU mode. We recommend using 'Auto (Recommended)' or 'DirectML GPU Accelerator'.";
            if (!onnxModelReady)
            {
                description += " (Requires Model Download)";
            }
        }
        else if (activeDevice == "GPU")
        {
            activeLabel = $"DirectML GPU ({modelName})";
            description = $"Uses the custom {modelName} model running locally via DirectML on your graphics card. Offers excellent generation speed.";
            if (!onnxModelReady)
            {
                description += " (Requires Model Download)";
            }
        }
        else if (activeDevice == "CPU")
        {
            activeLabel = $"DirectML CPU ({modelName})";
            description = $"Uses the custom {modelName} model running locally on your processor. Note: CPU generation will be slower and use more battery.";
            if (!onnxModelReady)
            {
                description += " (Requires Model Download)";
            }
        }
        else // Fallback
        {
            activeLabel = "Fallback Template Engine";
            description = "Uses procedural templates to generate daily briefings. No local AI model execution is performed.";
        }

        SettingsAiDeviceStatusText.Text = $"Active Engine: {activeLabel}";
        SettingsAiAcceleratorDescriptionText.Text = description;

        if (!string.IsNullOrEmpty(_settings.LastExecutionExplanation))
        {
            LastRunExplanationInfoBar.Message = _settings.LastExecutionExplanation;
            LastRunExplanationInfoBar.IsOpen = true;
            LastRunExplanationInfoBar.Visibility = Visibility.Visible;
        }
        else
        {
            LastRunExplanationInfoBar.IsOpen = false;
            LastRunExplanationInfoBar.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateModelListUi()
    {
        var downloadManager = App.Current.Services.GetRequiredService<ModelDownloadManager>();
        bool isDownloading = downloadManager.IsDownloading;
        string? downloadingModelId = downloadManager.DownloadingModelId;
        string activeModelId = _settings.SelectedLocalAiModel ?? "llama32_1b";
        string activeAccelerator = _settings.SelectedAiAccelerator ?? "Auto";

        bool phiSilicaSupported = false;
        string? npu = SettingsService.GetDetectedNpuName();
        if (!string.IsNullOrEmpty(npu) && npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var state = LanguageModel.GetReadyState();
                phiSilicaSupported = state == AIFeatureReadyState.Ready || state == AIFeatureReadyState.NotReady;
            }
            catch { }
        }

        bool isInternalAiActive = _settings.UseWindowsInternalAi && phiSilicaSupported && (activeAccelerator == "Auto" || activeAccelerator == "NPU");

        // Show/hide Copilot Runtime NPU override banner
        if (isInternalAiActive)
        {
            NpuCopilotRuntimeInfoBar.Title = activeAccelerator == "Auto" 
                ? "Windows Copilot Runtime (Phi Silica) Active"
                : "Qualcomm Hexagon NPU Active (Phi Silica)";
            NpuCopilotRuntimeInfoBar.Message = "Phi Silica runs built-in via the Windows Copilot Runtime. External model downloads and selections are disabled.";
            NpuCopilotRuntimeInfoBar.IsOpen = true;
            NpuCopilotRuntimeInfoBar.Visibility = Visibility.Visible;
        }
        else
        {
            NpuCopilotRuntimeInfoBar.IsOpen = false;
            NpuCopilotRuntimeInfoBar.Visibility = Visibility.Collapsed;
        }

        // Update Llama Card
        UpdateCardState(
            "llama32_1b",
            isInternalAiActive,
            isDownloading,
            downloadingModelId,
            activeModelId,
            LlamaActiveBadge,
            LlamaStatusText,
            LlamaDownloadBtn,
            LlamaUseBtn,
            LlamaDeleteBtn
        );

        // Update Qwen Card
        UpdateCardState(
            "qwen25_15b",
            isInternalAiActive,
            isDownloading,
            downloadingModelId,
            activeModelId,
            QwenActiveBadge,
            QwenStatusText,
            QwenDownloadBtn,
            QwenUseBtn,
            QwenDeleteBtn
        );

        // Update Gemma Card
        UpdateCardState(
            "gemma3_1b",
            isInternalAiActive,
            isDownloading,
            downloadingModelId,
            activeModelId,
            GemmaActiveBadge,
            GemmaStatusText,
            GemmaDownloadBtn,
            GemmaUseBtn,
            GemmaDeleteBtn
        );

        // Update Phi Card
        UpdateCardState(
            "phi35_mini",
            isInternalAiActive,
            isDownloading,
            downloadingModelId,
            activeModelId,
            PhiActiveBadge,
            PhiStatusText,
            PhiDownloadBtn,
            PhiUseBtn,
            PhiDeleteBtn
        );

        // Update hardware warning InfoBars
        UpdateHardwareWarning(activeModelId, activeAccelerator);
    }

    private void UpdateCardState(
        string modelId,
        bool isBuiltInActive,
        bool isDownloading,
        string? downloadingModelId,
        string activeModelId,
        UIElement activeBadge,
        TextBlock statusText,
        Button downloadBtn,
        Button useBtn,
        Button deleteBtn)
    {
        bool isDownloaded = SettingsService.IsModelDownloaded(modelId);
        bool isActive = activeModelId == modelId;

        // If Copilot built-in AI is active, everything is disabled
        if (isBuiltInActive)
        {
            activeBadge.Visibility = Visibility.Collapsed;
            statusText.Text = "Disabled (Built-in Active)";
            downloadBtn.Visibility = Visibility.Collapsed;
            useBtn.Visibility = Visibility.Collapsed;
            deleteBtn.Visibility = Visibility.Collapsed;
            return;
        }

        // Show/hide active badge
        activeBadge.Visibility = isActive ? Visibility.Visible : Visibility.Collapsed;

        if (isActive)
        {
            statusText.Text = "Active Model";
        }
        else if (isDownloaded)
        {
            statusText.Text = "Downloaded & Ready";
        }
        else
        {
            statusText.Text = "Not Downloaded";
        }

        // Handle buttons based on download status
        if (isDownloaded)
        {
            downloadBtn.Visibility = Visibility.Collapsed;
            useBtn.Visibility = Visibility.Visible;
            useBtn.IsEnabled = !isActive && !isDownloading;
            deleteBtn.Visibility = Visibility.Visible;
            deleteBtn.IsEnabled = !isActive && !isDownloading;
        }
        else
        {
            downloadBtn.Visibility = Visibility.Visible;
            downloadBtn.IsEnabled = !isDownloading;
            useBtn.Visibility = Visibility.Collapsed;
            deleteBtn.Visibility = Visibility.Collapsed;
        }

        // Special handling if THIS model is downloading
        if (isDownloading && downloadingModelId == modelId)
        {
            statusText.Text = "Downloading...";
            downloadBtn.Visibility = Visibility.Collapsed;
            useBtn.Visibility = Visibility.Collapsed;
            deleteBtn.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateHardwareWarning(string modelId, string accelerator)
    {
        HardwareWarningInfoBar.IsOpen = false;
        HardwareWarningInfoBar.Visibility = Visibility.Collapsed;

        // Check if Intel/AMD NPU is selected
        if (accelerator == "NPU_IntelAmd")
        {
            HardwareWarningInfoBar.Title = "Intel/AMD NPU Unsupported";
            HardwareWarningInfoBar.Message = "Intel and AMD NPUs are not directly supported for custom local models yet. Your execution will automatically fall back to DirectML CPU mode. We recommend using 'Auto (Recommended)' or 'DirectML GPU Accelerator'.";
            HardwareWarningInfoBar.Severity = InfoBarSeverity.Warning;
            HardwareWarningInfoBar.IsOpen = true;
            HardwareWarningInfoBar.Visibility = Visibility.Visible;
            return;
        }

        // Check if CPU is paired with Phi 3.5 Mini
        if (modelId == "phi35_mini" && accelerator == "CPU")
        {
            HardwareWarningInfoBar.Title = "Performance Warning";
            HardwareWarningInfoBar.Message = "Phi 3.5 Mini (3.8B parameters) is a relatively heavy model. Running it on CPU will be extremely slow (~2 tokens/sec). We highly recommend using GPU acceleration.";
            HardwareWarningInfoBar.Severity = InfoBarSeverity.Warning;
            HardwareWarningInfoBar.IsOpen = true;
            HardwareWarningInfoBar.Visibility = Visibility.Visible;
            return;
        }

        // Check if Qualcomm NPU is selected but system doesn't support it
        if (accelerator == "NPU" && _settings.UseWindowsInternalAi)
        {
            bool phiSilicaAvailable = false;
            bool phiSilicaSupported = false;
            string? npu = SettingsService.GetDetectedNpuName();
            if (!string.IsNullOrEmpty(npu) && npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    var state = LanguageModel.GetReadyState();
                    phiSilicaAvailable = state == AIFeatureReadyState.Ready;
                    phiSilicaSupported = state == AIFeatureReadyState.Ready || state == AIFeatureReadyState.NotReady;
                }
                catch { }
            }

            if (!phiSilicaSupported)
            {
                HardwareWarningInfoBar.Title = "Incompatible Configuration";
                HardwareWarningInfoBar.Message = "Qualcomm NPU mode is selected, but the Windows Copilot Runtime (Phi Silica) is not supported on this system or application context. Please select a different accelerator or ensure your device is a Copilot+ PC running packaged.";
                HardwareWarningInfoBar.Severity = InfoBarSeverity.Error;
                HardwareWarningInfoBar.IsOpen = true;
                HardwareWarningInfoBar.Visibility = Visibility.Visible;
            }
            else if (!phiSilicaAvailable)
            {
                HardwareWarningInfoBar.Title = "Model Download Required";
                HardwareWarningInfoBar.Message = "Phi Silica is supported on this Snapdragon Copilot+ PC, but the model packages are not fully downloaded yet. Running your first Smart Briefing will automatically trigger model provisioning and download in the background.";
                HardwareWarningInfoBar.Severity = InfoBarSeverity.Warning;
                HardwareWarningInfoBar.IsOpen = true;
                HardwareWarningInfoBar.Visibility = Visibility.Visible;
            }
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
            UpdateModelListUi();
        }
    }

    private void SettingsCancelDownloadBtn_Click(object sender, RoutedEventArgs e)
    {
        var downloadManager = App.Current.Services.GetRequiredService<ModelDownloadManager>();
        downloadManager.CancelDownload();
    }

    private void StartModelDownload(string modelId)
    {
        var downloadManager = App.Current.Services.GetRequiredService<ModelDownloadManager>();
        if (downloadManager.IsDownloading) return;

        SettingsDownloadProgressGrid.Visibility = Visibility.Visible;
        SettingsDownloadProgressBar.Value = 0;
        SettingsDownloadStatusText.Text = "Connecting to repository...";

        downloadManager.StartDownload(modelId);
        UpdateModelListUi();
    }

    private void LlamaDownloadBtn_Click(object sender, RoutedEventArgs e) => StartModelDownload("llama32_1b");
    private void QwenDownloadBtn_Click(object sender, RoutedEventArgs e) => StartModelDownload("qwen25_15b");
    private void GemmaDownloadBtn_Click(object sender, RoutedEventArgs e) => StartModelDownload("gemma3_1b");
    private void PhiDownloadBtn_Click(object sender, RoutedEventArgs e) => StartModelDownload("phi35_mini");

    private void SelectModel(string modelId)
    {
        _settings.SelectedLocalAiModel = modelId;
        _settings.LocalAiModelDownloaded = true; // Keep legacy check in sync
        SettingsService.Save(_settings);
        UpdateModelListUi();
        UpdateModelStatus();
    }

    private void LlamaUseBtn_Click(object sender, RoutedEventArgs e) => SelectModel("llama32_1b");
    private void QwenUseBtn_Click(object sender, RoutedEventArgs e) => SelectModel("qwen25_15b");
    private void GemmaUseBtn_Click(object sender, RoutedEventArgs e) => SelectModel("gemma3_1b");
    private void PhiUseBtn_Click(object sender, RoutedEventArgs e) => SelectModel("phi35_mini");

    private async void DeleteModel(string modelId)
    {
        ContentDialog dialog = new ContentDialog
        {
            Title = "Confirm Delete",
            Content = "Are you sure you want to delete this model's downloaded files? This will free up disk space.",
            PrimaryButtonText = "Delete",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = this.XamlRoot
        };

        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary)
        {
            try
            {
                string dir = SettingsService.GetModelDirectory(modelId);
                if (Directory.Exists(dir))
                {
                    Directory.Delete(dir, true);
                }
                UpdateModelListUi();
                UpdateModelStatus();
            }
            catch (Exception ex)
            {
                ContentDialog errDialog = new ContentDialog
                {
                    Title = "Delete Failed",
                    Content = $"Could not delete model files: {ex.Message}",
                    CloseButtonText = "OK",
                    XamlRoot = this.XamlRoot
                };
                try { await errDialog.ShowAsync(); } catch { }
            }
        }
    }

    private void LlamaDeleteBtn_Click(object sender, RoutedEventArgs e) => DeleteModel("llama32_1b");
    private void QwenDeleteBtn_Click(object sender, RoutedEventArgs e) => DeleteModel("qwen25_15b");
    private void GemmaDeleteBtn_Click(object sender, RoutedEventArgs e) => DeleteModel("gemma3_1b");
    private void PhiDeleteBtn_Click(object sender, RoutedEventArgs e) => DeleteModel("phi35_mini");

    private void FeaturesPage_Unloaded(object sender, RoutedEventArgs e)
    {
        try
        {
            _rssService.OnFeedChanged -= RssService_OnFeedChanged;
            _feedsList.CollectionChanged -= FeedsList_CollectionChanged;
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
            UpdateModelListUi();

            string selectedModelId = _settings.SelectedLocalAiModel ?? "llama32_1b";
            string modelName = selectedModelId switch
            {
                "llama32_1b" => "Llama 3.2 1B Instruct",
                "qwen25_15b" => "Qwen 2.5 1.5B Instruct",
                "gemma3_1b" => "Gemma 3 1B Instruct",
                "phi35_mini" => "Phi 3.5 Mini Instruct",
                _ => "Llama 3.2 1B Instruct"
            };

            ContentDialog dialog = new ContentDialog
            {
                Title = "Model Download Complete",
                Content = $"The local {modelName} model has been successfully downloaded and verified. Local AI accelerator is now active.",
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
            UpdateModelListUi();

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

    private void UseInternalAiCheckBox_Checked(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null) return;
        _settings.UseWindowsInternalAi = true;
        SettingsService.Save(_settings);
        UpdateModelStatus();
        UpdateModelListUi();
    }

    private void UseInternalAiCheckBox_Unchecked(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null) return;
        _settings.UseWindowsInternalAi = false;
        SettingsService.Save(_settings);
        UpdateModelStatus();
        UpdateModelListUi();
    }

    private void WidgetAgingSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializing || _settings == null || WidgetAgingSwitch == null) return;
        bool isOn = WidgetAgingSwitch.IsOn;
        _settings.WidgetAgingEnabled = isOn;
        SettingsService.Save(_settings);
        if (WidgetAgingSlider != null) WidgetAgingSlider.IsEnabled = isOn;
        if (WidgetGrainIntensitySlider != null) WidgetGrainIntensitySlider.IsEnabled = isOn;
    }

    private void WidgetAgingSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_isInitializing || _settings == null || WidgetAgingSlider == null || WidgetAgingLabel == null) return;
        int idx = (int)WidgetAgingSlider.Value;
        if (idx >= 0 && idx < AgingIntervals.Length)
        {
            int duration = AgingIntervals[idx];
            _settings.WidgetAgingDurationSeconds = duration;
            WidgetAgingLabel.Text = AgingLabels[idx];
            SettingsService.Save(_settings);
        }
    }

    private void WidgetGrainIntensitySlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_isInitializing || _settings == null || WidgetGrainIntensitySlider == null || WidgetGrainIntensityLabel == null) return;
        double value = WidgetGrainIntensitySlider.Value;
        _settings.WidgetAgingGrainIntensity = value;
        WidgetGrainIntensityLabel.Text = $"{value:F0}%";
        SettingsService.Save(_settings);
    }

    // ── NEWS FEEDS MANAGEMENT & DISCOVERY ──

    private async Task LoadFeedsListAsync()
    {
        _isUpdatingFeedsList = true;
        try
        {
            var subs = await _rssService.GetSubscriptionsAsync();
            var subIds = subs.Select(x => x.Id).ToHashSet();
            
            // 1. Remove items that are no longer present
            for (int i = _feedsList.Count - 1; i >= 0; i--)
            {
                if (!subIds.Contains(_feedsList[i].Id))
                {
                    _feedsList.RemoveAt(i);
                }
            }
            
            // 2. Insert, move, or update items
            for (int i = 0; i < subs.Count; i++)
            {
                var sub = subs[i];
                var existingIndex = -1;
                for (int j = 0; j < _feedsList.Count; j++)
                {
                    if (_feedsList[j].Id == sub.Id)
                    {
                        existingIndex = j;
                        break;
                    }
                }
                
                if (existingIndex == -1)
                {
                    // Add new item at the correct index
                    var vm = new SubscriptionItemViewModel(sub);
                    _feedsList.Insert(i, vm);
                }
                else
                {
                    // Update existing item model data
                    var vm = _feedsList[existingIndex];
                    
                    // Update model properties if they changed
                    if (vm.Name != sub.Name) { vm.Name = sub.Name; }
                    if (vm.Url != sub.Url) { vm.Url = sub.Url; }
                    if (vm.Category != sub.Category) { vm.Category = sub.Category; }
                    
                    // Copy new model instance fields to keep references correct
                    vm.Model.Name = sub.Name;
                    vm.Model.Url = sub.Url;
                    vm.Model.Category = sub.Category;
                    vm.Model.DisplayOrder = sub.DisplayOrder;
                    vm.Model.SyncedAt = sub.SyncedAt;
                    vm.Model.UpdatedAt = sub.UpdatedAt;
                    
                    // Move if index changed
                    if (existingIndex != i)
                    {
                        _feedsList.Move(existingIndex, i);
                    }
                }
            }
            CurrentFeedsListView.ItemsSource = _feedsList;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[FeaturesPage] LoadFeedsListAsync Error: {ex}");
        }
        finally
        {
            _isUpdatingFeedsList = false;
        }
    }

    private async void FeedSearchBox_QuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        string query = sender.Text;
        await PerformFeedSearchAsync(query);
    }

    private async void FeedSearchBox_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            string query = FeedSearchBox.Text;
            await PerformFeedSearchAsync(query);
        }
    }

    private async Task PerformFeedSearchAsync(string query)
    {
        if (string.IsNullOrWhiteSpace(query)) return;

        FeedSearchProgressBar.Visibility = Visibility.Visible;
        FeedSearchStatusText.Visibility = Visibility.Visible;
        FeedSearchStatusText.Text = "Searching for feeds...";
        DiscoveredFeedsListView.Visibility = Visibility.Collapsed;

        try
        {
            var results = await _rssService.DiscoverFeedsAsync(query);
            
            if (results != null && results.Any())
            {
                FeedSearchProgressBar.Visibility = Visibility.Collapsed;
                FeedSearchStatusText.Visibility = Visibility.Collapsed;
                
                DiscoveredFeedsListView.ItemsSource = results;
                DiscoveredFeedsListView.Visibility = Visibility.Visible;
            }
            else
            {
                FeedSearchProgressBar.Visibility = Visibility.Collapsed;
                FeedSearchStatusText.Text = "No feeds found. Check the URL or try another search term.";
            }
        }
        catch (Exception ex)
        {
            FeedSearchProgressBar.Visibility = Visibility.Collapsed;
            FeedSearchStatusText.Text = $"Error searching: {ex.Message}";
        }
    }

    private async void AddCustomFeedBtn_Click(object sender, RoutedEventArgs e)
    {
        string url = FeedSearchBox.Text;
        if (string.IsNullOrWhiteSpace(url))
        {
            var dialog = new ContentDialog
            {
                Title = "Empty URL",
                Content = "Please enter a URL or feed name.",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
            return;
        }

        if (!url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) && 
            !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            url = "https://" + url;
        }

        if (!Uri.TryCreate(url, UriKind.Absolute, out _))
        {
            var dialog = new ContentDialog
            {
                Title = "Invalid URL",
                Content = "Please enter a valid absolute URL.",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
            return;
        }

        try
        {
            var uri = new Uri(url);
            string defaultName = uri.Host;
            
            string userId = Daily_WinUI.App.SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
            await _rssService.AddFeedAsync(url, defaultName, "Tech", userId);
            await LoadFeedsListAsync();
            FeedSearchBox.Text = "";
        }
        catch (Exception ex)
        {
            var dialog = new ContentDialog
            {
                Title = "Subscription Error",
                Content = $"Failed to add custom feed: {ex.Message}",
                CloseButtonText = "OK",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
        }
    }

    private async void SubscribeDiscoveredFeed_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is Daily.Models.FeedSearchResult result)
        {
            string category = "Tech"; // default
            
            var grid = FindVisualParent<Grid>(btn);
            if (grid != null)
            {
                var combo = FindVisualChild<ComboBox>(grid, "CategoryCombo");
                if (combo != null && combo.SelectedItem is ComboBoxItem item)
                {
                    category = item.Tag?.ToString() ?? "Tech";
                }
            }

            try
            {
                btn.IsEnabled = false;
                
                string userId = Daily_WinUI.App.SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
                await _rssService.AddFeedAsync(result.Url, result.Name, category, userId);
                
                await LoadFeedsListAsync();
                
                FeedSearchBox.Text = "";
                DiscoveredFeedsListView.Visibility = Visibility.Collapsed;
            }
            catch (Exception ex)
            {
                var dialog = new ContentDialog
                {
                    Title = "Subscription Error",
                    Content = $"Failed to subscribe to feed: {ex.Message}",
                    CloseButtonText = "OK",
                    XamlRoot = this.XamlRoot
                };
                await dialog.ShowAsync();
                btn.IsEnabled = true;
            }
        }
    }

    private void FeedIcon_ImageFailed(object sender, ExceptionRoutedEventArgs e)
    {
        if (sender is Image img)
        {
            img.Visibility = Visibility.Collapsed;
            if (img.DataContext is SubscriptionItemViewModel vm)
            {
                vm.HasIcon = false;
            }
            else
            {
                var grid = FindVisualParent<Grid>(img);
                if (grid != null)
                {
                    var fallback = FindVisualChild<FontIcon>(grid, "FeedIconFallback");
                    if (fallback != null)
                    {
                        fallback.Visibility = Visibility.Visible;
                    }
                }
            }
        }
    }

    private void EditFeed_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is SubscriptionItemViewModel vm)
        {
            vm.StartEdit();
        }
    }

    private void CancelEditFeed_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is SubscriptionItemViewModel vm)
        {
            vm.CancelEdit();
        }
    }

    private async void SaveFeed_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is SubscriptionItemViewModel vm)
        {
            try
            {
                if (!Uri.TryCreate(vm.EditUrl, UriKind.Absolute, out _))
                {
                    var dialog = new ContentDialog
                    {
                        Title = "Invalid URL",
                        Content = "Please enter a valid absolute URL.",
                        CloseButtonText = "OK",
                        XamlRoot = this.XamlRoot
                    };
                    await dialog.ShowAsync();
                    return;
                }

                vm.CommitEdit();
                await _rssService.SaveSubscriptionAsync(vm.Model);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[FeaturesPage] Error saving feed: {ex.Message}");
            }
        }
    }

    private async void DeleteFeed_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is SubscriptionItemViewModel vm)
        {
            var dialog = new ContentDialog
            {
                Title = "Delete Feed",
                Content = $"Are you sure you want to delete the feed '{vm.Name}'?",
                PrimaryButtonText = "Delete",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Close,
                XamlRoot = this.XamlRoot
            };

            var res = await dialog.ShowAsync();
            if (res == ContentDialogResult.Primary)
            {
                await _rssService.DeleteSubscriptionAsync(vm.Id);
                _feedsList.Remove(vm);
            }
        }
    }

    private void RssService_OnFeedChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_feedsList.Any(x => x.IsEditing))
            {
                _ = LoadFeedsListAsync();
            }
        });
    }

    private void CurrentFeedsListView_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is ListView lv && lv.SelectedIndex != -1)
        {
            lv.SelectedIndex = -1;
        }
    }

    private async void FeedsList_CollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        try
        {
            var logDir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
            if (!System.IO.Directory.Exists(logDir)) System.IO.Directory.CreateDirectory(logDir);
            var logPath = System.IO.Path.Combine(logDir, "reorder_log.txt");
            
            var currentItems = "null";
            if (sender is System.Collections.ObjectModel.ObservableCollection<SubscriptionItemViewModel> coll)
            {
                currentItems = string.Join(", ", coll.Select(x => x.Name));
            }
            
            System.IO.File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] CollectionChanged: Action={e.Action}, OldIndex={e.OldStartingIndex}, NewIndex={e.NewStartingIndex}, IsUpdating={_isUpdatingFeedsList}, Items={currentItems}\n");
        }
        catch { }

        if (_isUpdatingFeedsList) return;
        await SaveOrderAsync();
    }

    private async Task SaveOrderAsync()
    {
        _reorderDts?.Cancel();
        _reorderDts = new System.Threading.CancellationTokenSource();
        var token = _reorderDts.Token;

        try
        {
            await Task.Delay(300, token);
            var names = string.Join(", ", _feedsList.Select(x => x.Name));
            
            try
            {
                var logDir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
                var logPath = System.IO.Path.Combine(logDir, "reorder_log.txt");
                System.IO.File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] SaveOrderAsync ordered list: {names}\n");
            }
            catch { }

            var orderedList = _feedsList.Select(x => x.Model).ToList();
            await _rssService.ReorderSubscriptionsAsync(orderedList);
        }
        catch (TaskCanceledException)
        {
            // Cancelled by a subsequent reorder event
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[FeaturesPage] SaveOrderAsync Error: {ex.Message}");
            try
            {
                var logDir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
                var logPath = System.IO.Path.Combine(logDir, "reorder_log.txt");
                System.IO.File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] SaveOrderAsync Exception: {ex.Message}\n");
            }
            catch { }
        }
    }

    // Visual Tree Helpers
    private T? FindVisualParent<T>(DependencyObject child) where T : DependencyObject
    {
        var parent = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(child);
        if (parent == null) return null;
        if (parent is T t) return t;
        return FindVisualParent<T>(parent);
    }

    private T? FindVisualChild<T>(DependencyObject parent, string name) where T : DependencyObject
    {
        int count = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < count; i++)
        {
            var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(parent, i);
            if (child is T t && child is FrameworkElement fe && fe.Name == name)
            {
                return t;
            }
            var result = FindVisualChild<T>(child, name);
            if (result != null) return result;
        }
        return null;
    }

    private void UpdateMediumUi()
    {
        if (!string.IsNullOrEmpty(_settings.MediumUsername))
        {
            MediumStatusText.Text = $"Status: Linked as @{_settings.MediumUsername}";
            MediumReadingListUrlHelpText.Text = "Your reading list has been successfully configured. You can customize the URL below if needed.";
            MediumLoginBtn.Content = "Change Account";
            MediumDisconnectBtn.Visibility = Visibility.Visible;
            MediumReadingListUrlTextBox.Visibility = Visibility.Visible;
            MediumReadingListUrlTextBox.Text = _settings.MediumReadingListUrl ?? $"https://medium.com/@{_settings.MediumUsername}/list/reading-list";
        }
        else
        {
            MediumStatusText.Text = "Status: Not Configured";
            MediumReadingListUrlHelpText.Text = "Reading List URL will be automatically configured upon login.";
            MediumLoginBtn.Content = "Login to Medium";
            MediumDisconnectBtn.Visibility = Visibility.Collapsed;
            MediumReadingListUrlTextBox.Visibility = Visibility.Collapsed;
        }
    }

    private void MediumLoginBtn_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var loginWindow = new MediumLoginWindow(_settings, UpdateMediumUi, this.ActualTheme);
            loginWindow.Activate();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[FeaturesPage] Error opening login window: {ex.Message}");
        }
    }

    private async void MediumDisconnectBtn_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            Title = "Disconnect Medium",
            Content = "Are you sure you want to disconnect your Medium account and log out?",
            PrimaryButtonText = "Disconnect",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = this.XamlRoot
        };

        var res = await dialog.ShowAsync();
        if (res == ContentDialogResult.Primary)
        {
            _settings.MediumUsername = null;
            _settings.MediumReadingListUrl = null;
            SettingsService.Save(_settings);
            UpdateMediumUi();

            try
            {
                var tempWebView = new WebView2();
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string userDataFolder = System.IO.Path.Combine(localAppData, "Daily.WinUI", "WebView2");
                var options = new Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions();
                var env = await Microsoft.Web.WebView2.Core.CoreWebView2Environment.CreateWithOptionsAsync(null, userDataFolder, options);
                await tempWebView.EnsureCoreWebView2Async(env);
                
                var cookieManager = tempWebView.CoreWebView2.CookieManager;
                var cookies = await cookieManager.GetCookiesAsync("https://medium.com");
                foreach (var cookie in cookies)
                {
                    cookieManager.DeleteCookie(cookie);
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[Medium Disconnect] Cookie clearing failed: {ex.Message}");
            }
        }
    }

    private void MediumReadingListUrlTextBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox tb)
        {
            var text = tb.Text?.Trim();
            if (!string.IsNullOrEmpty(text) && Uri.TryCreate(text, UriKind.Absolute, out _))
            {
                _settings.MediumReadingListUrl = text;
                SettingsService.Save(_settings);
            }
            else
            {
                tb.Text = _settings.MediumReadingListUrl ?? "";
            }
        }
    }

    // View Model for subscribed feed list items
    public class SubscriptionItemViewModel : System.ComponentModel.INotifyPropertyChanged
    {
        private bool _isEditing;
        private string _name = string.Empty;
        private string _url = string.Empty;
        private string _category = string.Empty;
        private string _iconUrl = string.Empty;
        private bool _hasIcon = true;

        private string _editName = string.Empty;
        private string _editUrl = string.Empty;
        private string _editCategory = string.Empty;

        public Daily.Models.LocalRssSubscription Model { get; }

        public SubscriptionItemViewModel(Daily.Models.LocalRssSubscription model)
        {
            Model = model;
            Name = model.Name;
            Url = model.Url;
            Category = model.Category;
            IconUrl = model.IconUrl;
            _hasIcon = !string.IsNullOrWhiteSpace(model.IconUrl);
            
            EditName = Name;
            EditUrl = Url;
            EditCategory = Category;
        }

        public string Id => Model.Id;

        public bool IsEditing
        {
            get => _isEditing;
            set
            {
                if (_isEditing != value)
                {
                    _isEditing = value;
                    OnPropertyChanged(nameof(IsEditing));
                }
            }
        }

        public string Name
        {
            get => _name;
            set
            {
                if (_name != value)
                {
                    _name = value;
                    OnPropertyChanged(nameof(Name));
                }
            }
        }

        public string Url
        {
            get => _url;
            set
            {
                if (_url != value)
                {
                    _url = value;
                    OnPropertyChanged(nameof(Url));
                }
            }
        }

        public string Category
        {
            get => _category;
            set
            {
                if (_category != value)
                {
                    _category = value;
                    OnPropertyChanged(nameof(Category));
                }
            }
        }

        public string IconUrl
        {
            get => _iconUrl;
            set
            {
                if (_iconUrl != value)
                {
                    _iconUrl = value;
                    OnPropertyChanged(nameof(IconUrl));
                }
            }
        }

        public bool HasIcon
        {
            get => _hasIcon;
            set
            {
                if (_hasIcon != value)
                {
                    _hasIcon = value;
                    OnPropertyChanged(nameof(HasIcon));
                }
            }
        }

        public string EditName
        {
            get => _editName;
            set
            {
                if (_editName != value)
                {
                    _editName = value;
                    OnPropertyChanged(nameof(EditName));
                }
            }
        }

        public string EditUrl
        {
            get => _editUrl;
            set
            {
                if (_editUrl != value)
                {
                    _editUrl = value;
                    OnPropertyChanged(nameof(EditUrl));
                }
            }
        }

        public string EditCategory
        {
            get => _editCategory;
            set
            {
                if (_editCategory != value)
                {
                    _editCategory = value;
                    OnPropertyChanged(nameof(EditCategory));
                }
            }
        }

        public void StartEdit()
        {
            EditName = Name;
            EditUrl = Url;
            EditCategory = Category;
            IsEditing = true;
        }

        public void CancelEdit()
        {
            IsEditing = false;
        }

        public void CommitEdit()
        {
            Name = EditName;
            Url = EditUrl;
            Category = EditCategory;
            
            Model.Name = Name;
            Model.Url = Url;
            Model.Category = Category;
            
            try
            {
                Model.IconUrl = $"https://www.google.com/s2/favicons?domain={new Uri(Url).Host}&sz=64";
                IconUrl = Model.IconUrl;
                HasIcon = !string.IsNullOrWhiteSpace(IconUrl);
            }
            catch
            {
                // Ignore Uri exception and retain old icon
            }

            IsEditing = false;
        }

        public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;
        protected virtual void OnPropertyChanged(string propertyName)
        {
            PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(propertyName));
        }
    }

    public sealed class MediumLoginWindow : Window
    {
        private readonly WebView2 _webView;
        private readonly ProgressRing _progressRing;
        private readonly AppSettings _settings;
        private readonly Action _onUiUpdate;
        private Windows.Foundation.TypedEventHandler<Microsoft.Web.WebView2.Core.CoreWebView2, Microsoft.Web.WebView2.Core.CoreWebView2SourceChangedEventArgs>? _sourceChangedHandler;
        private ElementTheme _theme;
        private IntPtr _hWnd = IntPtr.Zero;

        [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

        private void SetTitleBarTheme(IntPtr hwnd, ElementTheme theme)
        {
            try
            {
                int darkMode = theme == ElementTheme.Dark ? 1 : 0;
                DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref darkMode, sizeof(int));
                DwmSetWindowAttribute(hwnd, 19, ref darkMode, sizeof(int));
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MediumLoginWindow] SetTitleBarTheme error: {ex.Message}");
            }
        }

        public MediumLoginWindow(AppSettings settings, Action onUiUpdate, ElementTheme theme)
        {
            _settings = settings;
            _onUiUpdate = onUiUpdate;
            _theme = theme;
            
            this.Title = "Login to Medium";
            this.SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop();
            
            App.Current.RegisterSecondaryWindow(this);
            
            _webView = new WebView2
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch
            };

            if (theme == ElementTheme.Dark)
            {
                _webView.DefaultBackgroundColor = Windows.UI.Color.FromArgb(255, 0x1A, 0x14, 0x23);
            }
            else
            {
                _webView.DefaultBackgroundColor = Windows.UI.Color.FromArgb(255, 0xED, 0xE5, 0xD9);
            }

            _progressRing = new ProgressRing
            {
                IsActive = true,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Width = 50,
                Height = 50
            };

            var grid = new Grid
            {
                Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent),
                RequestedTheme = theme
            };
            grid.Children.Add(_webView);
            grid.Children.Add(_progressRing);

            this.Content = grid;

            _webView.NavigationCompleted += (s, args) =>
            {
                _progressRing.IsActive = false;
                _progressRing.Visibility = Visibility.Collapsed;
            };

            this.Activated += MediumLoginWindow_Activated;
            this.Closed += MediumLoginWindow_Closed;
        }

        public void ApplyTheme(ElementTheme theme)
        {
            _theme = theme;
            if (Content is FrameworkElement root)
            {
                root.RequestedTheme = theme;
            }
            if (_webView != null)
            {
                if (theme == ElementTheme.Dark)
                {
                    _webView.DefaultBackgroundColor = Windows.UI.Color.FromArgb(255, 0x1A, 0x14, 0x23);
                }
                else
                {
                    _webView.DefaultBackgroundColor = Windows.UI.Color.FromArgb(255, 0xED, 0xE5, 0xD9);
                }
            }
            if (_hWnd != IntPtr.Zero)
            {
                SetTitleBarTheme(_hWnd, theme);
            }
        }

        private async void MediumLoginWindow_Activated(object sender, WindowActivatedEventArgs args)
        {
            this.Activated -= MediumLoginWindow_Activated;

            try
            {
                _hWnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
                var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(_hWnd);
                var appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(windowId);
                
                appWindow.SetIcon("Assets/AppIcon.ico");
                appWindow.Resize(new Windows.Graphics.SizeInt32(850, 850));
                
                SetTitleBarTheme(_hWnd, _theme);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MediumLoginWindow] Sizing error: {ex.Message}");
            }

            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string userDataFolder = System.IO.Path.Combine(localAppData, "Daily.WinUI", "WebView2");
                System.IO.Directory.CreateDirectory(userDataFolder);

                var options = new Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions();
                var env = await Microsoft.Web.WebView2.Core.CoreWebView2Environment.CreateWithOptionsAsync(null, userDataFolder, options);
                await _webView.EnsureCoreWebView2Async(env);
                
                _sourceChangedHandler = async (senderCore, sourceArgs) =>
                {
                    var url = senderCore.Source;
                    if (string.IsNullOrEmpty(url)) return;

                    try
                    {
                        var uri = new Uri(url);
                        if (uri.Host == "medium.com")
                        {
                            var path = uri.AbsolutePath;
                            if (path.StartsWith("/@"))
                            {
                                var parts = path.Substring(2).Split('/');
                                var username = parts[0];
                                if (!string.IsNullOrEmpty(username))
                                {
                                    senderCore.SourceChanged -= _sourceChangedHandler;

                                    _settings.MediumUsername = username;
                                    _settings.MediumReadingListUrl = $"https://medium.com/@{username}/list/reading-list";
                                    SettingsService.Save(_settings);

                                    _onUiUpdate();

                                    this.Close();
                                }
                            }
                            else if (path == "/" || path == "" || path == "/?source=logo")
                            {
                                senderCore.Navigate("https://medium.com/me");
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[Medium Login] Error parsing URL {url}: {ex.Message}");
                    }
                };

                _webView.CoreWebView2.SourceChanged += _sourceChangedHandler;
                _webView.Source = new Uri("https://medium.com/m/signin");
            }
            catch (Exception ex)
            {
                _progressRing.IsActive = false;
                _progressRing.Visibility = Visibility.Collapsed;
                System.Diagnostics.Debug.WriteLine($"[MediumLoginWindow] WebView2 initialization failed: {ex.Message}");
            }
        }

        private void MediumLoginWindow_Closed(object sender, WindowEventArgs args)
        {
            this.Closed -= MediumLoginWindow_Closed;
            if (_webView != null && _webView.CoreWebView2 != null && _sourceChangedHandler != null)
            {
                _webView.CoreWebView2.SourceChanged -= _sourceChangedHandler;
            }
        }
    }
}
