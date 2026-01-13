using Microsoft.Maui.Controls;
using Microsoft.Maui.Platform;
using Microsoft.Maui.Devices;
using System;
using System.Linq;
using System.Threading.Tasks;

#if WINDOWS
using Microsoft.UI; 
using Microsoft.UI.Windowing;
using Windows.Graphics;
#endif
#if MACCATALYST
using Foundation;
using UIKit;
using ObjCRuntime;
using System.Runtime.InteropServices;
using CoreGraphics;
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
        // Desktop Window Reference
        private Window? _detailWindow;
        
#if MACCATALYST
        // Mac State Saving
        private Page? _previousMacPage;
        private CoreGraphics.CGRect _previousMacFrame;
        private DetailPage? _activeMacDetailPage;
        private DetailPage? _cachedMacDetailPage; // Cache to avoid recreating BlazorWebView
#endif

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

                     // 5. Get Target Monitor Info directly (Pixels)
                     // Reverting to DPI Conversion strategy as requested (User confirmed previous version worked better for Main Window)
                     
                     // Get Target DPI
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

                     // ---------------------------------------------------------
                     // ATOMIC MOVE STRATEGY (Eliminates Disjointedness)
                     // ---------------------------------------------------------
                     // We use DeferWindowPos to move BOTH windows in a single OS transaction.
                     // This guarantees they travel together within the same display refresh frame.
                     
                     IntPtr mainHandle = WinRT.Interop.WindowNative.GetWindowHandle(nativeWindow);
                     IntPtr detailHandle = IntPtr.Zero;
                     
                     if (_detailWindow != null && _detailWindow.Handler?.PlatformView is Microsoft.UI.Xaml.Window detailNative)
                     {
                         detailHandle = WinRT.Interop.WindowNative.GetWindowHandle(detailNative);
                     }

                     // Calculate Detail Target Pixels (if applicable)
                     int dX = 0, dY = 0, dW = 0, dH = 0;
                     bool moveDetail = (detailHandle != IntPtr.Zero);
                     
                     if (moveDetail)
                     {
                         // Use unified logic to get pixel targets
                         // Work Area Pixels
                         int workH = targetMi.rcWork.bottom - targetMi.rcWork.top;
                         
                         // Detail Height (90%)
                         dH = (int)(workH * 0.9);
                         dY = targetMi.rcWork.top + (workH - dH) / 2;
                         
                         // Detail Width (90% of space to left)
                         int spaceLeft = targetX_Px - targetMi.rcWork.left;
                         if (spaceLeft < 150) spaceLeft = 150;
                         dW = (int)(spaceLeft * 0.9);
                         
                         // Detail X (Overlap 50px)
                         dX = targetX_Px - dW + 50;
                     }

                     // Execute Atomic Move
                     int numWindows = moveDetail ? 2 : 1;
                     IntPtr hDefer = BeginDeferWindowPos(numWindows);
                     
                     const uint SWP_NOZORDER = 0x0004;
                     const uint SWP_NOACTIVATE = 0x0010;
                     
                     // 1. Queue Main Window
                     hDefer = DeferWindowPos(hDefer, mainHandle, IntPtr.Zero, targetX_Px, targetY_Px, targetW_Px, targetH_Px, SWP_NOZORDER | SWP_NOACTIVATE);
                     
                     // 2. Queue Detail Window
                     if (moveDetail)
                     {
                         hDefer = DeferWindowPos(hDefer, detailHandle, IntPtr.Zero, dX, dY, dW, dH, SWP_NOZORDER | SWP_NOACTIVATE);
                     }
                     
                     // 3. Commit Transaction
                     EndDeferWindowPos(hDefer);

                     // 4. Sync MAUI Properties (Post-Move) to keep framework happy
                     double targetX_Dip = targetX_Px / scale;
                     double targetY_Dip = targetY_Px / scale;
                     double targetW_Dip = targetW_Px / scale;
                     double targetH_Dip = targetH_Px / scale;

                     mainWindow.Dispatcher.Dispatch(() => 
                     {
                         mainWindow.X = targetX_Dip;
                         mainWindow.Y = targetY_Dip;
                         // W/H might need update too, but usually X/Y is enough for tracking
                         mainWindow.Width = targetW_Dip;
                         mainWindow.Height = targetH_Dip;
                     });
                     
                     if (moveDetail && _detailWindow != null)
                     {
                         _detailWindow.Dispatcher.Dispatch(() =>
                         {
                             // Reverse calculate DIPs for property sync
                             _detailWindow.X = dX / scale;
                             _detailWindow.Y = dY / scale;
                             _detailWindow.Width = dW / scale;
                             _detailWindow.Height = dH / scale;
                         });
                     }
                 }
            }
