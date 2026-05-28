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

        if (useInternalAi && !string.IsNullOrEmpty(npu) && npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
        {
            bestEngineName = "Qualcomm Hexagon NPU";
            bestEngineTag = "NPU";
            bestEngineReady = true;
        }
        else if (!string.IsNullOrEmpty(npu) && (npu.Contains("AMD", StringComparison.OrdinalIgnoreCase) || npu.Contains("Ryzen", StringComparison.OrdinalIgnoreCase)))
        {
            bestEngineName = "AMD Ryzen AI NPU";
            bestEngineTag = "NPU_IntelAmd";
            bestEngineReady = onnxModelReady;
        }
        else if (!string.IsNullOrEmpty(npu) && npu.Contains("Intel", StringComparison.OrdinalIgnoreCase))
        {
            bestEngineName = "Intel(R) AI Boost NPU";
            bestEngineTag = "NPU_IntelAmd";
            bestEngineReady = onnxModelReady;
        }
        else
        {
            bestEngineName = "DirectML GPU Accelerator";
            bestEngineTag = "GPU";
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
            activeLabel = $"{npuName} ({modelName})";
            description = $"Uses the custom {modelName} model running locally on the {npuName} via ONNX Runtime GenAI.";
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
}
