using System;
using System.Threading;
using Microsoft.UI.Xaml;
using Daily_WinUI.DesktopWidgets;

namespace Daily_WinUI.WidgetsHost;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();

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

        if (!createdNew)
        {
            // Another instance is already running!
            // If any argument was passed, forward as IPC command.
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

        Application.Start((p) =>
        {
            var context = new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
            System.Threading.SynchronizationContext.SetSynchronizationContext(context);
            new App();
        });

        // Keep mutex reference alive until application terminates
        GC.KeepAlive(mutex);
    }
}
