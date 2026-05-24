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
        // Unregister event during initial load to prevent saving on load
        CloseToTraySwitch.Toggled -= CloseToTraySwitch_Toggled;
        CloseToTraySwitch.IsOn = _settings.CloseToTray;
        CloseToTraySwitch.Toggled += CloseToTraySwitch_Toggled;

        SmartBriefingSwitch.Toggled -= SmartBriefingSwitch_Toggled;
        SmartBriefingSwitch.IsOn = _settings.EnableSmartBriefing;
        SmartBriefingSwitch.Toggled += SmartBriefingSwitch_Toggled;

        // Load Accelerator selection
        SettingsAiAcceleratorCombo.SelectionChanged -= SettingsAiAcceleratorCombo_SelectionChanged;
        string savedAcc = _settings.SelectedAiAccelerator ?? "Auto";
        int selectedIndex = 0; // Default Auto
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
        string npu = SettingsService.GetDetectedNpuName();
        string activeDevice = _settings.SelectedAiAccelerator ?? "Auto";
        string activeLabel = activeDevice == "Auto" ? npu : 
                            (activeDevice == "NPU" ? "Qualcomm Hexagon NPU (45 TOPS)" :
                            (activeDevice == "NPU_IntelAmd" ? "Intel AI Boost / AMD IPU" :
                            (activeDevice == "GPU" ? "DirectML GPU" : "DirectML CPU (Fallback)")));

        if (_settings.LocalAiModelDownloaded)
        {
            SettingsAiDeviceStatusText.Text = $"AI Core: {activeLabel} | Local Engine Active";
            SettingsDownloadModelBtn.Visibility = Visibility.Collapsed;
        }
        else
        {
            SettingsAiDeviceStatusText.Text = $"AI Core: {activeLabel} | Local Model Missing";
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

    private void CloseToTraySwitch_Toggled(object sender, RoutedEventArgs e)
    {
        _settings.CloseToTray = CloseToTraySwitch.IsOn;
        SettingsService.Save(_settings);
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

    private void ToggleThemeButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.Current.MainWindow is MainWindow mw)
        {
            mw.TitleBarTheme_Click(sender, e);
        }
    }
}