#endif
        }

#if MACCATALYST
        public void PreWarmMacDetail()
        {
             MainThread.BeginInvokeOnMainThread(() => 
             {
                 // Trigger Lazy Load
                 if (_cachedMacDetailPage == null)
                 {
                     _cachedMacDetailPage = new DetailPage(_refreshService, _detailNavigationService, _rssFeedService);
                 }
                 
                 // Trigger Attach (Hidden)
                 var mainWindow = Application.Current?.Windows.FirstOrDefault(w => w != _detailWindow);
                 if (mainWindow?.Page is MainPage mainPage)
                 {
                     // Attach content but keep overlay hidden/transparent
                     mainPage.MacDetailOverlay.Content = _cachedMacDetailPage.Content;
                     mainPage.MacDetailOverlay.IsVisible = false; 
                     // Ensure Logic Gate is Closed
                     _detailNavigationService.SetDetailVisibility(false);
                     Console.WriteLine("[WindowManagerService] PreWarmed Mac Detail View. Visibility: False");
                 }
             });
        }
#endif

#if WINDOWS
        // P/Invoke Definitions for Atomic Move
        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        static extern IntPtr BeginDeferWindowPos(int nNumWindows);

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        static extern IntPtr DeferWindowPos(IntPtr hWinPosInfo, IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        static extern bool EndDeferWindowPos(IntPtr hWinPosInfo);

        // Helper to Calculate Layout (Pure Logic)
        // Returns Desired Layout in DIPs and Pixels
        private (Rect dips, Rect pixels, double scale) GetDetailWindowDesiredLayout(Window detailWindow)
        {
             try
             {
                 var mainWindow = Application.Current?.Windows.FirstOrDefault(w => w != _detailWindow && w != null);
                 if (mainWindow == null) return (Rect.Zero, Rect.Zero, 1.0);

                 IntPtr mainHandle = IntPtr.Zero;
                 if (mainWindow.Handler?.PlatformView is Microsoft.UI.Xaml.Window mainNative)
                 {
                     mainHandle = WinRT.Interop.WindowNative.GetWindowHandle(mainNative);
                 }
                 if (mainHandle == IntPtr.Zero) return (Rect.Zero, Rect.Zero, 1.0);

                 // 1. Monitor & Scale
                 // Prefer RasterizationScale if available (Source of Truth)
                 double scale = 1.0;
                 if (mainWindow.Handler?.PlatformView is Microsoft.UI.Xaml.Window mn && 
                     mn.Content != null && mn.Content.XamlRoot != null)
                 {
                     scale = mn.Content.XamlRoot.RasterizationScale;
                 }
                 
                 IntPtr monitor = MonitorFromWindow(mainHandle, MONITOR_DEFAULTTONEAREST);
                 
                 // Fallback to OS API if needed (shouldn't happen often if Main is visible)
                 if (scale <= 0)
                 {
                      uint dpiX = 96, dpiY = 96;
                      try { GetDpiForMonitor(monitor, 0, out dpiX, out dpiY); } catch {}
                      scale = dpiX / 96.0;
                 }
                 if (scale <= 0) scale = 1.0;

                 // 2. Physical Metrics (Pixels)
                 MONITORINFO mi = new MONITORINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(MONITORINFO)) };
                 GetMonitorInfo(monitor, ref mi);
                 
                 RECT mainRect = new RECT();
                 GetWindowRect(mainHandle, ref mainRect);

                 // 3. Calculate Target (Pixels)
                 // Work Area
                 int workH = mi.rcWork.bottom - mi.rcWork.top;
                 
                 // Detail Height (90%)
                 int hPx = (int)(workH * 0.9);
                 int yPx = mi.rcWork.top + (workH - hPx) / 2;
                 
                 // Detail Width (90% of space to left)
                 int spaceLeft = mainRect.left - mi.rcWork.left;
                 if (spaceLeft < 150) spaceLeft = 150;
                 int wPx = (int)(spaceLeft * 0.9);
                 
                 // Detail X (Overlap 50px)
                 int xPx = mainRect.left - wPx + 50; 

                 // 4. Calculate DIPs
                 Rect dips = new Rect(xPx / scale, yPx / scale, wPx / scale, hPx / scale);
                 Rect pixels = new Rect(xPx, yPx, wPx, hPx);

                 return (dips, pixels, scale);
             }
             catch
             {
                 return (Rect.Zero, Rect.Zero, 1.0);
             }
        }

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
            // Note: _activeMacDetailPage might be non-null if Mac, but that's handled in Mac block

            DetailPage detailPage;
            
