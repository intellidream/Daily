using Microsoft.Maui.Controls;
using System;
using System.Linq;
using System.Threading.Tasks;

#if WINDOWS
using Microsoft.UI; 
using Microsoft.UI.Windowing;
using Windows.Graphics;
#endif

namespace Daily.Services
{
    public interface IWindowManagerService
    {
        void OpenDetailWindow();
        void OpenDetail(string view, string title = "Detail View", object? data = null);
        void CloseDetailWindow();
        void MoveMainWindowToNextDisplay();
    }

    public class WindowManagerService : IWindowManagerService
    {
        private readonly IRefreshService _refreshService;
        private readonly IDetailNavigationService _detailNavigationService;
        private readonly IRssFeedService _rssFeedService;

        // Desktop Window Reference
        private Window? _detailWindow;

        // Mobile Modal Reference
        private Page? _detailModal;

        public WindowManagerService(IRefreshService refreshService, IDetailNavigationService detailNavigationService, IRssFeedService rssFeedService)
        {
            _refreshService = refreshService;
            _detailNavigationService = detailNavigationService;
            _rssFeedService = rssFeedService;
            if (Application.Current != null)
            {
                Application.Current.RequestedThemeChanged += OnThemeChanged;
            }
        }

        public void OpenDetail(string view, string title = "Detail View", object? data = null)
        {
            _detailNavigationService.NavigateTo(view, title, data);
            OpenDetailWindow();
        }

        private void OnThemeChanged(object? sender, AppThemeChangedEventArgs e)
        {
#if WINDOWS
            if (_detailWindow != null && _detailWindow.Handler?.PlatformView is Microsoft.UI.Xaml.Window nativeWindow)
            {
                ApplyThemeToTitleBar(nativeWindow, e.RequestedTheme);
            }
#endif
        }

        public void MoveMainWindowToNextDisplay()
        {
#if WINDOWS
            var mainWindow = Application.Current?.Windows.FirstOrDefault(w => w != _detailWindow && w != null);
            if (mainWindow == null) return;
            
            // Need native window for P/Invoke
            if (mainWindow.Handler?.PlatformView is Microsoft.UI.Xaml.Window nativeWindow)
            {
                 // Handle can be retrieved on any thread, but generally safe to do here
                 var handle = WinRT.Interop.WindowNative.GetWindowHandle(nativeWindow);

                 // 1. Enumerate Monitors via Win32
                 var monitors = new System.Collections.Generic.List<IntPtr>();
                 EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, 
                     (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData) => 
                     {
                         monitors.Add(hMonitor);
                         return true;
                     }, IntPtr.Zero);
                 
                 // 2. Sort Monitors by X position
                 monitors.Sort((a, b) => 
                 {
                     MONITORINFO miA = new MONITORINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(MONITORINFO)) };
                     GetMonitorInfo(a, ref miA);
                     MONITORINFO miB = new MONITORINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(MONITORINFO)) };
                     GetMonitorInfo(b, ref miB);
                     return miA.rcWork.left.CompareTo(miB.rcWork.left);
                 });

                 if (monitors.Count > 1)
                 {
                     // 3. Find Current Monitor
                     IntPtr currentMonitor = MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST);
                     int currentIndex = monitors.IndexOf(currentMonitor);
                     if (currentIndex == -1) currentIndex = 0;
                     
                     // 4. Cycle to Next
                     int nextIndex = (currentIndex + 1) % monitors.Count;
                     IntPtr targetMonitor = monitors[nextIndex];
                     
                     MONITORINFO targetMi = new MONITORINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(MONITORINFO)) };
                     GetMonitorInfo(targetMonitor, ref targetMi);

                     // 5. Get Target DPI
                     // MDT_EFFECTIVE_DPI = 0
                     uint dpiX = 96;
                     uint dpiY = 96;
                     try 
                     {
                         GetDpiForMonitor(targetMonitor, 0, out dpiX, out dpiY);
                     }
                     catch { } // Fallback to 96 if fails
                     
                     double scale = dpiX / 96.0;
                     if (scale <= 0) scale = 1.0;

                     // 6. Calculate Layout in PIXELS (Physical)
                     // A. Get Current Physical Dimensions to preserve aspect ratio
                     RECT currentRect = new RECT();
                     GetWindowRect(handle, ref currentRect);
                     int currentW = currentRect.right - currentRect.left;
                     int currentH = currentRect.bottom - currentRect.top;
                     
                     double aspectRatio = 1.0;
                     if (currentH > 0)
                     {
                         aspectRatio = (double)currentW / currentH;
                     }

                     // B. Target Dimensions (Right Dock, Full Height)
                     int targetH_Px = targetMi.rcWork.bottom - targetMi.rcWork.top;
                     int targetW_Px = (int)(targetH_Px * aspectRatio);
                     if (targetW_Px < 320) targetW_Px = 320; // Safety min width

                     int targetX_Px = targetMi.rcWork.right - targetW_Px;
                     int targetY_Px = targetMi.rcWork.top;

                     // 7. Convert to DIPs for MAUI
                     double targetX_Dip = targetX_Px / scale;
                     double targetY_Dip = targetY_Px / scale;
                     double targetW_Dip = targetW_Px / scale;
                     double targetH_Dip = targetH_Px / scale;

                     System.Diagnostics.Debug.WriteLine($"[WindowMove] TargetMonitor: {nextIndex} | DPI: {dpiX} (x{scale:F2}) | Px: {targetX_Px},{targetY_Px} {targetW_Px}x{targetH_Px} => Dip: {targetX_Dip:F0},{targetY_Dip:F0} {targetW_Dip:F0}x{targetH_Dip:F0}");

                     // 8. Apply Properties on UI Thread
                     mainWindow.Dispatcher.Dispatch(() => 
                     {
                         mainWindow.X = targetX_Dip;
                         mainWindow.Y = targetY_Dip;
                         mainWindow.Width = targetW_Dip;
                         mainWindow.Height = targetH_Dip;
                     });
                 }
            }
