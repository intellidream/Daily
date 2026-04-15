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
                var showItem = new MenuFlyoutItem { Text = "Show" };
                showItem.Clicked += (s, e) => ClickHandler?.Invoke();
                
                var exitItem = new MenuFlyoutItem { Text = "Exit" };
                exitItem.Clicked += (s, e) => Application.Current?.Quit();
                
                menu.Add(showItem);
                menu.Add(exitItem);

                _trayIcon = new TaskbarIcon
                {
                    IconSource = "appicon_windows.ico",
                    ToolTipText = "Daily",
                    LeftClickCommand = new Command(() => ClickHandler?.Invoke())
                };

                FlyoutBase.SetContextFlyout(_trayIcon, menu);

                // Create the native tray icon
                _trayIcon.ForceCreate();
            }
        }
    }
}