#if MACCATALYST
            // Reuse cached instance if available
            if (_cachedMacDetailPage == null)
            {
                _cachedMacDetailPage = new DetailPage(_refreshService, _detailNavigationService, _rssFeedService);
            }
            detailPage = _cachedMacDetailPage;
#else
            detailPage = new DetailPage(_refreshService, _detailNavigationService, _rssFeedService);
#endif

#if ANDROID || IOS
            detailPage.Opacity = 1;
            _detailModal = detailPage;
            // Handle native back/swipe closing
            detailPage.Disappearing += (s, e) => _detailModal = null;

            // Push without animation to avoid "tremble"/clumsiness
            Application.Current?.Windows.FirstOrDefault()?.Page?.Navigation.PushModalAsync(detailPage, false);
#elif MACCATALYST
            detailPage.Opacity = 1;
            _activeMacDetailPage = detailPage; // Track for disposal
            
            // SINGLE WINDOW STRATEGY (Dynamic Resize)
            var mainWindow = Application.Current?.Windows.FirstOrDefault(w => w != _detailWindow);
            if (mainWindow?.Page is MainPage mainPage)
            {
                 // 1. Inject content into Overlay (Only if needed)
                 // NOTE: PreWarm might have already done this.
                 if (mainPage.MacDetailOverlay.Content != detailPage.Content)
                 {
                     mainPage.MacDetailOverlay.Content = detailPage.Content;
                 }
            // 2. Animate Appearance (Fade Out Main -> Resize -> Fade In Detail)
                 mainPage.MacDetailOverlay.Opacity = 0;
                 mainPage.MacDetailOverlay.IsVisible = true;
                 
                 mainPage.MacDetailOverlay.IsVisible = true;
                 
                 // ENABLE LOGIC GATE - Allows Carousel/heavy components to render
                 _detailNavigationService.SetDetailVisibility(true);

                 var targetView = _detailNavigationService.CurrentView;
                 var isWide = targetView == "Media" || targetView == "RssFeed";

                 MainThread.BeginInvokeOnMainThread(async () => 
                 {
                     // A. Instant Fade Out (Reset Opacity)
                     mainPage.MainWebView.Opacity = 0;

                     // B. Snap Window Size (if needed)
                     // If moving to Wide, OR if we need to shrink back but haven't yet
                     if (isWide || mainPage.Window.Width > 600) 
                     {
                        await ResizeMacWindow(isWide);
                     }
                     
                     // C. Show Detail Content Immediately
                     mainPage.MacDetailOverlay.Opacity = 1;
                 });
            }
            else if (mainWindow != null)
            {
                 // Fallback
                 _previousMacPage = mainWindow.Page;
                 mainWindow.Page = detailPage;
            }