#endif
        }

#if WINDOWS
        // P/Invoke Definitions
        private delegate bool MonitorEnumDelegate(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

        [System.Runtime.InteropServices.DllImport("User32.dll")]
        private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumDelegate lpfnEnum, IntPtr dwData);

        [System.Runtime.InteropServices.DllImport("User32.dll")]
        private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

        [System.Runtime.InteropServices.DllImport("User32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

        [System.Runtime.InteropServices.DllImport("User32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        
        [System.Runtime.InteropServices.DllImport("User32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, ref RECT lpRect);

        [System.Runtime.InteropServices.DllImport("Shcore.dll")]
        private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

        private const uint MONITOR_DEFAULTTONEAREST = 0x00000002;
        private const uint SWP_NOZORDER = 0x0004;
        private const uint SWP_NOACTIVATE = 0x0010;

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        private struct RECT
        {
            public int left;
            public int top;
            public int right;
            public int bottom;
        }

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        private struct MONITORINFO
        {
            public uint cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
        }
#endif


        public void OpenDetailWindow()
        {
            if (_detailWindow != null || _detailModal != null) return;

            var detailPage = new DetailPage(_refreshService, _detailNavigationService, _rssFeedService)
            {
#if ANDROID || IOS
                Opacity = 1 // Start visible immediately on Mobile
#else
                Opacity = 0 // Start invisible for fade-in on Desktop
#endif
            };

#if ANDROID || IOS
            _detailModal = detailPage;
            // Handle native back/swipe closing
            detailPage.Disappearing += (s, e) => _detailModal = null;

            // Push without animation to avoid "tremble"/clumsiness
            Application.Current?.MainPage?.Navigation.PushModalAsync(detailPage, false);
#else
            _detailWindow = new Window(detailPage)
            {
                Title = "Daily - Reading Pane"
            };

            // Pre-Calculate Position & Size (Windows Only Logic for now)
#if WINDOWS
            try 
            {
                // Get Main Window context
                var mainWindow = Application.Current?.Windows.FirstOrDefault(w => w != _detailWindow && w != null);
                if (mainWindow?.Handler?.PlatformView is Microsoft.UI.Xaml.Window mainNative)
                {
                    var mainAppWindow = mainNative.AppWindow;
                    if (mainAppWindow != null)
                    {
                        // Get Display Scale Factor
                        double scale = 1.0;
                        if (mainNative.Content != null && mainNative.Content.XamlRoot != null)
                        {
                            scale = mainNative.Content.XamlRoot.RasterizationScale;
                        }

                        var displayArea = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(mainAppWindow.Id, Microsoft.UI.Windowing.DisplayAreaFallback.Nearest);
                        var mainRect = mainAppWindow.Position;

                        if (displayArea != null)
                        {
                            var workArea = displayArea.WorkArea;

                            // 1. Calculate in RAW PIXELS (AppWindow/DisplayArea coords)
                            // Vertical: 90% Screen Height
                            double pixelHeight = workArea.Height * 0.9;
                            double pixelY = workArea.Y + (workArea.Height - pixelHeight) / 2;

                            // Horizontal: 90% Remaining Left Space (Use pixel math)
                            double spaceToLeft = mainRect.X - workArea.X;
                            if (spaceToLeft < 150) spaceToLeft = 150; 
                            double pixelWidth = spaceToLeft * 0.9;
                            
                            // Align to LEFT of app with Strong Overlap (+50px)
                            double pixelX = mainRect.X - pixelWidth + 50;

                            // 2. Convert to DIPs for MAUI Window Properties
                            _detailWindow.Width = pixelWidth / scale;
                            _detailWindow.Height = pixelHeight / scale;
                            _detailWindow.X = pixelX / scale;
                            _detailWindow.Y = pixelY / scale;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                 System.Diagnostics.Debug.WriteLine($"Pre-Layout usage error: {ex}");
            }
#endif

            _detailWindow.Created += (s, e) =>
            {
#if WINDOWS
                 ConfigureWindowStyle(_detailWindow);
#endif
                 new Animation(v => detailPage.Opacity = v, 0, 0.9, Easing.Linear)
                    .Commit(detailPage, "FadeIn", length: 1000);
            };
            
            _detailWindow.Destroying += (s, e) => 
            {
                SetMainWindowEnabled(true); // Re-enable main window
                _detailWindow = null;
            };

            Application.Current?.OpenWindow(_detailWindow);
            SetMainWindowEnabled(false); // Disable main window interaction
#endif
        }

        public void CloseDetailWindow()
        {
#if ANDROID || IOS
            if (_detailModal != null)
            {
                Application.Current?.MainPage?.Navigation.PopModalAsync();
                _detailModal = null;
            }
#else
            if (_detailWindow != null)
            {
                Application.Current?.CloseWindow(_detailWindow);
                _detailWindow = null;
                SetMainWindowEnabled(true); // Safety re-enable
            }
#endif
        }

        private void SetMainWindowEnabled(bool isEnabled)
        {
#if WINDOWS || MACCATALYST
            var mainWindow = Application.Current?.Windows.FirstOrDefault(w => w != _detailWindow && w != null);
            if (mainWindow?.Page is VisualElement content)
            {
                content.IsEnabled = isEnabled;
                // Optional: visual cue for disabled state if not automatic
                content.Opacity = isEnabled ? 1.0 : 0.8; 
            }
#endif
        }

#if WINDOWS 
        private async void ConfigureWindowStyle(Window window)
        {
            try 
            {
                var nativeWindow = window.Handler?.PlatformView as Microsoft.UI.Xaml.Window;
                if (nativeWindow == null) return;

                // Borderless Style Only
                nativeWindow.ExtendsContentIntoTitleBar = true;
                
                // Theme Title Bar based on initial request
                if (Application.Current != null)
                {
                    ApplyThemeToTitleBar(nativeWindow, Application.Current.RequestedTheme);
                }

                var windowId = nativeWindow.AppWindow.Id;
                var appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(windowId);
                
                if (appWindow != null)
                {
                    var presenter = appWindow.Presenter as OverlappedPresenter;
                    if (presenter != null) 
                    {
                       presenter.SetBorderAndTitleBar(false, false);
                       // User Requested: Non-resizable
                       presenter.IsResizable = false;
                       // User Requested: Modal behavior (Cannot go under)
                       presenter.IsAlwaysOnTop = true;
                    }
                }
            }
            catch { }
        }

        private void ApplyThemeToTitleBar(Microsoft.UI.Xaml.Window nativeWindow, AppTheme theme)
        {
            var appWindow = nativeWindow.AppWindow;
            if (appWindow != null)
            {
                var titleBar = appWindow.TitleBar;
                
                // If Dark theme, logic is White buttons. If Light theme, logic is Black buttons.
                var buttonColor = theme == AppTheme.Dark ? Windows.UI.Color.FromArgb(255, 255, 255, 255) : Windows.UI.Color.FromArgb(255, 0, 0, 0);
                
                titleBar.ButtonForegroundColor = buttonColor;
                titleBar.ButtonHoverForegroundColor = buttonColor;
                titleBar.ButtonPressedForegroundColor = buttonColor;
                titleBar.ButtonInactiveForegroundColor = buttonColor;

                titleBar.ButtonBackgroundColor = Windows.UI.Color.FromArgb(0, 0, 0, 0); // Transparent
                titleBar.ButtonInactiveBackgroundColor = Windows.UI.Color.FromArgb(0, 0, 0, 0);
            }
        }
#endif
    }
}
