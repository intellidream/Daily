using Daily.Services;
using System;
using H.NotifyIcon;

namespace Daily.Platforms.Windows
{
    public class WindowsTrayService : ITrayService
    {
        public Action? ClickHandler { get; set; }
        public void Initialize() { }
    }
}