#else
            detailPage.Opacity = 0; // Start invisible for fade-in
            _detailWindow = new Window(detailPage)
            {
                Title = "Daily - Reading Pane"
            };

            // 1. Subscribe to Events (Before Open)
            _detailWindow.Created += (s, e) =>
            {
#if WINDOWS
                 // Must apply style here because Handler is valid now
                 ConfigureWindowStyle(_detailWindow);
#endif


#if WINDOWS
                 // FORCE NATIVE SNAP (Fixes Initial Open on Secondary Displays)
                 // MAUI Properties (DIPs) can be ambiguous during creation on mixed DPI.
                 // We enforce the position using explicit PHYSICAL PIXELS via Win32.
                 try
                 {
                     var layout = GetDetailWindowDesiredLayout(_detailWindow);
                     if (layout.pixels != Rect.Zero && _detailWindow.Handler?.PlatformView is Microsoft.UI.Xaml.Window nativeWin)
                     {
                         IntPtr handle = WinRT.Interop.WindowNative.GetWindowHandle(nativeWin);
                         int x = (int)layout.pixels.X;
                         int y = (int)layout.pixels.Y;
                         int w = (int)layout.pixels.Width;
                         int h = (int)layout.pixels.Height;
                         
                         SetWindowPos(handle, IntPtr.Zero, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
                     }
                 }
                 catch { }
#endif
                 new Animation(v => detailPage.Opacity = v, 0, 0.9, Easing.Linear)
                    .Commit(detailPage, "FadeIn", length: 1000);
            };
            
            _detailWindow.Destroying += (s, e) => 
            {
                SetMainWindowEnabled(true); // Re-enable main window
                _detailWindow = null;
            };

#if WINDOWS
             // 2. Pre-Positioning (Eliminates Flash - Best Effort)
             var desired = GetDetailWindowDesiredLayout(_detailWindow);
             if (desired.dips != Rect.Zero)
             {
                 _detailWindow.X = desired.dips.X;
                 _detailWindow.Y = desired.dips.Y;
                 _detailWindow.Width = desired.dips.Width;
                 _detailWindow.Height = desired.dips.Height;
             }
#endif

            // 3. Open Window (Once)
            Application.Current.OpenWindow(_detailWindow);
            SetMainWindowEnabled(false); // Disable main window interaction
#endif
        }

        public void CloseDetailWindow()
        {
#if ANDROID || IOS
            if (_detailModal != null)
            {
                Application.Current?.Windows.FirstOrDefault()?.Page?.Navigation.PopModalAsync();
                _detailModal = null;
            }
#elif MACCATALYST
            // Restore Mac Main Window (Hide Overlay)
            var mainWindow = Application.Current?.Windows.FirstOrDefault(w => w != _detailWindow);
            
            if (mainWindow?.Page is MainPage mainPage)
            {
                // Force Clean Up always
                var wasVisible = mainPage.MacDetailOverlay.IsVisible;
                
                // DISABLE LOGIC GATE - Stops Carousel immediately
                _detailNavigationService.SetDetailVisibility(false);

                // Restore Mac Main Window (Fade Out Detail -> Resize -> Fade In Main)
                MainThread.BeginInvokeOnMainThread(async () => 
                {
                    if (wasVisible)
                    {
                        // A. Hide Detail Content
                        mainPage.MacDetailOverlay.Opacity = 0;
                        
                        mainPage.MacDetailOverlay.IsVisible = false;
                        mainPage.MacDetailOverlay.IsVisible = false;
                        // mainPage.MacDetailOverlay.Content = null; // PERSISTENT CACHE: Do not detach!
                        mainPage.MacDetailOverlay.Opacity = 1; 

                        // B. Snap Window Size Back (Restore)
                        await ResizeMacWindow(false);

                        // C. Show Main Content
                        mainPage.MainWebView.Opacity = 1;
                        
                        if (_activeMacDetailPage != null)
                        {
                            // CACHING STRATEGY: Do NOT Dispose. Just Reset.
                            _activeMacDetailPage.Reset();
                            
                            // _activeMacDetailPage = null; // We keep the reference in _cachedMacDetailPage, but _active tracks "current open". 
                            // Actually _activeMacDetailPage IS _cachedMacDetailPage.
                            // We can set active to null to indicate closed state.
                            _activeMacDetailPage = null;
                        }
                    }
                });
            }
            else if (mainWindow != null && _previousMacPage != null)
            {
                // Fallback for Page Swap
                mainWindow.Page = _previousMacPage;
                _previousMacPage = null;
                    if (_activeMacDetailPage != null)
                {
                     // CACHING STRATEGY: Do NOT Dispose. Just Reset.
                     _activeMacDetailPage.Reset();
                     _activeMacDetailPage = null;
                }
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
                
                // Square Corners (Apply LAST to ensure it overrides other styles)
                Daily.Platforms.Windows.WindowHelpers.ApplySquareCorners(nativeWindow);
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
            }
        }
#endif



