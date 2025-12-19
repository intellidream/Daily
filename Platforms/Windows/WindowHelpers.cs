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
                // DWMWCP_DONOTROUND = 3
                var attribute = 33;
                var preference = 3;
                DwmSetWindowAttribute(hWnd, attribute, ref preference, sizeof(int));
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WindowHelpers] Failed to apply square corners: {ex.Message}");
            }
        }
    }
}
#endif
