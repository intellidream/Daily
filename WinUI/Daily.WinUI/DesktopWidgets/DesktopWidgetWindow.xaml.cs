using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WinRT;
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
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] private static extern int FillRect(IntPtr hDC, ref RECT lprc, IntPtr hbr);
        [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
        [DllImport("user32.dll")] private static extern bool InvalidateRect(IntPtr hWnd, IntPtr lpRect, bool bErase);
        [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
        [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS pMarInset);
        [DllImport("dwmapi.dll")] private static extern int DwmEnableBlurBehindWindow(IntPtr hwnd, ref DWM_BLURBEHIND pBlurBehind);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
        [DllImport("gdi32.dll")] private static extern IntPtr GetStockObject(int fnObject);

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

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MARGINS
        {
            public int cxLeftWidth;
            public int cxRightWidth;
            public int cyTopHeight;
            public int cyBottomHeight;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct DWM_BLURBEHIND
        {
            public uint dwFlags;
            public int fEnable;
            public IntPtr hRgnBlur;
            public int fTransitionOnMaximized;
        }

        private const int GWL_STYLE = -16;
        private const int GWL_EXSTYLE = -20;
        private const int WS_POPUP = unchecked((int)0x80000000);
        private const int WS_FRAME_MASK = 0x00CF0000; // WS_CAPTION | WS_THICKFRAME | WS_BORDER | WS_DLGFRAME | WS_SYSMENU
        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_APPWINDOW = 0x00040000;

        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOZORDER = 0x0004;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const uint SWP_FRAMECHANGED = 0x0020;
        private const uint SWP_SHOWWINDOW = 0x0040;
        private const uint SWP_HIDEWINDOW = 0x0080;

        private const uint WM_ERASEBKGND = 0x0014;
        private const uint WM_MOUSEACTIVATE = 0x0021;
        private const uint WM_WINDOWPOSCHANGING = 0x0046;
        private const uint WM_DESTROY = 0x0002;
        private const uint WM_SYSCOMMAND = 0x0112;
        private const int SC_MINIMIZE = 0xF020;
        private const int MA_NOACTIVATE = 3;

        private const uint DWM_BB_ENABLE = 0x00000001;
        private const uint DWM_BB_BLURREGION = 0x00000002;
        private const int BLACK_BRUSH = 4;

        private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
        private const int DWMWA_BORDER_COLOR = 34;
        private const int DWMWCP_DONOTROUND = 1;
        private const int DWMWA_COLOR_NONE = unchecked((int)0xFFFFFFFE);

        public bool IsExplicitlyHidden { get; set; } = false;

        public DesktopWidgetWindow(DesktopWidgetModel model)
        {
            Model = model;
            this.InitializeComponent();

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

            // Subclass FIRST so WM_ERASEBKGND clears GDI redirection bitmap to 0x00000000 (premultiplied transparent black)
            _subclassProc = new SubclassProc(SubclassCallback);
            SetWindowSubclass(_hwnd, _subclassProc, new UIntPtr(1001), IntPtr.Zero);

            // Enable true per-pixel DWM alpha composition without rectangular DWM frame/border
            ConfigureTransparentWindowChrome();

            this.Closed += DesktopWidgetWindow_Closed;
            if (RootLayout != null)
            {
                RootLayout.Loaded += (s, e) => ConfigureTransparentWindowChrome();
                RootLayout.ActualThemeChanged += (s, e) => ApplyTransparency();
            }

            ApplyBackdrop();
            UpdateWindowSizeAndPosition();
            LoadWidgetView();

            // Display window on desktop layer without stealing keyboard focus or activating foreground
            SetWindowPos(_hwnd, IntPtr.Zero, Model.X, Model.Y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);

            UpdateLockVisuals();
        }

        private void ConfigureTransparentWindowChrome()
        {
            try
            {
                // Strip Win32 WS_DLGFRAME / WS_CAPTION / WS_BORDER / WS_THICKFRAME left by OverlappedPresenter + ExtendsContentIntoTitleBar
                // and set WS_POPUP so Windows draws zero 1px white frame and honors DWM per-pixel alpha outside RootCard's 20pt corners.
                int style = GetWindowLong(_hwnd, GWL_STYLE);
                int popupStyle = (style & ~WS_FRAME_MASK) | WS_POPUP;
                if (popupStyle != style)
                {
                    SetWindowLong(_hwnd, GWL_STYLE, popupStyle);
                    SetWindowPos(_hwnd, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
                }

                // Disable rectangular DWM corner clip and border outline so XAML RootCard's 20pt CornerRadius defines the silhouette
                int cornerPref = DWMWCP_DONOTROUND;
                DwmSetWindowAttribute(_hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref cornerPref, sizeof(int));

                int borderNone = DWMWA_COLOR_NONE;
                DwmSetWindowAttribute(_hwnd, DWMWA_BORDER_COLOR, ref borderNone, sizeof(int));

                var margins = new MARGINS
                {
                    cxLeftWidth = -1,
                    cxRightWidth = -1,
                    cyTopHeight = -1,
                    cyBottomHeight = -1
                };
                DwmExtendFrameIntoClientArea(_hwnd, ref margins);

                // Empty off-screen region activates per-pixel DWM alpha blending without Aero rectangular blur
                IntPtr emptyRgn = CreateRectRgn(-2, -2, -1, -1);
                try
                {
                    var bb = new DWM_BLURBEHIND
                    {
                        dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION,
                        fEnable = 1,
                        hRgnBlur = emptyRgn,
                        fTransitionOnMaximized = 0
                    };
                    DwmEnableBlurBehindWindow(_hwnd, ref bb);
                }
                finally
                {
                    if (emptyRgn != IntPtr.Zero)
                    {
                        DeleteObject(emptyRgn);
                    }
                }

                ClearGdiSurfaceToTransparentBlack();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopWidgetWindow] ConfigureTransparentWindowChrome warning: {ex.Message}");
            }
        }

        private void ClearGdiSurfaceToTransparentBlack()
        {
            try
            {
                IntPtr hdc = GetDC(_hwnd);
                if (hdc != IntPtr.Zero)
                {
                    try
                    {
                        if (GetClientRect(_hwnd, out RECT rc))
                        {
                            // In premultiplied DWM alpha, BLACK_BRUSH writes 0x00000000 (R=0,G=0,B=0,A=0 = 100% transparent),
                            // replacing WinUIDesktopWin32WindowClass's initial 0x00FFFFFF white GDI background.
                            FillRect(hdc, ref rc, GetStockObject(BLACK_BRUSH));
                        }
                    }
                    finally
                    {
                        ReleaseDC(_hwnd, hdc);
                    }
                }
                InvalidateRect(_hwnd, IntPtr.Zero, true);
            }
            catch { }
        }

        private IntPtr SubclassCallback(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam, UIntPtr uIdSubclass, IntPtr dwRefData)
        {
            if (uMsg == WM_ERASEBKGND)
            {
                if (GetClientRect(hWnd, out RECT rc))
                {
                    FillRect(wParam, ref rc, GetStockObject(BLACK_BRUSH));
                }
                return (IntPtr)1;
            }

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

        private void DesktopWidgetWindow_Closed(object sender, WindowEventArgs args)
        {
            try
            {
                if (RootCard?.Child is IDesktopWidgetView view)
                {
                    view.Detach();
                }
                if (RootCard != null)
                {
                    RootCard.Child = null;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopWidgetWindow] Closed cleanup warning: {ex.Message}");
            }
        }

        public void ApplyBackdrop()
        {
            if (this.SystemBackdrop is not TransparentSystemBackdrop)
            {
                this.SystemBackdrop = new TransparentSystemBackdrop();
            }

            ApplyTransparency();
        }

        public void ApplyTransparency()
        {
            bool isDark = RootLayout?.ActualTheme != ElementTheme.Light;

            // Ensure DWM never draws an outer rectangular 1px border outside the 20pt rounded card
            int borderNone = DWMWA_COLOR_NONE;
            DwmSetWindowAttribute(_hwnd, DWMWA_BORDER_COLOR, ref borderNone, sizeof(int));

            if (RootLayout != null)
            {
                RootLayout.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0));
            }

            if (RootCard != null)
            {
                // Smoothly map user Opacity (0.30 = Clear Glass -> 1.00 = Solid Glass) to per-pixel Liquid Glass alpha
                double op = Math.Clamp(Model.Opacity, 0.25, 1.0);
                double t = Math.Clamp((op - 0.30) / 0.70, 0.0, 1.0);

                byte topAlpha = (byte)Math.Clamp((int)Math.Round(84 + t * 160), 68, 246);
                byte bottomAlpha = (byte)Math.Clamp((int)Math.Round(70 + t * 166), 56, 238);

                bool isAcrylicTint = Model.Backdrop == DesktopBackdropType.Acrylic;

                var cardBg = new LinearGradientBrush
                {
                    StartPoint = new Windows.Foundation.Point(0, 0),
                    EndPoint = new Windows.Foundation.Point(1, 1)
                };

                if (isDark)
                {
                    var startColor = isAcrylicTint
                        ? Windows.UI.Color.FromArgb(topAlpha, 20, 32, 54)
                        : Windows.UI.Color.FromArgb(topAlpha, 15, 23, 42);
                    var endColor = isAcrylicTint
                        ? Windows.UI.Color.FromArgb(bottomAlpha, 12, 19, 34)
                        : Windows.UI.Color.FromArgb(bottomAlpha, 9, 14, 26);

                    cardBg.GradientStops.Add(new GradientStop { Color = startColor, Offset = 0.0 });
                    cardBg.GradientStops.Add(new GradientStop { Color = endColor, Offset = 1.0 });
                }
                else
                {
                    var startColor = isAcrylicTint
                        ? Windows.UI.Color.FromArgb(topAlpha, 255, 255, 255)
                        : Windows.UI.Color.FromArgb(topAlpha, 248, 250, 252);
                    var endColor = isAcrylicTint
                        ? Windows.UI.Color.FromArgb(bottomAlpha, 238, 246, 255)
                        : Windows.UI.Color.FromArgb(bottomAlpha, 241, 245, 249);

                    cardBg.GradientStops.Add(new GradientStop { Color = startColor, Offset = 0.0 });
                    cardBg.GradientStops.Add(new GradientStop { Color = endColor, Offset = 1.0 });
                }

                RootCard.Background = cardBg;

                // Specular Liquid Glass 20pt rim matching in-app WinUI & macOS widgets
                var borderBrush = new LinearGradientBrush
                {
                    StartPoint = new Windows.Foundation.Point(0, 0),
                    EndPoint = new Windows.Foundation.Point(1, 1)
                };

                if (isDark)
                {
                    borderBrush.GradientStops.Add(new GradientStop { Color = Windows.UI.Color.FromArgb(0x48, 0xFF, 0xFF, 0xFF), Offset = 0.0 });
                    borderBrush.GradientStops.Add(new GradientStop { Color = Windows.UI.Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF), Offset = 0.5 });
                    borderBrush.GradientStops.Add(new GradientStop { Color = Windows.UI.Color.FromArgb(0x2E, 0xFF, 0xFF, 0xFF), Offset = 1.0 });
                }
                else
                {
                    borderBrush.GradientStops.Add(new GradientStop { Color = Windows.UI.Color.FromArgb(0x88, 0xFF, 0xFF, 0xFF), Offset = 0.0 });
                    borderBrush.GradientStops.Add(new GradientStop { Color = Windows.UI.Color.FromArgb(0x28, 0x0F, 0x17, 0x2A), Offset = 1.0 });
                }

                RootCard.BorderBrush = borderBrush;
            }
        }

        public void SetWidgetOpacity(double opacity)
        {
            Model.Opacity = opacity;
            ApplyTransparency();
            DesktopWidgetManager.Instance.SaveConfiguration();
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
            ClearGdiSurfaceToTransparentBlack();
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

        public void UpdateLockVisuals()
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
            var micaItem = new ToggleMenuFlyoutItem { Text = "Mica Alt Glass (Recommended)", IsChecked = Model.Backdrop == DesktopBackdropType.MicaAlt };
            micaItem.Click += (s, e) =>
            {
                Model.Backdrop = DesktopBackdropType.MicaAlt;
                ApplyBackdrop();
                DesktopWidgetManager.Instance.SaveConfiguration();
            };
            backdropSubItem.Items.Add(micaItem);

            var acrylicItem = new ToggleMenuFlyoutItem { Text = "Acrylic Glass", IsChecked = Model.Backdrop == DesktopBackdropType.Acrylic };
            acrylicItem.Click += (s, e) =>
            {
                Model.Backdrop = DesktopBackdropType.Acrylic;
                ApplyBackdrop();
                DesktopWidgetManager.Instance.SaveConfiguration();
            };
            backdropSubItem.Items.Add(acrylicItem);
            menu.Items.Add(backdropSubItem);

            // Transparency Submenu
            var transSubItem = new MenuFlyoutSubItem { Text = "Transparency" };

            // Map continuous opacity to the closest discrete preset (guaranteeing exact single selection)
            int selectedPreset = 100;
            if (Model.Opacity <= 0.40) selectedPreset = 30;
            else if (Model.Opacity <= 0.60) selectedPreset = 50;
            else if (Model.Opacity <= 0.78) selectedPreset = 70;
            else if (Model.Opacity <= 0.92) selectedPreset = 85;
            else selectedPreset = 100; // default (100% Solid Glass)

            var op100 = new ToggleMenuFlyoutItem { Text = "100% (Solid Glass)", IsChecked = selectedPreset == 100 };
            op100.Click += (s, e) => SetWidgetOpacity(1.0);
            transSubItem.Items.Add(op100);

            var op85 = new ToggleMenuFlyoutItem { Text = "85% (Subtle Glass)", IsChecked = selectedPreset == 85 };
            op85.Click += (s, e) => SetWidgetOpacity(0.85);
            transSubItem.Items.Add(op85);

            var op70 = new ToggleMenuFlyoutItem { Text = "70% (Balanced Glass)", IsChecked = selectedPreset == 70 };
            op70.Click += (s, e) => SetWidgetOpacity(0.70);
            transSubItem.Items.Add(op70);

            var op50 = new ToggleMenuFlyoutItem { Text = "50% (Translucent)", IsChecked = selectedPreset == 50 };
            op50.Click += (s, e) => SetWidgetOpacity(0.50);
            transSubItem.Items.Add(op50);

            var op30 = new ToggleMenuFlyoutItem { Text = "30% (Clear Glass)", IsChecked = selectedPreset == 30 };
            op30.Click += (s, e) => SetWidgetOpacity(0.30);
            transSubItem.Items.Add(op30);

            menu.Items.Add(transSubItem);

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

            var target = sender as FrameworkElement ?? RootLayout;
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

        private void RootLayout_Tapped(object sender, TappedRoutedEventArgs e)
        {
            // If the user tapped on or inside a Button, do not navigate away
            var src = e.OriginalSource as DependencyObject;
            while (src != null && src != RootLayout)
            {
                if (src is Microsoft.UI.Xaml.Controls.Primitives.ButtonBase || src is Button)
                {
                    return;
                }
                src = VisualTreeHelper.GetParent(src);
            }

            NavigateToAssociatedHub();
        }

        public void NavigateToAssociatedHub()
        {
            int tabIndex = Model.Type switch
            {
                DesktopWidgetType.Combined => 1, // Executive Brief / Home
                DesktopWidgetType.Money => 2,    // Finances Hub
                DesktopWidgetType.TagDos => 3,   // TagDos Hub
                DesktopWidgetType.Sleep => 4,    // Health Hub
                DesktopWidgetType.Stress => 4,   // Health Hub
                DesktopWidgetType.Bubbles => 5,  // Habits Hub (Hydration)
                DesktopWidgetType.Smokes => 5,   // Habits Hub (Smokes)
                DesktopWidgetType.Weather => 6,  // Weather Hub
                DesktopWidgetType.Cosmos => 9,   // Cosmos Hub
                _ => 1
            };

#if !WIDGETS_HOST
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.DispatcherQueue.TryEnqueue(() =>
                {
                    mw.ShowAndActivate();
                    mw.NavigateToTab(tabIndex);
                });
                return;
            }
#endif

            WidgetsHostIpc.ForwardNavigationToMainApp(tabIndex);
        }

        public void SendToBottom()
        {
            // Do NOT use HWND_BOTTOM on Windows 11 as it pushes the window beneath WorkerW (wallpaper).
            // Retain window at desktop Z-order without stealing foreground activation.
            ConfigureTransparentWindowChrome();
            SetWindowPos(_hwnd, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }

    public interface IDesktopWidgetView
    {
        void RefreshData();
        void Detach();
    }
}
