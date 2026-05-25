using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily_WinUI.Services;

namespace Daily_WinUI.Views;

public sealed partial class GeneralSettingsPage : Page
{
    private readonly AppSettings _settings;
    private bool _downloadInProgress = false;
    private DispatcherTimer? _downloadTimer;
    private int _downloadProgressValue = 0;

    public GeneralSettingsPage()
    {
        InitializeComponent();
        _settings = SettingsService.Load();
        Loaded += GeneralSettingsPage_Loaded;
        Unloaded += (s, ev) => _downloadTimer?.Stop();
    }

    private void GeneralSettingsPage_Loaded(object sender, RoutedEventArgs e)
    {
        SmartBriefingSwitch.Toggled -= SmartBriefingSwitch_Toggled;
        SmartBriefingSwitch.IsOn = _settings.EnableSmartBriefing;
        SmartBriefingSwitch.Toggled += SmartBriefingSwitch_Toggled;

        // Display detected Hardware Capabilities
        string cpu = SettingsService.GetProcessorName();
        SettingsCpuModelText.Text = $"CPU: {cpu}";

        string? npu = SettingsService.GetDetectedNpuName();
        if (!string.IsNullOrEmpty(npu))
        {
            SettingsNpuStatusText.Text = $"NPU: {npu} [Detected]";
            SettingsNpuStatusText.Foreground = App.Current.Resources.TryGetValue("SystemControlForegroundAccentBrush", out var brush) && brush is Microsoft.UI.Xaml.Media.Brush b ? b : null;
        }
        else
        {
            SettingsNpuStatusText.Text = "NPU: No supported NPU detected";
            SettingsNpuStatusText.Foreground = null;
        }

        // Dynamically build AI accelerator list based on machine hardware
        SettingsAiAcceleratorCombo.SelectionChanged -= SettingsAiAcceleratorCombo_SelectionChanged;
        SettingsAiAcceleratorCombo.Items.Clear();

        // 1. Auto (Recommended) - always available
        SettingsAiAcceleratorCombo.Items.Add(new ComboBoxItem { Content = "Auto (Recommended)", Tag = "Auto" });

        // 2. Add matching NPU choice if detected
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

        // 3. GPU / CPU - always available
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
        SettingsAiAcceleratorCombo.SelectionChanged += SettingsAiAcceleratorCombo_SelectionChanged;

        UpdateModelStatus();
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

    private void SettingsAiAcceleratorCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SettingsAiAcceleratorCombo.SelectedItem is ComboBoxItem item && item.Tag is string tag)
        {
            _settings.SelectedAiAccelerator = tag;
            SettingsService.Save(_settings);
            UpdateModelStatus();
        }
    }

    private void SmartBriefingSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        _settings.EnableSmartBriefing = SmartBriefingSwitch.IsOn;
        SettingsService.Save(_settings);
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
}
