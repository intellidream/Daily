using Daily.Services;
using Daily.Pages;
using Microsoft.Extensions.DependencyInjection;
using System.Runtime.InteropServices;
#if WINDOWS
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Windows.Graphics;
#endif
#if MACCATALYST
using UIKit;
using Foundation;
using CoreGraphics;
using Daily.Platforms.MacCatalyst;
#endif

namespace Daily
{
    public partial class App : Application
    {
        private readonly ITrayService _trayService;
        private readonly IRefreshService _refreshService;
        private readonly IBackButtonService _backButtonService;
        private readonly Supabase.Client _supabase;
        private readonly IDatabaseService _databaseService;
        private readonly ISettingsService _settingsService;
        private readonly IHabitsService _habitsService;
        private readonly ISyncService _syncService;
        private readonly IServiceProvider _serviceProvider;

        private readonly WindowManagerService _windowManagerService;
        private readonly DebugLogger _logger;

        public App(ITrayService trayService, IRefreshService refreshService, IBackButtonService backButtonService, Supabase.Client supabase, IDatabaseService databaseService, ISettingsService settingsService, IHabitsService habitsService, ISyncService syncService, WindowManagerService windowManagerService, DebugLogger logger, IServiceProvider serviceProvider)
        {
            InitializeComponent();
            _windowManagerService = windowManagerService;
            _trayService = trayService;
            _supabase = supabase;
            _databaseService = databaseService;
            _settingsService = settingsService;
            _habitsService = habitsService;
            _syncService = syncService;
            _refreshService = refreshService;
            _backButtonService = backButtonService;
            _logger = logger;
            _serviceProvider = serviceProvider;
#if MACCATALYST
            // Daily.Platforms.MacCatalyst.MacTrayService.Log("App Constructor Called");
#endif

            // Initialize Data Layer & Services
            Task.Run(async () => 
            {
                _logger.Log("[App] Initialization Started.");
                await _databaseService.InitializeAsync();
                await _supabase.InitializeAsync();
                
                // MANUAL HYDRATION
                var currentSession = _supabase.Auth.CurrentSession;
                if (currentSession == null)
                {
                    _logger.Log("[App] Supabase Session is NULL. Attempting Manual Hydration...");
                    try 
                    {
                        var persistence = new Daily.Services.Auth.MauiSessionPersistence(_logger);
                        var storedSession = persistence.LoadSession();
                        if (storedSession != null && !string.IsNullOrEmpty(storedSession.AccessToken))
                        {
                             _logger.Log($"[App] Hydrating Session for {storedSession.User?.Email}...");
                             await _supabase.Auth.SetSession(storedSession.AccessToken, storedSession.RefreshToken);
                             
                             // CRITICAL: Restore Provider Token (YouTube) which SetSession ignores
                             if (_supabase.Auth.CurrentSession != null && !string.IsNullOrEmpty(storedSession.ProviderToken))
                             {
                                 _supabase.Auth.CurrentSession.ProviderToken = storedSession.ProviderToken;
                                 if (!string.IsNullOrEmpty(storedSession.ProviderRefreshToken))
                                 {
                                     _supabase.Auth.CurrentSession.ProviderRefreshToken = storedSession.ProviderRefreshToken;
                                 }
                                 _logger.Log($"[App] Restored ProviderToken (Length: {storedSession.ProviderToken.Length})");
                                 
                                 // PERSIST: We must re-save immediately, otherwise the internal SetSession 
                                 // saved a version *without* the token, and next restart it will be gone.
                                 persistence.SaveSession(_supabase.Auth.CurrentSession);
                                 _logger.Log($"[App] Re-saved Session with ProviderToken to ensure persistence.");
                             }

                             currentSession = _supabase.Auth.CurrentSession;
                             _logger.Log($"[App] Manual Hydration Result: {(currentSession != null ? "Success" : "Failed")}");
                        }
                        else
                        {
                            _logger.Log("[App] No Stored Session found.");
                        }
                    }
                    catch(Exception ex)
                    {
                         _logger.Log($"[App] Manual Hydration Error: {ex}");
                    }
                }
                else
                {
                    _logger.Log($"[App] Supabase Auto-Loaded Session: {currentSession.User?.Email}");
                }

                await _settingsService.InitializeAsync();
                _logger.Log($"[App] Settings Initialized. IsAuthenticated: {_settingsService.IsAuthenticated}");
                
                await _habitsService.InitializeAsync();
                
                _syncService.StartBackgroundSync();
            });

            _trayService.Initialize();
            _trayService.ClickHandler = () => 
            {
                var window = Application.Current?.Windows.FirstOrDefault();
                if (window != null)
                {
                    window.Dispatcher.Dispatch(() => 
                    {
                        #if WINDOWS
                        var nativeWindow = window.Handler?.PlatformView as Microsoft.UI.Xaml.Window;
                        if (nativeWindow != null)
                        {
                            var handle = WinRT.Interop.WindowNative.GetWindowHandle(nativeWindow);
                            var id = Win32Interop.GetWindowIdFromWindow(handle);
                            var appWindow = AppWindow.GetFromWindowId(id);
                            appWindow.Show();
                        }
                        #endif
                    });
                }
            };
        }

