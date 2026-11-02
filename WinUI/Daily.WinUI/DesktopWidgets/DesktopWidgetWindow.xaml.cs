using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WinRT.Interop;

namespace Daily_WinUI.DesktopWidgets
{
    public sealed partial class DesktopWidgetWindow : Window
    {
        public DesktopWidgetModel Model { get; private set; }

        private bool _isDragging = false;
        private POINT _dragStartCursor;
        private PointInt32 _dragStartWindowPos;
        private readonly SubclassProc _subclassProc;
        private readonly IntPtr _hwnd;
        private FrameworkElement? _currentView;

        // ── Win32 P/Invoke ──────────────────────────────────────────────────────────
        [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT lpPoint);
        [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("comctl32.dll", SetLastError = true)]
        private static extern bool SetWindowSubclass(IntPtr hWnd, SubclassProc pfnSubclass, UIntPtr uIdSubclass, IntPtr dwRefData);

        [DllImport("comctl32.dll", SetLastError = true)]
        private static extern bool RemoveWindowSubclass(IntPtr hWnd, SubclassProc pfnSubclass, UIntPtr uIdSubclass);

        [DllImport("comctl32.dll", SetLastError = true)]
        private static extern IntPtr DefSubclassProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam);

        private delegate IntPtr SubclassProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam, UIntPtr uIdSubclass, IntPtr dwRefData);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int x;
            public int y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WINDOWPOS
        {
            public IntPtr hwnd;
            public IntPtr hwndInsertAfter;
            public int x;
            public int y;
            public int cx;
            public int cy;
            public uint flags;
        }

        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_APPWINDOW = 0x00040000;

        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const uint SWP_SHOWWINDOW = 0x0040;
        private const uint SWP_HIDEWINDOW = 0x0080;

        private const uint WM_MOUSEACTIVATE = 0x0021;
        private const uint WM_WINDOWPOSCHANGING = 0x0046;
        private const uint WM_DESTROY = 0x0002;
        private const uint WM_SYSCOMMAND = 0x0112;
        private const int SC_MINIMIZE = 0xF020;
        private const int MA_NOACTIVATE = 3;

        private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
        private const int DWMWCP_ROUND = 2;

        public bool IsExplicitlyHidden { get; set; } = false;

        public DesktopWidgetWindow(DesktopWidgetModel model)
        {
            Model = model;
            this.InitializeComponent();

            ApplyBackdrop();

            // Configure borderless window
            AppWindow.TitleBar.ExtendsContentIntoTitleBar = true;
            if (AppWindow.Presenter is OverlappedPresenter presenter)
            {
                presenter.IsResizable = false;
                presenter.IsMaximizable = false;
                presenter.IsMinimizable = false;
                presenter.SetBorderAndTitleBar(false, false);
                presenter.IsAlwaysOnTop = false;
            }

            _hwnd = WindowNative.GetWindowHandle(this);

            // Hide from Alt+Tab and taskbar, prevent activating as foreground window
            int exStyle = GetWindowLong(_hwnd, GWL_EXSTYLE);
            SetWindowLong(_hwnd, GWL_EXSTYLE, (exStyle | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE) & ~WS_EX_APPWINDOW);

            // Windows 11 DWM rounded corners
            int cornerPref = DWMWCP_ROUND;
            DwmSetWindowAttribute(_hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref cornerPref, sizeof(int));

            // Subclass to enforce MA_NOACTIVATE and prevent off-screen minimization
            _subclassProc = new SubclassProc(SubclassCallback);
            SetWindowSubclass(_hwnd, _subclassProc, new UIntPtr(1001), IntPtr.Zero);

            UpdateWindowSizeAndPosition();
            LoadWidgetView();

            // Display window on desktop layer without stealing keyboard focus or activating foreground
            SetWindowPos(_hwnd, IntPtr.Zero, Model.X, Model.Y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);

            UpdateLockVisuals();
        }

        private IntPtr SubclassCallback(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam, UIntPtr uIdSubclass, IntPtr dwRefData)
        {
            if (uMsg == WM_MOUSEACTIVATE)
            {
                // Prevent mouse clicks from activating this window as active foreground
                return (IntPtr)MA_NOACTIVATE;
            }

            if (uMsg == WM_SYSCOMMAND && ((int)wParam & 0xFFF0) == SC_MINIMIZE)
            {
                // Prevent desktop widget from ever being minimized
                return IntPtr.Zero;
            }

            if (uMsg == WM_WINDOWPOSCHANGING)
            {
                // Prevent Win + D ("Show Desktop") from pushing widgets off-screen (-32000) or hiding them
                try
                {
                    if (lParam != IntPtr.Zero)
                    {
                        var pos = Marshal.PtrToStructure<WINDOWPOS>(lParam);
                        bool modified = false;

                        if (pos.x <= -10000 || pos.y <= -10000)
                        {
                            pos.x = Model.X;
                            pos.y = Model.Y;
                            pos.flags |= SWP_NOMOVE;
                            modified = true;
                        }

                        if ((pos.flags & SWP_HIDEWINDOW) != 0 && !IsExplicitlyHidden)
                        {
                            pos.flags &= ~SWP_HIDEWINDOW;
                            pos.flags |= SWP_SHOWWINDOW;
                            modified = true;
                        }

                        if (modified)
                        {
                            Marshal.StructureToPtr(pos, lParam, false);
                        }
                    }
                }
                catch { }
            }

            if (uMsg == WM_DESTROY)
            {
                RemoveWindowSubclass(hWnd, _subclassProc, uIdSubclass);
            }

            return DefSubclassProc(hWnd, uMsg, wParam, lParam);
        }

        public void ApplyBackdrop()
        {
            if (Model.Backdrop == DesktopBackdropType.MicaAlt)
            {
                this.SystemBackdrop = new MicaBackdrop { Kind = Microsoft.UI.Composition.SystemBackdrops.MicaKind.BaseAlt };
            }
            else
            {
                this.SystemBackdrop = new DesktopAcrylicBackdrop();
            }

            if (CardBorder != null)
            {
                CardBorder.Opacity = Model.Opacity;
            }
        }

        public void UpdateWindowSizeAndPosition()
        {
            uint dpi = GetDpiForWindow(_hwnd);
            double scale = dpi > 0 ? (double)dpi / 96.0 : 1.0;

            int widthPt = 360;
            int heightPt = 170;

            switch (Model.Size)
            {
                case DesktopWidgetSize.Small:
                    widthPt = 170;
                    heightPt = 170;
                    break;
                case DesktopWidgetSize.Medium:
                    widthPt = 360;
                    heightPt = 170;
                    break;
                case DesktopWidgetSize.Large:
                    widthPt = 360;
                    heightPt = 360;
                    break;
            }

            int targetWidth = (int)(widthPt * scale);
            int targetHeight = (int)(heightPt * scale);

            AppWindow.MoveAndResize(new RectInt32(Model.X, Model.Y, targetWidth, targetHeight));
        }

        public void LoadWidgetView()
        {
            _currentView = DesktopWidgetViewFactory.CreateView(Model, this);
            WidgetContentHost.Content = _currentView;
        }

        public void RefreshViewData()
        {
            if (_currentView is IDesktopWidgetView refreshable)
            {
                refreshable.RefreshData();
            }
        }

        private void UpdateLockVisuals()
        {
            if (DragHandle != null)
            {
                DragHandle.Visibility = Model.IsLocked ? Visibility.Collapsed : Visibility.Visible;
            }
        }

        // ── Drag & Reposition Handlers ──────────────────────────────────────────────
        private void Header_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            if (Model.IsLocked) return;

            var properties = e.GetCurrentPoint(HeaderOverlay).Properties;
            if (properties.IsLeftButtonPressed)
            {
                _isDragging = true;
                GetCursorPos(out _dragStartCursor);
                _dragStartWindowPos = AppWindow.Position;
                HeaderOverlay.CapturePointer(e.Pointer);
                e.Handled = true;
            }
        }

        private void Header_PointerMoved(object sender, PointerRoutedEventArgs e)
        {
            if (!_isDragging || Model.IsLocked) return;

            if (GetCursorPos(out POINT currentCursor))
            {
                int dx = currentCursor.x - _dragStartCursor.x;
                int dy = currentCursor.y - _dragStartCursor.y;

                int newX = _dragStartWindowPos.X + dx;
                int newY = _dragStartWindowPos.Y + dy;

                AppWindow.Move(new PointInt32(newX, newY));
                e.Handled = true;
            }
        }

        private void Header_PointerReleased(object sender, PointerRoutedEventArgs e)
        {
            if (!_isDragging) return;

            _isDragging = false;
            HeaderOverlay.ReleasePointerCapture(e.Pointer);

            // Snap to 16px magnetic grid and clamp to visible desktop work area
            var curPos = AppWindow.Position;
            int snappedX = (int)(Math.Round((double)curPos.X / 16.0) * 16);
            int snappedY = (int)(Math.Round((double)curPos.Y / 16.0) * 16);

            Model.X = snappedX;
            Model.Y = snappedY;
            DesktopWidgetManager.ClampModelToWorkArea(Model, DesktopWidgetManager.GetDesktopWorkArea());

            AppWindow.Move(new PointInt32(Model.X, Model.Y));

            // Retain window at desktop Z-order without stealing foreground activation (do NOT use HWND_BOTTOM)
            SetWindowPos(_hwnd, IntPtr.Zero, Model.X, Model.Y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);

            DesktopWidgetManager.Instance.SaveConfiguration();
            e.Handled = true;
        }

        // ── Context Menu ────────────────────────────────────────────────────────────
        private void Header_ContextRequested(UIElement sender, ContextRequestedEventArgs args)
        {
            ShowContextMenu(sender, args);
        }

        public void ShowContextMenu(UIElement sender, ContextRequestedEventArgs? args = null)
        {
            var menu = new MenuFlyout();

            // Widget Title Header
            var titleItem = new MenuFlyoutItem
            {
                Text = $"{Model.Type} Widget",
                IsEnabled = false
            };
            menu.Items.Add(titleItem);
            menu.Items.Add(new MenuFlyoutSeparator());

            // Size Submenu
            var sizeSubItem = new MenuFlyoutSubItem { Text = "Size" };
            
            var smallItem = new ToggleMenuFlyoutItem { Text = "Small (170×170)", IsChecked = Model.Size == DesktopWidgetSize.Small };
            smallItem.Click += (s, e) => ChangeSize(DesktopWidgetSize.Small);
            sizeSubItem.Items.Add(smallItem);

            var medItem = new ToggleMenuFlyoutItem { Text = "Medium (360×170)", IsChecked = Model.Size == DesktopWidgetSize.Medium };
            medItem.Click += (s, e) => ChangeSize(DesktopWidgetSize.Medium);
            sizeSubItem.Items.Add(medItem);

            var largeItem = new ToggleMenuFlyoutItem { Text = "Large (360×360)", IsChecked = Model.Size == DesktopWidgetSize.Large };
            largeItem.Click += (s, e) => ChangeSize(DesktopWidgetSize.Large);
            sizeSubItem.Items.Add(largeItem);

            menu.Items.Add(sizeSubItem);

            // Lock Position Toggle
            var lockItem = new ToggleMenuFlyoutItem
            {
                Text = "Lock Position",
                IsChecked = Model.IsLocked
            };
            lockItem.Click += (s, e) =>
            {
                Model.IsLocked = !Model.IsLocked;
                UpdateLockVisuals();
                DesktopWidgetManager.Instance.SaveConfiguration();
            };
            menu.Items.Add(lockItem);

            // Backdrop Style Submenu
            var backdropSubItem = new MenuFlyoutSubItem { Text = "Glass Effect" };
            var acrylicItem = new ToggleMenuFlyoutItem { Text = "Acrylic Glass", IsChecked = Model.Backdrop == DesktopBackdropType.Acrylic };
            acrylicItem.Click += (s, e) =>
            {
                Model.Backdrop = DesktopBackdropType.Acrylic;
                ApplyBackdrop();
                DesktopWidgetManager.Instance.SaveConfiguration();
            };
            backdropSubItem.Items.Add(acrylicItem);

            var micaItem = new ToggleMenuFlyoutItem { Text = "Mica Alt Glass", IsChecked = Model.Backdrop == DesktopBackdropType.MicaAlt };
            micaItem.Click += (s, e) =>
            {
                Model.Backdrop = DesktopBackdropType.MicaAlt;
                ApplyBackdrop();
                DesktopWidgetManager.Instance.SaveConfiguration();
            };
            backdropSubItem.Items.Add(micaItem);
            menu.Items.Add(backdropSubItem);

            menu.Items.Add(new MenuFlyoutSeparator());

            // Refresh Data
            var refreshItem = new MenuFlyoutItem { Text = "Refresh Data" };
            refreshItem.Click += (s, e) => RefreshViewData();
            menu.Items.Add(refreshItem);

            // Add Another Widget Submenu
            var addWidgetSub = new MenuFlyoutSubItem { Text = "Add Widget" };
            foreach (DesktopWidgetType wt in Enum.GetValues(typeof(DesktopWidgetType)))
            {
                var curType = wt;
                var addItem = new MenuFlyoutItem { Text = curType.ToString() };
                addItem.Click += (s, e) =>
                {
                    DesktopWidgetManager.Instance.AddWidget(curType, DesktopWidgetSize.Medium, Model.X + 40, Model.Y + 40);
                };
                addWidgetSub.Items.Add(addItem);
            }
            menu.Items.Add(addWidgetSub);

            menu.Items.Add(new MenuFlyoutSeparator());

            // Remove Widget
            var removeItem = new MenuFlyoutItem
            {
                Text = "Remove Widget"
            };
            removeItem.Click += (s, e) =>
            {
                DesktopWidgetManager.Instance.RemoveWidget(this);
            };
            menu.Items.Add(removeItem);

            var target = sender as FrameworkElement ?? CardBorder;
            if (args != null && args.TryGetPosition(target, out var pos))
            {
                menu.ShowAt(target, pos);
            }
            else
            {
                menu.ShowAt(target);
            }
        }

        private void ChangeSize(DesktopWidgetSize newSize)
        {
            if (Model.Size == newSize) return;

            Model.Size = newSize;
            UpdateWindowSizeAndPosition();
            LoadWidgetView();
            DesktopWidgetManager.Instance.SaveConfiguration();
        }

        public void SendToBottom()
        {
            // Do NOT use HWND_BOTTOM on Windows 11 as it pushes the window beneath WorkerW (wallpaper).
            // Retain window at desktop Z-order without stealing foreground activation.
            SetWindowPos(_hwnd, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }

    public interface IDesktopWidgetView
    {
        void RefreshData();
    }
}