#if MACCATALYST
        // Anchor Strategy: Capture the EXACT frame of the sidebar just before expanding
        private CoreGraphics.CGRect _sidebarAnchor = CoreGraphics.CGRect.Empty;
        
        // KVC Cache
        private static readonly Foundation.NSString _keyFrame = new Foundation.NSString("frame");
        private static readonly Foundation.NSString _keyScreen = new Foundation.NSString("screen");
        private static readonly Foundation.NSString _keyVisibleFrame = new Foundation.NSString("visibleFrame");
        
        private async Task ResizeMacWindow(bool expanded)
        {
            try 
            {
                 // Small delay to allow UI to settle before resizing start
                 await Task.Delay(10);
                 
                 // Robust Window Retrieval (Now Optimized in App.xaml.cs)
                 var nsWindow = (Application.Current as Daily.App)?.GetMainNSWindow();
                 
                 if (nsWindow == null) return;

                 // Get Current Frame & Screen
                 var nsWindowFrameVal = nsWindow.ValueForKey(_keyFrame) as NSValue;
                 
                 if (nsWindowFrameVal == null) return;
                 var appKitWindowFrame = nsWindowFrameVal.CGRectValue;
                 
                 double targetWidth = 0;
                 CoreGraphics.CGRect targetRect;
                 
                 var nsScreen = nsWindow.ValueForKey(_keyScreen);
                 var appKitScreenFrame = new CoreGraphics.CGRect(0,0,1920,1080);
                 double screenWidth = 1920;
                 if (nsScreen != null)
                 {
                     var visibleFrameObj = nsScreen.ValueForKey(_keyVisibleFrame);
                     if (visibleFrameObj is NSValue nsFrameValue)
                     {
                         appKitScreenFrame = nsFrameValue.CGRectValue;
                         screenWidth = appKitScreenFrame.Width;
                     }
                 }

                 if (expanded)
                 {
                     // Capture Anchor if small (Logic V11: Only capture if we look "Small")
                     // 50% threshold handles both 1920 and smaller screens
                     if (appKitWindowFrame.Width < screenWidth * 0.5)
                     {
                         _sidebarAnchor = appKitWindowFrame;
                     }

                     // LOGIC V11: Relative Sizing (90% of Active Screen)
                     targetWidth = screenWidth * 0.90;
                     // Cap at 1500 points (effectively 3000px on Retina)
                     if (targetWidth > 1500) targetWidth = 1500;

                     // Center Logic
                     var screenCenterX = appKitScreenFrame.X + (appKitScreenFrame.Width / 2);
                     var newX = screenCenterX - (targetWidth / 2);
                     targetRect = new CoreGraphics.CGRect(newX, appKitWindowFrame.Y, targetWidth, appKitWindowFrame.Height);
                 }
                 else
                 {
                     // Shrink Logic V11: Relative Sidebar
                     // If Screen > 1200, we assume 450 points is safe.
                     // If Screen < 1200 (e.g. iPad size), we take 35% 
                     if (screenWidth > 1200)
                     {
                         targetWidth = 450;
                     }
                     else
                     {
                         targetWidth = screenWidth * 0.35; // Fallback for smaller screens
                         if (targetWidth < 320) targetWidth = 320; // Absolute min
                     }
                     
                     if (!_sidebarAnchor.IsEmpty)
                     {
                         // Restore Position from Anchor (Anti-Drift)
                         targetRect = new CoreGraphics.CGRect(_sidebarAnchor.X, _sidebarAnchor.Y, targetWidth, _sidebarAnchor.Height);
                     }
                     else
                     {
                         // Fallback Maintain LEFT edge
                         targetRect = new CoreGraphics.CGRect(appKitWindowFrame.X, appKitWindowFrame.Y, targetWidth, appKitWindowFrame.Height);
                     }
                 }

                 Console.WriteLine($"[ResizeMacWindow] Resizing {appKitWindowFrame.Width} -> {targetWidth}");

                 // Direct frame setting works reliably.
                 var rectVal = NSValue.FromCGRect(targetRect);
                 
                 nsWindow.SetValueForKey(rectVal, _keyFrame);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[ResizeMacWindow] Error: {ex.Message}");
            }
            
            // Wait for Layout to catch up
            await Task.Delay(50);
        }
#endif
    }
}

