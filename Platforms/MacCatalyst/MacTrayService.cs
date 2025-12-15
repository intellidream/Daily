using Daily.Services;
using Microsoft.Maui.Controls;
using UIKit;
using Foundation;
using ObjCRuntime;
using System.Runtime.InteropServices;

namespace Daily.Platforms.MacCatalyst
{
    public class MacTrayService : ITrayService
    {
        private NSObject? _statusItem;
        public Action? ClickHandler { get; set; }

        [DllImport("/usr/lib/system/libdyld.dylib")]
        private static extern IntPtr dlopen(string path, int mode);

        public void Initialize()
        {
             MainThread.BeginInvokeOnMainThread(() =>
             {
                 try 
                 {
                     Log("Attempting to load AppKit...");
                     var handle = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", 0x2); // RTLD_NOW = 2
                     Log($"dlopen result: {handle}");
                     
                     // Deep Interop to access NSStatusBar
                     
                     // Deep Interop to access NSStatusBar
                     Log("Step 1: Init at " + DateTime.Now);
                     
                     // Get NSStatusBar.systemStatusBar
                     var statusBarClass = new Class("NSStatusBar");
                     if (statusBarClass.Handle == IntPtr.Zero)
                     {
                         Log("Error: NSStatusBar class not found (AppKit not loaded?)");
                         return;
                     }
                     
                     var systemStatusBarSelector = new Selector("systemStatusBar");
                     var systemStatusBar = Runtime.GetNSObject(
                         IntPtr_objc_msgSend(statusBarClass.Handle, systemStatusBarSelector.Handle)
                     );

                     if (systemStatusBar == null) 
                     {
                         Log("Error: systemStatusBar is null");
                         return;
                     }

                     // Create Status Item
                     var statusItemWithLengthSelector = new Selector("statusItemWithLength:");
                     // -1.0 for Variable Length
                     _statusItem = Runtime.GetNSObject(
                         IntPtr_objc_msgSend_Double(systemStatusBar.Handle, statusItemWithLengthSelector.Handle, -1.0)
                     );

                     if (_statusItem == null)
                     {
                         Log("Error: _statusItem is null");
                         return;
                     }

                     Log("Step 2: Status Item created");

                     // Set Image
                     var buttonSelector = new Selector("button");
                     var button = Runtime.GetNSObject(
                         IntPtr_objc_msgSend(_statusItem.Handle, buttonSelector.Handle)
                     );
                     
                     if (button != null)
                     {
                         Log("Step 3: Button found");
                         
                         // Set Image (Use Real App Icon)
                         var nsAppClass = new Class("NSApplication");
                         var sharedAppSelector = new Selector("sharedApplication");
                         var sharedApp = Runtime.GetNSObject(
                             IntPtr_objc_msgSend(nsAppClass.Handle, sharedAppSelector.Handle)
                         );
                         
                         var appIconSelector = new Selector("applicationIconImage");
                         var image = Runtime.GetNSObject(
                             IntPtr_objc_msgSend(sharedApp.Handle, appIconSelector.Handle)
                         );

                         if (image == null)
                         {
                             // Fallback to Star if App Icon fails
                             Log("App Icon is null, using Star fallback...");
                             var nsImageClass = new Class("NSImage");
                             var sysImgSelector = new Selector("imageWithSystemSymbolName:accessibilityDescription:");
                             image = Runtime.GetNSObject(
                                 IntPtr_objc_msgSend_IntPtr_IntPtr(
                                     nsImageClass.Handle, 
                                     sysImgSelector.Handle, 
                                     new NSString("star.fill").Handle, 
                                     IntPtr.Zero
                                 )
                             );
                         }
                         
                         if (image != null)
                         {
                             // Resize image to fit tray (18x18 or 22x22)
                             // [image setSize:CGSizeMake(22, 22)]
                             var setSizeSelector = new Selector("setSize:");
                             void_objc_msgSend_CGSize(image.Handle, setSizeSelector.Handle, new CoreGraphics.CGSize(22, 22));
                             
                             // [button setImage:image]
                             var setImageSelector = new Selector("setImage:");
                             void_objc_msgSend_IntPtr(button.Handle, setImageSelector.Handle, image.Handle);
                             
                             // Clear Title
                             button.SetValueForKey(new NSString(""), new NSString("title"));
                             
                             Log("Set Button Image (AppIcon or Star)");
                         }
                         else
                         {
                             // Fallback to text
                             button.SetValueForKey(new NSString("Daily"), new NSString("title"));
                             Log("Image failed completely, set Title");
                         }
                         
                         // Create Target early
                         var target = new TrayTarget(this);
                         _target = target; // Keep reference

                         // Wire Button Action (Click to Toggle)
                         // [button setTarget:target]
                         var setTargetSelector = new Selector("setTarget:");
                         void_objc_msgSend_IntPtr(button.Handle, setTargetSelector.Handle, target.Handle);
                         
                         // [button setAction:@selector(toggleWindow:)]
                         var setActionSelector = new Selector("setAction:");
                         var toggleAction = new Selector("toggleWindow:");
                         void_objc_msgSend_IntPtr(button.Handle, setActionSelector.Handle, toggleAction.Handle);
                         
                         // [button sendActionOn: LeftMouseDown] (Default is usually correct, but we can ensure it)
                         
                         Log("Wired Button Action to toggleWindow:");

                         // Create NSMenu (Optional, keep for reference or RightClick future)
                         var nsMenuClass = new Class("NSMenu");
                         var nsMenuItemClass = new Class("NSMenuItem");
                         
                         // menu = [[NSMenu alloc] initWithTitle:@"Daily"]
                         var allocSelector = new Selector("alloc");
                         var initTitleSelector = new Selector("initWithTitle:");
                         
                         var menuAlloc = IntPtr_objc_msgSend(nsMenuClass.Handle, allocSelector.Handle);
                         var menu = Runtime.GetNSObject(
                             IntPtr_objc_msgSend_IntPtr(menuAlloc, initTitleSelector.Handle, new NSString("Daily").Handle)
                         );

                         if (menu != null)
                         {
                             Log("Step 4: NSMenu created (but not attached for primary click/action)");

                             // Create MenuItem "Quit"
                             var quitAction = new Selector("terminate:");
                             // var quitItemAlloc = ...
                             // skipping full menu build for now to keep it clean, as user wants Click-Toggle.
                             // We are NOT doing statusItem.setMenu(menu) here.
                         }
                     }
                 }
                 catch (Exception ex)
                 {
                     Console.WriteLine($"Failed to initialize Native Mac tray icon: {ex}");
                 }
             });
        }

