using Daily.Services;
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

        public App(ITrayService trayService, IRefreshService refreshService, IBackButtonService backButtonService, Supabase.Client supabase, IDatabaseService databaseService)
        {
            InitializeComponent();
            _trayService = trayService;
            _supabase = supabase;
            _databaseService = databaseService;
#if MACCATALYST
            // Daily.Platforms.MacCatalyst.MacTrayService.Log("App Constructor Called");
#endif
            _refreshService = refreshService;
            _backButtonService = backButtonService;

            // Initialize Data Layer
            Task.Run(async () => 
            {
                await _databaseService.InitializeAsync();
                await _supabase.InitializeAsync();
            });

            _trayService.Initialize();
            _trayService.ClickHandler = () => 
            {
                MainPage?.Dispatcher.Dispatch(() => 
                {
                    var window = Application.Current?.Windows.FirstOrDefault();
                    if (window != null)
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
                    }
                });
            };
        }

        protected override Window CreateWindow(IActivationState? activationState)
        {
            var window = new Window(new MainPage(_refreshService, _backButtonService)) { Title = "Daily" };
            
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

            return window;
        }

#if MACCATALYST
        public NSObject? GetMainNSWindow()
        {
            try
            {
                var nsAppClass = new ObjCRuntime.Class("NSApplication");
                var sharedAppSelector = new ObjCRuntime.Selector("sharedApplication");
                var sharedApp = ObjCRuntime.Runtime.GetNSObject(
                    IntPtr_objc_msgSend(nsAppClass.Handle, sharedAppSelector.Handle)
                );
                
                if (sharedApp == null) return null;

                var windowsSelector = new ObjCRuntime.Selector("windows");
                var windowsArrayPtr = IntPtr_objc_msgSend(sharedApp.Handle, windowsSelector.Handle);
                var windowsArray = ObjCRuntime.Runtime.GetNSObject<Foundation.NSArray>(windowsArrayPtr);
                
                if (windowsArray != null)
                {
                    for (nuint i = 0; i < windowsArray.Count; i++)
                    {
                        var win = windowsArray.GetItem<NSObject>(i);
                        // Skip NSStatusBarWindow and Popups
                        if (win.Description.Contains("StatusBar")) continue;
                        if (win.Description.Contains("PopupMenu")) continue;
                        
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
                            
                            // Always use Sidebar metrics (User Request: Stability over Dynamic Sizing)
                            double width = 450; 
                            double widthToUse = width;
                            double height = visibleFrame.Height; 
                            double y = visibleFrame.Y; 
                            double x = 0;

                            if (trayFrame.Width > 0 && trayFrame.Height > 0)
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

        // Clean P/Invokes
        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern IntPtr IntPtr_objc_msgSend(IntPtr receiver, IntPtr selector);

        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern void void_objc_msgSend_Bool(IntPtr receiver, IntPtr selector, bool arg1);

        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern void void_objc_msgSend_UInt(IntPtr receiver, IntPtr selector, uint arg1);
#endif

        #if WINDOWS
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
                    
                    int width = 800; // Sidebar width
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
    }
}