        protected override Window CreateWindow(IActivationState? activationState)
        {
            var homePage = _serviceProvider.GetRequiredService<HomePage>();
            var window = new Window(new NavigationPage(homePage)) { Title = "Daily" };
            
            window.Created += (s, e) =>
            {
                #if WINDOWS
                ConfigureWindowsWindow(window);
                #elif MACCATALYST
                try
                {
                    // Simple Startup Hide (One-shot)
                    // We wait briefly for the window to be attached to the scene
                    MainThread.BeginInvokeOnMainThread(async () => 
                    {
                        await Task.Delay(100); 
                        
                        var nsWindow = GetMainNSWindow();
                        if (nsWindow != null)
                        {
                             var selector = new ObjCRuntime.Selector("orderOut:");
                             nsWindow.PerformSelector(selector, null, 0);
                             Console.WriteLine("Hidden on start.");
                        }
                    });
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Failed to hide window on start: {ex}");
                }
                #endif

            };
            
            #if MACCATALYST
            // Pre-Warm Detail View (avoid 5s cold start latency on first open)
            window.Created += async (s, e) => 
            {
                await Task.Delay(500); // Wait for Main Page to fully render
                MainThread.BeginInvokeOnMainThread(() => 
                {
                   (Application.Current as App)?.GetWindowManager()?.PreWarmMacDetail();
                });
            };
            #endif

            return window;
        }

#if MACCATALYST
        public NSObject? GetMainNSWindow()
        {
            try
            {
                var sharedApp = ObjCRuntime.Runtime.GetNSObject(
                    IntPtr_objc_msgSend(_clsNSApplication, _selSharedApp)
                );
                
                if (sharedApp == null) return null;

                var windowsArrayPtr = IntPtr_objc_msgSend(sharedApp.Handle, _selWindows);
                var windowsArray = ObjCRuntime.Runtime.GetNSObject<Foundation.NSArray>(windowsArrayPtr);
                
                if (windowsArray != null)
                {
                    for (nuint i = 0; i < windowsArray.Count; i++)
                    {
                        var win = windowsArray.GetItem<NSObject>(i);
                        // Skip NSStatusBarWindow and Popups
                        var desc = win.Description;
                        if (desc.Contains("StatusBar")) continue;
                        if (desc.Contains("PopupMenu")) continue;
                        
                        return win; // Return first candidate
                    }
                    if (windowsArray.Count > 0) return windowsArray.GetItem<NSObject>(0);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error finding window: {ex}");
            }
            return null;
        }

        public void ToggleWindow()
        {
            MainThread.BeginInvokeOnMainThread(() =>
            {
                // MacTrayService.Log("ToggleWindow called on MainThread");

                try
                {
                    // Make App Active first
                    var nsAppClass = new ObjCRuntime.Class("NSApplication");
                    var sharedAppSelector = new ObjCRuntime.Selector("sharedApplication");
                    var sharedApp = ObjCRuntime.Runtime.GetNSObject(
                        IntPtr_objc_msgSend(nsAppClass.Handle, sharedAppSelector.Handle)
                    );
                    
                    if (sharedApp != null)
                    {
                        var activateSelector = new ObjCRuntime.Selector("activateIgnoringOtherApps:");
                        void_objc_msgSend_Bool(sharedApp.Handle, activateSelector.Handle, true);
                    }

                    var nsWindow = GetMainNSWindow();
                    if (nsWindow != null)
                    {
                        // Check visibility
                        var isVisible = nsWindow.ValueForKey(new Foundation.NSString("isVisible")) as Foundation.NSNumber;
                        bool currentlyVisible = isVisible?.BoolValue ?? false;
                        
                        if (currentlyVisible)
                        {
                            // Hide
                            var selector = new ObjCRuntime.Selector("orderOut:");
                            nsWindow.PerformSelector(selector, null, 0);
                            // MacTrayService.Log("Window Hidden");
                        }
                        else
                        {
                            // Show & Position
                            
                            // 1. Get Screen Info (Visible Frame for Dock Awareness)
                            var nsScreenClass_ = new ObjCRuntime.Class("NSScreen");
                            var mainScreenSelector = new ObjCRuntime.Selector("mainScreen");
                            var mainScreen = ObjCRuntime.Runtime.GetNSObject(
                                 IntPtr_objc_msgSend(nsScreenClass_.Handle, mainScreenSelector.Handle)
                            );
                            
                            CoreGraphics.CGRect visibleFrame = new CoreGraphics.CGRect(0,0,1920,1080);
                            
                            if (mainScreen != null)
                            {
                                var visibleFrameVal = mainScreen.ValueForKey(new Foundation.NSString("visibleFrame")) as Foundation.NSValue;
                                visibleFrame = visibleFrameVal?.CGRectValue ?? visibleFrame;
                            }
                            
                            // 2. Calculate Frame
                            var trayFrame = MacTrayService.LastTrayFrame;
                            
                            // Check State for Width Strategy
                            bool isDetailActive = _windowManagerService?.IsMacDetailActive ?? false;
                            
                            double width = 450;
                            if (isDetailActive)
                            {
                                // Wide Mode (Match ResizeMacWindow logic)
                                width = visibleFrame.Width * 0.90;
                                if (width > 1500) width = 1500;
                            }

                            double widthToUse = width;
                            double height = visibleFrame.Height; 
                            double y = visibleFrame.Y; 
                            double x = 0;

                            if (isDetailActive)
                            {
                                // Center on Screen
                                var screenCenterX = visibleFrame.X + (visibleFrame.Width / 2);
                                x = screenCenterX - (widthToUse / 2);
                            }
                            else if (trayFrame.Width > 0 && trayFrame.Height > 0)
                            {
                                var trayCenterX = trayFrame.X + (trayFrame.Width / 2);
                                x = trayCenterX - (widthToUse / 2);
                                                                
                                if (x < visibleFrame.X) x = visibleFrame.X;
                                if (x + widthToUse > visibleFrame.X + visibleFrame.Width) x = visibleFrame.X + visibleFrame.Width - widthToUse;
                            }
                            else
                            {
                                x = visibleFrame.X + visibleFrame.Width - widthToUse;
                            }
                            
                            var rect = new CoreGraphics.CGRect(x, y, widthToUse, height);
                            
                            // 3. Apply Frame
                            nsWindow.SetValueForKey(
                                Foundation.NSValue.FromCGRect(rect), 
                                new Foundation.NSString("frame")
                            );
                            
                            // 4. Set Level (Status Window)
                            nsWindow.SetValueForKey(Foundation.NSNumber.FromInt32(25), new Foundation.NSString("level"));

                            
                            // 5. Apply Style (Borderless = 0)
                            // This removes Chrome and Resizability
                            // NSWindowStyleMaskBorderless = 0
                            nsWindow.SetValueForKey(Foundation.NSNumber.FromInt32(0), new Foundation.NSString("styleMask"));

                            // 6. Ensure Shadow
                            nsWindow.SetValueForKey(Foundation.NSNumber.FromBoolean(true), new Foundation.NSString("hasShadow"));

                            // 7. Rounded Corners (MACOS LOOK)
                            try 
                            {
                                // A. Set Window Transparent/Clear
                                nsWindow.SetValueForKey(Foundation.NSNumber.FromBoolean(false), new Foundation.NSString("opaque"));
                                
                                var nsColorClass = new ObjCRuntime.Class("NSColor");
                                var clearColorSelector = new ObjCRuntime.Selector("clearColor");
                                var clearColor = ObjCRuntime.Runtime.GetNSObject(
                                    IntPtr_objc_msgSend(nsColorClass.Handle, clearColorSelector.Handle)
                                );
                                nsWindow.SetValueForKey(clearColor!, new Foundation.NSString("backgroundColor"));

                                // B. Round the ContentView Layer
                                // Use KVC Path for safety
                                var contentView = nsWindow.ValueForKey(new Foundation.NSString("contentView")) as NSObject;

                                if (contentView != null)
                                {
                                    contentView.SetValueForKey(Foundation.NSNumber.FromBoolean(true), new Foundation.NSString("wantsLayer"));
                                    
                                    // Set Corner Radius on Layer
                                    // Layer is a property of NSView
                                    contentView.SetValueForKeyPath(Foundation.NSNumber.FromDouble(12.0), new Foundation.NSString("layer.cornerRadius"));
                                    contentView.SetValueForKeyPath(Foundation.NSNumber.FromBoolean(true), new Foundation.NSString("layer.masksToBounds"));
                                }
                            }
                            catch(Exception ex) 
                            {
                                Console.WriteLine($"Rounding Error: {ex}");
                            }

                            // 8. Show
                            var selector = new ObjCRuntime.Selector("makeKeyAndOrderFront:");
                            nsWindow.PerformSelector(selector, null, 0);
                            // MacTrayService.Log($"Window Shown at {rect}");
                        }
                    }
                }
                catch (Exception ex)
                {
                    // MacTrayService.Log($"Error in Toggle: {ex}");
                }
            });
        }


        // Interop Cache
        private static readonly IntPtr _clsNSApplication = ObjCRuntime.Class.GetHandle("NSApplication");
        private static readonly IntPtr _clsNSScreen = ObjCRuntime.Class.GetHandle("NSScreen");
        private static readonly IntPtr _clsNSColor = ObjCRuntime.Class.GetHandle("NSColor");
        
        private static readonly IntPtr _selSharedApp = ObjCRuntime.Selector.GetHandle("sharedApplication");
        private static readonly IntPtr _selWindows = ObjCRuntime.Selector.GetHandle("windows");
        private static readonly IntPtr _selActivateIgnoring = ObjCRuntime.Selector.GetHandle("activateIgnoringOtherApps:");
        private static readonly IntPtr _selOrderOut = ObjCRuntime.Selector.GetHandle("orderOut:");
        private static readonly IntPtr _selIsVisible = ObjCRuntime.Selector.GetHandle("isVisible");
        private static readonly IntPtr _selMainScreen = ObjCRuntime.Selector.GetHandle("mainScreen");
        private static readonly IntPtr _selVisibleFrame = ObjCRuntime.Selector.GetHandle("visibleFrame");
        private static readonly IntPtr _selFrame = ObjCRuntime.Selector.GetHandle("frame");
        private static readonly IntPtr _selSetFrame = ObjCRuntime.Selector.GetHandle("setFrame:"); // Setter selector usually generated, but KeyValueCoding uses keys.
        // For KeyValueCoding, we use NSStrings. Cache those too.
        private static readonly Foundation.NSString _keyFrame = new Foundation.NSString("frame");
        private static readonly Foundation.NSString _keyScreen = new Foundation.NSString("screen");
        private static readonly Foundation.NSString _keyVisibleFrame = new Foundation.NSString("visibleFrame");

        // Clean P/Invokes
        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern IntPtr IntPtr_objc_msgSend(IntPtr receiver, IntPtr selector);

        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern void void_objc_msgSend_Bool(IntPtr receiver, IntPtr selector, bool arg1);

        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern void void_objc_msgSend_UInt(IntPtr receiver, IntPtr selector, uint arg1);
#endif

        #if WINDOWS
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hwnd);

