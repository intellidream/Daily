using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Daily.Services;
using Daily.Services.Finances;
using Daily.Services.Health;
using Daily_WinUI.DesktopWidgets;
using Daily_WinUI.Services;
using Daily_WinUI.Services.Cosmos;
using Daily_WinUI.WidgetsHost.Services;

namespace Daily_WinUI;

public partial class App : Application
{
    public static new App Current => (App)Application.Current;
    public IServiceProvider? Services { get; private set; }
    public DispatcherQueue DispatcherQueue { get; private set; } = null!;
    public object? MainWindow => null;

    private readonly List<Window> _activeSecondaryWindows = new();
    public IReadOnlyList<Window> ActiveSecondaryWindows => _activeSecondaryWindows;

    public void RegisterSecondaryWindow(Window window)
    {
        _activeSecondaryWindows.Add(window);
        window.Closed += (s, e) =>
        {
            _activeSecondaryWindows.Remove(window);
        };
    }

    public void CloseAllSecondaryWindows()
    {
        var copy = _activeSecondaryWindows.ToList();
        foreach (var w in copy)
        {
            try { w.Close(); } catch { }
        }
        _activeSecondaryWindows.Clear();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        DispatcherQueue = DispatcherQueue.GetForCurrentThread();

        var services = new ServiceCollection();
        ConfigureServices(services);
        Services = services.BuildServiceProvider();

        // Mark this process as the WidgetsHost so DesktopWidgetManager executes locally
        WidgetsHostIpc.IsRunningInHostProcess = true;

        // Initialize Desktop Widgets
        DesktopWidgetManager.Instance.Initialize();

        // Start Named Pipe listener for IPC commands from Daily.WinUI or other clients
        StartIpcListener();

        // Periodic maintenance timer (every 15 min): refresh weather & widget data with 0 idle CPU
        var refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(15) };
        refreshTimer.Tick += (s, e) =>
        {
            try
            {
                DesktopWidgetManager.Instance.RefreshAllWidgets();
            }
            catch { }
        };
        refreshTimer.Start();
    }

    private void ConfigureServices(IServiceCollection services)
    {
        // Core Database
        var db = new DatabaseService();
        services.AddSingleton<IDatabaseService>(db);

        // Lean local SQLite-first implementations for desktop widgets
        services.AddSingleton<IHabitsService, WidgetsHostHabitsService>();
        services.AddSingleton<IHealthHubService, WidgetsHostHealthService>();
        services.AddSingleton<IFinancesService, WidgetsHostFinancesService>();
        services.AddSingleton<ITagdosService, WidgetsHostTagdosService>();

        // Standalone clients
        services.AddSingleton<WeatherClient>();
        services.AddSingleton<LocationService>();
        services.AddSingleton(AstronomyService.Shared);
    }

    private void StartIpcListener()
    {
        var thread = new Thread(() =>
        {
            while (true)
            {
                try
                {
                    using var server = new NamedPipeServerStream(
                        WidgetsHostIpc.PipeName,
                        PipeDirection.In,
                        NamedPipeServerStream.MaxAllowedServerInstances,
                        PipeTransmissionMode.Message,
                        PipeOptions.Asynchronous);

                    server.WaitForConnection();
                    using var reader = new StreamReader(server);
                    var line = reader.ReadLine();
                    if (string.IsNullOrWhiteSpace(line)) continue;

                    string command = line.Trim();
                    DispatcherQueue?.TryEnqueue(() => HandleIpcCommand(command));
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"[WidgetsHost IPC] Error: {ex.Message}");
                    Thread.Sleep(200);
                }
            }
        })
        {
            IsBackground = true,
            Name = "WidgetsHost_IpcListener"
        };
        thread.Start();
    }

    private void HandleIpcCommand(string cmd)
    {
        SettingsService.Reload();

        if (cmd.Equals("ping", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (cmd.Equals("refresh", StringComparison.OrdinalIgnoreCase))
        {
            DesktopWidgetManager.Instance.RefreshAllWidgets();
        }
        else if (cmd.Equals("show_all", StringComparison.OrdinalIgnoreCase))
        {
            DesktopWidgetManager.Instance.ShowAll();
        }
        else if (cmd.Equals("hide_all", StringComparison.OrdinalIgnoreCase))
        {
            DesktopWidgetManager.Instance.HideAll();
        }
        else if (cmd.Equals("lock", StringComparison.OrdinalIgnoreCase))
        {
            DesktopWidgetManager.Instance.SetAllLocked(true);
        }
        else if (cmd.Equals("unlock", StringComparison.OrdinalIgnoreCase))
        {
            DesktopWidgetManager.Instance.SetAllLocked(false);
        }
        else if (cmd.Equals("reset", StringComparison.OrdinalIgnoreCase))
        {
            DesktopWidgetManager.Instance.ResetToDefaults();
        }
        else if (cmd.StartsWith("add:", StringComparison.OrdinalIgnoreCase) || cmd.StartsWith("add_widget:", StringComparison.OrdinalIgnoreCase))
        {
            var parts = cmd.Split(':');
            if (parts.Length >= 5 &&
                Enum.TryParse<DesktopWidgetType>(parts[1], true, out var type) &&
                Enum.TryParse<DesktopWidgetSize>(parts[2], true, out var size) &&
                int.TryParse(parts[3], out int x) &&
                int.TryParse(parts[4], out int y))
            {
                DesktopWidgetManager.Instance.AddWidget(type, size, x, y);
            }
            else if (parts.Length >= 3 &&
                     Enum.TryParse<DesktopWidgetType>(parts[1], true, out var simpleType) &&
                     Enum.TryParse<DesktopWidgetSize>(parts[2], true, out var simpleSize))
            {
                DesktopWidgetManager.Instance.AddWidget(simpleType, simpleSize, 100, 100);
            }
        }
        else if (cmd.Equals("shutdown", StringComparison.OrdinalIgnoreCase))
        {
            DesktopWidgetManager.Instance.HideAll();
            Environment.Exit(0);
        }
    }
}
