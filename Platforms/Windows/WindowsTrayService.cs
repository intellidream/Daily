using Daily.Services;
using System;
using Microsoft.Maui.Controls;
using H.NotifyIcon;

namespace Daily.Platforms.Windows
{
    public class WindowsTrayService : ITrayService
    {
        public Action? ClickHandler { get; set; }
        private TaskbarIcon? _trayIcon;

        public void Initialize() 
        {
            if (_trayIcon == null)
            {
                var menu = new MenuFlyout();
                var showItem = new MenuFlyoutItem { Text = "Show", Command = new Command(() => ClickHandler?.Invoke()) };
                var exitItem = new MenuFlyoutItem { Text = "Exit", Command = new Command(() => Application.Current?.Quit()) };
                
                menu.Add(showItem);
                menu.Add(exitItem);

                string absolutePath = System.IO.Path.Combine(System.AppContext.BaseDirectory, "appicon_windows.ico");

                _trayIcon = new TaskbarIcon
                {
                    ToolTipText = "Daily",
                    LeftClickCommand = new Command(() => ClickHandler?.Invoke()),
                    DoubleClickCommand = new Command(() => ClickHandler?.Invoke())
                };

                if (System.IO.File.Exists(absolutePath))
                {
                    try
                    {
                        _trayIcon.Icon = new System.Drawing.Icon(absolutePath);
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[WindowsTrayService] Failed to load icon natively: {ex}");
                    }
                }
                else
                {
                    System.Diagnostics.Debug.WriteLine($"[WindowsTrayService] Icon file not found at: {absolutePath}");
                }

                FlyoutBase.SetContextFlyout(_trayIcon, menu);

                // Create the native tray icon
                _trayIcon.ForceCreate();
            }
        }
    }
}
