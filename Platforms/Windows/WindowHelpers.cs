#if WINDOWS
using Microsoft.UI.Xaml;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Daily.Platforms.Windows
{
    public static class WindowHelpers
    {
        private delegate IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        private static readonly Dictionary<IntPtr, IntPtr> OriginalWndProcs = new();
        private static readonly Dictionary<IntPtr, WndProc> WndProcDelegates = new();

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int pvAttribute, int cbAttribute);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
        private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

        [DllImport("user32.dll", EntryPoint = "CallWindowProcW")]
        private static extern IntPtr CallWindowProc(IntPtr lpPrevWndFunc, IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        private const int GwlWndProc = -4;
        private const uint WmNcLButtonDblClk = 0x00A3;
        private const uint WmSysCommand = 0x0112;
        private const int HtCaption = 2;
        private const int ScMaximize = 0xF030;

        private const int DwmwaWindowCornerPreference = 33;
        private const int DwmwaBorderColor = 34;
        private const int DwmwcpDontRound = 1;
        private const int DwmwcpRound = 2;
        private const int DwmwaColorDefault = unchecked((int)0xFFFFFFFF);

        public static void ApplySquareCorners(Microsoft.UI.Xaml.Window window)
        {
            try
            {
                var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
                
                var preference = DwmwcpDontRound;
                var result = DwmSetWindowAttribute(hWnd, DwmwaWindowCornerPreference, ref preference, sizeof(int));
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

        public static void DisableTitleBarDoubleClick(Microsoft.UI.Xaml.Window window)
        {
            try
            {
                var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
                if (OriginalWndProcs.ContainsKey(hWnd))
                {
                    return;
                }

                WndProc newWndProc = (handle, msg, wParam, lParam) =>
                {
                    if ((msg == WmNcLButtonDblClk && wParam == new IntPtr(HtCaption)) ||
                        (msg == WmSysCommand && ((int)wParam & 0xFFF0) == ScMaximize))
                    {
                        return IntPtr.Zero;
                    }

                    if (OriginalWndProcs.TryGetValue(handle, out var originalProc))
                    {
                        return CallWindowProc(originalProc, handle, msg, wParam, lParam);
                    }

                    return IntPtr.Zero;
                };

                var newProcPtr = Marshal.GetFunctionPointerForDelegate(newWndProc);
                var original = SetWindowLongPtr(hWnd, GwlWndProc, newProcPtr);
                OriginalWndProcs[hWnd] = original;
                WndProcDelegates[hWnd] = newWndProc;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WindowHelpers] Failed to disable title bar double click: {ex.Message}");
            }
        }

        public static void ApplyRoundedCorners(Microsoft.UI.Xaml.Window window)
        {
            try
            {
                var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(window);

                var preference = DwmwcpRound;
                var result = DwmSetWindowAttribute(hWnd, DwmwaWindowCornerPreference, ref preference, sizeof(int));
                if (result != 0)
                {
                    Console.WriteLine($"[WindowHelpers] DwmSetWindowAttribute failed with HRESULT: {result}");
                }
                else 
                {
                    Console.WriteLine($"[WindowHelpers] Rounded corners applied successfully to HWND: {hWnd}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WindowHelpers] Failed to apply rounded corners: {ex.Message}");
            }
        }

        public static void ApplySystemBorderColor(Microsoft.UI.Xaml.Window window)
        {
            try
            {
                var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
                var color = DwmwaColorDefault;
                var result = DwmSetWindowAttribute(hWnd, DwmwaBorderColor, ref color, sizeof(int));
                if (result != 0)
                {
                    Console.WriteLine($"[WindowHelpers] DwmSetWindowAttribute border color failed with HRESULT: {result}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WindowHelpers] Failed to apply system border color: {ex.Message}");
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
                        int height = workArea.Height;

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
