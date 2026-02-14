using System.Windows.Input;
using Daily.Services;

namespace Daily.Views;

public partial class DebugWidgetView : ContentView
{
    private readonly DebugLogger? _debugLogger;
    private readonly DebugWidgetViewModel _viewModel;

    public DebugWidgetView()
    {
        InitializeComponent();

        var services = Application.Current?.Handler?.MauiContext?.Services;
        _debugLogger = services?.GetService<DebugLogger>();

        _viewModel = new DebugWidgetViewModel(_debugLogger);
        BindingContext = _viewModel;

        if (_debugLogger != null)
        {
            _debugLogger.OnLogAdded += HandleLogAdded;
        }
    }

    private async void OnCopyClicked(object? sender, EventArgs e)
    {
        if (_debugLogger == null)
        {
            return;
        }

        _viewModel.Refresh();
        var textToCopy = LogEditor?.Text;
        if (string.IsNullOrWhiteSpace(textToCopy))
        {
            textToCopy = string.Join("\n", _debugLogger.Logs);
        }
        if (string.IsNullOrWhiteSpace(textToCopy))
        {
            return;
        }

        try
        {
            await MainThread.InvokeOnMainThreadAsync(() => Clipboard.SetTextAsync(textToCopy));
            _debugLogger.Log("[DebugWidget] Logs copied to clipboard.");
        }
        catch (Exception ex)
        {
            _debugLogger.Log($"[DebugWidget] Clipboard copy failed: {ex.Message}");
        }
    }

    private void OnClearClicked(object? sender, EventArgs e)
    {
        _debugLogger?.Clear();
        _viewModel.Refresh();
    }

    private void HandleLogAdded()
    {
        MainThread.BeginInvokeOnMainThread(() => _viewModel.Refresh());
    }


    protected override void OnHandlerChanging(HandlerChangingEventArgs args)
    {
        if (args.OldHandler != null && _debugLogger != null)
        {
            _debugLogger.OnLogAdded -= HandleLogAdded;
        }

        base.OnHandlerChanging(args);
    }

    private sealed class DebugWidgetViewModel : System.ComponentModel.INotifyPropertyChanged
    {
        private readonly DebugLogger? _logger;

        public DebugWidgetViewModel(DebugLogger? logger)
        {
            _logger = logger;
            ClearCommand = new Command(() => _logger?.Clear());
            CopyCommand = new Command(async () => await CopyAsync());
            Refresh();
        }

        public ICommand ClearCommand { get; }
        public ICommand CopyCommand { get; }

        public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;

        public string LogText { get; private set; } = string.Empty;

        public void Refresh()
        {
            LogText = _logger == null ? "Diagnostics logger unavailable." : string.Join("\n", _logger.Logs);
            PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(nameof(LogText)));
        }

        private async Task CopyAsync()
        {
            Refresh();
            if (string.IsNullOrEmpty(LogText))
            {
                return;
            }

            await MainThread.InvokeOnMainThreadAsync(() => Clipboard.SetTextAsync(LogText));
        }
    }
}
