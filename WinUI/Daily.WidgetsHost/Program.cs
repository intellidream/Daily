using System;
using System.IO;
using System.Threading;
using Microsoft.UI.Xaml;
using Daily_WinUI.DesktopWidgets;

namespace Daily_WinUI.WidgetsHost;

public static class Program
{
    private static void Log(string msg)
    {
        try
        {
            var p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "daily_widgetshost_debug.log");
            File.AppendAllText(p, $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss.fff}] [PID={Environment.ProcessId}] {msg}\r\n");
        }
        catch { }
    }

    [STAThread]
    public static void Main(string[] args)
    {
        Log($"Main enter. Args: {(args != null ? string.Join(" ", args) : "none")}");
        try
        {
            Log("Calling WinRT.ComWrappersSupport.InitializeComWrappers()...");
            WinRT.ComWrappersSupport.InitializeComWrappers();
            Log("ComWrappers initialized.");

            bool createdNew;
            Mutex? mutex = null;
            try
            {
                mutex = new Mutex(true, WidgetsHostIpc.MutexName, out createdNew);
            }
            catch (AbandonedMutexException)
            {
                createdNew = true;
            }

            Log($"Mutex check: createdNew={createdNew}");

            if (!createdNew)
            {
                Log("Another instance is running, forwarding command and exiting.");
                if (args != null && args.Length > 0)
                {
                    _ = WidgetsHostIpc.SendCommandAsync(string.Join(" ", args));
                }
                else
                {
                    _ = WidgetsHostIpc.SendCommandAsync("show_all");
                }
                return;
            }

            Log("Calling Application.Start...");
            Application.Start((p) =>
            {
                Log("Application.Start callback invoked.");
                try
                {
                    var context = new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                        Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
                    System.Threading.SynchronizationContext.SetSynchronizationContext(context);
                    Log("Instantiating App...");
                    new App();
                    Log("App instantiated.");
                }
                catch (Exception ex)
                {
                    Log($"Exception inside Application.Start callback: {ex}");
                    throw;
                }
            });

            Log("Application.Start finished.");
            GC.KeepAlive(mutex);
        }
        catch (Exception ex)
        {
            Log($"FATAL EXCEPTION in Main: {ex}");
        }
    }
}
