using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Windowing;
using Windows.Graphics;
using Daily_WinUI.Services;

namespace Daily_WinUI.DesktopWidgets
{
    public sealed class DesktopWidgetManager
    {
        public static DesktopWidgetManager Instance { get; } = new();

        private readonly List<DesktopWidgetWindow> _activeWidgets = new();
        public IReadOnlyList<DesktopWidgetWindow> ActiveWidgets => _activeWidgets;

        private bool _isInitialized = false;

        private DesktopWidgetManager() { }

        public void Initialize()
        {
            if (_isInitialized) return;
            _isInitialized = true;

            try
            {
                var settings = SettingsService.Load();
                if (!settings.DesktopWidgetsEnabled)
                {
                    return;
                }

                LoadWidgets();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopWidgetManager] Initialize error: {ex}");
            }
        }

        private void LoadWidgets()
        {
            List<DesktopWidgetModel>? models = null;
            var settings = SettingsService.Load();
            string? json = settings.DesktopWidgetsConfigJson;

            if (!string.IsNullOrWhiteSpace(json))
            {
                try
                {
                    models = JsonSerializer.Deserialize<List<DesktopWidgetModel>>(json);
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[DesktopWidgetManager] Error deserializing config: {ex.Message}");
                }
            }

            if (models == null || models.Count == 0)
            {
                models = CreateDefaultWidgets();
            }

            bool migrated = false;
            foreach (var model in models)
            {
                // Auto-migrate legacy Acrylic widgets to MicaAlt for crisp, artifact-free Liquid Glass
                if (model.Backdrop == DesktopBackdropType.Acrylic)
                {
                    model.Backdrop = DesktopBackdropType.MicaAlt;
                    migrated = true;
                }
                SpawnWidgetWindow(model);
            }

            if (migrated)
            {
                SaveConfiguration();
            }
        }

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
        private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, out RECT pvParam, uint fWinIni);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern uint GetDpiForSystem();

        private const uint SPI_GETWORKAREA = 0x0030;

        public static double GetDesktopDpiScale()
        {
            try
            {
                uint dpi = GetDpiForSystem();
                if (dpi > 0)
                {
                    return (double)dpi / 96.0;
                }
            }
            catch { }
            return 1.0;
        }

        public static RectInt32 GetDesktopWorkArea()
        {
            try
            {
                if (SystemParametersInfo(SPI_GETWORKAREA, 0, out RECT r, 0))
                {
                    int w = r.Right - r.Left;
                    int h = r.Bottom - r.Top;
                    if (w > 200 && h > 200)
                    {
                        return new RectInt32(r.Left, r.Top, w, h);
                    }
                }
            }
            catch { }

            var displayArea = DisplayArea.Primary;
            return displayArea?.WorkArea ?? new RectInt32(0, 0, 1382, 728);
        }

        public static void ClampModelToWorkArea(DesktopWidgetModel model, RectInt32 workArea)
        {
            double scale = GetDesktopDpiScale();
            int widgetWidth = (int)((model.Size == DesktopWidgetSize.Small ? 170 : 360) * scale);
            int widgetHeight = (int)((model.Size == DesktopWidgetSize.Large ? 360 : 170) * scale);

            int maxX = workArea.X + workArea.Width - widgetWidth - (int)(16 * scale);
            int maxY = workArea.Y + workArea.Height - widgetHeight - (int)(16 * scale);

            if (model.X > maxX) model.X = Math.Max(workArea.X + (int)(16 * scale), maxX);
            if (model.X < workArea.X) model.X = workArea.X + (int)(16 * scale);
            if (model.Y > maxY) model.Y = Math.Max(workArea.Y + (int)(16 * scale), maxY);
            if (model.Y < workArea.Y) model.Y = workArea.Y + (int)(16 * scale);
        }

        private List<DesktopWidgetModel> CreateDefaultWidgets()
        {
            var list = new List<DesktopWidgetModel>();
            var workArea = GetDesktopWorkArea();
            double scale = GetDesktopDpiScale();

            int mediumWidth = (int)(360 * scale);
            int smallWidth = (int)(170 * scale);
            int mediumHeight = (int)(170 * scale);
            int smallHeight = (int)(170 * scale);
            int padding = (int)(24 * scale);
            int gap = (int)(12 * scale);

            // Place on the right side of the desktop wallpaper with 24pt padding
            int rightX = Math.Max(padding, workArea.X + workArea.Width - mediumWidth - padding);
            int startY = workArea.Y + padding;

            // 1. Combined Widget (Medium)
            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Combined,
                Size = DesktopWidgetSize.Medium,
                X = rightX,
                Y = startY,
                IsLocked = false
            });

            // 2. Bubbles Widget (Small) & Smokes Widget (Small) side-by-side
            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Bubbles,
                Size = DesktopWidgetSize.Small,
                X = rightX,
                Y = startY + mediumHeight + gap,
                IsLocked = false
            });

            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Smokes,
                Size = DesktopWidgetSize.Small,
                X = rightX + smallWidth + gap,
                Y = startY + mediumHeight + gap,
                IsLocked = false
            });

            // 3. Money Widget (Medium)
            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Money,
                Size = DesktopWidgetSize.Medium,
                X = rightX,
                Y = startY + mediumHeight + gap + smallHeight + gap,
                IsLocked = false
            });

            return list;
        }

        private DesktopWidgetWindow SpawnWidgetWindow(DesktopWidgetModel model)
        {
            var workArea = GetDesktopWorkArea();
            ClampModelToWorkArea(model, workArea);

            var window = new DesktopWidgetWindow(model);
            _activeWidgets.Add(window);

            App.Current.RegisterSecondaryWindow(window);

            window.Closed += (s, e) =>
            {
                _activeWidgets.Remove(window);
            };

            window.Activate();
            return window;
        }

        public void AddWidget(DesktopWidgetType type, DesktopWidgetSize size, int x, int y)
        {
            var dq = App.Current?.MainWindow?.DispatcherQueue;
            if (dq != null && !dq.HasThreadAccess)
            {
                dq.TryEnqueue(() => AddWidget(type, size, x, y));
                return;
            }

            // Ensure widgets are enabled in settings
            var settings = SettingsService.Load();
            if (!settings.DesktopWidgetsEnabled)
            {
                settings.DesktopWidgetsEnabled = true;
                SettingsService.Save(settings);
            }

            var model = new DesktopWidgetModel
            {
                Type = type,
                Size = size,
                X = x,
                Y = y,
                IsLocked = false
            };

            var window = SpawnWidgetWindow(model);
            window.IsExplicitlyHidden = false;
            window.AppWindow.Show();
            window.SendToBottom();

            SaveConfiguration();
        }

        public void RemoveWidget(DesktopWidgetWindow window)
        {
            _activeWidgets.Remove(window);
            try
            {
                window.Close();
            }
            catch { }

            SaveConfiguration();
        }

        public void SaveConfiguration()
        {
            try
            {
                var settings = SettingsService.Load();
                var models = _activeWidgets.Select(w => w.Model).ToList();
                string json = JsonSerializer.Serialize(models, new JsonSerializerOptions { WriteIndented = true });
                settings.DesktopWidgetsConfigJson = json;
                SettingsService.Save(settings);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopWidgetManager] SaveConfiguration error: {ex.Message}");
            }
        }

        public void ShowAll()
        {
            foreach (var w in _activeWidgets)
            {
                w.IsExplicitlyHidden = false;
                w.AppWindow.Show();
                w.SendToBottom();
            }
        }

        public void HideAll()
        {
            foreach (var w in _activeWidgets)
            {
                w.IsExplicitlyHidden = true;
                w.AppWindow.Hide();
            }
        }

        public void ToggleVisibility()
        {
            bool anyVisible = _activeWidgets.Any(w => w.AppWindow.IsVisible);
            if (anyVisible)
            {
                HideAll();
            }
            else
            {
                ShowAll();
            }
        }

        public void SetAllLocked(bool locked)
        {
            foreach (var w in _activeWidgets)
            {
                w.Model.IsLocked = locked;
            }
            SaveConfiguration();
        }

        public void RefreshAllWidgets()
        {
            foreach (var w in _activeWidgets)
            {
                w.RefreshViewData();
            }
        }

        public void ResetToDefaults()
        {
            // Close all
            var copy = _activeWidgets.ToList();
            foreach (var w in copy)
            {
                try { w.Close(); } catch { }
            }
            _activeWidgets.Clear();

            // Clear json
            var settings = SettingsService.Load();
            settings.DesktopWidgetsConfigJson = string.Empty;
            SettingsService.Save(settings);

            // Respawn
            LoadWidgets();
            SaveConfiguration();
        }
    }
}
