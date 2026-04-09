using Daily.Services;
using System;
using Microsoft.Maui.Controls;

namespace Daily.Platforms.Windows
{
    public class WindowsTrayService : ITrayService
    {
        public Action? ClickHandler { get; set; }

        public void Initialize() 
        {
            // Initialization is handled in XAML (App.xaml) and code behind.
        }
    }
}
