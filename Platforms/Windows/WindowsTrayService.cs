using Daily.Services;
using System;
using H.NotifyIcon;

namespace Daily.Platforms.Windows
{
    public class WindowsTrayService : ITrayService
    {
        private TaskbarIcon _taskbarIcon;

        public Action ClickHandler { get; set; }

        public void Initialize()
        {
            // H.NotifyIcon usually works via XAML or DI, but we can try to instantiate it.
            // However, in MAUI it's best used as a lifecycle event or via the builder.
            // For now, we'll leave this empty as we'll configure it in MauiProgram/App.xaml
            // actually, let's just use the library's features.
        }
    }
}
