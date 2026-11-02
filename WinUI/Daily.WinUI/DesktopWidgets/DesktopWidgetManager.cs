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

            foreach (var model in models)
            {
                SpawnWidgetWindow(model);
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

        private const uint SPI_GETWORKAREA = 0x0030;

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

        private static void ClampModelToWorkArea(DesktopWidgetModel model, RectInt32 workArea)
        {
            int widgetWidth = model.Size == DesktopWidgetSize.Small ? 170 : 360;
            int widgetHeight = model.Size == DesktopWidgetSize.Large ? 360 : 170;

            int maxX = workArea.X + workArea.Width - widgetWidth - 16;
            int maxY = workArea.Y + workArea.Height - widgetHeight - 16;

            if (model.X > maxX) model.X = Math.Max(workArea.X + 16, maxX);
            if (model.X < workArea.X) model.X = workArea.X + 16;
            if (model.Y > maxY) model.Y = Math.Max(workArea.Y + 16, maxY);
            if (model.Y < workArea.Y) model.Y = workArea.Y + 16;
        }

        private List<DesktopWidgetModel> CreateDefaultWidgets()
        {
            var list = new List<DesktopWidgetModel>();
            var workArea = GetDesktopWorkArea();

            // Place on the right side of the desktop wallpaper with 24px padding
            int padding = 24;
            int rightX = Math.Max(padding, workArea.X + workArea.Width - 360 - padding);
            int startY = workArea.Y + 24;

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
                Y = startY + 182,
                IsLocked = false
            });

            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Smokes,
                Size = DesktopWidgetSize.Small,
                X = rightX + 180,
                Y = startY + 182,
                IsLocked = false
            });

            // 3. Money Widget (Medium)
            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Money,
                Size = DesktopWidgetSize.Medium,
                X = rightX,
                Y = startY + 364,
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
            var model = new DesktopWidgetModel
            {
                Type = type,
                Size = size,
                X = x,
                Y = y,
                IsLocked = false
            };

            SpawnWidgetWindow(model);
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
                w.AppWindow.Show();
                w.SendToBottom();
            }
        }

        public void HideAll()
        {
            foreach (var w in _activeWidgets)
            {
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
