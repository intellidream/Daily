using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Daily_WinUI.DesktopWidgets
{
    /// <summary>
    /// Custom WinUI 3 SystemBackdrop that assigns a 100% transparent DirectComposition brush
    /// to the window's composition target, enabling true per-pixel alpha and arbitrary XAML
    /// CornerRadius (20pt Liquid Glass) without WS_EX_LAYERED swapchain crashes or DWM Acrylic ghosting.
    /// </summary>
    public sealed partial class TransparentSystemBackdrop : SystemBackdrop
    {
        private static object? _dispatcherQueueController;
        private Windows.UI.Composition.CompositionColorBrush? _transparentBrush;

        [StructLayout(LayoutKind.Sequential)]
        private struct DispatcherQueueOptions
        {
            public int dwSize;
            public int threadType;
            public int apartmentType;
        }

        [DllImport("CoreMessaging.dll")]
        private static extern int CreateDispatcherQueueController(
            [In] DispatcherQueueOptions options,
            [In, Out, MarshalAs(UnmanagedType.IUnknown)] ref object? dispatcherQueueController);

        private static void EnsureWindowsSystemDispatcherQueueController()
        {
            if (Windows.System.DispatcherQueue.GetForCurrentThread() != null)
            {
                return;
            }

            if (_dispatcherQueueController == null)
            {
                var options = new DispatcherQueueOptions
                {
                    dwSize = Marshal.SizeOf<DispatcherQueueOptions>(),
                    threadType = 2,    // DQTYPE_THREAD_CURRENT
                    apartmentType = 2  // DQTAT_COM_STA
                };
                CreateDispatcherQueueController(options, ref _dispatcherQueueController);
            }
        }

        protected override void OnTargetConnected(ICompositionSupportsSystemBackdrop connectedTarget, XamlRoot xamlRoot)
        {
            base.OnTargetConnected(connectedTarget, xamlRoot);

            EnsureWindowsSystemDispatcherQueueController();
            var compositor = new Windows.UI.Composition.Compositor();
            _transparentBrush = compositor.CreateColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0));
            connectedTarget.SystemBackdrop = _transparentBrush;
        }

        protected override void OnTargetDisconnected(ICompositionSupportsSystemBackdrop disconnectedTarget)
        {
            disconnectedTarget.SystemBackdrop = null;
            _transparentBrush?.Dispose();
            _transparentBrush = null;

            base.OnTargetDisconnected(disconnectedTarget);
        }
    }
}
