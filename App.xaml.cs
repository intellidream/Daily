using Daily.Services;
#if WINDOWS
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Windows.Graphics;
#endif

namespace Daily
{
    public partial class App : Application
    {
        private readonly ITrayService _trayService;

        public App(ITrayService trayService)
        {
            InitializeComponent();
            _trayService = trayService;
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
            var window = new Window(new MainPage()) { Title = "Daily" };
            
            window.Created += (s, e) =>
            {
                #if WINDOWS
                // ConfigureWindowsWindow(window);
                #endif
            };

            return window;
        }

        #if WINDOWS
        private void ConfigureWindowsWindow(Window window)
        {
            window.HandlerChanged += (s, e) =>
            {
                var nativeWindow = window.Handler?.PlatformView as Microsoft.UI.Xaml.Window;
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
                    
                    int width = 400; // Sidebar width
                    int height = workArea.Height;
                    int x = workArea.X + workArea.Width - width;
                    int y = workArea.Y;

                    appWindow.MoveAndResize(new RectInt32(x, y, width, height));
                }
            };
        }
        #endif
    }
}
