using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WinRT.Interop;

namespace Daily_WinUI
{
    public sealed partial class TaskbarCompanionWindow : Window
    {
        private readonly Controls.TaskbarGlanceFlyoutControl _glanceControl;

        [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);

        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_APPWINDOW = 0x00040000;

        public TaskbarCompanionWindow()
        {
            this.SystemBackdrop = new DesktopAcrylicBackdrop();

            _glanceControl = new Controls.TaskbarGlanceFlyoutControl();
            _glanceControl.RequestCloseFlyout += (s, e) => Hide();

            var rootGrid = new Grid
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch
            };
            rootGrid.Children.Add(_glanceControl);
            this.Content = rootGrid;

            // Configure borderless floating window
            AppWindow.TitleBar.ExtendsContentIntoTitleBar = true;
            if (AppWindow.Presenter is OverlappedPresenter presenter)
            {
                presenter.IsResizable = false;
                presenter.IsMaximizable = false;
                presenter.IsMinimizable = false;
                presenter.SetBorderAndTitleBar(false, false);
                presenter.IsAlwaysOnTop = true;
            }

            var hwnd = WindowNative.GetWindowHandle(this);
            // Hide from Alt+Tab and taskbar
            int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            SetWindowLong(hwnd, GWL_EXSTYLE, (exStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);

            // Auto-hide when deactivated (clicked outside)
            this.Activated += (s, args) =>
            {
                if (args.WindowActivationState == WindowActivationState.Deactivated)
                {
                    Hide();
                }
            };
        }

        public void ShowNearTray()
        {
            var hwnd = WindowNative.GetWindowHandle(this);
            uint dpi = GetDpiForWindow(hwnd);
            double scale = dpi > 0 ? (double)dpi / 96.0 : 1.0;

            int targetWidth = (int)(360 * scale);
            int targetHeight = (int)(540 * scale);

            var displayArea = DisplayArea.Primary ?? DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
            var workArea = displayArea.WorkArea;

            // Horizontally aligned to bottom-right corner of work area, vertically right above taskbar
            int x = workArea.X + workArea.Width - targetWidth - (int)(16 * scale);
            int y = workArea.Y + workArea.Height - targetHeight - (int)(12 * scale);

            AppWindow.MoveAndResize(new RectInt32(x, y, targetWidth, targetHeight));

            // Inherit theme from MainWindow
            if (App.Current.MainWindow?.Content is FrameworkElement mainRoot && this.Content is FrameworkElement myRoot)
            {
                myRoot.RequestedTheme = mainRoot.ActualTheme;
            }

            AppWindow.Show();
            this.Activate();
            SetForegroundWindow(hwnd);
        }

        public void Hide()
        {
            AppWindow.Hide();
        }

        public bool IsVisible => AppWindow.IsVisible;
    }
}