        private void ConfigureWindowsWindow(Window window)
        {
            Action<Window> applySettings = (w) =>
            {
                var nativeWindow = w.Handler?.PlatformView as Microsoft.UI.Xaml.Window;
                if (nativeWindow == null) return;

                var handle = WinRT.Interop.WindowNative.GetWindowHandle(nativeWindow);
                var id = Win32Interop.GetWindowIdFromWindow(handle);
                var appWindow = AppWindow.GetFromWindowId(id);

                if (appWindow != null)
                {
                    // Remove title bar and borders
                    var presenter = appWindow.Presenter as OverlappedPresenter;
                    if (presenter != null)
                    {
                        presenter.IsMaximizable = false;
                        presenter.IsMinimizable = false;
                        presenter.IsResizable = false;
                        presenter.SetBorderAndTitleBar(false, false);
                    }
                    

                    


                    // Position on the right side
                    var displayArea = DisplayArea.GetFromWindowId(id, DisplayAreaFallback.Primary);
                    var workArea = displayArea.WorkArea;
                    
                    int width = 950; // Fallback
                    
                    // DPI SCALING LOGIC
                    // Target: 480 Effective Points (Sidebar Size)
                    double targetPoints = 480; 
                    double scale = 1.0;

                    // Try to get scale from XamlRoot (Most Accurate)
                    if (nativeWindow.Content != null && nativeWindow.Content.XamlRoot != null)
                    {
                        scale = nativeWindow.Content.XamlRoot.RasterizationScale;
                    }
                    else 
                    {
                        // Fallback: Estimate from DPI
                        try 
                        {
                            var dpi = GetDpiForWindow(handle);
                            scale = dpi / 96.0;
                        }
                        catch { scale = 1.0; }
                    }

                    if (scale <= 0) scale = 1.0;
                    width = (int)(targetPoints * scale);

                    // Safety Min/Max
                    if (width < 320) width = 320; 
                    if (width > 1200) width = 1200;

                    int height = workArea.Height;
                    int x = workArea.X + workArea.Width - width;
                    int y = workArea.Y;

                    appWindow.MoveAndResize(new RectInt32(x, y, width, height));
                }
            };

            if (window.Handler?.PlatformView != null)
            {
                applySettings(window);
            }

            window.HandlerChanged += (s, e) => applySettings(window);
        }




        #endif

        
        public WindowManagerService? GetWindowManager() => _windowManagerService;
    }
}
