using Microsoft.Maui.Controls;
using System;
using System.Linq;
using System.Threading.Tasks;

#if WINDOWS
using Microsoft.UI; 
using Microsoft.UI.Windowing;
using Windows.Graphics;
#endif

namespace Daily.Services
{
    public interface IWindowManagerService
    {
        void OpenDetailWindow();
        void OpenDetail(string view, string title = "Detail View", object? data = null);
        void CloseDetailWindow();
    }

    public class WindowManagerService : IWindowManagerService
    {
        private readonly IRefreshService _refreshService;
        private readonly IDetailNavigationService _detailNavigationService;
        private readonly IRssFeedService _rssFeedService;

        // Desktop Window Reference
        private Window? _detailWindow;

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

        public void OpenDetailWindow()
        {
            if (_detailWindow != null || _detailModal != null) return;

            var detailPage = new DetailPage(_refreshService, _detailNavigationService, _rssFeedService)
            {
#if ANDROID || IOS
                Opacity = 1 // Start visible immediately on Mobile
#else
                Opacity = 0 // Start invisible for fade-in on Desktop
#endif
            };

#if ANDROID || IOS
            _detailModal = detailPage;
            // Handle native back/swipe closing
            detailPage.Disappearing += (s, e) => _detailModal = null;

            // Push without animation to avoid "tremble"/clumsiness
            Application.Current?.MainPage?.Navigation.PushModalAsync(detailPage, false);
#else
            _detailWindow = new Window(detailPage)
            {
                Title = "Daily - Reading Pane"
            };

            // Pre-Calculate Position & Size (Windows Only Logic for now)
#if WINDOWS
            try 
            {
                // Get Main Window context
                var mainWindow = Application.Current?.Windows.FirstOrDefault(w => w != _detailWindow && w != null);
                if (mainWindow?.Handler?.PlatformView is Microsoft.UI.Xaml.Window mainNative)
                {
                    var mainAppWindow = mainNative.AppWindow;
                    if (mainAppWindow != null)
                    {
                        // Get Display Scale Factor
                        double scale = 1.0;
                        if (mainNative.Content != null && mainNative.Content.XamlRoot != null)
                        {
                            scale = mainNative.Content.XamlRoot.RasterizationScale;
                        }

                        var displayArea = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(mainAppWindow.Id, Microsoft.UI.Windowing.DisplayAreaFallback.Nearest);
                        var mainRect = mainAppWindow.Position;

                        if (displayArea != null)
                        {
                            var workArea = displayArea.WorkArea;

                            // 1. Calculate in RAW PIXELS (AppWindow/DisplayArea coords)
                            // Vertical: 90% Screen Height
                            double pixelHeight = workArea.Height * 0.9;
                            double pixelY = workArea.Y + (workArea.Height - pixelHeight) / 2;

                            // Horizontal: 90% Remaining Left Space (Use pixel math)
                            double spaceToLeft = mainRect.X - workArea.X;
                            if (spaceToLeft < 150) spaceToLeft = 150; 
                            double pixelWidth = spaceToLeft * 0.9;
                            
                            // Align to LEFT of app with Strong Overlap (+50px)
                            double pixelX = mainRect.X - pixelWidth + 50;

                            // 2. Convert to DIPs for MAUI Window Properties
                            _detailWindow.Width = pixelWidth / scale;
                            _detailWindow.Height = pixelHeight / scale;
                            _detailWindow.X = pixelX / scale;
                            _detailWindow.Y = pixelY / scale;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                 System.Diagnostics.Debug.WriteLine($"Pre-Layout usage error: {ex}");
            }
#endif

            _detailWindow.Created += (s, e) =>
            {
#if WINDOWS
                 ConfigureWindowStyle(_detailWindow);
#endif
                 new Animation(v => detailPage.Opacity = v, 0, 0.9, Easing.Linear)
                    .Commit(detailPage, "FadeIn", length: 1000);
            };
            
            _detailWindow.Destroying += (s, e) => 
            {
                SetMainWindowEnabled(true); // Re-enable main window
                _detailWindow = null;
            };

            Application.Current?.OpenWindow(_detailWindow);
            SetMainWindowEnabled(false); // Disable main window interaction
#endif
        }

        public void CloseDetailWindow()
        {
#if ANDROID || IOS
            if (_detailModal != null)
            {
                Application.Current?.MainPage?.Navigation.PopModalAsync();
                _detailModal = null;
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
                titleBar.ButtonInactiveBackgroundColor = Windows.UI.Color.FromArgb(0, 0, 0, 0);
            }
        }
#endif
    }
}