        public static void Log(string message) 
        {
            try {
                Console.WriteLine(message);
            } catch {}
        }

        public static CoreGraphics.CGRect LastTrayFrame { get; set; }

        private TrayTarget? _target;

        [Register("TrayTarget")]
        public class TrayTarget : NSObject
        {
            private WeakReference<MacTrayService> _service;

            public TrayTarget(MacTrayService service)
            {
                _service = new WeakReference<MacTrayService>(service);
            }

            [Export("validateMenuItem:")]
            public bool ValidateMenuItem(NSObject item) => true;

            [Export("toggleWindow:")]
            public void ToggleWindow(NSObject sender)
            {
                if (_service.TryGetTarget(out var service))
                {
                    try {
                        var statusItem = service._statusItem;
                        if (statusItem != null)
                        {
                            var buttonSelector = new Selector("button");
                            var button = Runtime.GetNSObject(IntPtr_objc_msgSend(statusItem.Handle, buttonSelector.Handle));
                            if (button != null)
                            {
                                var windowSelector = new Selector("window");
                                var window = Runtime.GetNSObject(IntPtr_objc_msgSend(button.Handle, windowSelector.Handle));
                                
                                if (window != null)
                                {
                                     var frameVal = window.ValueForKey(new NSString("frame")) as NSValue;
                                     LastTrayFrame = frameVal?.CGRectValue ?? CoreGraphics.CGRect.Empty;
                                }
                            }
                        }
                    } catch(Exception e) { MacTrayService.Log("Failed to capture tray frame: " + e); }

                    service.ClickHandler?.Invoke();
                    var app = Microsoft.Maui.Controls.Application.Current as App;
#if MACCATALYST
                    app?.ToggleWindow();
#endif
                }
            }
        }
        
        // P/Invokes
        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern IntPtr IntPtr_objc_msgSend(IntPtr receiver, IntPtr selector);

        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern IntPtr IntPtr_objc_msgSend_Double(IntPtr receiver, IntPtr selector, double arg1);

        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern IntPtr IntPtr_objc_msgSend_IntPtr(IntPtr receiver, IntPtr selector, IntPtr arg1);
        
        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern IntPtr IntPtr_objc_msgSend_IntPtr_IntPtr(IntPtr receiver, IntPtr selector, IntPtr arg1, IntPtr arg2);

        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern IntPtr IntPtr_objc_msgSend_IntPtr_IntPtr_IntPtr(IntPtr receiver, IntPtr selector, IntPtr arg1, IntPtr arg2, IntPtr arg3);
        
        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern void void_objc_msgSend_Bool(IntPtr receiver, IntPtr selector, bool arg1);

        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern void void_objc_msgSend_CGSize(IntPtr receiver, IntPtr selector, CoreGraphics.CGSize arg1);
        
        [DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
        static extern void void_objc_msgSend_IntPtr(IntPtr receiver, IntPtr selector, IntPtr arg1);
    }
}
