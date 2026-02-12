#if WINDOWS
using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;

namespace Daily.Platforms.Windows
{
    public static class WindowHelpers
    {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int pvAttribute, int cbAttribute);

        public static void ApplySquareCorners(Microsoft.UI.Xaml.Window window)
        {
            try
            {
                var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
                
                // DWMWA_WINDOW_CORNER_PREFERENCE = 33
                // DWMWCP_DONOTROUND = 1
                var attribute = 33;
                var preference = 1;
                var result = DwmSetWindowAttribute(hWnd, attribute, ref preference, sizeof(int));
                if (result != 0)
                {
                    Console.WriteLine($"[WindowHelpers] DwmSetWindowAttribute failed with HRESULT: {result}");
                }
                else 
                {
                    Console.WriteLine($"[WindowHelpers] Square corners applied successfully to HWND: {hWnd}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WindowHelpers] Failed to apply square corners: {ex.Message}");
            }
        }

        public static void ResizeAndDockRight(Microsoft.UI.Xaml.Window window, int effectiveWidth, int effectiveHeight)
        {
            try
            {
                var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
                var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hWnd);
                var appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(windowId);

                if (appWindow != null)
                {
                    // get the display area
                    var displayArea = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(windowId, Microsoft.UI.Windowing.DisplayAreaFallback.Primary);

                    if (displayArea != null)
                    {
                        // Calculate DPI scale
                        // We can't easily get exact DPI here without PInvoke, but we can assume 'effective' means we need to scale?
                        // No, AppWindow.ResizeClient uses actual pixels.
                        // But the user requested "effective pixels".
                        // Use a rough estimate or just set it. 
                        // Wait, previous plan was to use PInvoke GetDpiForWindow if available, or just set it.
                        // Let's use the explicit logic I had before or a simpler one.
                        
                        // We will just invoke the logic to set 450 width.
                        
                        // NOTE: To get proper scaling we usually need extended logic. 
                        // For now, let's use the simple implementation:
                        
                        var workArea = displayArea.WorkArea;
                        
                        // Calculate standard DPI density (approximate if we don't have GetDpiForWindow)
                        // Actually AppWindow sizes are in physical pixels usually? 
                        // Let's just set the width to a reasonable value. Reference suggests simply setting logic.
                        
                        // Let's try to get scaling factor from the window handle? 
                        // Or just use the requested width * scaling?
                        // Let's assume input is already what we want?
                        // No, the prompt said "effective pixels".
                        
                        // Let's implement GetDpiForWindow PInvoke to be precise.
                        double scale = GetScaleFactor(hWnd);
                        int width = (int)(effectiveWidth * scale);
                        // int height = (int)(effectiveHeight * scale); // We want full height
                        int height = workArea.Height; // Full height of work area

                        int x = workArea.Width + workArea.X - width;
                        int y = workArea.Y;

                        appWindow.MoveAndResize(new global::Windows.Graphics.RectInt32(x, y, width, height));
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WindowHelpers] Failed to resize and dock: {ex.Message}");
            }
        }

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hwnd);

        private static double GetScaleFactor(IntPtr hwnd)
        {
            try
            {
                uint dpi = GetDpiForWindow(hwnd);
                if (dpi == 0) return 1.0;
                return dpi / 96.0;
            }
            catch
            {
                return 1.0;
            }
        }
    }
}
#endif
